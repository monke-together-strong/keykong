import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const build = Bun.spawnSync(
  [process.execPath, join(root, "scripts/build.ts"), "--testing"],
  {
    cwd: root,
    stdout: "inherit",
    stderr: "inherit",
  },
);

if (build.exitCode !== 0) {
  throw new Error(`testing CLI build exited with status ${build.exitCode}`);
}
