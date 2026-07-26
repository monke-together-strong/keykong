import { requestLimits } from "./limits";

export const requestSchema = {
  $schema: "https://json-schema.org/draft/2020-12/schema",
  $id: "https://key-kong.dev/schema/request-v1.json",
  title: "Key Kong request",
  description:
    `Version 1 request contract for Key Kong. Serialized requests are limited to ${requestLimits.bytes} bytes.`,
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
      oneOf: [
        { $ref: "#/$defs/appendDelivery" },
        { $ref: "#/$defs/insertLineDelivery" },
        { $ref: "#/$defs/setEnvDelivery" },
      ],
    },
    appendDelivery: {
      type: "object",
      additionalProperties: false,
      required: ["id", "path", "operation", "template"],
      properties: {
        id: { $ref: "#/$defs/id" },
        path: { $ref: "#/$defs/deliveryPath" },
        operation: { const: "append" },
        template: { $ref: "#/$defs/deliveryTemplate" },
      },
    },
    insertLineDelivery: {
      type: "object",
      additionalProperties: false,
      required: ["id", "path", "operation", "line", "template"],
      properties: {
        id: { $ref: "#/$defs/id" },
        path: { $ref: "#/$defs/deliveryPath" },
        operation: { const: "insert_line" },
        line: { type: "integer", minimum: 1 },
        template: { $ref: "#/$defs/deliveryTemplate" },
      },
    },
    setEnvDelivery: {
      type: "object",
      additionalProperties: false,
      required: ["id", "path", "operation", "key", "field"],
      properties: {
        id: { $ref: "#/$defs/id" },
        path: { $ref: "#/$defs/deliveryPath" },
        operation: {
          const: "set_env",
          description:
            "Sets one Environment Assignment from one single-valued field.",
        },
        key: {
          type: "string",
          pattern: "^[A-Za-z_][A-Za-z0-9_]*$",
          description: "The exact, case-sensitive dotenv key to set.",
        },
        field: {
          $ref: "#/$defs/id",
          description:
            "The stable ID of a text, secret, or single-select source field.",
        },
      },
    },
    deliveryPath: {
      type: "string",
      pattern: "^/",
      description:
        "Absolute path to an existing readable and writable regular file.",
    },
    deliveryTemplate: {
      type: "string",
      pattern:
        "\\{\\{\\s*[\\p{L}\\p{N}][\\p{L}\\p{N}_-]*\\s*\\}\\}",
      description:
        "Must contain a reference to an existing field; brace syntax and secret references are validated semantically.",
    },
  },
} as const;
