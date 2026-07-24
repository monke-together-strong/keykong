import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const request = JSON.stringify({
    schemaVersion: 1,
    id: "deploy",
    title: "Deploy",
    fields: [
      { id: "environment", label: "Environment", type: "text" },
      {
        id: "region",
        label: "Region",
        type: "select",
        options: [{ label: "Oregon", value: "us-west-2" }],
      },
      {
        id: "features",
        label: "Features",
        type: "multi_select",
        options: [
          { label: "Audit", value: "audit" },
          { label: "Alerts", value: "alerts" },
        ],
      },
    ],
  });
const result = Bun.spawnSync(
  [join(root, "dist/bin/key-kong"), "request", "-"],
  {
    stdin: new TextEncoder().encode(request),
    stdout: "pipe",
    stderr: "pipe",
    env: { ...Bun.env, KEY_KONG_PACKAGE_SMOKE: "1" },
  },
);
const output = JSON.parse(result.stdout.toString());
if (result.exitCode !== 0 || output.status !== "completed") {
  throw new Error("packaged CLI smoke test failed");
}
