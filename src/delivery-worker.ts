import { insertBeforeLine } from "./content";
import {
  setEnvironmentAssignment,
  validateEnvironmentContent,
} from "./environment";
import { renderTemplate } from "./template";
import { openTarget, type TargetIdentity } from "./target";
import type {
  Delivery,
  DeliveryWorkerRequest,
  ResponseValue,
} from "./types";

declare const KEY_KONG_TESTING: boolean;
declare var self: Worker;

function prepareContent(
  delivery: Delivery,
  content: Buffer,
  values: Record<string, ResponseValue>,
): Buffer | undefined {
  switch (delivery.operation) {
    case "append":
      return Buffer.concat([content, renderTemplate(delivery.template, values)]);
    case "insert_line":
      return insertBeforeLine(
        content,
        delivery.line,
        renderTemplate(delivery.template, values),
      );
    case "set_env":
      return setEnvironmentAssignment(
        content,
        delivery.key,
        values[delivery.field] as string,
      );
  }
}

async function execute(
  delivery: Delivery,
  values: Record<string, ResponseValue>,
  expected: TargetIdentity,
  protectedKeys?: ReadonlySet<string>,
) {
  const { handle, identity } = await openTarget(delivery.path);
  try {
    if (identity.dev !== expected.dev || identity.ino !== expected.ino) {
      throw new Error("target changed");
    }

    const content = await handle.readFile();
    const result = prepareContent(delivery, content, values);
    if (!result) throw new Error("line outside target");
    if (protectedKeys) validateEnvironmentContent(result, protectedKeys);

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
    const environmentTargets = new Map<string, Set<string>>();
    for (const delivery of event.data.deliveries) {
      const target = targets.get(delivery.id)!;
      const targetKey = `${target.dev}:${target.ino}`;
      const protectedKeys = environmentTargets.get(targetKey);
      if (
        delivery.operation === "set_env" &&
        protectedKeys?.has(delivery.key)
      ) {
        failed.push(delivery.id);
        continue;
      }
      try {
        await execute(
          delivery,
          event.data.values,
          target,
          protectedKeys,
        );
        if (delivery.operation === "set_env") {
          const keys = protectedKeys ?? new Set<string>();
          keys.add(delivery.key);
          environmentTargets.set(targetKey, keys);
        }
      } catch {
        failed.push(delivery.id);
      }
    }
    postMessage({ failed });
  } catch {
    postMessage({ error: true });
  }
};
