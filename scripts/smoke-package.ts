import { readdirSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const layout = [
  ...readdirSync(join(root, "dist/bin")).map((name) => `bin/${name}`),
  ...readdirSync(join(root, "dist/libexec")).map((name) => `libexec/${name}`),
].sort();
if (layout.join("\n") !== "bin/key-kong\nlibexec/key-kong-prompt") {
  throw new Error(`unexpected packaged executables: ${layout.join(", ")}`);
}

const cli = join(root, "dist/bin/key-kong");
const version = Bun.spawnSync([cli, "--version"], {
  stdout: "pipe",
  stderr: "pipe",
});
if (version.exitCode !== 0 || version.stdout.toString() !== "key-kong 1.0.0\n") {
  throw new Error("packaged CLI version smoke test failed");
}

const schema = Bun.spawnSync([cli, "schema"], {
  stdout: "pipe",
  stderr: "pipe",
});
if (schema.exitCode !== 0 || JSON.parse(schema.stdout.toString()).properties
  ?.schemaVersion?.const !== 1) {
  throw new Error("packaged CLI schema smoke test failed");
}

const helper = Bun.spawnSync(
  [join(root, "dist/libexec/key-kong-prompt")],
  { stdin: new TextEncoder().encode("{}"), stdout: "pipe", stderr: "pipe" },
);
if (
  helper.exitCode !== 1 ||
  helper.stdout.toString() !== "" ||
  helper.stderr.toString() !== "native prompt failed\n"
) {
  throw new Error("packaged Prompt Adapter smoke test failed");
}
