export const requestSchema = {
  $schema: "https://json-schema.org/draft/2020-12/schema",
  $id: "https://key-kong.dev/schema/request-v1.json",
  title: "Key Kong request",
  type: "object",
  additionalProperties: false,
  required: ["schemaVersion", "id", "title", "fields"],
  properties: {
    schemaVersion: { const: 1 },
    id: { $ref: "#/$defs/id" },
    title: { type: "string", minLength: 1 },
    fields: {
      type: "array",
      minItems: 1,
      items: { $ref: "#/$defs/field" },
    },
    deliveries: {
      type: "array",
      items: { $ref: "#/$defs/delivery" },
    },
  },
  $defs: {
    id: {
      type: "string",
      pattern: "^[\\p{L}\\p{N}][\\p{L}\\p{N}_-]*$",
    },
    option: {
      type: "object",
      additionalProperties: false,
      required: ["label", "value"],
      properties: {
        label: { type: "string", minLength: 1 },
        value: { type: "string", minLength: 1 },
      },
    },
    field: {
      type: "object",
      additionalProperties: false,
      required: ["id", "label", "type"],
      properties: {
        id: { $ref: "#/$defs/id" },
        label: { type: "string", minLength: 1 },
        type: { enum: ["text", "secret", "select", "multi_select"] },
        options: {
          type: "array",
          minItems: 1,
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
        path: { type: "string", minLength: 1 },
        operation: { enum: ["append", "insert_line"] },
        line: { type: "integer", minimum: 1 },
        template: { type: "string" },
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
