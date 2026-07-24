import { insertBeforeLine } from "./content";
import { DeadlineExpired, type Deadline } from "./deadline";
import { renderTemplate } from "./template";
import { openTarget, type TargetIdentity } from "./target";
import type { Delivery, ResponseValue } from "./types";

declare const KEY_KONG_TESTING: boolean;

interface WorkerRequest {
  deliveries: Delivery[];
  values: Record<string, ResponseValue>;
  targets: Array<[string, { dev: string; ino: string }]>;
}

async function execute(
  delivery: Delivery,
  values: Record<string, ResponseValue>,
  expected: TargetIdentity,
) {
  const { handle, identity } = await openTarget(delivery.path);
  try {
    if (identity.dev !== expected.dev || identity.ino !== expected.ino) {
      throw new Error("target changed");
    }

    const content = await handle.readFile();
    const rendered = renderTemplate(delivery.template, values);
    const result = delivery.operation === "append"
      ? Buffer.concat([content, rendered])
      : insertBeforeLine(content, delivery.line!, rendered);
    if (!result) throw new Error("line outside target");

    let offset = 0;
    while (offset < result.length) {
      if (KEY_KONG_TESTING && process.env.KEY_KONG_TEST_BLOCK_WRITE_MS) {
        await Bun.sleep(Number(process.env.KEY_KONG_TEST_BLOCK_WRITE_MS));
      }
      const { bytesWritten } = await handle.write(
        result,
        offset,
        result.length - offset,
        offset,
      );
      if (bytesWritten === 0) throw new Error("target write made no progress");
      offset += bytesWritten;
    }
    await handle.truncate(result.length);
  } finally {
    await handle.close();
  }
}

async function executeAll(
  deliveries: Delivery[],
  values: Record<string, ResponseValue>,
  targets: Map<string, TargetIdentity>,
): Promise<string[]> {
  const failed: string[] = [];
  for (const delivery of deliveries) {
    try {
      await execute(delivery, values, targets.get(delivery.id)!);
    } catch {
      failed.push(delivery.id);
    }
  }
  return failed;
}

export async function deliveryWorkerCommand(): Promise<number> {
  try {
    const request = JSON.parse(await Bun.stdin.text()) as WorkerRequest;
    const targets = new Map(
      request.targets.map(([id, identity]) => [
        id,
        { dev: BigInt(identity.dev), ino: BigInt(identity.ino) },
      ]),
    );
    const failed = await executeAll(
      request.deliveries,
      request.values,
      targets,
    );
    await Bun.write(Bun.stdout, `${JSON.stringify(failed)}\n`);
    return 0;
  } catch {
    return 1;
  }
}

export async function deliver(
  deliveries: Delivery[],
  values: Record<string, ResponseValue>,
  targets: Map<string, TargetIdentity>,
  deadline: Deadline,
): Promise<string[]> {
  if (deliveries.length === 0) return [];

  const workerRequest: WorkerRequest = {
    deliveries,
    values,
    targets: [...targets].map(([id, identity]) => [
      id,
      { dev: String(identity.dev), ino: String(identity.ino) },
    ]),
  };
  const worker = Bun.spawn([process.execPath, "__deliver"], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "ignore",
    env: Bun.env,
  });
  const input = worker.stdin as import("bun").FileSink;
  input.write(JSON.stringify(workerRequest));
  input.end();

  try {
    const [output, exitCode] = await deadline.run(
      Promise.all([
        new Response(
          worker.stdout as ReadableStream<Uint8Array>,
        ).text(),
        worker.exited,
      ]),
      () => worker.kill(9),
    );
    if (exitCode !== 0) return deliveries.map(({ id }) => id);
    const failed: unknown = JSON.parse(output);
    if (
      !Array.isArray(failed) ||
      failed.some((id) => typeof id !== "string") ||
      failed.some((id) => !deliveries.some((delivery) => delivery.id === id))
    ) {
      return deliveries.map(({ id }) => id);
    }
    return failed;
  } catch (error) {
    if (error instanceof DeadlineExpired) {
      await worker.exited;
      throw error;
    }
    return deliveries.map(({ id }) => id);
  }
}
