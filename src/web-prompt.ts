import { randomBytes } from "node:crypto";
import { rename, rm } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
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

const settingsSchema = z.object({
  url: z.url({ protocol: /^https$/ }),
  port: z.int().min(1).max(65_535),
  allow: z.string().min(1),
});

export type WebPromptSettings = z.infer<typeof settingsSchema>;

// Field IDs cannot start with "_", so this never collides with a field.
const control = "_action";

function settingsPath(): string {
  const base = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  return join(base, "keykong", "web-prompt.json");
}

export async function readWebPromptSettings(): Promise<
  WebPromptSettings | undefined
> {
  const file = Bun.file(settingsPath());
  if (!(await file.exists())) return undefined;
  const settings = settingsSchema.safeParse(
    await file.json().catch(() => undefined),
  );
  if (!settings.success) {
    throw new KeyKongError(
      "PROMPT_FAILED",
      `web prompt settings in ${settingsPath()} are invalid; run keykong prompt web or keykong prompt native`,
      1,
    );
  }
  return settings.data;
}

export async function writeWebPromptSettings(settings: WebPromptSettings) {
  const temporary = `${settingsPath()}.${process.pid}.next`;
  await Bun.write(temporary, `${JSON.stringify(settings)}\n`);
  await rename(temporary, settingsPath());
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
  const ended = () => page(410, "<p>This Key Kong request has ended.</p>");

  const server = await listen(settings.port, deadline, async (incoming) => {
    if (incoming.headers.get("tailscale-user-login") !== settings.allow) {
      return page(403, "<p>This Key Kong request is not available to you.</p>");
    }
    const path = new URL(incoming.url).pathname;
    if (path === "/" && !finished) {
      return new Response(null, { status: 303, headers: { Location: url } });
    }
    if (path !== `/${id}` || finished) return ended();
    if (incoming.method === "GET") return page(200, form(request));
    if (
      incoming.method !== "POST" ||
      incoming.headers.get("origin") !== new URL(settings.url).origin
    ) {
      return page(403, "<p>This submission was rejected.</p>");
    }

    const submitted = await incoming.formData().catch(() => undefined);
    if (finished) return ended();
    if (!submitted) {
      return page(400, form(request, "The submission could not be read."));
    }
    if (submitted.get(control) === "cancel") {
      finish({ status: "cancelled" });
      return page(200, "<p>Cancelled. You can close this tab.</p>");
    }
    let values: Record<string, ResponseValue>;
    try {
      values = validateSubmission(
        Object.fromEntries(
          request.fields.map((field) => [
            field.id,
            field.type === "multi_select"
              ? submitted.getAll(field.id)
              : submitted.get(field.id),
          ]),
        ),
        request,
      );
    } catch {
      return page(
        422,
        form(request, "Every field needs a value on a single line."),
      );
    }
    finish({ status: "submitted", values });
    return page(200, "<p>Submitted. You can close this tab.</p>");
  });

  try {
    await deadline.run(
      Bun.write(Bun.stderr, `keykong: waiting for input at ${url}\n`),
    );
    return await deadline.run(promise);
  } finally {
    finished = true;
    // Let the acknowledgement flush without outliving the deadline.
    await Promise.race([
      server.stop(),
      Bun.sleep(Math.min(1_000, deadline.remaining())),
    ]);
    await server.stop(true);
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
    const name = Bun.escapeHTML(field.id);
    const label = Bun.escapeHTML(field.label);
    if (field.type === "multi_select") {
      const options = field.options!.map((option) =>
        `<label class="option"><input type="checkbox" name="${name}" value="${
          Bun.escapeHTML(option.value)
        }"> ${Bun.escapeHTML(option.label)}</label>`
      );
      return `<fieldset><legend>${label}</legend>${options.join("")}</fieldset>`;
    }
    if (field.type === "select") {
      const options = field.options!.map((option) =>
        `<option value="${Bun.escapeHTML(option.value)}">${Bun.escapeHTML(option.label)}</option>`
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
  return `<form method="post"><h1>${Bun.escapeHTML(request.title)}</h1>${
    error ? `<p role="alert">${Bun.escapeHTML(error)}</p>` : ""
  }${fields.join("")}${deliveries}<div class="actions">` +
    `<button name="${control}" value="submit">Submit</button>` +
    `<button name="${control}" value="cancel" formnovalidate>Cancel</button>` +
    `</div></form>`;
}

function describe(delivery: Delivery): string {
  const path = `<code>${Bun.escapeHTML(delivery.path)}</code>`;
  if (delivery.operation === "set_env") {
    return `Set <code>${Bun.escapeHTML(delivery.key)}</code> in ${path} from ${
      Bun.escapeHTML(delivery.field)
    }`;
  }
  const template = `<code>${Bun.escapeHTML(delivery.template)}</code>`;
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
        // Browsers send `Origin: null` with form posts under `no-referrer`.
        "Referrer-Policy": "same-origin",
      },
    },
  );
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
