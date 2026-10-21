export const sectionKinds = {
  function: { title: 'Functions', color: 0x26d7ed }, method: { title: 'Methods', color: 0x6ba8ff },
  type: { title: 'Types', color: 0xc58bff }, constant: { title: 'Constants', color: 0xffce79 },
  variable: { title: 'Variables', color: 0x72d9b0 }, other: { title: 'Other symbols', color: 0xd1a6c7 },
};

export function sectionKind(section) {
  const kind = String(section?.kind || '').toLowerCase();
  if (kind.includes('method') || kind === 'constructor') return 'method';
  if (kind.includes('function')) return 'function';
  if (['class', 'struct', 'enum', 'interface', 'trait', 'type', 'type_alias'].includes(kind)) return 'type';
  if (kind.includes('constant') || kind === 'const') return 'constant';
  if (['variable', 'field', 'property', 'parameter'].includes(kind)) return 'variable';
  return 'other';
}

const bounded = (value, fallback, minimum, maximum) => Number.isFinite(Number(value))
  ? Math.max(minimum, Math.min(maximum, Number(value))) : fallback;

export function graphPreferences(saved = {}) {
  if (!saved || typeof saved !== 'object' || Array.isArray(saved)) saved = {};
  return {
    mode: ['kind', 'size', 'health', 'none'].includes(saved.mode) ? saved.mode : 'kind',
    threshold: bounded(saved.threshold, 100, 10, 500),
    maxComplexity: bounded(saved.maxComplexity, 10, 1, 100),
    maxLoopDepth: bounded(saved.maxLoopDepth, 3, 1, 20),
    kinds: Object.fromEntries(Object.keys(sectionKinds).map(kind => [kind, saved.kinds?.[kind] !== false])),
    modules: saved.modules !== false, files: saved.files !== false, sections: saved.sections !== false,
    edges: saved.edges && typeof saved.edges === 'object' ? { ...saved.edges } : {},
    relatedOnly: saved.relatedOnly === true, pan: saved.pan === true,
    entryPoints: saved.entryPoints !== false,
    sourceBody: saved.sourceBody !== false,
  };
}

export const linkKinds = {
  import: { title: 'Imports', color: 0xb06bff }, call: { title: 'Calls', color: 0xffb454 },
  inherit: { title: 'Inheritance', color: 0x28e0ff }, relation: { title: 'Other relations', color: 0xb06bff },
  io: { title: 'External links', color: 0x59d0a0 }, local: { title: 'Local links', color: 0xff6ec7 },
};

export function sectionChecks(section, preferences) {
  const metrics = section?.metrics;
  if (!metrics?.measured || section.sourceRemainder || !['function', 'method'].includes(sectionKind(section))) {
    return { status: 'unknown', reasons: [] };
  }
  const checks = [ ['length', metrics.sourceLines, preferences.threshold],
    ['complexity', metrics.cyclomatic, preferences.maxComplexity],
    ['nesting', metrics.maxLoopDepth, preferences.maxLoopDepth] ];
  if (checks.some(([, value]) => !Number.isFinite(value) || value < 0)) return { status: 'unknown', reasons: [] };
  const reasons = checks.filter(([, value, limit]) => value > limit)
    .map(([rule, value, limit]) => ({ rule, value, limit }));
  return { status: reasons.length ? 'review' : 'clear', reasons };
}

export const checkColors = { unknown: 0x69889a, clear: 0x64dca6, review: 0xff6878 };
