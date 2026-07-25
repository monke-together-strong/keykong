import type { ResponseValue } from "./types";

const fieldReference =
  /\{\{\s*([\p{L}\p{N}][\p{L}\p{N}_-]*)\s*\}\}/gu;

export function parseTemplate(
  template: string,
): {
  references: string[];
  literal: string;
  trailingLiteral: string;
} | undefined {
  const references: string[] = [];
  let trailingLiteralStart = 0;
  const literal = template.replace(
    fieldReference,
    (match: string, fieldID: string, offset: number) => {
      references.push(fieldID);
      trailingLiteralStart = offset + match.length;
      return "";
    },
  );
  return literal.includes("{{") || literal.includes("}}")
    ? undefined
    : {
      references,
      literal,
      trailingLiteral: template.slice(trailingLiteralStart),
    };
}

export function renderTemplate(
  template: string,
  values: Record<string, ResponseValue>,
): Buffer {
  return Buffer.from(
    template.replace(fieldReference, (_, fieldID: string) => {
      const value = values[fieldID]!;
      return Array.isArray(value) ? JSON.stringify(value) : value;
    }),
  );
}
