import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { insertBeforeLine } from "./content";
import type { Deadline } from "./deadline";
import type { Delivery, ResponseValue } from "./types";
import type { TargetIdentity } from "./validation";

function render(template: string, values: Record<string, ResponseValue>): Buffer {
  return Buffer.from(
    template.replace(/\{\{\s*([\p{L}\p{N}_-]+)\s*\}\}/gu, (_, fieldID: string) => {
      const value = values[fieldID];
      return Array.isArray(value) ? JSON.stringify(value) : value;
    }),
  );
}

async function executeOne(
  delivery: Delivery,
  values: Record<string, ResponseValue>,
  expected: TargetIdentity,
  deadline: Deadline,
) {
  deadline.check();
  const handle = await open(
    delivery.path,
    constants.O_RDWR | constants.O_NOFOLLOW,
  );
  try {
    const info = await handle.stat({ bigint: true });
    if (!info.isFile() || info.dev !== expected.dev || info.ino !== expected.ino) {
      throw new Error("target changed");
    }
    const content = await handle.readFile();
    const rendered = render(delivery.template, values);
    const result = delivery.operation === "append"
      ? Buffer.concat([content, rendered])
      : insertBeforeLine(content, delivery.line!, rendered);
    if (!result) throw new Error("line outside target");
    deadline.check();
    let offset = 0;
    while (offset < result.length) {
      deadline.check();
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
  deadline: Deadline,
): Promise<string[]> {
  const failed: string[] = [];
  for (const delivery of deliveries) {
    deadline.check();
    try {
      await executeOne(delivery, values, targets.get(delivery.id)!, deadline);
    } catch (error) {
      deadline.check();
      failed.push(delivery.id);
    }
  }
  return failed;
}
