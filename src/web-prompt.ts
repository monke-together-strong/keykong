import { randomBytes } from "node:crypto";
import { rename, rm } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import type { Deadline } from "./deadline";
import { KeyKongError } from "./errors";
import { requestLimits } from "./limits";
import type { PromptResponse, Request, ResponseValue } from "./types";
import { validateSubmission } from "./validation";
import { form, page } from "./web-prompt-page";

export const mountPath = "/keykong";

const settingsSchema = z.object({
  url: z
    .url({ protocol: /^https$/ })
    .regex(new RegExp(`^https://[^/?#\\s]+${mountPath}$`)),
  port: z.int().min(1).max(65_535),
  allow: z.string().trim().min(1),
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
  try {
    await Bun.write(temporary, `${JSON.stringify(settings)}\n`);
    await rename(temporary, settingsPath());
  } finally {
    await rm(temporary, { force: true });
  }
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
  const origin = new URL(settings.url).origin;
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
      incoming.headers.get("origin") !== origin
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
    // Stop listening without waiting on in-flight uploads, which would delay
    // delivery; they end when the process exits.
    void server.stop();
  }
}

async function listen(
  port: number,
  deadline: Deadline,
  fetch: (request: globalThis.Request) => Promise<Response>,
): Promise<Bun.Server<undefined>> {
  for (let attempt = 0; ; attempt++) {
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
    if (attempt === 0) {
      await deadline.run(
        Bun.write(Bun.stderr, `keykong: port ${port} is in use; waiting for it\n`),
      );
    }
    // Another request usually owns the port until it finishes.
    await deadline.run(Bun.sleep(250));
  }
}
