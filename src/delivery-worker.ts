import { insertBeforeLine } from "./content";
import { renderTemplate } from "./template";
import { openTarget, type TargetIdentity } from "./target";
import type {
  Delivery,
  DeliveryWorkerRequest,
  ResponseValue,
} from "./types";

declare const KEY_KONG_TESTING: boolean;
declare var self: Worker;

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

self.onmessage = async (event: MessageEvent<DeliveryWorkerRequest>) => {
  try {
    if (
      KEY_KONG_TESTING &&
      process.env.KEY_KONG_TEST_DELIVERY_PID_MARKER
    ) {
      await Bun.write(
        process.env.KEY_KONG_TEST_DELIVERY_PID_MARKER,
        String(process.pid),
      );
    }
    const targets = new Map(
      event.data.targets.map(([id, identity]) => [
        id,
        { dev: BigInt(identity.dev), ino: BigInt(identity.ino) },
      ]),
    );
    const failed: string[] = [];
    for (const delivery of event.data.deliveries) {
      try {
        await execute(
          delivery,
          event.data.values,
          targets.get(delivery.id)!,
        );
      } catch {
        failed.push(delivery.id);
      }
    }
    postMessage({ failed });
  } catch {
    postMessage({ error: true });
  }
};
