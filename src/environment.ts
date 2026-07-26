interface PhysicalLine {
  body: string;
  ending: "" | "\n" | "\r\n";
}

const prefixPattern = String.raw`[\t ]*(?:export [\t ]*)?`;
const targetPrefixPattern = String.raw`[=\t ]*(?:export [\t ]*)?`;
const assignmentPattern = new RegExp(
  `^${targetPrefixPattern}[^#=\\t ][^=]*=(.*)$`,
  "s",
);

function trimHorizontalStart(value: string): string {
  return value.replace(/^[\t ]*/, "");
}

function consumesFollowingLine(lines: PhysicalLine[], index: number): boolean {
  const next = lines
    .slice(index + 1)
    .map(({ body }) => trimHorizontalStart(body))
    .find((body) => body !== "");
  return next !== undefined && !next.startsWith("#");
}

function physicalLines(text: string): PhysicalLine[] {
  const lines: PhysicalLine[] = [];
  let start = 0;
  for (let index = 0; index < text.length; index++) {
    if (text[index] === "\r" && text[index + 1] !== "\n") {
      throw new Error("unsupported line ending");
    }
    if (text[index] !== "\n") continue;
    const crlf = index > start && text[index - 1] === "\r";
    lines.push({
      body: text.slice(start, crlf ? index - 1 : index),
      ending: crlf ? "\r\n" : "\n",
    });
    start = index + 1;
  }
  if (start < text.length) {
    lines.push({ body: text.slice(start), ending: "" });
  }
  return lines;
}

function validateTarget(
  lines: PhysicalLine[],
  replacedIndex?: number,
): "\n" | "\r\n" {
  const endings = new Set(
    lines.flatMap(({ ending }) => ending === "" ? [] : [ending]),
  );
  if (endings.size > 1) throw new Error("mixed line endings");

  for (const [index, { body }] of lines.entries()) {
    if (trimHorizontalStart(body).startsWith("#")) continue;
    const assignment = assignmentPattern.exec(body);
    const rawRightHandSide = assignment?.[1];
    if (
      rawRightHandSide !== "" &&
      rawRightHandSide !== undefined &&
      /^[\t ]+$/.test(rawRightHandSide) &&
      (
        index !== replacedIndex ||
        consumesFollowingLine(lines, index)
      )
    ) {
      throw new Error("cross-line whitespace assignment");
    }
    const rightHandSide = rawRightHandSide === undefined
      ? undefined
      : trimHorizontalStart(rawRightHandSide);
    const quote = rightHandSide?.[0];
    if (
      (quote === '"' || quote === "'" || quote === "`") &&
      rightHandSide!.lastIndexOf(quote) === 0 &&
      lines.slice(index + 1).some(({ body }) => body.includes(quote))
    ) {
      throw new Error("multiline quoted assignment");
    }
  }

  return [...endings][0] ?? "\n";
}

function serialize(value: string): string {
  // Submission validation rejects physical line breaks before delivery.
  // Node expands a literal \n sequence only inside double quotes.
  if (!value.includes('"') && !value.includes(String.raw`\n`)) {
    return `"${value}"`;
  }
  if (!value.includes("'")) return `'${value}'`;
  if (!/^[\t ]|[\t ]$/.test(value)) {
    const openingQuote = ['"', "'", "`"].includes(value[0]!)
      ? value[0]
      : undefined;
    if (
      openingQuote
        ? value.indexOf(openingQuote, 1) < 0
        : !value.includes("#")
    ) {
      return value;
    }
  }
  throw new Error("value cannot be represented losslessly");
}

export function setEnvironmentAssignment(
  content: Buffer,
  key: string,
  value: string,
): Buffer {
  const text = new TextDecoder("utf-8", {
    fatal: true,
    ignoreBOM: true,
  }).decode(content);
  const lines = physicalLines(text);
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const active = new RegExp(
    `^(${prefixPattern}${escapedKey}[\\t ]*=)(.*)$`,
    "s",
  );
  const matches = lines.flatMap(({ body }, index) => {
    if (trimHorizontalStart(body).startsWith("#")) return [];
    const match = active.exec(body);
    return match ? [{ index, prefix: match[1]! }] : [];
  });
  if (matches.length > 1) throw new Error("duplicate active key");
  const lineEnding = validateTarget(lines, matches[0]?.index);

  const serialized = serialize(value);
  if (matches.length === 1) {
    const { index, prefix } = matches[0]!;
    lines[index]!.body = `${prefix}${serialized}`;
  } else {
    if (lines.length > 0 && lines.at(-1)!.ending === "") {
      lines.at(-1)!.ending = lineEnding;
    }
    lines.push({
      body: `${key}=${serialized}`,
      ending: lineEnding,
    });
  }
  validateTarget(lines);

  return Buffer.from(
    lines.map(({ body, ending }) => body + ending).join(""),
    "utf8",
  );
}
