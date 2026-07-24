import { constants } from "node:fs";
import { lstat, open } from "node:fs/promises";
import { isAbsolute } from "node:path";
import type { Deadline } from "./deadline";
import { ExpiredError, KeyKongError } from "./errors";
import { requestLimits } from "./limits";
import type {
  Delivery,
  Field,
  Request,
  ResponseValue,
} from "./types";

export interface TargetIdentity {
  dev: bigint;
  ino: bigint;
}

const idPattern = /^[\p{L}\p{N}][\p{L}\p{N}_-]*$/u;
const newlinePattern = /[\r\n\v\f\u0085\u2028\u2029]/u;
const fieldTypes = new Set(["text", "secret", "select", "multi_select"]);
const deliveryOperations = new Set(["append", "insert_line"]);

function invalid(message: string): never {
  throw new KeyKongError("INVALID_REQUEST", message, 2);
}

function object(value: unknown, description: string): Record<string, unknown> {
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

function id(value: unknown, description: string): asserts value is string {
  if (typeof value !== "string" || !idPattern.test(value)) {
    invalid(`${description} is invalid`);
  }
}

function validateField(value: unknown, deadline: Deadline): Field {
  deadline.check();
  const field = object(value, "field");
  exactKeys(field, ["id", "label", "type", "options"], ["id", "label", "type"], "field");
  id(field.id, "field ID");
  singleLine(field.label, `field '${field.id}' label`);
  if (typeof field.type !== "string" || !fieldTypes.has(field.type)) {
    invalid(`field '${field.id}' type is invalid`);
  }

  if (field.type === "text" || field.type === "secret") {
    if ("options" in field) invalid(`field '${field.id}' must not define options`);
  } else {
    if (!Array.isArray(field.options) || field.options.length === 0) {
      invalid(`field '${field.id}' must define at least one option`);
    }
    if (field.options.length > requestLimits.optionsPerField) {
      invalid(
        `field '${field.id}' exceeds ${requestLimits.optionsPerField} options`,
      );
    }
    const values = new Set<string>();
    for (const rawOption of field.options) {
      deadline.check();
      const option = object(rawOption, `field '${field.id}' option`);
      exactKeys(option, ["label", "value"], ["label", "value"], `field '${field.id}' option`);
      singleLine(option.label, `field '${field.id}' option label`);
      singleLine(option.value, `field '${field.id}' option value`);
      if (values.has(option.value)) invalid(`field '${field.id}' option values must be unique`);
      values.add(option.value);
    }
  }
  return field as unknown as Field;
}

function templateReferences(
  template: string,
  deliveryID: string,
  deadline?: Deadline,
): string[] {
  const references: string[] = [];
  let cursor = 0;
  while (cursor < template.length) {
    deadline?.check();
    const opening = template.indexOf("{{", cursor);
    const strayClosing = template.indexOf("}}", cursor);
    if (strayClosing >= 0 && (opening < 0 || strayClosing < opening)) {
      invalid(`delivery '${deliveryID}' template has invalid braces`);
    }
    if (opening < 0) break;
    const closing = template.indexOf("}}", opening + 2);
    if (closing < 0) invalid(`delivery '${deliveryID}' template has an unclosed field reference`);
    const reference = template.slice(opening + 2, closing).trim();
    id(reference, `delivery '${deliveryID}' template field reference`);
    references.push(reference);
    cursor = closing + 2;
  }
  if (template.indexOf("}}", cursor) >= 0) {
    invalid(`delivery '${deliveryID}' template has invalid braces`);
  }
  return references;
}

function validateDelivery(
  value: unknown,
  fields: Map<string, Field>,
  deadline: Deadline,
): Delivery {
  deadline.check();
  const delivery = object(value, "delivery");
  exactKeys(
    delivery,
    ["id", "path", "operation", "line", "template"],
    ["id", "path", "operation", "template"],
    "delivery",
  );
  id(delivery.id, "delivery ID");
  if (typeof delivery.path !== "string" || !isAbsolute(delivery.path)) {
    invalid(`delivery '${delivery.id}' path must be absolute`);
  }
  if (
    typeof delivery.operation !== "string" ||
    !deliveryOperations.has(delivery.operation)
  ) {
    invalid(`delivery '${delivery.id}' operation is invalid`);
  }
  if (typeof delivery.template !== "string") {
    invalid(`delivery '${delivery.id}' template must be a string`);
  }
  if (delivery.operation === "append" && "line" in delivery) {
    invalid(`append delivery '${delivery.id}' must not define a line`);
  }
  if (
    delivery.operation === "insert_line" &&
    (!Number.isInteger(delivery.line) || Number(delivery.line) <= 0)
  ) {
    invalid(`insert_line delivery '${delivery.id}' needs a positive line`);
  }
  const references = templateReferences(delivery.template, delivery.id, deadline);
  if (references.length === 0) {
    invalid(`delivery '${delivery.id}' template must reference at least one field`);
  }
  for (const reference of references) {
    if (!fields.has(reference)) {
      invalid(`delivery '${delivery.id}' references unknown field '${reference}'`);
    }
  }
  return delivery as unknown as Delivery;
}

async function openValidatedTarget(
  delivery: Delivery,
  deadline: Deadline,
): Promise<{ identity: TargetIdentity; lines: number }> {
  try {
    deadline.check();
    const linkInfo = await lstat(delivery.path, { bigint: true });
    if (!linkInfo.isFile() || linkInfo.isSymbolicLink()) throw new Error();
    const handle = await open(
      delivery.path,
      constants.O_RDWR | constants.O_NOFOLLOW,
    );
    try {
      const info = await handle.stat({ bigint: true });
      if (!info.isFile()) throw new Error();
      const buffer = Buffer.allocUnsafe(64 * 1024);
      let position = 0;
      let lines = 1;
      while (true) {
        deadline.check();
        const { bytesRead } = await deadline.race(
          handle.read(buffer, 0, buffer.length, position),
        );
        if (bytesRead === 0) break;
        for (let index = 0; index < bytesRead; index++) {
          if (buffer[index] === 10) lines++;
        }
        position += bytesRead;
      }
      return {
        identity: { dev: info.dev, ino: info.ino },
        lines,
      };
    } finally {
      await handle.close();
    }
  } catch (error) {
    if (error instanceof ExpiredError) throw error;
    invalid(
      `delivery '${delivery.id}' target must be an existing readable and writable regular file`,
    );
  }
}

function simulateDelivery(delivery: Delivery, lines: number): number {
  if (delivery.operation === "insert_line" && delivery.line! > lines) {
    invalid(`delivery '${delivery.id}' line is outside the target`);
  }
  const rendered = delivery.template.replace(
    /\{\{\s*[\p{L}\p{N}_-]+\s*\}\}/gu,
    "",
  );
  let addedLines = 0;
  for (let index = 0; index < rendered.length; index++) {
    if (rendered.charCodeAt(index) === 10) addedLines++;
  }
  if (delivery.operation === "insert_line" && !rendered.endsWith("\n")) {
    addedLines++;
  }
  return lines + addedLines;
}

export async function validateRequest(
  raw: unknown,
  deadline: Deadline,
): Promise<{
  request: Request;
  targets: Map<string, TargetIdentity>;
}> {
  deadline.check();
  const value = object(raw, "request");
  exactKeys(
    value,
    ["schemaVersion", "id", "title", "fields", "deliveries"],
    ["schemaVersion", "id", "title", "fields"],
    "request",
  );
  if (value.schemaVersion !== 1) invalid("schemaVersion must be 1");
  id(value.id, "request ID");
  singleLine(value.title, "request title");
  if (!Array.isArray(value.fields) || value.fields.length === 0) {
    invalid("at least one field is required");
  }
  if (value.fields.length > requestLimits.fields) {
    invalid(`request exceeds ${requestLimits.fields} fields`);
  }
  if ("deliveries" in value && !Array.isArray(value.deliveries)) {
    invalid("deliveries must be an array");
  }

  const fields = value.fields.map((field) => validateField(field, deadline));
  const fieldsByID = new Map(fields.map((field) => [field.id, field]));
  if (fieldsByID.size !== fields.length) invalid("field IDs must be unique");
  const deliveryValues = (value.deliveries ?? []) as unknown[];
  if (deliveryValues.length > requestLimits.deliveries) {
    invalid(`request exceeds ${requestLimits.deliveries} deliveries`);
  }
  const deliveries = deliveryValues.map((delivery) =>
    validateDelivery(delivery, fieldsByID, deadline),
  );
  if (new Set(deliveries.map((delivery) => delivery.id)).size !== deliveries.length) {
    invalid("delivery IDs must be unique");
  }
  const referenced = new Set(
    deliveries.flatMap((delivery) =>
      templateReferences(delivery.template, delivery.id, deadline),
    ),
  );
  for (const field of fields) {
    if (field.type === "secret" && !referenced.has(field.id)) {
      invalid(
        `secret field '${field.id}' must be referenced by a delivery's template`,
      );
    }
  }

  const targets = new Map<string, TargetIdentity>();
  const simulatedTargets = new Map<
    string,
    { identity: TargetIdentity; lines: number }
  >();
  for (const delivery of deliveries) {
    deadline.check();
    const target =
      simulatedTargets.get(delivery.path) ??
      (await openValidatedTarget(delivery, deadline));
    targets.set(delivery.id, target.identity);
    simulatedTargets.set(delivery.path, {
      identity: target.identity,
      lines: simulateDelivery(delivery, target.lines),
    });
  }
  return {
    request: { ...value, fields, deliveries } as unknown as Request,
    targets,
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
  const expected = new Set(request.fields.map((field) => field.id));
  if (
    Object.keys(submitted).length !== expected.size ||
    Object.keys(submitted).some((key) => !expected.has(key))
  ) {
    invalidSubmission();
  }

  const result: Record<string, ResponseValue> = {};
  for (const field of request.fields) {
    const value = submitted[field.id];
    if (field.type === "text" || field.type === "secret") {
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
      if ([...selected].some((entry) => !field.options!.some((option) => option.value === entry))) {
        invalidSubmission();
      }
      result[field.id] = field.options!.map((option) => option.value).filter((entry) => selected.has(entry));
    }
  }
  return result;
}
