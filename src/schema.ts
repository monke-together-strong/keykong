import { requestLimits } from "./limits";

export const requestSchema = {
  $schema: "https://json-schema.org/draft/2020-12/schema",
  $id: "https://key-kong.dev/schema/request-v1.json",
  title: "Key Kong request",
  description:
    `Serialized requests are limited to ${requestLimits.bytes} UTF-8 bytes. ` +
    "The CLI also validates unique IDs, field references, secret delivery, " +
    "target accessibility and identity, and insertion-line bounds.",
  type: "object",
  additionalProperties: false,
  required: ["schemaVersion", "id", "title", "fields"],
  properties: {
    schemaVersion: { const: 1 },
    id: { $ref: "#/$defs/id" },
    title: { $ref: "#/$defs/singleLine" },
    fields: {
      type: "array",
      minItems: 1,
      maxItems: requestLimits.fields,
      items: { $ref: "#/$defs/field" },
    },
    deliveries: {
      type: "array",
      maxItems: requestLimits.deliveries,
      items: { $ref: "#/$defs/delivery" },
    },
  },
  $defs: {
    id: {
      type: "string",
      pattern: "^[\\p{L}\\p{N}][\\p{L}\\p{N}_-]*$",
    },
    singleLine: {
      type: "string",
      minLength: 1,
      pattern:
        "^(?=[\\s\\S]*\\S)[^\\r\\n\\v\\f\\u0085\\u2028\\u2029]+(?![\\s\\S])",
    },
    option: {
      type: "object",
      additionalProperties: false,
      required: ["label", "value"],
      properties: {
        label: { $ref: "#/$defs/singleLine" },
        value: { $ref: "#/$defs/singleLine" },
      },
    },
    field: {
      type: "object",
      additionalProperties: false,
      required: ["id", "label", "type"],
      properties: {
        id: { $ref: "#/$defs/id" },
        label: { $ref: "#/$defs/singleLine" },
        type: { enum: ["text", "secret", "select", "multi_select"] },
        options: {
          type: "array",
          minItems: 1,
          maxItems: requestLimits.optionsPerField,
          items: { $ref: "#/$defs/option" },
        },
      },
      allOf: [
        {
          if: {
            properties: {
              type: { enum: ["select", "multi_select"] },
            },
            required: ["type"],
          },
          then: { required: ["options"] },
          else: { not: { required: ["options"] } },
        },
      ],
    },
    delivery: {
      type: "object",
      additionalProperties: false,
      required: ["id", "path", "operation", "template"],
      properties: {
        id: { $ref: "#/$defs/id" },
        path: {
          type: "string",
          pattern: "^/",
          description:
            "Absolute path to an existing readable and writable regular file.",
        },
        operation: { enum: ["append", "insert_line"] },
        line: { type: "integer", minimum: 1 },
        template: {
          type: "string",
          pattern:
            "\\{\\{\\s*[\\p{L}\\p{N}][\\p{L}\\p{N}_-]*\\s*\\}\\}",
          description:
            "Must contain a reference to an existing field; brace syntax and secret references are validated semantically.",
        },
      },
      allOf: [
        {
          if: {
            properties: { operation: { const: "insert_line" } },
            required: ["operation"],
          },
          then: { required: ["line"] },
          else: { not: { required: ["line"] } },
        },
      ],
    },
  },
} as const;
