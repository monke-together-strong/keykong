import { isAbsolute } from "node:path";
import { insertBeforeLine } from "./content";
import { DeadlineExpired, type Deadline } from "./deadline";
import { KeyKongError } from "./errors";
import { setEnvironmentAssignment } from "./environment";
import { requestLimits } from "./limits";
import { parseTemplate, renderTemplate } from "./template";
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
const deliveryOperations = new Set(["append", "insert_line", "set_env"]);
const environmentKeyPattern = /^[A-Za-z_][A-Za-z0-9_]*$/;

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

function validateField(value: unknown, deadline: Deadline): Field {
  deadline.assertActive();
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
    if (field.options.length > requestLimits.optionsPerField) {
      invalid(
        `field '${field.id}' must define at most ${requestLimits.optionsPerField} options`,
      );
    }
    const optionValues = new Set<string>();
    for (const rawOption of field.options) {
      deadline.assertActive();
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
  deadline: Deadline,
): {
  delivery: Delivery;
  references: string[];
  literal: string;
  trailingLiteral: string;
} {
  deadline.assertActive();
  const delivery = requireObject(value, "delivery");
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
  if (delivery.operation === "set_env") {
    exactKeys(
      delivery,
      ["id", "path", "operation", "key", "field"],
      ["id", "path", "operation", "key", "field"],
      "delivery",
    );
    if (
      typeof delivery.key !== "string" ||
      !environmentKeyPattern.test(delivery.key)
    ) {
      invalid(`set_env delivery '${delivery.id}' key is invalid`);
    }
    requireID(delivery.field, `set_env delivery '${delivery.id}' field`);
    const field = fields.get(delivery.field);
    if (!field) {
      invalid(
        `set_env delivery '${delivery.id}' references unknown field '${delivery.field}'`,
      );
    }
    if (field.type === "multi_select") {
      invalid(
        `set_env delivery '${delivery.id}' field must be single-valued`,
      );
    }
    return {
      delivery: delivery as unknown as Delivery,
      references: [delivery.field],
      literal: "",
      trailingLiteral: "",
    };
  }

  exactKeys(
    delivery,
    ["id", "path", "operation", "line", "template"],
    ["id", "path", "operation", "template"],
    "delivery",
  );
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
  deadline.assertActive();
  if (!parsed || parsed.references.length === 0) {
    invalid(
      `delivery '${delivery.id}' template must contain valid field references`,
    );
  }
  for (const reference of parsed.references) {
    deadline.assertActive();
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
    trailingLiteral: parsed.trailingLiteral,
  };
}

async function inspectTarget(
  delivery: Delivery,
  deadline: Deadline,
  captureContent: boolean,
): Promise<{ identity: TargetIdentity; lines: number; content?: Buffer }> {
  try {
    const { handle, identity } = await deadline.run(openTarget(delivery.path));
    try {
      let lines = 1;
      const buffer = Buffer.allocUnsafe(64 * 1024);
      const chunks: Buffer[] = [];
      let position = 0;
      while (true) {
        const { bytesRead } = await deadline.run(
          handle.read(buffer, 0, buffer.length, position),
        );
        if (bytesRead === 0) break;
        if (captureContent) {
          chunks.push(Buffer.from(buffer.subarray(0, bytesRead)));
        }
        position += bytesRead;
        for (let index = 0; index < bytesRead; index++) {
          if (buffer[index] === 10) lines++;
        }
      }
      return {
        identity,
        lines,
        ...(captureContent
          ? { content: Buffer.concat(chunks, position) }
          : {}),
      };
    } finally {
      await handle.close();
    }
  } catch (error) {
    if (error instanceof DeadlineExpired) throw error;
    invalid(
      `delivery '${delivery.id}' target must be an existing readable and writable regular file`,
    );
  }
}

function simulateDelivery(
  delivery: Delivery,
  literal: string,
  trailingLiteral: string,
  lines: number,
): number {
  if (delivery.operation === "insert_line" && delivery.line! > lines) {
    invalid(`delivery '${delivery.id}' line is outside the target`);
  }
  const addedNewlines = [...literal].filter((value) => value === "\n").length;
  // Every field value accepted by validateSubmission renders at least one
  // non-newline byte, so only the literal after the final reference can make
  // the rendered template end in a newline.
  return lines +
    addedNewlines +
    (
        delivery.operation === "insert_line" &&
          !trailingLiteral.endsWith("\n")
      ? 1
      : 0
  );
}

function countNewlines(content: Buffer): number {
  return content.reduce(
    (count, byte) => count + Number(byte === 10),
    0,
  );
}

export async function validateRequest(
  raw: unknown,
  deadline: Deadline,
): Promise<{
  request: Request;
  targets: Map<string, TargetIdentity>;
}> {
  deadline.assertActive();
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
  if (value.fields.length > requestLimits.fields) {
    invalid(`at most ${requestLimits.fields} fields are allowed`);
  }
  if ("deliveries" in value && !Array.isArray(value.deliveries)) {
    invalid("deliveries must be an array");
  }
  if (
    Array.isArray(value.deliveries) &&
    value.deliveries.length > requestLimits.deliveries
  ) {
    invalid(`at most ${requestLimits.deliveries} deliveries are allowed`);
  }

  const fields = value.fields.map((field) => validateField(field, deadline));
  const fieldsByID = new Map(fields.map((field) => [field.id, field]));
  const validationValues = Object.fromEntries(
    fields.map((field) => [
      field.id,
      field.type === "multi_select"
        ? ["keykong-validation"]
        : "keykong-validation",
    ]),
  ) as Record<string, ResponseValue>;
  if (fieldsByID.size !== fields.length) invalid("field IDs must be unique");
  const validatedDeliveries = ((value.deliveries ?? []) as unknown[]).map((delivery) =>
    validateDelivery(delivery, fieldsByID, deadline)
  );
  const deliveries = validatedDeliveries.map(({ delivery }) => delivery);
  if (
    new Set(deliveries.map((delivery) => delivery.id)).size !==
      deliveries.length
  ) {
    invalid("delivery IDs must be unique");
  }
  const environmentAssignments = new Map<string, Set<string>>();
  for (const delivery of deliveries) {
    if (delivery.operation !== "set_env") continue;
    const assignedKeys = environmentAssignments.get(delivery.path) ??
      new Set<string>();
    if (assignedKeys.has(delivery.key)) {
      invalid(
        `set_env deliveries for '${delivery.path}' key '${delivery.key}' must be unique`,
      );
    }
    assignedKeys.add(delivery.key);
    environmentAssignments.set(delivery.path, assignedKeys);
  }

  const referencedFields = new Set(
    validatedDeliveries.flatMap(({ references }) => references),
  );
  for (const field of fields) {
    deadline.assertActive();
    if (field.type === "secret" && !referencedFields.has(field.id)) {
      invalid(
        `secret field '${field.id}' must be referenced by a delivery`,
      );
    }
  }

  const targets = new Map<string, TargetIdentity>();
  const inspectedTargets = new Map<
    string,
    { identity: TargetIdentity; lines: number; content?: Buffer }
  >();
  const inspectedTargetsByIdentity = new Map<
    string,
    { identity: TargetIdentity; lines: number; content?: Buffer }
  >();
  const environmentKeysByTarget = new Map<string, Set<string>>();
  for (const delivery of deliveries) {
    if (
      delivery.operation !== "set_env" ||
      inspectedTargets.has(delivery.path)
    ) {
      continue;
    }
    const target = await inspectTarget(delivery, deadline, true);
    const targetKey = `${target.identity.dev}:${target.identity.ino}`;
    inspectedTargets.set(delivery.path, target);
    if (!inspectedTargetsByIdentity.has(targetKey)) {
      inspectedTargetsByIdentity.set(targetKey, target);
    }
  }
  for (const [index, delivery] of deliveries.entries()) {
    deadline.assertActive();
    const inspectedTarget = inspectedTargets.get(delivery.path) ??
      await inspectTarget(delivery, deadline, false);
    const targetKey =
      `${inspectedTarget.identity.dev}:${inspectedTarget.identity.ino}`;
    const cachedTarget = inspectedTargetsByIdentity.get(targetKey);
    const target = cachedTarget === undefined
      ? inspectedTarget
      : {
        ...cachedTarget,
        content: cachedTarget.content ?? inspectedTarget.content,
      };
    targets.set(delivery.id, target.identity);
    if (delivery.operation === "set_env") {
      const assignedKeys = environmentKeysByTarget.get(targetKey) ??
        new Set<string>();
      if (assignedKeys.has(delivery.key)) {
        invalid(
          `set_env deliveries for the same target key '${delivery.key}' must be unique`,
        );
      }
      assignedKeys.add(delivery.key);
      environmentKeysByTarget.set(targetKey, assignedKeys);
    }
    let nextLines: number;
    let nextContent: Buffer | undefined;
    if (delivery.operation === "set_env") {
      try {
        const content = target.content!;
        const beforeNewlines = countNewlines(content);
        nextContent = setEnvironmentAssignment(
          content,
          delivery.key,
          "keykong-validation",
        );
        const afterNewlines = countNewlines(nextContent);
        nextLines = target.lines + afterNewlines - beforeNewlines;
      } catch {
        invalid(
          `set_env delivery '${delivery.id}' target is not a supported dotenv file`,
        );
      }
    } else {
      if (target.content) {
        const rendered = renderTemplate(delivery.template, validationValues);
        nextContent = delivery.operation === "append"
          ? Buffer.concat([target.content, rendered])
          : insertBeforeLine(target.content, delivery.line, rendered);
        if (!nextContent) {
          invalid(`delivery '${delivery.id}' line is outside the target`);
        }
        nextLines = countNewlines(nextContent) + 1;
      } else {
        nextLines = simulateDelivery(
          delivery,
          validatedDeliveries[index]!.literal,
          validatedDeliveries[index]!.trailingLiteral,
          target.lines,
        );
      }
    }
    const nextTarget = {
      identity: target.identity,
      lines: nextLines,
      content: nextContent,
    };
    inspectedTargets.set(delivery.path, nextTarget);
    inspectedTargetsByIdentity.set(targetKey, nextTarget);
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
