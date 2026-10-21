import { sectionKind, sectionKinds, sectionChecks, checkColors } from './graph-highlight-policy.js';

export function applyGraphHighlights(root, board, data, preferences, selection) {
  const files = new Map(data.files.map(file => [file.id, file]));
  const selected = [...data.files, ...(data.exts || [])].find(file =>
    file.repositoryId === selection?.repositoryId && file._path === selection?.path);
  board.getScene().traverse(node => {
    const file = files.get(node.userData?.fileId), index = node.userData?.methodIndex;
    if (!Number.isInteger(index) || !node.material?.color || !file) return;
    const section = file.methods?.[index], material = node.material;
    node.userData.granttapBaseColor ??= material.color.clone();
    node.userData.granttapBaseOpacity ??= material.opacity;
    material.color.copy(node.userData.granttapBaseColor);
    const measured = section && !section.sourceRemainder && !file.symbolsUnavailable;
    if (measured && preferences.mode === 'kind') material.color.set(sectionKinds[sectionKind(section)].color);
    if (measured && preferences.mode === 'size' && section.loc > preferences.threshold) material.color.set(0xffb454);
    if (measured && preferences.mode === 'health') material.color.set(checkColors[sectionChecks(section, preferences).status]);
    material.opacity = measured && preferences.mode === 'kind' && !preferences.kinds[sectionKind(section)]
      ? 0.18 : node.userData.granttapBaseOpacity;
    if (material.transparent !== (material.opacity < 1)) material.needsUpdate = true;
    material.transparent = material.opacity < 1;
    if (material.emissive) material.emissive.copy(material.color);
  });
  for (const key of ['modules', 'files', 'sections']) {
    root.classList.toggle(`graph-hide-${key === 'modules' ? 'module' : key === 'files' ? 'file' : 'section'}-labels`, !preferences[key]);
  }
  for (const edge of data.edges) {
    const enabled = preferences.edges[edge.type] !== false && (!preferences.relatedOnly || !selected
      || edge.a === selected.id || edge.b === selected.id);
    if (edge.mesh) edge.mesh.visible = enabled;
    if (edge.line) edge.line.visible = enabled;
    edge.granttapVisible = enabled;
  }
  board.setGraphDisplayPreferences?.({ edges: preferences.edges,
    markers: { entry: preferences.entryPoints },
    relatedId: preferences.relatedOnly && selected ? selected.id : null });
}
