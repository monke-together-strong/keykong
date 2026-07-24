import { readFile } from "node:fs/promises";
import type { Deadline } from "./deadline";
import { deliver } from "./delivery";
import { ExpiredError, KeyKongError } from "./errors";
import { prompt } from "./prompt";
import type { Result } from "./types";
import { validateRequest, validateSubmission } from "./validation";

export interface Execution {
  result: Result;
  exitCode: 0 | 1 | 2;
  diagnostic?: string;
}

function usage(): never {
  throw new KeyKongError("CLI_USAGE", "usage: key-kong request <file|->", 2);
}

export async function requestCommand(
  args: string[],
  deadline: Deadline,
): Promise<Execution> {
  if (args.length !== 2 || args[0] !== "request") usage();
  const source = args[1]!;
  let text: string;
  try {
    text =
      source === "-"
        ? await deadline.race(Bun.stdin.text())
        : await deadline.race(readFile(source, "utf8"));
  } catch (error) {
    if (error instanceof KeyKongError || error instanceof ExpiredError) throw error;
    throw new KeyKongError("INVALID_REQUEST", "request could not be read", 2);
  }

  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new KeyKongError("INVALID_REQUEST", "request is not valid JSON", 2);
  }
  const { request, targets } = await deadline.race(validateRequest(raw));
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
  const failed = await deadline.race(
    deliver(request.deliveries, values, targets, deadline),
  );
  for (const field of request.fields) delete values[field.id];

  if (failed.length === 0) {
    return { result: { status: "completed", values: publicValues }, exitCode: 0 };
  }
  if (failed.length === request.deliveries.length) {
    return {
      result: {
        status: "failed",
        values: publicValues,
        error: { code: "DELIVERY_FAILED", message: "all deliveries failed" },
      },
      exitCode: 1,
      diagnostic: "all deliveries failed",
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
    diagnostic: "some deliveries failed",
  };
}
