import { dirname, resolve } from "node:path";
import type { Deadline } from "./deadline";
import { ExpiredError, KeyKongError } from "./errors";
import type { PromptRequest, PromptResponse, Request } from "./types";

declare const KEY_KONG_TESTING: boolean;

function helperPath(): string {
  if (KEY_KONG_TESTING && process.env.KEY_KONG_PROMPT_EXECUTABLE) {
    return process.env.KEY_KONG_PROMPT_EXECUTABLE;
  }
  return resolve(dirname(process.execPath), "../libexec/key-kong-prompt");
}

export async function prompt(
  request: Request,
  deadline: Deadline,
): Promise<PromptResponse> {
  const projected: PromptRequest = {
    title: request.title,
    fields: request.fields,
    deliveries: request.deliveries.map(({ path, operation, line }) => ({
      path,
      operation,
      ...(line === undefined ? {} : { line }),
    })),
  };

  let subprocess: ReturnType<typeof Bun.spawn>;
  try {
    subprocess = Bun.spawn([helperPath()], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: process.env,
    });
  } catch {
    throw new KeyKongError("PROMPT_FAILED", "native prompt could not be started", 1);
  }

  const signals = [
    ["SIGHUP", 129],
    ["SIGINT", 130],
    ["SIGTERM", 143],
  ] as const;
  const handlers = signals.map(([signal, exitCode]) => {
    const handler = () => {
      subprocess.kill();
      process.exit(exitCode);
    };
    process.once(signal, handler);
    return [signal, handler] as const;
  });

  try {
    const input = subprocess.stdin as import("bun").FileSink;
    input.write(JSON.stringify(projected));
    input.end();
    const stdout = new Response(
      subprocess.stdout as ReadableStream<Uint8Array>,
    ).text();
    const stderr = new Response(
      subprocess.stderr as ReadableStream<Uint8Array>,
    ).text();
    const exitCode = await deadline.race(
      subprocess.exited,
      () => subprocess.kill(),
    );
    const [output] = await deadline.race(Promise.all([stdout, stderr]));

    if (exitCode !== 0) {
      throw new KeyKongError("PROMPT_FAILED", "native prompt failed", 1);
    }
    const response: unknown = JSON.parse(output);
    if (
      !response ||
      typeof response !== "object" ||
      Array.isArray(response)
    ) {
      throw new Error();
    }
    const candidate = response as Record<string, unknown>;
    if (
      candidate.status === "cancelled" &&
      Object.keys(candidate).length === 1
    ) {
      return { status: "cancelled" };
    }
    if (
      candidate.status === "submitted" &&
      Object.keys(candidate).length === 2 &&
      "values" in candidate
    ) {
      return candidate as unknown as PromptResponse;
    }
    throw new Error();
  } catch (error) {
    if (error instanceof KeyKongError || error instanceof ExpiredError) {
      throw error;
    }
    throw new KeyKongError("PROMPT_FAILED", "native prompt returned an invalid response", 1);
  } finally {
    subprocess.kill();
    for (const [signal, handler] of handlers) {
      process.removeListener(signal, handler);
    }
  }
}
