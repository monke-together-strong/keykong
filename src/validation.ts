import { isAbsolute } from "node:path";
import { KeyKongError } from "./errors";
import { parseTemplate } from "./template";
import { openTarget, type TargetIdentity } from "./target";
import type {
  Delivery,
  Field,
  Request,
  ResponseValue,
} from "./types";

const idPattern = /^[\p{L}\p{N}][\p{L}\p{N}_-]*$/u;
const newlinePattern = /[\r\n\v\f\u0085\u2028\u2029]/u;
const fieldTypes = new Set(["text", "secret", "select", "multi_select"]);
const deliveryOperations = new Set(["append", "insert_line"]);

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

function singleLine(
  value: unknown,
  description: string,
): asserts value is string {
  if (
    typeof value !== "string" ||
    value.trim() === "" ||
    newlinePattern.test(value)
  ) {
    invalid(`${description} must be a non-empty single line`);
  }
}

function requireID(
  value: unknown,
  description: string,
): asserts value is string {
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
  if (typeof field.type !== "string" || !fieldTypes.has(field.type)) {
    invalid(`field '${field.id}' type is invalid`);
  }

  if (field.type === "text" || field.type === "secret") {
    if ("options" in field) {
      invalid(`field '${field.id}' must not define options`);
    }
  } else {
    if (!Array.isArray(field.options) || field.options.length === 0) {
      invalid(`field '${field.id}' must define at least one option`);
    }
    const optionValues = new Set<string>();
    for (const rawOption of field.options) {
      const option = requireObject(
        rawOption,
        `field '${field.id}' option`,
      );
      exactKeys(
        option,
        ["label", "value"],
        ["label", "value"],
        `field '${field.id}' option`,
      );
      singleLine(option.label, `field '${field.id}' option label`);
      singleLine(option.value, `field '${field.id}' option value`);
      if (optionValues.has(option.value)) {
        invalid(`field '${field.id}' option values must be unique`);
      }
      optionValues.add(option.value);
    }
  }
  return field as unknown as Field;
}

function validateDelivery(
  value: unknown,
  fields: Map<string, Field>,
): { delivery: Delivery; references: string[]; literal: string } {
  const delivery = requireObject(value, "delivery");
  exactKeys(
    delivery,
    ["id", "path", "operation", "line", "template"],
    ["id", "path", "operation", "template"],
    "delivery",
  );
  requireID(delivery.id, "delivery ID");
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

  const parsed = parseTemplate(delivery.template);
  if (!parsed || parsed.references.length === 0) {
    invalid(
      `delivery '${delivery.id}' template must contain valid field references`,
    );
  }
  for (const reference of parsed.references) {
    if (!fields.has(reference)) {
      invalid(
        `delivery '${delivery.id}' references unknown field '${reference}'`,
      );
    }
  }
  return {
    delivery: delivery as unknown as Delivery,
    references: parsed.references,
    literal: parsed.literal,
  };
}

async function inspectTarget(
  delivery: Delivery,
): Promise<{ identity: TargetIdentity; lines: number }> {
  try {
    const { handle, identity } = await openTarget(delivery.path);
    try {
      const content = await handle.readFile();
      let lines = 1;
      for (const byte of content) {
        if (byte === 10) lines++;
      }
      return { identity, lines };
    } finally {
      await handle.close();
    }
  } catch {
    invalid(
      `delivery '${delivery.id}' target must be an existing readable and writable regular file`,
    );
  }
}

function simulateDelivery(
  delivery: Delivery,
  literal: string,
  lines: number,
): number {
  if (delivery.operation === "insert_line" && delivery.line! > lines) {
    invalid(`delivery '${delivery.id}' line is outside the target`);
  }
  const addedNewlines = [...literal].filter((value) => value === "\n").length;
  return lines +
    addedNewlines +
    (delivery.operation === "insert_line" && !literal.endsWith("\n") ? 1 : 0);
}

export async function validateRequest(raw: unknown): Promise<{
  request: Request;
  targets: Map<string, TargetIdentity>;
}> {
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
  if ("deliveries" in value && !Array.isArray(value.deliveries)) {
    invalid("deliveries must be an array");
  }

  const fields = value.fields.map(validateField);
  const fieldsByID = new Map(fields.map((field) => [field.id, field]));
  if (fieldsByID.size !== fields.length) invalid("field IDs must be unique");
  const validatedDeliveries = ((value.deliveries ?? []) as unknown[]).map((delivery) =>
    validateDelivery(delivery, fieldsByID)
  );
  const deliveries = validatedDeliveries.map(({ delivery }) => delivery);
  if (
    new Set(deliveries.map((delivery) => delivery.id)).size !==
      deliveries.length
  ) {
    invalid("delivery IDs must be unique");
  }

  const referencedFields = new Set(
    validatedDeliveries.flatMap(({ references }) => references),
  );
  for (const field of fields) {
    if (field.type === "secret" && !referencedFields.has(field.id)) {
      invalid(
        `secret field '${field.id}' must be referenced by a delivery's template`,
      );
    }
  }

  const targets = new Map<string, TargetIdentity>();
  const inspectedTargets = new Map<
    string,
    { identity: TargetIdentity; lines: number }
  >();
  for (const [index, delivery] of deliveries.entries()) {
    const target = inspectedTargets.get(delivery.path) ??
      await inspectTarget(delivery);
    targets.set(delivery.id, target.identity);
    inspectedTargets.set(delivery.path, {
      identity: target.identity,
      lines: simulateDelivery(
        delivery,
        validatedDeliveries[index]!.literal,
        target.lines,
      ),
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
      if (
        [...selected].some(
          (entry) =>
            !field.options!.some((option) => option.value === entry),
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
