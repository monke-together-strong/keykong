import { KeyKongError } from "./errors";
import { DeadlineExpired, type Deadline } from "./deadline";
import { deliver } from "./delivery";
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
  try {
    return await deadline.run(
      source === "-" ? Bun.stdin.text() : Bun.file(source).text(),
    );
  } catch (error) {
    if (error instanceof DeadlineExpired) throw error;
    throw new KeyKongError("INVALID_REQUEST", "request could not be read", 2);
  }
}

export async function requestCommand(
  args: string[],
  deadline: Deadline,
): Promise<Execution> {
  if (args.length !== 2 || args[0] !== "request") usage();
  const text = await readRequest(args[1]!, deadline);
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new KeyKongError("INVALID_REQUEST", "request is not valid JSON", 2);
  }

  const { request, targets } = await deadline.run(validateRequest(raw));
  if (KEY_KONG_TESTING && process.env.KEY_KONG_TEST_INTERNAL_FAILURE) {
    throw new Error("forced internal failure");
  }
  const response = await prompt(request, deadline);
  if (response.status === "cancelled") {
    return { result: { status: "cancelled", values: {} }, exitCode: 1 };
  }

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
