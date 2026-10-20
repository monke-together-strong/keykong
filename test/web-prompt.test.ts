import { afterEach, beforeEach, expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const cli = join(root, "dist/bin/keykong");
const owner = "owner@example.com";
let directory: string;
let tailscaleLog: string;
let env: Record<string, string>;

beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), "keykong-web-"));
  const bin = join(directory, "bin");
  await mkdir(bin);
  tailscaleLog = join(directory, "tailscale.log");
  await writeFile(join(directory, "status.json"), tailscaleStatus({}));
  await writeFile(join(directory, "serve-status.json"), "{}");
  await writeFile(
    join(bin, "tailscale"),
    `#!/bin/sh\nprintf '%s\\n' "$*" >> "${tailscaleLog}"\n` +
      `[ "$1" = status ] && cat "${join(directory, "status.json")}"\n` +
      `[ "$1 $2" = "serve status" ] && cat "${join(directory, "serve-status.json")}"\n` +
      `exit 0\n`,
  );
  await chmod(join(bin, "tailscale"), 0o700);
  env = {
    ...Bun.env,
    PATH: `${bin}:${Bun.env.PATH}`,
    XDG_CONFIG_HOME: join(directory, "config"),
  } as Record<string, string>;
});

afterEach(async () => {
  await rm(directory, { recursive: true, force: true });
});

function tailscaleStatus({ tags }: { tags?: string[] }) {
  return JSON.stringify({
    Self: {
      DNSName: "wukong.example.ts.net.",
      UserID: 7,
      ...(tags ? { Tags: tags } : {}),
    },
    // Tailscale reports no user profiles for a tagged node without user peers.
    User: tags ? null : { "7": { LoginName: owner } },
  });
}

function keykong(args: string[], overrides: Record<string, string> = {}) {
  const result = Bun.spawnSync([cli, ...args], {
    env: { ...env, ...overrides },
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    code: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

async function tailscaleCalls() {
  return (await readFile(tailscaleLog, "utf8")).trimEnd().split("\n");
}

test("prompt web mounts Key Kong under the node's Tailscale HTTPS URL", async () => {
  const configured = keykong(["prompt", "web"]);

  expect(configured.code).toBe(0);
  expect(configured.stdout).toBe(
    '{"prompt":"web","url":"https://wukong.example.ts.net/keykong"}\n',
  );
  const calls = await tailscaleCalls();
  expect(calls[0]).toBe("status --json");
  expect(calls[1]).toMatch(
    /^serve --bg --yes --https=443 --set-path \/keykong http:\/\/127\.0\.0\.1:\d+$/,
  );
  // Outside the ephemeral range other programs are assigned from.
  expect(Number(calls[1]!.split(":").at(-1))).toBeLessThan(32_768);
  expect(keykong(["prompt"]).stdout).toBe(configured.stdout);
});

const origin = "https://wukong.example.ts.net";

async function configureWeb() {
  expect(keykong(["prompt", "web"]).code).toBe(0);
  const serve = (await tailscaleCalls()).at(-1)!;
  return Number(serve.match(/127\.0\.0\.1:(\d+)$/)![1]);
}

async function startRequest(
  target: string,
  { fields, deadlineMS }: { fields?: object[]; deadlineMS?: number } = {},
) {
  const file = join(directory, "request.json");
  await writeFile(
    file,
    JSON.stringify({
      id: "configure",
      title: "Configure <service>",
      fields: fields ?? [
        { id: "environment", label: "Environment", type: "text" },
        { id: "api_token", label: "API token", type: "secret" },
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
      deliveries: fields ? [] : [
        {
          id: "token",
          path: target,
          operation: "set_env",
          key: "API_TOKEN",
          field: "api_token",
        },
      ],
    }),
  );
  const process = Bun.spawn([cli, "request", file], {
    env: deadlineMS
      ? { ...env, KEY_KONG_TEST_DEADLINE_MS: String(deadlineMS) }
      : env,
    stdout: "pipe",
    stderr: "pipe",
  });
  const reader = process.stderr.getReader();
  const decoder = new TextDecoder();
  let stderr = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) throw new Error(`request ended without a URL: ${stderr}`);
    stderr += decoder.decode(value);
    const match = stderr.match(/waiting for input at (\S+)\n/);
    if (match) {
      reader.releaseLock();
      return { process, url: match[1]! };
    }
  }
}

function browser(url: string, init: RequestInit = {}, login = owner) {
  return fetch(url, {
    redirect: "manual",
    ...init,
    headers: { "Tailscale-User-Login": login, Origin: origin, ...init.headers },
  });
}

test("the allowed Tailscale user completes a web request from its page", async () => {
  const port = await configureWeb();
  const target = join(directory, "app.env");
  await writeFile(target, "");
  const { process, url } = await startRequest(target);

  expect(url).toMatch(/^https:\/\/wukong\.example\.ts\.net\/keykong\/[\w-]{22}$/);
  const local = `http://127.0.0.1:${port}/${url.split("/").at(-1)}`;
  const bookmark = await browser(`http://127.0.0.1:${port}/`);
  expect(bookmark.status).toBe(303);
  expect(bookmark.headers.get("location")).toBe(url);
  const page = await (await browser(local)).text();
  expect(page).toContain("Configure &lt;service&gt;");
  expect(page).toContain('type="password" name="api_token"');
  expect(page).toContain(target);

  const submitted = await browser(local, {
    method: "POST",
    body: new URLSearchParams([
      ["environment", "prod"],
      ["api_token", "highly-secret"],
      ["region", "us-west-2"],
      ["features", "alerts"],
      ["_action", "submit"],
    ]),
  });

  expect(submitted.status).toBe(200);
  expect(await process.exited).toBe(0);
  expect(await new Response(process.stdout).text()).toBe(
    '{"status":"completed","values":{"environment":"prod","region":"us-west-2","features":["alerts"]}}\n',
  );
  expect(await readFile(target, "utf8")).toBe('API_TOKEN="highly-secret"\n');
});

test("other tailnet users are refused and cancelling delivers nothing", async () => {
  const port = await configureWeb();
  const target = join(directory, "app.env");
  await writeFile(target, "");
  const { process, url } = await startRequest(target);
  const local = `http://127.0.0.1:${port}/${url.split("/").at(-1)}`;

  expect((await browser(local, {}, "intruder@example.com")).status).toBe(403);
  const cancelled = await browser(local, {
    method: "POST",
    body: new URLSearchParams([["_action", "cancel"]]),
  });

  expect(cancelled.status).toBe(200);
  expect(await process.exited).toBe(1);
  expect(await new Response(process.stdout).text()).toBe(
    '{"status":"cancelled","values":{}}\n',
  );
  expect(await readFile(target, "utf8")).toBe("");
});

test("a page from an earlier request cannot answer the next one", async () => {
  const port = await configureWeb();
  const target = join(directory, "app.env");
  await writeFile(target, "");
  const cancel = { method: "POST", body: new URLSearchParams([["_action", "cancel"]]) };
  const earlier = await startRequest(target);
  const earlierPage = `http://127.0.0.1:${port}/${earlier.url.split("/").at(-1)}`;
  await browser(earlierPage, cancel);
  await earlier.process.exited;

  const next = await startRequest(target);

  expect((await browser(earlierPage, cancel)).status).toBe(410);
  const nextPage = `http://127.0.0.1:${port}/${next.url.split("/").at(-1)}`;
  expect((await browser(nextPage, cancel)).status).toBe(200);
  expect(await next.process.exited).toBe(1);
});

test("a tagged node needs an explicitly allowed login", async () => {
  await writeFile(join(directory, "status.json"), tailscaleStatus({ tags: ["tag:wukong"] }));

  const refused = keykong(["prompt", "web"]);

  expect(refused.code).toBe(2);
  expect(JSON.parse(refused.stdout).error).toEqual({
    code: "CLI_USAGE",
    message: "this Tailscale node is tagged; pass --allow <login>",
  });
  expect(keykong(["prompt"]).stdout).toBe('{"prompt":"native"}\n');
  expect(keykong(["prompt", "web", "--allow", owner]).code).toBe(0);
});

test("a field named action is a value, not a page control", async () => {
  const port = await configureWeb();
  const { process, url } = await startRequest(join(directory, "app.env"), {
    fields: [{ id: "action", label: "Action", type: "text" }],
  });

  await browser(`http://127.0.0.1:${port}/${url.split("/").at(-1)}`, {
    method: "POST",
    body: new URLSearchParams([["action", "cancel"], ["_action", "submit"]]),
  });

  expect(await process.exited).toBe(0);
  expect(await new Response(process.stdout).text()).toBe(
    '{"status":"completed","values":{"action":"cancel"}}\n',
  );
});

test("a stalled browser submission cannot delay an accepted one", async () => {
  const port = await configureWeb();
  const { process, url } = await startRequest(join(directory, "app.env"), {
    fields: [{ id: "environment", label: "Environment", type: "text" }],
    deadlineMS: 2_000,
  });
  const page = `http://127.0.0.1:${port}/${url.split("/").at(-1)}`;
  const stalled = browser(page, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new ReadableStream({
      start: (controller) => controller.enqueue(new TextEncoder().encode("environment=")),
    }),
  }).catch(() => undefined);
  // Submit with well under a second of the request deadline left.
  await Bun.sleep(1_100);

  const submitted = await browser(page, {
    method: "POST",
    body: new URLSearchParams([["environment", "prod"], ["_action", "submit"]]),
  });

  expect(await submitted.text()).toContain("Submitted.");
  expect(await process.exited).toBe(0);
  expect(await new Response(process.stdout).text()).toBe(
    '{"status":"completed","values":{"environment":"prod"}}\n',
  );
  await stalled;
});

test("a request reports a taken port, and prompt web moves off it", async () => {
  const port = await configureWeb();
  const squatter = Bun.serve({
    hostname: "127.0.0.1",
    port,
    fetch: () => new Response(),
  });
  const file = join(directory, "request.json");
  await writeFile(
    file,
    JSON.stringify({
      id: "configure",
      title: "Configure",
      fields: [{ id: "environment", label: "Environment", type: "text" }],
      deliveries: [],
    }),
  );

  try {
    const request = keykong(["request", file], { KEY_KONG_TEST_DEADLINE_MS: "500" });
    expect(request.code).toBe(1);
    expect(JSON.parse(request.stdout).status).toBe("expired");
    expect(request.stderr).toContain(`keykong: port ${port} is in use; waiting for it\n`);
    expect(await configureWeb()).not.toBe(port);
  } finally {
    squatter.stop(true);
  }
});

test("invalid settings are reported until a prompt switch replaces them", async () => {
  await mkdir(join(directory, "config", "keykong"), { recursive: true });
  await writeFile(
    join(directory, "config", "keykong", "web-prompt.json"),
    '{"url":"https://wukong.example.ts.net/keykong","port":0,"allow":"owner@example.com"}',
  );

  const shown = keykong(["prompt"]);

  expect(shown.code).toBe(1);
  expect(JSON.parse(shown.stdout).error.code).toBe("PROMPT_FAILED");
  expect(keykong(["prompt", "native"]).stdout).toBe('{"prompt":"native"}\n');
  expect(keykong(["prompt"]).stdout).toBe('{"prompt":"native"}\n');
});

test("prompt native removes only this node's HTTPS mount", async () => {
  const serveStatus = (listener: string) =>
    writeFile(
      join(directory, "serve-status.json"),
      JSON.stringify({ Web: { [listener]: { Handlers: { "/keykong": {} } } } }),
    );
  const removal = "serve --https=443 --set-path /keykong off";
  await configureWeb();
  await serveStatus("wukong.example.ts.net:8443");

  expect(keykong(["prompt", "native"]).stdout).toBe('{"prompt":"native"}\n');
  expect(await tailscaleCalls()).not.toContain(removal);

  await configureWeb();
  await serveStatus("wukong.example.ts.net:443");

  expect(keykong(["prompt", "native"]).stdout).toBe('{"prompt":"native"}\n');
  expect((await tailscaleCalls()).at(-1)).toBe(removal);
  expect(keykong(["prompt"]).stdout).toBe('{"prompt":"native"}\n');
});

test("prompt native needs Tailscale only once web settings exist", async () => {
  const missing = { PATH: join(directory, "missing") };
  expect(keykong(["prompt", "native"], missing).stdout).toBe('{"prompt":"native"}\n');
  await configureWeb();

  const native = keykong(["prompt", "native"], missing);

  expect(native.code).toBe(1);
  expect(JSON.parse(native.stdout).error.code).toBe("PROMPT_FAILED");
  expect(JSON.parse(keykong(["prompt"]).stdout).prompt).toBe("web");
});
