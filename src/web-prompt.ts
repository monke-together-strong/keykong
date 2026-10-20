import { randomBytes } from "node:crypto";
import { mkdir, rm } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { Deadline } from "./deadline";
import { KeyKongError } from "./errors";
import { requestLimits } from "./limits";
import type {
  Delivery,
  PromptResponse,
  Request,
  ResponseValue,
} from "./types";
import { validateSubmission } from "./validation";

export interface WebPromptSettings {
  url: string;
  port: number;
  allow: string;
}

function settingsPath(): string {
  const base = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  return join(base, "keykong", "web-prompt.json");
}

export async function readWebPromptSettings(): Promise<
  WebPromptSettings | undefined
> {
  const file = Bun.file(settingsPath());
  if (!(await file.exists())) return undefined;
  try {
    const value = await file.json();
    if (
      typeof value.url === "string" &&
      Number.isInteger(value.port) &&
      typeof value.allow === "string"
    ) {
      return { url: value.url, port: value.port, allow: value.allow };
    }
  } catch {}
  throw new KeyKongError(
    "PROMPT_FAILED",
    `web prompt settings are invalid: ${settingsPath()}`,
    1,
  );
}

export async function writeWebPromptSettings(settings: WebPromptSettings) {
  await mkdir(dirname(settingsPath()), { recursive: true });
  await Bun.write(settingsPath(), `${JSON.stringify(settings)}\n`);
}

export async function removeWebPromptSettings() {
  await rm(settingsPath(), { force: true });
}

export async function webPrompt(
  request: Request,
  settings: WebPromptSettings,
  deadline: Deadline,
): Promise<PromptResponse> {
  const id = randomBytes(16).toString("base64url");
  const url = `${settings.url}/${id}`;
  const { promise, resolve } = Promise.withResolvers<PromptResponse>();
  let finished = false;
  const finish = (response: PromptResponse) => {
    finished = true;
    resolve(response);
  };

  const server = await listen(settings.port, deadline, async (incoming) => {
    if (incoming.headers.get("tailscale-user-login") !== settings.allow) {
      return page(403, "<p>This Key Kong request is not available to you.</p>");
    }
    const path = new URL(incoming.url).pathname;
    if (path === "/" && !finished) {
      return new Response(null, { status: 303, headers: { Location: url } });
    }
    if (path !== `/${id}` || finished) {
      return page(410, "<p>This Key Kong request has ended.</p>");
    }
    if (incoming.method === "GET") return page(200, form(request));
    if (
      incoming.method !== "POST" ||
      incoming.headers.get("origin") !== new URL(settings.url).origin
    ) {
      return page(403, "<p>This submission was rejected.</p>");
    }

    const submitted = await incoming.formData().catch(() => undefined);
    if (!submitted) {
      return page(400, form(request, "The submission could not be read."));
    }
    if (finished) return page(410, "<p>This Key Kong request has ended.</p>");
    if (submitted.get("action") === "cancel") {
      finish({ status: "cancelled" });
      return page(200, "<p>Cancelled. You can close this tab.</p>");
    }
    const values = Object.fromEntries(
      request.fields.map((field) => [
        field.id,
        field.type === "multi_select"
          ? submitted.getAll(field.id)
          : submitted.get(field.id),
      ]),
    );
    try {
      validateSubmission(values, request);
    } catch {
      return page(
        422,
        form(request, "Every field needs a value on a single line."),
      );
    }
    finish({
      status: "submitted",
      values: values as Record<string, ResponseValue>,
    });
    return page(200, "<p>Submitted. You can close this tab.</p>");
  });

  await Bun.write(Bun.stderr, `keykong: waiting for input at ${url}\n`);
  try {
    return await deadline.run(promise);
  } finally {
    await server.stop();
  }
}

async function listen(
  port: number,
  deadline: Deadline,
  fetch: (request: globalThis.Request) => Promise<Response>,
): Promise<Bun.Server<undefined>> {
  while (true) {
    try {
      return Bun.serve({
        hostname: "127.0.0.1",
        port,
        maxRequestBodySize: requestLimits.bytes,
        fetch,
      });
    } catch (error) {
      if ((error as { code?: string }).code !== "EADDRINUSE") {
        throw new KeyKongError(
          "PROMPT_FAILED",
          "web prompt could not be started",
          1,
        );
      }
    }
    // Another request owns the port until it finishes.
    await deadline.run(Bun.sleep(250));
  }
}

function form(request: Request, error?: string): string {
  const fields = request.fields.map((field) => {
    const name = escape(field.id);
    const label = escape(field.label);
    if (field.type === "multi_select") {
      const options = field.options!.map((option) =>
        `<label class="option"><input type="checkbox" name="${name}" value="${
          escape(option.value)
        }"> ${escape(option.label)}</label>`
      );
      return `<fieldset><legend>${label}</legend>${options.join("")}</fieldset>`;
    }
    if (field.type === "select") {
      const options = field.options!.map((option) =>
        `<option value="${escape(option.value)}">${escape(option.label)}</option>`
      );
      return `<label>${label}<select name="${name}" required>` +
        `<option value="" disabled selected hidden>Choose…</option>${
          options.join("")
        }</select></label>`;
    }
    const input = field.type === "secret"
      ? `type="password" name="${name}" autocomplete="new-password"`
      : `type="text" name="${name}" autocomplete="off"`;
    return `<label>${label}<input ${input} required spellcheck="false" autocapitalize="off"></label>`;
  });
  const deliveries = request.deliveries.length === 0 ? "" : `<section><h2>Delivery</h2><ul>${
    request.deliveries.map((delivery) => `<li>${describe(delivery)}</li>`)
      .join("")
  }</ul></section>`;
  return `<form method="post"><h1>${escape(request.title)}</h1>${
    error ? `<p role="alert">${escape(error)}</p>` : ""
  }${fields.join("")}${deliveries}<div class="actions">` +
    `<button name="action" value="submit">Submit</button>` +
    `<button name="action" value="cancel" formnovalidate>Cancel</button>` +
    `</div></form>`;
}

function describe(delivery: Delivery): string {
  const path = `<code>${escape(delivery.path)}</code>`;
  if (delivery.operation === "set_env") {
    return `Set <code>${escape(delivery.key)}</code> in ${path} from ${
      escape(delivery.field)
    }`;
  }
  const template = `<code>${escape(delivery.template)}</code>`;
  return delivery.operation === "insert_line"
    ? `Insert at line ${delivery.line} of ${path}: ${template}`
    : `Append to ${path}: ${template}`;
}

function page(status: number, body: string): Response {
  return new Response(
    `<!doctype html><html lang="en"><meta charset="utf-8">` +
      `<meta name="viewport" content="width=device-width, initial-scale=1">` +
      `<title>Key Kong</title><style>${style}</style><main>${body}</main></html>`,
    {
      status,
      headers: {
        "Cache-Control": "no-store",
        "Content-Security-Policy":
          "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
        "Content-Type": "text/html; charset=utf-8",
        "Referrer-Policy": "no-referrer",
      },
    },
  );
}

const entities: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

function escape(text: string): string {
  return text.replace(/[&<>"']/g, (character) => entities[character]!);
}

const style = `
:root { color-scheme: light dark; font: 16px/1.5 system-ui, sans-serif; }
main { max-width: 32rem; margin: 2rem auto; padding: 0 1rem; }
label, fieldset { display: block; margin: 0 0 1rem; }
label.option { margin: 0.25rem 0; }
input:not([type=checkbox]), select { display: block; box-sizing: border-box; width: 100%; margin-top: 0.25rem; padding: 0.5rem; font: inherit; }
fieldset { border: 1px solid #8886; border-radius: 0.5rem; }
h2 { font-size: 1rem; }
code { overflow-wrap: anywhere; }
[role=alert] { color: #c33; }
.actions { display: flex; gap: 0.5rem; }
button { padding: 0.5rem 1rem; font: inherit; }
`;
