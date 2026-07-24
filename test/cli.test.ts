import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const cli = join(root, "dist/bin/key-kong");
const fakePrompt = join(root, "test/fake-prompt.ts");
let directory: string;

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), "key-kong-"));
  await chmod(fakePrompt, 0o700);
});

afterAll(async () => {
  await rm(directory, { recursive: true, force: true });
});

function request() {
  return JSON.stringify({
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
}

function run(
  args: string[],
  options: { stdin?: string; mode?: string; marker?: string } = {},
) {
  const process = Bun.spawnSync([cli, ...args], {
    stdin: options.stdin
      ? new TextEncoder().encode(options.stdin)
      : undefined,
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...Bun.env,
      KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
      KEY_KONG_FAKE_MODE: options.mode ?? "submit",
      ...(options.marker ? { KEY_KONG_FAKE_MARKER: options.marker } : {}),
    },
  });
  return {
    code: process.exitCode,
    stdout: process.stdout.toString(),
    stderr: process.stderr.toString(),
  };
}

describe("built CLI response request", () => {
  test("missing operand fails immediately without reading standard input", () => {
    const result = run(["request"]);

    expect(result.code).toBe(2);
    expect(result.stdout).toBe(
      '{"status":"failed","values":{},"error":{"code":"CLI_USAGE","message":"usage: key-kong request <file|->"}}\n',
    );
  });

  test("schema, help, and version expose the versioned contract", () => {
    const schema = JSON.parse(run(["schema"]).stdout);

    expect(schema.properties.schemaVersion.const).toBe(1);
    expect(schema.$defs.field.properties.type.enum).toEqual([
      "text",
      "secret",
      "select",
      "multi_select",
    ]);
    expect(schema.$defs.delivery.required).toEqual([
      "id",
      "path",
      "operation",
      "template",
    ]);
    expect(run(["--help"]).stdout).toContain("key-kong request <file|->");
    expect(run(["--version"]).stdout).toBe("key-kong 1.0.0\n");
  });

  test("explicit standard input completes all response field kinds", () => {
    const result = run(["request", "-"], { stdin: request() });

    expect(result.code).toBe(0);
    expect(result.stdout).toBe(
      '{"status":"completed","values":{"environment":"prod","region":"us-west-2","features":["audit","alerts"]}}\n',
    );
    expect(result.stderr).toBe("");
  });

  test("request file completes through the helper process protocol", async () => {
    const input = join(directory, "request.json");
    await writeFile(input, request());

    const result = run(["request", input]);

    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout).values.region).toBe("us-west-2");
  });

  test("cancellation returns no collected values", () => {
    const result = run(["request", "-"], {
      stdin: request(),
      mode: "cancel",
    });

    expect(result.code).toBe(1);
    expect(result.stdout).toBe('{"status":"cancelled","values":{}}\n');
  });

  test("invalid response request is rejected before launching the helper", async () => {
    const marker = join(directory, "invalid-launched");
    const input = request().replace('"schemaVersion":1', '"schemaVersion":2');

    const result = run(["request", "-"], { stdin: input, marker });

    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout).error.code).toBe("INVALID_REQUEST");
    expect(await Bun.file(marker).exists()).toBeFalse();
  });

  test("delivery and secret execution remain outside this response-only slice", async () => {
    const marker = join(directory, "unsupported-launched");
    const input = JSON.stringify({
      schemaVersion: 1,
      id: "secret",
      title: "Secret",
      fields: [{ id: "token", label: "Token", type: "secret" }],
      deliveries: [],
    });

    const result = run(["request", "-"], { stdin: input, marker });

    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout).error.code).toBe("INVALID_REQUEST");
    expect(await Bun.file(marker).exists()).toBeFalse();
  });

  test("invalid helper output becomes a machine-readable prompt failure", () => {
    const result = run(["request", "-"], {
      stdin: request(),
      mode: "malformed",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error.code).toBe("PROMPT_FAILED");
    expect(result.stdout).not.toContain("not-json");
  });

  test("production build ignores the test helper environment override", async () => {
    const layout = join(directory, "production");
    const bin = join(layout, "bin");
    const libexec = join(layout, "libexec");
    const productionCLI = join(bin, "key-kong");
    const bundledHelper = join(libexec, "key-kong-prompt");
    const overrideHelper = join(layout, "override-prompt");
    await mkdir(bin, { recursive: true });
    await mkdir(libexec, { recursive: true });
    await writeFile(
      bundledHelper,
      `#!/bin/sh
cat >/dev/null
printf '%s\\n' '{"status":"submitted","values":{"environment":"prod","region":"us-west-2","features":["audit","alerts"]}}'
`,
    );
    await writeFile(overrideHelper, "#!/bin/sh\nexit 9\n");
    await chmod(bundledHelper, 0o700);
    await chmod(overrideHelper, 0o700);
    const build = Bun.spawnSync(
      [
        "bun",
        "build",
        "--compile",
        "--define",
        "KEY_KONG_TESTING=false",
        "--outfile",
        productionCLI,
        join(root, "src/main.ts"),
      ],
      { stdout: "pipe", stderr: "pipe" },
    );
    expect(build.exitCode).toBe(0);

    const result = Bun.spawnSync([productionCLI, "request", "-"], {
      stdin: new TextEncoder().encode(request()),
      stdout: "pipe",
      stderr: "pipe",
      env: { ...Bun.env, KEY_KONG_PROMPT_EXECUTABLE: overrideHelper },
    });

    expect(result.exitCode).toBe(0);
    expect(JSON.parse(result.stdout.toString()).status).toBe("completed");
  });

  test("legacy Swift CLI remains buildable as a migration fallback", () => {
    const result = Bun.spawnSync(
      [
        "swift",
        "build",
        "--package-path",
        join(root, "native/macos"),
        "--product",
        "key-kong",
      ],
      { stdout: "pipe", stderr: "pipe" },
    );

    expect(result.exitCode).toBe(0);
  });
});
