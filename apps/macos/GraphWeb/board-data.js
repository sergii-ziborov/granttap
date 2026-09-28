// Convert the bounded Weavatrix reports visible to this Mesh into Repo Lens data.
// The renderer never receives source contents, credentials, or synthetic demo data.
function sourceNodes(report) {
  const map = report.codeMap;
  if (Array.isArray(map?.files) && map.files.length) {
    return map.files.map(file => ({
      id: file.path, label: file.path.split('/').at(-1), path: file.path,
      module: `${report.repositoryId}/${file.path.includes('/') ? file.path.slice(0, file.path.lastIndexOf('/')) : '.'}`,
      kind: 'file', lineCount: file.lineCount, symbols: file.symbols || [],
    }));
  }
  return (report.nodes || []).map(node => ({
    id: node.id, label: node.label, path: node.id,
    module: report.repositoryId, kind: node.kind, symbols: [],
  }));
}

function edgeType(relation) {
  const label = String(relation || '').toLowerCase();
  if (label.includes('call')) return 'call';
  if (label.includes('inherit') || label.includes('extend')) return 'inherit';
  if (label.includes('import') || label.includes('depend')) return 'import';
  return 'relation';
}

export function boardData(reports) {
  const modules = [], files = [], edges = [], exts = [];
  const identities = new Map();
  const selected = (reports || []).map(report => ({ report, nodes: sourceNodes(report) }))
    .filter(item => item.nodes.length);
  const names = [...new Set(selected.flatMap(item => item.nodes.map(node => node.module)))].sort();
  const columns = Math.max(1, Math.ceil(Math.sqrt(names.length)));
  const layouts = new Map();
  names.forEach((name, index) => {
    const count = selected.reduce((sum, item) => sum + item.nodes.filter(node => node.module === name).length, 0);
    const grid = Math.ceil(Math.sqrt(count));
    const cx = (index % columns - (columns - 1) / 2) * 110;
    const cz = (Math.floor(index / columns) - (Math.ceil(names.length / columns) - 1) / 2) * 110;
    layouts.set(name, { index, grid, cx, cz, position: 0 });
    modules.push({ name, n: count, _cx: cx, _cz: cz, _half: grid * 9 + 8, _g: grid });
  });
  selected.forEach(({ report, nodes }) => {
    nodes.forEach(node => {
      if (typeof node.id !== 'string' || typeof node.label !== 'string') return;
      const layout = layouts.get(node.module);
      const position = layout.position++;
      const x = layout.cx + ((position % layout.grid) - (layout.grid - 1) / 2) * 16;
      const z = layout.cz + (Math.floor(position / layout.grid) - (layout.grid - 1) / 2) * 16;
      const methods = node.symbols.map(symbol => ({ name: symbol.label,
        loc: Math.max(1, Number(symbol.lineCount) || 1), line: symbol.startLine, health: null }));
      if (!methods.length) methods.push({ name: 'Symbols unavailable',
        loc: Math.max(1, Number(node.lineCount) || 20), health: null });
      const id = files.length;
      identities.set(`${report.repositoryId}\u0000${node.id}`, id);
      files.push({ id, name: node.label, module: node.module, modIdx: layout.index,
        x, z, _path: node.path, _fileId: node.id, kind: node.kind, methods,
        unknownHealth: true, symbolsUnavailable: node.symbols.length === 0,
        loc: node.lineCount ?? null, height: methods.reduce((sum, method) => sum + method.loc * 0.085 + 0.45, 0),
        coverage: null, fanIn: 0, fanOut: 0 });
    });
  });
  selected.forEach(({ report }) => {
    for (const external of report.codeMap?.externals || []) {
      const id = files.length + exts.length;
      identities.set(`${report.repositoryId}\u0000${external.id}`, id);
      exts.push({ id, name: `${external.label} · ${report.repositoryId}`,
        kind: external.kind, isExternal: true, modIdx: -1, color: 0x8fa7c7,
        x: -130 - Math.floor(exts.length / 8) * 18,
        z: (exts.length % 8 - 3.5) * 20, fanIn: 0, fanOut: 0, height: 7 });
    }
  });
  const byId = [...files, ...exts];
  selected.forEach(({ report }) => {
    const map = report.codeMap;
    const relations = map?.files?.length ? (map.roads || []) : (report.relations || []);
    for (const relation of relations) {
      const a = identities.get(`${report.repositoryId}\u0000${relation.source}`);
      const b = identities.get(`${report.repositoryId}\u0000${relation.target}`);
      if (a === undefined || b === undefined) continue;
      edges.push({ a, b, type: byId[a].isExternal || byId[b].isExternal ? 'io' : edgeType(relation.relation),
        relation: relation.relation, payload: relation.evidenceCount || 1 });
      byId[a].fanOut += 1;
      byId[b].fanIn += 1;
    }
  });
  return { MODULES: modules, files, edges, exts, agent: null };
}
