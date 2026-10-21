/** Render measured source that was not assigned to a reported symbol separately. */
export function sourceSegments(node) {
  const methods = node.symbols.map(symbol => ({ id: symbol.id, kind: symbol.kind, name: symbol.label,
    loc: Math.max(1, Number(symbol.lineCount) || 1), line: symbol.startLine, health: null,
    metrics: symbol.metrics ?? null }));
  if (!methods.length) return [{ name: 'Symbols unavailable',
    loc: Math.max(1, Number(node.lineCount) || 20), health: null, sourceRemainder: true }];
  const total = node.lineCount;
  if (!Number.isInteger(total) || total <= 0 || node.symbols.some(symbol =>
    !Number.isInteger(symbol.startLine) || !Number.isInteger(symbol.lineCount))) return methods;
  const ranges = node.symbols.map(symbol => [Math.max(1, symbol.startLine),
    Math.min(total, symbol.startLine + Math.max(0, symbol.lineCount) - 1)])
    .sort((a, b) => a[0] - b[0]);
  let covered = 0, end = 0;
  for (const [start, finish] of ranges) {
    covered += Math.max(0, finish - Math.max(start, end + 1) + 1);
    end = Math.max(end, finish);
  }
  if (covered < total) methods.push({ name: 'Other source lines', kind: 'source',
    loc: total - covered, health: null, sourceRemainder: true });
  return methods;
}
