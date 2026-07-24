import { KeyKongError } from "./errors";
import type { Field, Request, ResponseValue } from "./types";

const idPattern = /^[\p{L}\p{N}][\p{L}\p{N}_-]*$/u;
const newlinePattern = /[\r\n\v\f\u0085\u2028\u2029]/u;
const responseFieldTypes = new Set(["text", "select", "multi_select"]);

function invalid(message: string): never {
  throw new KeyKongError("INVALID_REQUEST", message, 2);
}

function requireObject(
  value: unknown,
  description: string,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    invalid(`${description} must be an object`);
  }
  return value as Record<string, unknown>;
}

function exactKeys(
  value: Record<string, unknown>,
  allowed: string[],
  required: string[],
  description: string,
) {
  const extra = Object.keys(value).find((key) => !allowed.includes(key));
  if (extra) invalid(`${description} contains unknown property '${extra}'`);
  const missing = required.find((key) => !(key in value));
  if (missing) invalid(`${description} is missing '${missing}'`);
}

function singleLine(value: unknown, description: string): asserts value is string {
  if (
    typeof value !== "string" ||
    value.trim() === "" ||
    newlinePattern.test(value)
  ) {
    invalid(`${description} must be a non-empty single line`);
  }
}

function requireID(value: unknown, description: string): asserts value is string {
  if (typeof value !== "string" || !idPattern.test(value)) {
    invalid(`${description} is invalid`);
  }
}

function validateField(value: unknown): Field {
  const field = requireObject(value, "field");
  exactKeys(
    field,
    ["id", "label", "type", "options"],
    ["id", "label", "type"],
    "field",
  );
  requireID(field.id, "field ID");
  singleLine(field.label, `field '${field.id}' label`);
  if (typeof field.type !== "string" || !responseFieldTypes.has(field.type)) {
    invalid(`field '${field.id}' is not a response field`);
  }

  if (field.type === "text") {
    if ("options" in field) invalid(`field '${field.id}' must not define options`);
  } else {
    if (!Array.isArray(field.options) || field.options.length === 0) {
      invalid(`field '${field.id}' must define at least one option`);
    }
    const values = new Set<string>();
    for (const rawOption of field.options) {
      const option = requireObject(rawOption, `field '${field.id}' option`);
      exactKeys(
        option,
        ["label", "value"],
        ["label", "value"],
        `field '${field.id}' option`,
      );
      singleLine(option.label, `field '${field.id}' option label`);
      singleLine(option.value, `field '${field.id}' option value`);
      if (values.has(option.value)) {
        invalid(`field '${field.id}' option values must be unique`);
      }
      values.add(option.value);
    }
  }
  return field as unknown as Field;
}

export function validateRequest(raw: unknown): Request {
  const value = requireObject(raw, "request");
  exactKeys(
    value,
    ["schemaVersion", "id", "title", "fields", "deliveries"],
    ["schemaVersion", "id", "title", "fields"],
    "request",
  );
  if (value.schemaVersion !== 1) invalid("schemaVersion must be 1");
  requireID(value.id, "request ID");
  singleLine(value.title, "request title");
  if (!Array.isArray(value.fields) || value.fields.length === 0) {
    invalid("at least one field is required");
  }
  const fields = value.fields.map(validateField);
  if (new Set(fields.map((field) => field.id)).size !== fields.length) {
    invalid("field IDs must be unique");
  }
  if (
    "deliveries" in value &&
    (!Array.isArray(value.deliveries) || value.deliveries.length !== 0)
  ) {
    invalid("response-only requests must not define deliveries");
  }
  return {
    schemaVersion: 1,
    id: value.id,
    title: value.title,
    fields,
    deliveries: [],
  };
}

function invalidSubmission(): never {
  throw new KeyKongError(
    "PROMPT_FAILED",
    "native prompt returned an invalid submission",
    1,
  );
}

export function validateSubmission(
  values: unknown,
  request: Request,
): Record<string, ResponseValue> {
  if (!values || typeof values !== "object" || Array.isArray(values)) {
    invalidSubmission();
  }
  const submitted = values as Record<string, unknown>;
  if (
    Object.keys(submitted).length !== request.fields.length ||
    Object.keys(submitted).some(
      (key) => !request.fields.some((field) => field.id === key),
    )
  ) {
    invalidSubmission();
  }

  const result: Record<string, ResponseValue> = {};
  for (const field of request.fields) {
    const value = submitted[field.id];
    if (field.type === "text") {
      if (
        typeof value !== "string" ||
        value.trim() === "" ||
        newlinePattern.test(value)
      ) {
        invalidSubmission();
      }
      result[field.id] = value;
    } else if (field.type === "select") {
      if (
        typeof value !== "string" ||
        !field.options!.some((option) => option.value === value)
      ) {
        invalidSubmission();
      }
      result[field.id] = value;
    } else {
      if (
        !Array.isArray(value) ||
        value.length === 0 ||
        value.some((entry) => typeof entry !== "string") ||
        new Set(value).size !== value.length
      ) {
        invalidSubmission();
      }
      const selected = new Set(value as string[]);
      if (
        [...selected].some(
          (entry) => !field.options!.some((option) => option.value === entry),
        )
      ) {
        invalidSubmission();
      }
      result[field.id] = field
        .options!.map((option) => option.value)
        .filter((entry) => selected.has(entry));
    }
  }
  return result;
}
