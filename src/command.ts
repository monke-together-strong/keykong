import { KeyKongError } from "./errors";
import { DeadlineExpired, type Deadline } from "./deadline";
import { deliver } from "./delivery";
import { requestLimits } from "./limits";
import { prompt } from "./prompt";
import type { Result } from "./types";
import { validateRequest, validateSubmission } from "./validation";

declare const KEY_KONG_TESTING: boolean;

export interface Execution {
  result: Result;
  exitCode: 0 | 1 | 2;
}

function usage(): never {
  throw new KeyKongError("CLI_USAGE", "usage: key-kong request <file|->", 2);
}

async function readRequest(source: string, deadline: Deadline): Promise<string> {
  const reader = (source === "-" ? Bun.stdin : Bun.file(source))
    .stream()
    .getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await deadline.run(
        reader.read(),
        () => void reader.cancel(),
      );
      if (done) break;
      bytes += value.byteLength;
      if (bytes > requestLimits.bytes) {
        await reader.cancel();
        throw new KeyKongError(
          "INVALID_REQUEST",
          `request exceeds ${requestLimits.bytes} bytes`,
          2,
        );
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof DeadlineExpired) throw error;
    if (error instanceof KeyKongError) throw error;
    throw new KeyKongError("INVALID_REQUEST", "request could not be read", 2);
  } finally {
    reader.releaseLock();
  }
  return Buffer.concat(chunks, bytes).toString("utf8");
}

export async function requestCommand(
  args: string[],
  deadline: Deadline,
): Promise<Execution> {
  if (args.length !== 2 || args[0] !== "request") usage();
  const text = await readRequest(args[1]!, deadline);
  deadline.assertActive();
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new KeyKongError("INVALID_REQUEST", "request is not valid JSON", 2);
  }
  deadline.assertActive();

  const { request, targets } = await deadline.run(
    validateRequest(raw, deadline),
  );
  if (KEY_KONG_TESTING && process.env.KEY_KONG_TEST_INTERNAL_FAILURE) {
    throw new Error("forced internal failure");
  }
  const response = await prompt(request, deadline);
  if (response.status === "cancelled") {
    return { result: { status: "cancelled", values: {} }, exitCode: 1 };
  }

  deadline.assertActive();
  const values = validateSubmission(response.values, request);
  for (const fieldID of Object.keys(response.values)) {
    delete response.values[fieldID];
  }
  const publicValues = Object.fromEntries(
    request.fields
      .filter((field) => field.type !== "secret")
      .map((field) => [field.id, values[field.id]!]),
  );
  const failed = await deliver(request.deliveries, values, targets, deadline);
  for (const field of request.fields) delete values[field.id];

  if (failed.length === 0) {
    return {
      result: { status: "completed", values: publicValues },
      exitCode: 0,
    };
  }
  if (failed.length === request.deliveries.length) {
    return {
      result: {
        status: "failed",
        values: publicValues,
        error: { code: "DELIVERY_FAILED", message: "all deliveries failed" },
      },
      exitCode: 1,
    };
  }
  return {
    result: {
      status: "partial",
      values: publicValues,
      failedDeliveries: failed,
      error: { code: "DELIVERY_FAILED", message: "some deliveries failed" },
    },
    exitCode: 1,
  };
}
