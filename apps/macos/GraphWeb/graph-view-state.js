import { findGraphFile } from './graph-inspection.js';
import { updateGraphFog } from './graph-camera-framing.js';

function stateKey(data) {
  const identity = JSON.stringify(['projects', data.projectIds || [],
    'repositories', [...new Set(data.files.map(file => file.repositoryId))].sort()]);
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
const validView = view => view && view.enabled && ['fullWidth', 'fullHeight', 'width', 'height']
  .every(key => Number.isFinite(view[key]) && view[key] > 0 && view[key] <= 16384)
  && ['offsetX', 'offsetY'].every(key => Number.isFinite(view[key]) && Math.abs(view[key]) <= 16384);

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
          viewport: { aspect: board.getCamera().aspect },
          view: board.getCamera().view,
          selection: inspector.selection(), preferences,
        }));
      } catch { /* View preferences do not affect the saved source reports. */ }
    },
  };
}

export function compatibleGraphViewport(camera, value) {
  const previous = value?.viewport?.aspect;
  return !Number.isFinite(previous) || previous <= 0 || !Number.isFinite(camera.aspect)
    || Math.max(camera.aspect / previous, previous / camera.aspect) <= 1.15;
}

export function restoreGraphView(board, inspector, value, restoreCamera = true) {
  if (!value) return;
  const camera = board.getCamera(), view = value.view;
  board.stopCameraFlight();
  if (restoreCamera) {
    camera.position.fromArray(value.position);
    if (validView(view)) {
      const width = camera.aspect * 1000, height = 1000;
      camera.setViewOffset(width, height, view.offsetX / view.fullWidth * width,
        view.offsetY / view.fullHeight * height, width, height);
    } else camera.clearViewOffset();
    board.getControls().target.fromArray(value.target); board.getControls().update();
    updateGraphFog(board);
  }
  if (value.selection && inspector.restoreSelection) inspector.restoreSelection(value.selection);
  else if (value.selection?.index != null) inspector.openMethod(value.selection);
  else if (value.selection) inspector.openFile(value.selection);
}
