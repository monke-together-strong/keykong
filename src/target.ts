import { constants } from "node:fs";
import { open, type FileHandle } from "node:fs/promises";

export interface TargetIdentity {
  dev: bigint;
  ino: bigint;
}

export async function openTarget(path: string): Promise<{
  handle: FileHandle;
  identity: TargetIdentity;
}> {
  const handle = await open(path, constants.O_RDWR | constants.O_NOFOLLOW);
  try {
    const info = await handle.stat({ bigint: true });
    if (!info.isFile()) throw new Error("target is not a regular file");
    return {
      handle,
      identity: { dev: info.dev, ino: info.ino },
    };
  } catch (error) {
    await handle.close();
    throw error;
  }
}
