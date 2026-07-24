import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  closeSync,
  constants,
  openSync,
  writeSync,
} from "node:fs";
import {
  chmod,
  mkdtemp,
  readFile,
  readdir,
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

function run(
  args: string[],
  options: {
    stdin?: string;
    mode?: string;
    timeout?: string;
    marker?: string;
    internalFailure?: boolean;
  } = {},
) {
  const process = Bun.spawnSync([cli, ...args], {
    stdin: options.stdin ? new TextEncoder().encode(options.stdin) : undefined,
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...Bun.env,
      KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
      KEY_KONG_FAKE_MODE: options.mode ?? "submit",
      KEY_KONG_TEST_TIMEOUT_SECONDS: options.timeout ?? "5",
      ...(options.marker ? { KEY_KONG_FAKE_MARKER: options.marker } : {}),
      ...(options.internalFailure
        ? { KEY_KONG_TEST_FORCE_INTERNAL_FAILURE: "1" }
        : {}),
    },
  });
  return {
    code: process.exitCode,
    stdout: process.stdout.toString(),
    stderr: process.stderr.toString(),
  };
}

function request(path: string) {
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
      { id: "api_token", label: "API token", type: "secret" },
    ],
    deliveries: [
      {
        id: "config",
        path,
        operation: "append",
        template: "{{ environment }} {{ region }} {{ features }} {{ api_token }}\\n",
      },
    ],
  });
}

function withDeliveries(
  path: string,
  deliveries: Array<Record<string, unknown>>,
) {
  const value = JSON.parse(request(path));
  value.deliveries = deliveries;
  return JSON.stringify(value);
}

describe("built CLI", () => {
  test("missing operand fails immediately with JSON and usage exit code", () => {
    const result = run(["request"]);
    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout)).toEqual({
      status: "failed",
      values: {},
      error: { code: "CLI_USAGE", message: "usage: key-kong request <file|->" },
    });
  });

  test("schema, help, and version are available", () => {
    const schema = JSON.parse(run(["schema"]).stdout);
    expect(schema.properties.schemaVersion.const).toBe(1);
    expect(schema.$defs.field.allOf[0].then.required).toEqual(["options"]);
    expect(schema.$defs.field.allOf[0].else.not.required).toEqual(["options"]);
    expect(schema.$defs.delivery.allOf[0].then.required).toEqual(["line"]);
    expect(schema.$defs.delivery.allOf[0].else.not.required).toEqual(["line"]);
    expect(run(["--help"]).stdout).toContain("key-kong request <file|->");
    expect(run(["--version"]).stdout.trim()).toBe("key-kong 1.0.0");
  });

  test("request via stdin completes delivery and omits secrets", async () => {
    const target = join(directory, "completed.txt");
    await writeFile(target, "");
    const result = run(["request", "-"], { stdin: request(target) });

    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual({
      status: "completed",
      values: {
        environment: "prod",
        region: "us-west-2",
        features: ["audit", "alerts"],
      },
    });
    expect(result.stdout + result.stderr).not.toContain("highly-secret");
    expect(await readFile(target, "utf8")).toBe(
      'prod us-west-2 ["audit","alerts"] highly-secret\\n',
    );
  });

  test("request file and cancellation return a valid outcome", async () => {
    const target = join(directory, "cancel-target.txt");
    const input = join(directory, "request.json");
    await writeFile(target, "");
    await writeFile(input, request(target));
    const result = run(["request", input], { mode: "cancel" });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout)).toEqual({ status: "cancelled", values: {} });
    expect(await readFile(target, "utf8")).toBe("");
  });

  test("response-only request may omit deliveries", () => {
    const result = run(["request", "-"], {
      stdin: JSON.stringify({
        schemaVersion: 1,
        id: "response",
        title: "Response",
        fields: [
          { id: "environment", label: "Environment", type: "text" },
        ],
      }),
      mode: "response_only",
    });
    expect(result.code).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual({
      status: "completed",
      values: { environment: "prod" },
    });
  });

  test("invalid request never launches the prompt", async () => {
    const target = join(directory, "invalid-target.txt");
    await writeFile(target, "");
    const result = run(["request", "-"], {
      stdin: request(target).replace('"schemaVersion":1', '"schemaVersion":2'),
      mode: "block",
      timeout: "0.2",
    });

    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout).error.code).toBe("INVALID_REQUEST");
  });

  test("unexpected failures return the stable internal error", () => {
    const result = run(["request", "-"], { internalFailure: true });
    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout)).toEqual({
      status: "failed",
      values: {},
      error: {
        code: "INTERNAL_FAILURE",
        message: "unexpected internal failure",
      },
    });
    expect(result.stderr).toBe("unexpected internal failure\n");
  });

  test("malformed helper output is sanitized", async () => {
    const target = join(directory, "malformed-target.txt");
    await writeFile(target, "");
    const result = run(["request", "-"], {
      stdin: request(target),
      mode: "malformed",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error.code).toBe("PROMPT_FAILED");
    expect(result.stderr).not.toContain("not-json");
  });

  test.each([
    "empty",
    "extra",
    "nonzero",
    "crash",
    "invalid_submission",
  ])(
    "helper failure mode %s is sanitized",
    async (mode) => {
      const target = join(directory, `helper-${mode}.txt`);
      await writeFile(target, "");
      const result = run(["request", "-"], {
        stdin: request(target),
        mode,
      });
      expect(result.code).toBe(1);
      expect(JSON.parse(result.stdout).error.code).toBe("PROMPT_FAILED");
      expect(result.stderr).not.toContain("highly-secret");
    },
  );

  test("ordered append and insert deliveries affect the same target", async () => {
    const target = join(directory, "ordered.txt");
    await writeFile(target, "first\nthird\n");
    const input = withDeliveries(target, [
      {
        id: "insert",
        path: target,
        operation: "insert_line",
        line: 2,
        template: "{{ environment }}",
      },
      {
        id: "append",
        path: target,
        operation: "append",
        template: "{{ region }} {{ api_token }}",
      },
    ]);
    const result = run(["request", "-"], { stdin: input });

    expect(result.code).toBe(0);
    expect(await readFile(target, "utf8")).toBe(
      "first\nprod\nthird\nus-west-2 highly-secret",
    );
  });

  test("target lines are validated in delivery order", async () => {
    const target = join(directory, "ordered-validation.txt");
    await writeFile(target, "first\n");
    const input = withDeliveries(target, [
      {
        id: "append",
        path: target,
        operation: "append",
        template: "{{ environment }}\n",
      },
      {
        id: "insert",
        path: target,
        operation: "insert_line",
        line: 3,
        template: "{{ api_token }}",
      },
    ]);
    const result = run(["request", "-"], { stdin: input });

    expect(result.code).toBe(0);
    expect(await readFile(target, "utf8")).toBe(
      "first\nprod\nhighly-secret\n",
    );
  });

  test("target replacement produces a partial result after retaining success", async () => {
    const first = join(directory, "partial-first.txt");
    const second = join(directory, "partial-second.txt");
    await writeFile(first, "");
    await writeFile(second, "");
    const input = withDeliveries(first, [
      {
        id: "first",
        path: first,
        operation: "append",
        template: "{{ environment }}",
      },
      {
        id: "second",
        path: second,
        operation: "append",
        template: "{{ api_token }}",
      },
    ]);
    const result = run(["request", "-"], {
      stdin: input,
      mode: "replace_last",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout)).toEqual({
      status: "partial",
      values: {
        environment: "prod",
        region: "us-west-2",
        features: ["audit", "alerts"],
      },
      failedDeliveries: ["second"],
      error: { code: "DELIVERY_FAILED", message: "some deliveries failed" },
    });
    expect(await readFile(first, "utf8")).toBe("prod");
    expect(result.stdout + result.stderr).not.toContain("highly-secret");
  });

  test("all failed deliveries are distinguished from partial completion", async () => {
    const target = join(directory, "all-failed.txt");
    await writeFile(target, "");
    const result = run(["request", "-"], {
      stdin: request(target),
      mode: "replace_last",
    });
    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error).toEqual({
      code: "DELIVERY_FAILED",
      message: "all deliveries failed",
    });
    expect(JSON.parse(result.stdout).failedDeliveries).toBeUndefined();
  });

  test("deadline expires while ordered delivery is in progress", async () => {
    const target = join(directory, "blocked-delivery.txt");
    await writeFile(target, "");
    const count = 2_500;
    const deliveries = Array.from({ length: count }, (_, index) => ({
      id: `delivery-${index}`,
      path: target,
      operation: "append",
      template: "{{ api_token }}",
    }));
    const result = run(["request", "-"], {
      stdin: withDeliveries(target, deliveries),
      mode: "delayed",
      timeout: "0.2",
    });
    const delivered = await readFile(target, "utf8");

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout)).toEqual({ status: "expired", values: {} });
    expect(delivered.length).toBeGreaterThan(0);
    expect(delivered.length).toBeLessThan(count * "highly-secret".length);
  });

  test("blocked helper expires", async () => {
    const target = join(directory, "expiry-target.txt");
    const marker = join(directory, "expiry-terminated.txt");
    await writeFile(target, "");
    const result = run(["request", "-"], {
      stdin: request(target),
      mode: "block",
      timeout: "0.05",
      marker,
    });
    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout)).toEqual({ status: "expired", values: {} });
    for (let attempt = 0; attempt < 20; attempt++) {
      if (await Bun.file(marker).exists()) break;
      await Bun.sleep(10);
    }
    expect(await readFile(marker, "utf8")).toBe("terminated");
  });

  test("late helper response is discarded", async () => {
    const target = join(directory, "late-response.txt");
    await writeFile(target, "");
    const result = run(["request", "-"], {
      stdin: request(target),
      mode: "late",
      timeout: "0.05",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout)).toEqual({ status: "expired", values: {} });
    expect(await readFile(target, "utf8")).toBe("");
  });

  test("secret delivery creates no log artifacts", async () => {
    const isolated = await mkdtemp(join(directory, "no-logs-"));
    const target = join(isolated, "secret.txt");
    await writeFile(target, "");
    const result = run(["request", "-"], { stdin: request(target) });

    expect(result.stdout + result.stderr).not.toContain("highly-secret");
    expect(await readdir(isolated)).toEqual(["secret.txt"]);
    expect(await readFile(target, "utf8")).toContain("highly-secret");
  });

  test("blocked explicit stdin expires without waiting for EOF", async () => {
    const process = Bun.spawn([cli, "request", "-"], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
        KEY_KONG_TEST_TIMEOUT_SECONDS: "0.05",
      },
    });
    const stdout = new Response(process.stdout).text();
    const exitCode = await process.exited;

    expect(exitCode).toBe(1);
    expect(JSON.parse(await stdout)).toEqual({ status: "expired", values: {} });
  });

  test("blocked standard output cannot outlive the deadline", async () => {
    const fifo = join(directory, "blocked-output.fifo");
    expect(Bun.spawnSync(["mkfifo", fifo]).exitCode).toBe(0);
    const descriptor = openSync(
      fifo,
      constants.O_RDWR | constants.O_NONBLOCK,
    );
    const chunk = Buffer.alloc(16 * 1024);
    try {
      while (true) writeSync(descriptor, chunk);
    } catch {
      // The full pipe is the fixture.
    }

    const process = Bun.spawn([cli, "invalid"], {
      stdout: descriptor,
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_TEST_TIMEOUT_SECONDS: "0.1",
      },
    });
    const exitCode = await Promise.race([
      process.exited,
      Bun.sleep(1_000).then(() => -1),
    ]);
    if (exitCode === -1) process.kill();
    closeSync(descriptor);

    expect(exitCode).toBe(1);
  });

  test("delivery inherits the caller sandbox", async () => {
    const target = join(directory, "sandbox-target.txt");
    const profile = join(directory, "sandbox.profile");
    await writeFile(target, "unchanged\n");
    await writeFile(
      profile,
      [
        "(version 1)",
        "(deny default)",
        "(allow process*)",
        "(allow file-read*)",
        "(allow sysctl-read)",
      ].join("\n"),
    );
    const result = Bun.spawnSync(
      ["/usr/bin/sandbox-exec", "-f", profile, cli, "request", "-"],
      {
        stdin: new TextEncoder().encode(request(target)),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...Bun.env,
          KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
          KEY_KONG_TEST_TIMEOUT_SECONDS: "5",
        },
      },
    );

    expect(result.exitCode).toBe(2);
    expect(JSON.parse(result.stdout.toString()).error.code).toBe(
      "INVALID_REQUEST",
    );
    expect(await readFile(target, "utf8")).toBe("unchanged\n");
  });
});
