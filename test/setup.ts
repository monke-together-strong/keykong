import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
// Keep the developer's Key Kong settings, such as a web prompt, out of tests.
process.env.XDG_CONFIG_HOME = join(root, "dist", "test-config");
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
