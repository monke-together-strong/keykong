import type { ResponseValue } from "./types";

const fieldReference =
  /\{\{\s*([\p{L}\p{N}][\p{L}\p{N}_-]*)\s*\}\}/gu;

export function parseTemplate(
  template: string,
): { references: string[]; literal: string } | undefined {
  const references: string[] = [];
  const literal = template.replace(fieldReference, (_, fieldID: string) => {
    references.push(fieldID);
    return "";
  });
  return literal.includes("{{") || literal.includes("}}")
    ? undefined
    : { references, literal };
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
