import type { ErrorCode } from "./types";

export class KeyKongError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
    readonly exitCode: 1 | 2,
  ) {
    super(message);
  }
}

export class ExpiredError extends Error {}
