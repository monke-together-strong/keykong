import { insertBeforeLine } from "./content";
import { renderTemplate } from "./template";
import { openTarget, type TargetIdentity } from "./target";
import type { Delivery, ResponseValue } from "./types";

async function execute(
  delivery: Delivery,
  values: Record<string, ResponseValue>,
  expected: TargetIdentity,
) {
  const { handle, identity } = await openTarget(delivery.path);
  try {
    if (
      identity.dev !== expected.dev ||
      identity.ino !== expected.ino
    ) {
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

export async function deliver(
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
