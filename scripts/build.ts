import { mkdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
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

await mkdir(dirname(output), { recursive: true });

const build = await Bun.build({
  compile: {
    autoloadBunfig: false,
    autoloadDotenv: false,
    outfile: output,
  },
  define: {
    KEY_KONG_TESTING: String(testing),
  },
  entrypoints: [
    join(root, "src", "main.ts"),
    join(root, "src", "delivery-worker.ts"),
  ],
});

if (!build.success) {
  for (const log of build.logs) {
    console.error(log.message);
  }
  process.exit(1);
}
