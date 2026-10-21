import { updateGraphFog } from './graph-camera-framing.js';

export function findGraphFile(data, selection) {
  const nodes = [...data.files, ...(data.exts || [])];
  if (typeof selection?.id === 'number') return nodes.find(file => file.id === selection.id);
  return nodes.find(file => file.repositoryId === selection?.repositoryId && file._path === selection?.path
    && Boolean(file.isExternal) === Boolean(selection?.external));
}

export function sourceSection(file, index) {
  const method = file?.methods?.[index];
  if (!method || file.symbolsUnavailable || method.sourceRemainder) return null;
  return { id: method.id, name: method.name, kind: method.kind, line: method.line,
    endLine: method.line == null ? null : method.line + method.loc - 1,
    loc: method.loc, repositoryId: file.repositoryId, path: file._path,
    sourceRevision: file.sourceRevision, analysisRevision: file.analysisRevision,
    analysisStatus: file.analysisStatus, partial: file.partial, metrics: method.metrics ?? null };
}

export function graphFileLinks(data, file) {
  const nodes = [...data.files, ...data.exts];
  return data.edges.filter(edge => edge.a === file.id || edge.b === file.id).map(edge => ({
    direction: edge.a === file.id ? 'out' : 'in', relation: edge.relation,
    neighbor: nodes.find(node => node.id === (edge.a === file.id ? edge.b : edge.a)),
  })).filter(link => link.neighbor);
}

export function graphFileMatches(data, query) {
  const needle = String(query || '').trim().toLocaleLowerCase();
  return [...data.files, ...(data.exts || [])].map(file => ({ file,
    sections: file.symbolsUnavailable ? [] : (file.methods || []).map((section, index) => ({ section, index }))
      .filter(item => !item.section.sourceRemainder && needle && item.section.name.toLocaleLowerCase().includes(needle)),
  })).filter(item => !needle || item.file._path.toLocaleLowerCase().includes(needle)
    || item.file.name?.toLocaleLowerCase().includes(needle) || item.sections.length);
}

export function zoomGraphCamera(board, factor) {
  const camera = board.getCamera(), controls = board.getControls();
  if (!Number.isFinite(factor) || factor <= 0) return false;
  board.stopCameraFlight();
  if (controls.enableDamping) {
    const position = camera.position.clone(), target = controls.target.clone();
    // Drain OrbitControls' pending rotation/pan without moving the user's
    // current frame. Its next animation tick must not rotate a zoom button.
    controls.enableDamping = false; controls.update();
    camera.position.copy(position); controls.target.copy(target); controls.update();
    controls.enableDamping = true;
  }
  const delta = camera.position.clone().sub(controls.target);
  const distance = delta.length();
  if (!distance) return false;
  camera.position.copy(controls.target).add(delta.multiplyScalar(
    Math.min(controls.maxDistance ?? 12_000, Math.max(controls.minDistance ?? 8, distance * factor)) / distance));
  updateGraphFog(board); controls.update();
  return true;
}

export function applySectionHighlights(board, data, limit) {
  const threshold = Number.isFinite(Number(limit)) ? Math.max(10, Number(limit)) : 100;
  board.getScene().traverse(node => {
    const id = node.userData?.fileId, index = node.userData?.methodIndex;
    if (!Number.isInteger(index) || !node.material?.color) return;
    const file = data.files.find(file => file.id === id), section = sourceSection(file, index);
    node.userData.granttapBaseColor ??= node.material.color.clone();
    node.material.color.copy(node.userData.granttapBaseColor);
    if (section && section.loc > threshold) node.material.color.set(0xffb454);
    if (node.material.emissive) node.material.emissive.copy(node.material.color);
  });
}
