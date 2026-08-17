import { ok } from "node:assert/strict";

import type { ResponseValue } from "./types";

export function requireResponseValue(
  values: Record<string, ResponseValue>,
  field: string,
) {
  const value = values[field];
  ok(value !== undefined, `missing response value for ${field}`);
  return value;
}

export function serializeResponseValue(value: ResponseValue) {
  return Array.isArray(value) ? JSON.stringify(value) : value;
}
