import { sourceSegments } from './graph-source-sections.js';

// Convert the bounded Weavatrix reports visible to this Mesh into Repo Lens data.
// The renderer never receives source contents, credentials, or synthetic demo data.
function sourceNodes(report) {
  const map = report.codeMap;
  if (Array.isArray(map?.files) && map.files.length) {
    return map.files.map(file => ({
      id: file.path, label: file.path.split('/').at(-1), path: file.path,
      module: `${report.repositoryId}/${file.path.includes('/') ? file.path.slice(0, file.path.lastIndexOf('/')) : '.'}`,
      moduleTitle: file.path.includes('/') ? file.path.slice(0, file.path.lastIndexOf('/')) : '(root)',
      kind: 'file', lineCount: file.lineCount, language: file.language, symbols: file.symbols || [],
    }));
  }
  return (report.nodes || []).map(node => ({
    id: node.id, label: node.label, path: node.id,
    module: report.repositoryId, kind: node.kind, symbols: [],
    moduleTitle: report.repositoryId.split('/').at(-1),
  }));
}

function edgeType(relation) {
  const label = String(relation || '').toLowerCase();
  if (label.includes('call')) return 'call';
  if (label.includes('inherit') || label.includes('extend')) return 'inherit';
  if (label.includes('import') || label.includes('depend')) return 'import';
  return 'relation';
}

function placeExternalServices(modules, services) {
  if (!services.length) return;
  const left = Math.min(...modules.map(module => module._cx - module._half));
  const near = Math.min(...modules.map(module => module._cz - module._half));
  const far = Math.max(...modules.map(module => module._cz + module._half));
  const rows = Math.min(8, services.length), center = (near + far) / 2;
  const step = Math.max(16, Math.min(28, (far - near) / Math.max(1, rows - 1)));
  services.forEach((service, index) => {
    service.x = left - 32 - Math.floor(index / rows) * 20;
    service.z = center + (index % rows - (rows - 1) / 2) * step;
  });
}

export function boardData(reports) {
  const modules = [], files = [], edges = [], exts = [];
  const identities = new Map(), componentIds = new Map();
  const selected = (reports || []).map(report => ({ report, nodes: sourceNodes(report) }))
    .filter(item => item.nodes.length);
  const names = [...new Set(selected.flatMap(item => item.nodes.map(node => node.module)))].sort();
  const multiple = new Set(selected.map(item => item.report.repositoryId)).size > 1;
  const titles = new Map(selected.flatMap(({ report, nodes }) => nodes.map(node => [node.module,
    multiple ? `${report.repositoryId.split('/').at(-1)} · ${node.moduleTitle}` : node.moduleTitle])));
  const columns = Math.max(1, Math.ceil(Math.sqrt(names.length)));
  const layouts = new Map();
  const largestHalf = Math.max(20, ...names.map(name => {
    const count = selected.reduce((sum, item) => sum + item.nodes.filter(node => node.module === name).length, 0);
    return Math.ceil(Math.sqrt(count)) * 9 + 8;
  }));
  const spacing = largestHalf * 2 + 26;
  names.forEach((name, index) => {
    const count = selected.reduce((sum, item) => sum + item.nodes.filter(node => node.module === name).length, 0);
    const grid = Math.ceil(Math.sqrt(count));
    const cx = (index % columns - (columns - 1) / 2) * spacing;
    const cz = (Math.floor(index / columns) - (Math.ceil(names.length / columns) - 1) / 2) * spacing;
    layouts.set(name, { index, grid, cx, cz, position: 0 });
    modules.push({ name, displayName: titles.get(name), n: count, _cx: cx, _cz: cz, _half: grid * 9 + 8, _g: grid });
  });
  selected.forEach(({ report, nodes }) => {
    nodes.forEach(node => {
      if (typeof node.id !== 'string' || typeof node.label !== 'string') return;
      const layout = layouts.get(node.module);
      const position = layout.position++;
      const x = layout.cx + ((position % layout.grid) - (layout.grid - 1) / 2) * 16;
      const z = layout.cz + (Math.floor(position / layout.grid) - (layout.grid - 1) / 2) * 16;
      const methods = sourceSegments(node);
      const id = files.length;
      identities.set(`${report.repositoryId}\u0000${node.id}`, id);
      if (!report.codeMap?.files?.length) componentIds.set(`${report.repositoryId}\u0000${node.id}`, id);
      files.push({ id, name: node.label, module: node.module, modIdx: layout.index,
        x, z, _path: node.path, _fileId: node.id, kind: node.kind, methods,
        repositoryId: report.repositoryId, sourceRevision: report.sourceRevision,
        analysisRevision: report.revision, analysisStatus: report.analysisStatus,
        partial: report.truncated || report.codeMap?.truncated || report.analysisStatus !== 'COMPLETE',
        language: node.language,
        unknownHealth: true, symbolsUnavailable: node.symbols.length === 0,
        reportedSectionCount: node.symbols.length,
        loc: node.lineCount ?? null, height: methods.reduce((sum, method) => sum + method.loc * 0.085 + 0.45, 0),
        coverage: null, fanIn: 0, fanOut: 0 });
    });
  });
  selected.forEach(({ report }) => {
    for (const external of report.codeMap?.externals || []) {
      const id = files.length + exts.length;
      identities.set(`${report.repositoryId}\u0000${external.id}`, id);
      exts.push({ id, name: `${external.label} · ${report.repositoryId}`,
        repositoryId: report.repositoryId, _path: external.id,
        sourceRevision: report.sourceRevision, analysisRevision: report.revision,
        analysisStatus: report.analysisStatus, partial: report.analysisStatus !== 'COMPLETE',
        symbolsUnavailable: true,
        kind: external.kind, isExternal: true, modIdx: -1, color: 0x8fa7c7,
        x: 0, z: 0, fanIn: 0, fanOut: 0, height: 7 });
    }
    // The file map and architecture report describe different levels of the
    // same repository. Keep services/components beside file towers instead of
    // silently dropping every architecture node when files are available.
    if (report.codeMap?.files?.length) for (const node of report.nodes || []) {
      const id = files.length + exts.length;
      componentIds.set(`${report.repositoryId}\u0000${node.id}`, id);
      exts.push({ id, name: `${node.label} · ${report.repositoryId}`,
        repositoryId: report.repositoryId, _path: node.id,
        sourceRevision: report.sourceRevision, analysisRevision: report.revision,
        analysisStatus: report.analysisStatus, partial: report.analysisStatus !== 'COMPLETE',
        symbolsUnavailable: true,
        kind: node.kind, isExternal: true, modIdx: -1,
        color: node.kind === 'service' ? 0x59d0a0 : 0xc38bff,
        x: 0, z: 0, fanIn: 0, fanOut: 0, height: 7 });
    }
  });
  placeExternalServices(modules, exts);
  const byId = [...files, ...exts];
  selected.forEach(({ report }) => {
    const map = report.codeMap;
    const addRelations = (relations, nodes, architecture = false) => { for (const relation of relations) {
      const a = nodes.get(`${report.repositoryId}\u0000${relation.source}`);
      const b = nodes.get(`${report.repositoryId}\u0000${relation.target}`);
      if (a === undefined || b === undefined) continue;
      edges.push({ a, b, type: !architecture && (byId[a].isExternal || byId[b].isExternal)
        ? 'io' : edgeType(relation.relation),
        relation: relation.relation, payload: relation.evidenceCount || 1 });
      byId[a].fanOut += 1;
      byId[b].fanIn += 1;
    } };
    if (map?.files?.length) addRelations(map.roads || [], identities);
    addRelations(report.relations || [], componentIds, true);
  });
  return { MODULES: modules, files, edges, exts, agent: null,
    projectIds: [...new Set(selected.map(item => item.report.projectId).filter(Boolean))].sort() };
}
