export function insertBeforeLine(
  content: Buffer,
  line: number,
  rendered: Buffer,
): Buffer | undefined {
  let offset = 0;
  let currentLine = 1;
  while (currentLine < line && offset < content.length) {
    const newline = content.indexOf(10, offset);
    if (newline < 0) return undefined;
    offset = newline + 1;
    currentLine++;
  }
  if (currentLine !== line) return undefined;

  const addition =
    rendered.at(-1) === 10
      ? rendered
      : Buffer.concat([rendered, Buffer.from("\n")]);
  return Buffer.concat([
    content.subarray(0, offset),
    addition,
    content.subarray(offset),
  ]);
}
