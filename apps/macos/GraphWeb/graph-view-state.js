function stateKey(data) {
  const identity = JSON.stringify(data.projectIds?.length ? ['projects', data.projectIds]
    : ['repositories', [...new Set(data.files.map(file => file.repositoryId))].sort()]);
  let hash = 5381;
  for (const char of identity) hash = (Math.imul(hash, 33) ^ char.charCodeAt(0)) >>> 0;
  return `granttap.graph.view.scope.${hash}`;
}

export function currentGraphSelection(data, selection) {
  if (!selection) return null;
  const file = findGraphFile(data, selection);
  if (!file) return null;
  const index = (file.methods || []).findIndex(method => method.id != null && method.id === selection.symbolId);
  return { ...selection, index: index < 0 || file.symbolsUnavailable ? null : index };
}

const validVector = vector => Array.isArray(vector) && vector.length === 3
  && vector.every(number => Number.isFinite(number) && Math.abs(number) <= 12_000);

export function graphViewState(window, data) {
  const key = stateKey(data);
  return {
    load() {
      try {
        const value = JSON.parse(window.localStorage.getItem(key) || 'null');
        return value && validVector(value.position) && validVector(value.target) ? value : null;
      } catch { return null; }
    },
    save(board, inspector, preferences) {
      try {
        window.localStorage.setItem(key, JSON.stringify({
          position: board.getCamera().position.toArray(), target: board.getControls().target.toArray(),
          selection: inspector.selection(), preferences,
        }));
      } catch { /* View preferences do not affect the saved source reports. */ }
    },
  };
}

export function restoreGraphView(board, inspector, value) {
  if (!value) return;
  board.stopCameraFlight(); board.getCamera().position.fromArray(value.position);
  board.getControls().target.fromArray(value.target); board.getControls().update();
  if (value.selection && inspector.restoreSelection) inspector.restoreSelection(value.selection);
  else if (value.selection?.index != null) inspector.openMethod(value.selection);
  else if (value.selection) inspector.openFile(value.selection);
}
import { findGraphFile } from './graph-inspection.js';

