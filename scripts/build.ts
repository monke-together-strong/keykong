import {
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
} from "node:fs";
import { mkdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const artifactDirectory = join(root, ".build", "bun");
const defaultOutput = join(root, "dist", "bin", "keykong");
const arguments_ = process.argv.slice(2);
const testing = arguments_.includes("--testing");
const outputIndex = arguments_.indexOf("--outfile");
const output = outputIndex === -1
  ? defaultOutput
  : resolve(arguments_[outputIndex + 1] ?? "");
const expectedArguments = outputIndex === -1
  ? Number(testing)
  : Number(testing) + 2;

if (arguments_.length !== expectedArguments || !output) {
  console.error("usage: bun scripts/build.ts [--testing] [--outfile <path>]");
  process.exit(2);
}

await mkdir(artifactDirectory, { recursive: true });

const build = Bun.spawnSync(
  [
    "bun",
    "build",
    "--compile",
    "--define",
    `KEY_KONG_TESTING=${testing}`,
    "--outfile",
    output,
    join(root, "src", "main.ts"),
    join(root, "src", "delivery-worker.ts"),
  ],
  {
    cwd: artifactDirectory,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  },
);

const artifactFiles = [root, artifactDirectory].flatMap((directory) =>
  readdirSync(directory, { withFileTypes: true })
    .filter(
      (entry) =>
        entry.isFile() &&
        entry.name.startsWith(".") &&
        entry.name.endsWith(".bun-build"),
    )
    .map((entry) => {
      const path = join(directory, entry.name);
      return { directory, name: entry.name, path, changed: statSync(path).mtimeMs };
    })
);

artifactFiles.sort(
  (left, right) =>
    right.changed - left.changed || right.name.localeCompare(left.name),
);

for (const [index, artifact] of artifactFiles.entries()) {
  if (index >= 3) {
    unlinkSync(artifact.path);
  } else if (artifact.directory !== artifactDirectory) {
    renameSync(artifact.path, join(artifactDirectory, artifact.name));
  }
}

process.exit(build.exitCode);
