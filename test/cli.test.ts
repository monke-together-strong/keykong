import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  closeSync,
  constants,
  openSync,
  writeSync,
} from "node:fs";
import {
  chmod,
  link as createHardLink,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
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

function deliveryRequest(path: string) {
  return JSON.stringify({
    schemaVersion: 1,
    id: "deploy-secret",
    title: "Deploy secret",
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
        template:
          "{{ environment }} {{ region }} {{ features }} {{ api_token }}\n",
      },
    ],
  });
}

function withDeliveries(
  path: string,
  deliveries: Array<Record<string, unknown>>,
) {
  const value = JSON.parse(deliveryRequest(path));
  value.deliveries = deliveries;
  return JSON.stringify(value);
}

function setEnvRequest(path: string, key = "API_TOKEN", field = "api_token") {
  return withDeliveries(path, [
    {
      id: "environment_assignment",
      path,
      operation: "set_env",
      key,
      field,
    },
  ]);
}

const nodeParseEnvScript = `
const { readFileSync } = require("node:fs");
const { parseEnv } = require("node:util");

const content = readFileSync(0, "utf8");
process.stdout.write(JSON.stringify(parseEnv(content)));
`;

function parseWithNode(content: string): Record<string, string> {
  const process = Bun.spawnSync(
    ["node", "-e", nodeParseEnvScript],
    {
      stdin: new TextEncoder().encode(content),
      stdout: "pipe",
      stderr: "pipe",
    },
  );
  if (process.exitCode !== 0) {
    throw new Error(
      `Node parseEnv failed: ${process.stderr.toString().trim()}`,
    );
  }
  return JSON.parse(process.stdout.toString());
}

function run(
  args: string[],
  options: {
    stdin?: string;
    mode?: string;
    marker?: string;
    pidMarker?: string;
    deadlineMS?: number;
    internalFailure?: boolean;
    secret?: string;
  } = {},
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
      ...(options.pidMarker
        ? { KEY_KONG_FAKE_PID_MARKER: options.pidMarker }
        : {}),
      ...(options.deadlineMS
        ? { KEY_KONG_TEST_DEADLINE_MS: String(options.deadlineMS) }
        : {}),
      ...(options.internalFailure
        ? { KEY_KONG_TEST_INTERNAL_FAILURE: "1" }
        : {}),
      ...(options.secret === undefined
        ? {}
        : { KEY_KONG_FAKE_SECRET: options.secret }),
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
    expect(schema.$defs.delivery.oneOf).toEqual([
      { $ref: "#/$defs/appendDelivery" },
      { $ref: "#/$defs/insertLineDelivery" },
      { $ref: "#/$defs/setEnvDelivery" },
    ]);
    expect(schema.$defs.setEnvDelivery.required).toEqual([
      "id",
      "path",
      "operation",
      "key",
      "field",
    ]);
    expect(schema.$defs.setEnvDelivery.properties.operation.const).toBe(
      "set_env",
    );
    expect(schema.$defs.setEnvDelivery.properties.key.pattern).toBe(
      "^[A-Za-z_][A-Za-z0-9_]*$",
    );
    expect(schema.$defs.appendDelivery.required).toEqual([
      "id",
      "path",
      "operation",
      "template",
    ]);
    expect(schema.$defs.insertLineDelivery.required).toEqual([
      "id",
      "path",
      "operation",
      "line",
      "template",
    ]);
    expect(schema.properties.fields.maxItems).toBe(256);
    expect(schema.properties.deliveries.maxItems).toBe(256);
    expect(schema.$defs.field.properties.options.maxItems).toBe(256);
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

  test("cancellation requires a clean helper exit", () => {
    const result = run(["request", "-"], {
      stdin: request(),
      mode: "cancel_nonzero",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error.code).toBe("PROMPT_FAILED");
  });

  test("a blocked helper is terminated at the whole-request deadline", async () => {
    const pidMarker = join(directory, "blocked-helper.pid");
    const started = performance.now();
    const result = run(["request", "-"], {
      stdin: request(),
      mode: "block",
      deadlineMS: 100,
      pidMarker,
    });

    expect(performance.now() - started).toBeLessThan(1_000);
    expect(result.code).toBe(1);
    expect(result.stdout).toBe('{"status":"expired","values":{}}\n');
    expect(result.stderr).toBe("request deadline expired\n");
    const helperPID = Number(await readFile(pidMarker, "utf8"));
    expect(() => process.kill(helperPID, 0)).toThrow();
  });

  test("a helper resisting graceful termination is forcefully reaped", async () => {
    const pidMarker = join(directory, "resistant-helper.pid");
    const started = performance.now();
    const result = run(["request", "-"], {
      stdin: request(),
      mode: "resist_termination",
      deadlineMS: 100,
      pidMarker,
    });

    expect(performance.now() - started).toBeLessThan(1_000);
    expect(result.code).toBe(1);
    expect(result.stdout).toBe('{"status":"expired","values":{}}\n');
    const helperPID = Number(await readFile(pidMarker, "utf8"));
    expect(() => process.kill(helperPID, 0)).toThrow();
  });

  test("a late helper response is discarded after expiry", () => {
    const result = run(["request", "-"], {
      stdin: request(),
      mode: "late",
      deadlineMS: 100,
    });

    expect(result.code).toBe(1);
    expect(result.stdout).toBe('{"status":"expired","values":{}}\n');
  });

  test("invalid response request is rejected before launching the helper", async () => {
    const marker = join(directory, "invalid-launched");
    const input = request().replace('"schemaVersion":1', '"schemaVersion":2');

    const result = run(["request", "-"], { stdin: input, marker });

    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout).error.code).toBe("INVALID_REQUEST");
    expect(await Bun.file(marker).exists()).toBeFalse();
  });

  test("oversized requests are rejected before parsing or prompting", async () => {
    const marker = join(directory, "oversized-launched");
    const result = run(["request", "-"], {
      stdin: request() + " ".repeat(1_048_577),
      marker,
    });

    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout).error).toEqual({
      code: "INVALID_REQUEST",
      message: "request exceeds 1048576 bytes",
    });
    expect(await Bun.file(marker).exists()).toBeFalse();
  });

  test("a secret without a delivery is rejected before launching the helper", async () => {
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

  test("delivery renders every field kind and omits the secret from results", async () => {
    const target = join(directory, "completed.txt");
    await writeFile(target, "");

    const result = run(["request", "-"], { stdin: deliveryRequest(target) });

    expect(result.code).toBe(0);
    expect(result.stdout).toBe(
      '{"status":"completed","values":{"environment":"prod","region":"us-west-2","features":["audit","alerts"]}}\n',
    );
    expect(result.stdout + result.stderr).not.toContain("highly-secret");
    expect(await readFile(target, "utf8")).toBe(
      'prod us-west-2 ["audit","alerts"] highly-secret\n',
    );
  });

  test("set_env appends a missing key without exposing its secret field", async () => {
    const target = join(directory, "set-env-empty.env");
    await writeFile(target, "");

    const result = run(["request", "-"], { stdin: setEnvRequest(target) });

    expect(result.code).toBe(0);
    expect(result.stdout + result.stderr).not.toContain("highly-secret");
    const content = await readFile(target, "utf8");
    expect(content).toBe('API_TOKEN="highly-secret"\n');
    expect(parseWithNode(content).API_TOKEN).toBe("highly-secret");
  });

  test("set_env preserves assignment prefixes and the target line style", async () => {
    const cases = [
      {
        name: "final-lf",
        before: "OTHER=one\n",
        after: 'OTHER=one\nAPI_TOKEN="highly-secret"\n',
      },
      {
        name: "missing-final-newline",
        before: "OTHER=one",
        after: 'OTHER=one\nAPI_TOKEN="highly-secret"\n',
      },
      {
        name: "crlf",
        before: "OTHER=one\r\n",
        after: 'OTHER=one\r\nAPI_TOKEN="highly-secret"\r\n',
      },
      {
        name: "unquoted",
        before: "API_TOKEN=old\n",
        after: 'API_TOKEN="highly-secret"\n',
      },
      {
        name: "shorter-replacement",
        before: "API_TOKEN=a-very-long-value-that-must-be-truncated\nAFTER=one\n",
        after: 'API_TOKEN="highly-secret"\nAFTER=one\n',
      },
      {
        name: "whitespace-only",
        before: "API_TOKEN= \n",
        after: 'API_TOKEN="highly-secret"\n',
      },
      {
        name: "whitespace-before-comment",
        before: "API_TOKEN= \n# stop\nOTHER=one\n",
        after: 'API_TOKEN="highly-secret"\n# stop\nOTHER=one\n',
      },
      {
        name: "unrelated-whitespace-at-eof",
        before: "API_TOKEN=old\nOTHER= ",
        after: 'API_TOKEN="highly-secret"\nOTHER= ',
      },
      {
        name: "double-quoted",
        before: 'API_TOKEN="old value"\n',
        after: 'API_TOKEN="highly-secret"\n',
      },
      {
        name: "formatted-export",
        before: "  export API_TOKEN  = 'old' # stale\r\n",
        after: '  export API_TOKEN  ="highly-secret"\r\n',
      },
      {
        name: "export-space-tab",
        before: "export \tAPI_TOKEN=old\n",
        after: 'export \tAPI_TOKEN="highly-secret"\n',
      },
      {
        name: "export-tab-is-key",
        before: "export\tAPI_TOKEN=old\n",
        after:
          'export\tAPI_TOKEN=old\nAPI_TOKEN="highly-secret"\n',
      },
      {
        name: "comments-and-case",
        before: "# API_TOKEN=old\napi_token=other\n",
        after:
          '# API_TOKEN=old\napi_token=other\nAPI_TOKEN="highly-secret"\n',
      },
      {
        name: "skipped-empty-key-line",
        before: "=ignored\nOTHER=one\n",
        after:
          '=ignored\nOTHER=one\nAPI_TOKEN="highly-secret"\n',
      },
    ];

    for (const testCase of cases) {
      const target = join(directory, `custom-${testCase.name}.settings`);
      await writeFile(target, testCase.before);

      const result = run(["request", "-"], { stdin: setEnvRequest(target) });

      expect(result.code).toBe(0);
      expect(await readFile(target, "utf8")).toBe(testCase.after);
    }
  });

  test("set_env chooses the first lossless Node dotenv representation", async () => {
    const cases = [
      {
        name: "double",
        value: "spaces $dollars \\\\slashes # hashes",
        assignment: 'API_TOKEN="spaces $dollars \\\\slashes # hashes"\n',
      },
      {
        name: "node-backslash",
        value: String.raw`literal\rsequence`,
        assignment: String.raw`API_TOKEN="literal\rsequence"` + "\n",
      },
      {
        name: "node-backslash-n",
        value: String.raw`literal\nsequence`,
        assignment: String.raw`API_TOKEN='literal\nsequence'` + "\n",
      },
      {
        name: "unmatched-leading-quote",
        value: '"abc\'#hash',
        assignment: 'API_TOKEN="abc\'#hash\n',
      },
      {
        name: "single",
        value: 'contains "double" quotes',
        assignment: 'API_TOKEN=\'contains "double" quotes\'\n',
      },
      {
        name: "unquoted",
        value: 'both"quotes\'stay',
        assignment: 'API_TOKEN=both"quotes\'stay\n',
      },
      {
        name: "unquoted-non-ascii-whitespace",
        value: ' both"quotes\'stay ',
        assignment: 'API_TOKEN= both"quotes\'stay \n',
      },
    ];

    for (const testCase of cases) {
      const target = join(directory, `serialized-${testCase.name}.env`);
      await writeFile(target, "");

      const result = run(["request", "-"], {
        stdin: setEnvRequest(target),
        secret: testCase.value,
      });

      expect(result.code).toBe(0);
      const content = await readFile(target, "utf8");
      expect(content).toBe(testCase.assignment);
      expect(parseWithNode(content).API_TOKEN).toBe(testCase.value);
    }
  });

  test("set_env rejects unsupported target content before prompting", async () => {
    const cases: Array<{ name: string; content: string | Buffer }> = [
      {
        name: "duplicate-key",
        content: "API_TOKEN=one\nexport API_TOKEN=two\n",
      },
      {
        name: "invalid-utf8",
        content: Buffer.from([0x41, 0x50, 0x49, 0x3d, 0xff, 0x0a]),
      },
      {
        name: "multiline-quoted-assignment",
        content: 'OTHER="first\nsecond"\n',
      },
      {
        name: "multiline-broad-key",
        content: 'BAD-KEY="first\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "multiline-leading-equals",
        content: '==  export A="first\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "multiline-export-hash-key",
        content: 'export #BAD="first\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "multiline-export-empty-key",
        content: 'export ="first\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "multiline-unicode-line-separator",
        content: 'OTHER="first\u2028\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "multiline-unicode-paragraph-separator",
        content: 'OTHER="first\u2029\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "cross-line-whitespace-assignment",
        content: "OTHER= \nAPI_TOKEN=shadow\n",
      },
      {
        name: "target-cross-line-whitespace-assignment",
        content: "API_TOKEN= \nOTHER=one\n",
      },
      {
        name: "whitespace-before-appended-target",
        content: "OTHER= ",
      },
      {
        name: "empty-key-prefixed-assignment",
        content: "=API_TOKEN=shadow\n",
      },
      {
        name: "empty-key-prefixed-duplicate",
        content: "=API_TOKEN=one\nAPI_TOKEN=two\n",
      },
      {
        name: "spaced-empty-key-prefixed-assignment",
        content: "= =API_TOKEN=shadow\n",
      },
      {
        name: "bom-prefixed-multiline-assignment",
        content: '\uFEFF# OTHER="first\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "nbsp-prefixed-multiline-assignment",
        content: '\u00A0# OTHER="first\nAPI_TOKEN=shadow\nsecond"\n',
      },
      {
        name: "mixed-line-endings",
        content: "ONE=1\r\nTWO=2\n",
      },
    ];

    for (const testCase of cases) {
      const target = join(directory, `unsupported-${testCase.name}.env`);
      const marker = join(directory, `unsupported-${testCase.name}.launched`);
      await writeFile(target, testCase.content);
      const before = await readFile(target);

      const result = run(["request", "-"], {
        stdin: setEnvRequest(target),
        marker,
      });

      expect(result.code).toBe(2);
      expect(JSON.parse(result.stdout).error.code).toBe("INVALID_REQUEST");
      expect(await Bun.file(marker).exists()).toBeFalse();
      expect(await readFile(target)).toEqual(before);
    }
  });

  test("set_env fails unchanged when no lossless representation exists", async () => {
    const target = join(directory, "unrepresentable.env");
    await writeFile(target, "API_TOKEN=old\n");
    const value = ' leading "double" and \'single\' # trailing ';

    const result = run(["request", "-"], {
      stdin: setEnvRequest(target),
      secret: value,
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error.code).toBe("DELIVERY_FAILED");
    expect(result.stdout + result.stderr).not.toContain(value);
    expect(await readFile(target, "utf8")).toBe("API_TOKEN=old\n");
  });

  test("set_env rejects physical newlines before delivery", async () => {
    const target = join(directory, "multiline-submission.env");
    await writeFile(target, "API_TOKEN=old\n");

    const result = run(["request", "-"], {
      stdin: setEnvRequest(target),
      secret: 'left\nright"\'',
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error.code).toBe("PROMPT_FAILED");
    expect(await readFile(target, "utf8")).toBe("API_TOKEN=old\n");
  });

  test("set_env policy is rejected before launching the Prompt Adapter", async () => {
    const target = join(directory, "set-env-validated.env");
    const link = join(directory, "set-env-validated-link.env");
    const directoryTarget = join(directory, "set-env-directory");
    const inaccessibleTarget = join(directory, "set-env-inaccessible.env");
    const hardlinkTarget = join(directory, "set-env-hardlink.env");
    await writeFile(target, "");
    await writeFile(inaccessibleTarget, "");
    await createHardLink(target, hardlinkTarget);
    await chmod(inaccessibleTarget, 0o400);
    await symlink(target, link);
    await mkdir(directoryTarget);
    const cases = [
      {
        name: "invalid-key",
        input: setEnvRequest(target, "NOT-VALID"),
      },
      {
        name: "unknown-field",
        input: setEnvRequest(target, "TOKEN", "missing"),
      },
      {
        name: "multi-select-field",
        input: setEnvRequest(target, "FEATURES", "features"),
      },
      {
        name: "template-property",
        input: withDeliveries(target, [{
          id: "forbidden-template",
          path: target,
          operation: "set_env",
          key: "TOKEN",
          field: "api_token",
          template: "{{ api_token }}",
        }]),
      },
      {
        name: "dialect-property",
        input: withDeliveries(target, [{
          id: "forbidden-dialect",
          path: target,
          operation: "set_env",
          key: "TOKEN",
          field: "api_token",
          dialect: "node",
        }]),
      },
      {
        name: "line-property",
        input: withDeliveries(target, [{
          id: "forbidden-line",
          path: target,
          operation: "set_env",
          key: "TOKEN",
          field: "api_token",
          line: 1,
        }]),
      },
      {
        name: "repeated-path-key",
        input: withDeliveries(target, [
          {
            id: "first",
            path: target,
            operation: "set_env",
            key: "TOKEN",
            field: "api_token",
          },
          {
            id: "second",
            path: target,
            operation: "set_env",
            key: "TOKEN",
            field: "api_token",
          },
        ]),
      },
      {
        name: "repeated-identity-key",
        input: withDeliveries(target, [
          {
            id: "first",
            path: target,
            operation: "set_env",
            key: "TOKEN",
            field: "api_token",
          },
          {
            id: "second",
            path: hardlinkTarget,
            operation: "set_env",
            key: "TOKEN",
            field: "api_token",
          },
        ]),
      },
      {
        name: "missing-target",
        input: setEnvRequest(join(directory, "does-not-exist.env")),
      },
      {
        name: "relative-target",
        input: setEnvRequest("relative.env"),
      },
      {
        name: "symlink-target",
        input: setEnvRequest(link),
      },
      {
        name: "non-regular-target",
        input: setEnvRequest(directoryTarget),
      },
      {
        name: "inaccessible-target",
        input: setEnvRequest(inaccessibleTarget),
      },
    ];

    try {
      for (const testCase of cases) {
        const marker = join(directory, `set-env-${testCase.name}.launched`);
        const result = run(["request", "-"], {
          stdin: testCase.input,
          marker,
        });

        expect(result.code).toBe(2);
        expect(JSON.parse(result.stdout).error.code).toBe("INVALID_REQUEST");
        expect(await Bun.file(marker).exists()).toBeFalse();
      }
    } finally {
      await chmod(inaccessibleTarget, 0o600);
    }
  });

  test("set_env accepts text and single-select source fields", async () => {
    const cases = [
      { field: "environment", key: "ENVIRONMENT", value: "prod" },
      { field: "region", key: "REGION", value: "us-west-2" },
    ];

    for (const testCase of cases) {
      const target = join(directory, `source-${testCase.field}.env`);
      await writeFile(target, "");
      const input = JSON.parse(request());
      input.deliveries = [{
        id: `set_${testCase.field}`,
        path: target,
        operation: "set_env",
        key: testCase.key,
        field: testCase.field,
      }];

      const result = run(["request", "-"], {
        stdin: JSON.stringify(input),
      });

      expect(result.code).toBe(0);
      expect(await readFile(target, "utf8")).toBe(
        `${testCase.key}="${testCase.value}"\n`,
      );
    }
  });

  test("different set_env keys stay ordered with existing operations", async () => {
    const target = join(directory, "set-env-ordered.env");
    await writeFile(target, "");
    const input = withDeliveries(target, [
      {
        id: "environment",
        path: target,
        operation: "set_env",
        key: "ENVIRONMENT",
        field: "environment",
      },
      {
        id: "comment",
        path: target,
        operation: "insert_line",
        line: 2,
        template: "# {{ region }}",
      },
      {
        id: "token",
        path: target,
        operation: "set_env",
        key: "API_TOKEN",
        field: "api_token",
      },
    ]);

    const result = run(["request", "-"], { stdin: input });

    expect(result.code).toBe(0);
    expect(await readFile(target, "utf8")).toBe(
      'ENVIRONMENT="prod"\n# us-west-2\nAPI_TOKEN="highly-secret"\n',
    );

    const hardlinkTarget = join(directory, "set-env-ordered-hardlink.env");
    const alias = join(directory, "set-env-ordered-hardlink-alias.env");
    await writeFile(hardlinkTarget, "");
    await createHardLink(hardlinkTarget, alias);
    const hardlinkInput = withDeliveries(hardlinkTarget, [
      {
        id: "environment",
        path: hardlinkTarget,
        operation: "set_env",
        key: "API_TOKEN",
        field: "api_token",
      },
      {
        id: "comment",
        path: alias,
        operation: "insert_line",
        line: 2,
        template: "# {{ region }}",
      },
    ]);

    const hardlinkResult = run(["request", "-"], {
      stdin: hardlinkInput,
    });

    expect(hardlinkResult.code).toBe(0);
    expect(await readFile(hardlinkTarget, "utf8")).toBe(
      'API_TOKEN="highly-secret"\n# us-west-2\n',
    );
  });

  test("a later failed set_env retains an earlier Environment Assignment", async () => {
    const first = join(directory, "set-env-partial-first.env");
    const second = join(directory, "set-env-partial-second.env");
    await writeFile(first, "");
    await writeFile(second, "");
    const input = withDeliveries(first, [
      {
        id: "first",
        path: first,
        operation: "set_env",
        key: "API_TOKEN",
        field: "api_token",
      },
      {
        id: "second",
        path: second,
        operation: "set_env",
        key: "API_TOKEN",
        field: "api_token",
      },
    ]);

    const result = run(["request", "-"], {
      stdin: input,
      mode: "replace_last",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).failedDeliveries).toEqual(["second"]);
    expect(result.stdout + result.stderr).not.toContain("highly-secret");
    expect(await readFile(first, "utf8")).toBe(
      'API_TOKEN="highly-secret"\n',
    );
    expect(await readFile(second, "utf8")).toBe("");
  });

  test("a later set_env cannot close an earlier unquoted fallback", async () => {
    const target = join(directory, "set-env-unmatched-quote.env");
    await writeFile(target, "");
    const input = withDeliveries(target, [
      {
        id: "first",
        path: target,
        operation: "set_env",
        key: "FIRST",
        field: "api_token",
      },
      {
        id: "second",
        path: target,
        operation: "set_env",
        key: "SECOND",
        field: "environment",
      },
    ]);
    const secret = '"abc\'#hash';

    const result = run(["request", "-"], {
      stdin: input,
      secret,
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).failedDeliveries).toEqual(["second"]);
    expect(result.stdout + result.stderr).not.toContain(secret);
    const content = await readFile(target, "utf8");
    expect(content).toBe(`FIRST=${secret}\n`);
    expect(parseWithNode(content).FIRST).toBe(secret);
  });

  test("a later template delivery cannot invalidate set_env", async () => {
    const secret = '"abc\'#hash';
    for (const operation of ["append", "insert_line"] as const) {
      const target = join(directory, `set-env-before-${operation}.env`);
      await writeFile(target, "");
      const input = withDeliveries(target, [
        {
          id: "first",
          path: target,
          operation: "set_env",
          key: "FIRST",
          field: "api_token",
        },
        {
          id: "second",
          path: target,
          operation,
          ...(operation === "insert_line" ? { line: 2 } : {}),
          template: '# "{{ environment }}"\n',
        },
      ]);

      const result = run(["request", "-"], {
        stdin: input,
        secret,
      });

      expect(result.code).toBe(1);
      expect(JSON.parse(result.stdout).failedDeliveries).toEqual(["second"]);
      expect(result.stdout + result.stderr).not.toContain(secret);
      const content = await readFile(target, "utf8");
      expect(content).toBe(`FIRST=${secret}\n`);
      expect(parseWithNode(content).FIRST).toBe(secret);
    }

    const target = join(directory, "set-env-before-hardlink.env");
    const alias = join(directory, "set-env-before-hardlink-alias.env");
    await writeFile(target, "");
    await createHardLink(target, alias);
    const input = withDeliveries(target, [
      {
        id: "first",
        path: target,
        operation: "set_env",
        key: "FIRST",
        field: "api_token",
      },
      {
        id: "second",
        path: alias,
        operation: "append",
        template: '# "{{ environment }}"\n',
      },
    ]);

    const result = run(["request", "-"], {
      stdin: input,
      secret,
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).failedDeliveries).toEqual(["second"]);
    expect(await readFile(target, "utf8")).toBe(`FIRST=${secret}\n`);

    const duplicateTarget = join(directory, "set-env-before-duplicate.env");
    await writeFile(duplicateTarget, "");
    const duplicateInput = withDeliveries(duplicateTarget, [
      {
        id: "first",
        path: duplicateTarget,
        operation: "set_env",
        key: "FIRST",
        field: "api_token",
      },
      {
        id: "second",
        path: duplicateTarget,
        operation: "append",
        template: "FIRST={{ environment }}\n",
      },
    ]);

    const duplicateResult = run(["request", "-"], {
      stdin: duplicateInput,
    });

    expect(duplicateResult.code).toBe(1);
    expect(JSON.parse(duplicateResult.stdout).failedDeliveries).toEqual([
      "second",
    ]);
    expect(await readFile(duplicateTarget, "utf8")).toBe(
      'FIRST="highly-secret"\n',
    );
  });

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

  test("line simulation accounts for an inserted template ending in a field", async () => {
    const target = join(directory, "rendered-lines.txt");
    await writeFile(target, "one\n");
    const input = withDeliveries(target, [
      {
        id: "first",
        path: target,
        operation: "insert_line",
        line: 2,
        template: "header\n{{ api_token }}",
      },
      {
        id: "second",
        path: target,
        operation: "insert_line",
        line: 4,
        template: "{{ environment }}",
      },
    ]);

    const result = run(["request", "-"], { stdin: input });

    expect(result.code).toBe(0);
    expect(await readFile(target, "utf8")).toBe(
      "one\nheader\nhighly-secret\nprod\n",
    );
  });

  test("target replacement returns partial after retaining completed deliveries", async () => {
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
    expect(await readFile(second, "utf8")).toBe("");
    expect(result.stdout + result.stderr).not.toContain("highly-secret");
  });

  test("all failed deliveries return failed without delivery IDs", async () => {
    const target = join(directory, "all-failed.txt");
    await writeFile(target, "");

    const result = run(["request", "-"], {
      stdin: deliveryRequest(target),
      mode: "replace_last",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout)).toEqual({
      status: "failed",
      values: {
        environment: "prod",
        region: "us-west-2",
        features: ["audit", "alerts"],
      },
      error: { code: "DELIVERY_FAILED", message: "all deliveries failed" },
    });
    expect(await readFile(target, "utf8")).toBe("");
  });

  test("delivery policy is validated before launching the helper", async () => {
    const target = join(directory, "validated.txt");
    const link = join(directory, "validated-link.txt");
    await writeFile(target, "one\n");
    await symlink(target, link);
    const cases = [
      {
        name: "invalid delivery ID",
        input: withDeliveries(target, [
          {
            id: "not valid",
            path: target,
            operation: "append",
            template: "{{ api_token }}",
          },
        ]),
      },
      {
        name: "unknown template field",
        input: withDeliveries(target, [
          {
            id: "unknown",
            path: target,
            operation: "append",
            template: "{{ missing }}",
          },
        ]),
      },
      {
        name: "relative target",
        input: withDeliveries(target, [
          {
            id: "relative",
            path: "relative.txt",
            operation: "append",
            template: "{{ api_token }}",
          },
        ]),
      },
      {
        name: "symlink target",
        input: withDeliveries(target, [
          {
            id: "symlink",
            path: link,
            operation: "append",
            template: "{{ api_token }}",
          },
        ]),
      },
      {
        name: "invalid insertion line",
        input: withDeliveries(target, [
          {
            id: "line",
            path: target,
            operation: "insert_line",
            line: 3,
            template: "{{ api_token }}",
          },
        ]),
      },
    ];

    for (const testCase of cases) {
      const marker = join(
        directory,
        `validation-${testCase.name.replaceAll(" ", "-")}`,
      );
      const result = run(["request", "-"], {
        stdin: testCase.input,
        marker,
      });
      expect(JSON.parse(result.stdout).error.code).toBe("INVALID_REQUEST");
      expect(await Bun.file(marker).exists()).toBeFalse();
    }
    expect(await readFile(target, "utf8")).toBe("one\n");
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
        stdin: new TextEncoder().encode(deliveryRequest(target)),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...Bun.env,
          KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
          KEY_KONG_FAKE_MODE: "submit",
        },
      },
    );

    expect(result.exitCode).toBe(2);
    expect(JSON.parse(result.stdout.toString()).error.code).toBe(
      "INVALID_REQUEST",
    );
    expect(await readFile(target, "utf8")).toBe("unchanged\n");
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

  test("empty submitted fields fail before delivery", async () => {
    const target = join(directory, "empty-submission.txt");
    await writeFile(target, "unchanged\n");

    const result = run(["request", "-"], {
      stdin: deliveryRequest(target),
      mode: "empty",
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error.code).toBe("PROMPT_FAILED");
    expect(await readFile(target, "utf8")).toBe("unchanged\n");
  });

  test("native helper faults return sanitized prompt failures", () => {
    for (const mode of ["malformed", "extra", "eof", "nonzero", "crash"]) {
      const result = run(["request", "-"], { stdin: request(), mode });

      expect(result.code).toBe(1);
      expect(JSON.parse(result.stdout).error).toEqual({
        code: "PROMPT_FAILED",
        message: "native prompt returned an invalid response",
      });
      expect(result.stdout + result.stderr).not.toContain("raw-native-secret");
    }
  });

  test("deadline covers blocked request input", async () => {
    const child = Bun.spawn([cli, "request", "-"], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
        KEY_KONG_TEST_DEADLINE_MS: "100",
      },
    });

    expect(await child.exited).toBe(1);
    expect(await new Response(child.stdout).text()).toBe(
      '{"status":"expired","values":{}}\n',
    );
  });

  test("deadline covers delivery work", async () => {
    const target = join(directory, "blocked-delivery.txt");
    const pidMarker = join(directory, "delivery-worker.pid");
    await writeFile(target, "");
    const child = Bun.spawn([cli, "request", "-"], {
      stdin: new TextEncoder().encode(deliveryRequest(target)),
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
        KEY_KONG_TEST_DEADLINE_MS: "100",
        KEY_KONG_TEST_BLOCK_WRITE_MS: "200",
        KEY_KONG_TEST_DELIVERY_PID_MARKER: pidMarker,
      },
    });

    expect(await child.exited).toBe(1);
    expect(await new Response(child.stdout).text()).toBe(
      '{"status":"expired","values":{}}\n',
    );
    expect(Number(await readFile(pidMarker, "utf8"))).toBe(child.pid);
    await Bun.sleep(250);
    expect(await readFile(target, "utf8")).toBe("");
  });

  test("deadline stops set_env before a blocked write", async () => {
    const target = join(directory, "blocked-set-env.env");
    await writeFile(target, "API_TOKEN=old\n");
    const child = Bun.spawn([cli, "request", "-"], {
      stdin: new TextEncoder().encode(setEnvRequest(target)),
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
        KEY_KONG_TEST_DEADLINE_MS: "100",
        KEY_KONG_TEST_BLOCK_WRITE_MS: "200",
      },
    });

    expect(await child.exited).toBe(1);
    expect(await new Response(child.stdout).text()).toBe(
      '{"status":"expired","values":{}}\n',
    );
    await Bun.sleep(250);
    expect(await readFile(target, "utf8")).toBe("API_TOKEN=old\n");
  });

  test("blocked caller output cannot extend the process deadline", async () => {
    const child = Bun.spawn([cli, "request", "-"], {
      stdin: new TextEncoder().encode(request()),
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
        KEY_KONG_FAKE_MODE: "large",
        KEY_KONG_TEST_DEADLINE_MS: "300",
      },
    });

    const exitCode = await Promise.race([
      child.exited,
      Bun.sleep(1_000).then(() => -1),
    ]);
    if (exitCode === -1) child.kill();
    expect(exitCode).not.toBe(-1);
  });

  test("blocked expired-result output cannot extend the process deadline", async () => {
    const fifo = join(directory, "blocked-expired-output.fifo");
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

    const child = Bun.spawn([cli, "request", "-"], {
      stdin: "pipe",
      stdout: descriptor,
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_PROMPT_EXECUTABLE: fakePrompt,
        KEY_KONG_TEST_DEADLINE_MS: "100",
      },
    });
    const exitCode = await Promise.race([
      child.exited,
      Bun.sleep(1_000).then(() => -1),
    ]);
    if (exitCode === -1) child.kill();
    closeSync(descriptor);

    expect(exitCode).toBe(1);
  });

  test("unexpected failures use the stable internal error category", () => {
    const result = run(["request", "-"], {
      stdin: request(),
      internalFailure: true,
    });

    expect(result.code).toBe(1);
    expect(JSON.parse(result.stdout).error).toEqual({
      code: "INTERNAL_FAILURE",
      message: "unexpected internal failure",
    });
  });

  test("production build ignores the test helper environment override", async () => {
    const layout = join(directory, "production");
    const bin = join(layout, "bin");
    const libexec = join(layout, "libexec");
    const productionCLI = join(bin, "key-kong");
    const bundledHelper = join(
      libexec,
      "KeyKongPrompt.app/Contents/MacOS/key-kong-prompt",
    );
    const overrideHelper = join(layout, "override-prompt");
    await mkdir(bin, { recursive: true });
    await mkdir(resolve(bundledHelper, ".."), { recursive: true });
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
        join(root, "src/delivery-worker.ts"),
      ],
      { stdout: "pipe", stderr: "pipe" },
    );
    expect(build.exitCode).toBe(0);

    const result = Bun.spawnSync([productionCLI, "request", "-"], {
      stdin: new TextEncoder().encode(request()),
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...Bun.env,
        KEY_KONG_PROMPT_EXECUTABLE: overrideHelper,
        KEY_KONG_TEST_INTERNAL_FAILURE: "1",
        KEY_KONG_TEST_DEADLINE_MS: "1",
      },
    });

    expect(result.exitCode).toBe(0);
    expect(JSON.parse(result.stdout.toString()).status).toBe("completed");
  });

});
