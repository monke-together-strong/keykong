import { KeyKongError } from "./errors";
import { prompt } from "./prompt";
import type { Result } from "./types";
import { validateRequest, validateSubmission } from "./validation";

export interface Execution {
  result: Result;
  exitCode: 0 | 1 | 2;
}

function usage(): never {
  throw new KeyKongError("CLI_USAGE", "usage: key-kong request <file|->", 2);
}

async function readRequest(source: string): Promise<string> {
  try {
    return await (source === "-" ? Bun.stdin.text() : Bun.file(source).text());
  } catch {
    throw new KeyKongError("INVALID_REQUEST", "request could not be read", 2);
  }
}

export async function requestCommand(args: string[]): Promise<Execution> {
  if (args.length !== 2 || args[0] !== "request") usage();
  const text = await readRequest(args[1]!);
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new KeyKongError("INVALID_REQUEST", "request is not valid JSON", 2);
  }

  const request = validateRequest(raw);
  const response = await prompt(request);
  if (response.status === "cancelled") {
    return { result: { status: "cancelled", values: {} }, exitCode: 1 };
  }
  return {
    result: {
      status: "completed",
      values: validateSubmission(response.values, request),
    },
    exitCode: 0,
  };
}
