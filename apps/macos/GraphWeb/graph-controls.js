import { findGraphFile, zoomGraphCamera } from './graph-inspection.js';
import { graphButton, graphText } from './graph-language.js';
import { createGraphBrowser } from './graph-browser.js';
import { graphViewSettings, graphControlsHelp } from './graph-view-settings.js';
import { graphViewState, restoreGraphView, currentGraphSelection } from './graph-view-state.js';

export function createGraphControls(root, data, board, inspector) {
  const document = root.ownerDocument, controls = document.createElement('nav');
  controls.className = 'graph-camera'; controls.setAttribute('aria-label', graphText(document, 'Graph camera controls'));
  const store = graphViewState(document.defaultView, data), saved = store.load();
  if (saved) saved.selection = currentGraphSelection(data, saved.selection);
  const threshold = Number(saved?.preferences?.threshold);
  const preferences = { threshold: Number.isFinite(threshold) ? Math.min(300, Math.max(10, threshold)) : 100,
    pan: saved?.preferences?.pan === true };
  const save = () => store.save(board, inspector, preferences);
  const selected = saved?.selection && findGraphFile(data, saved.selection);
  if (selected) {
    if (saved.selection.index != null) board.focusSection(selected.id, saved.selection.index);
    else board.focusNode(selected.id);
    // Repo Lens lays out section labels on the next frame. Retain the user's
    // orbit after that layout instead of leaving the section's default flight.
    document.defaultView.requestAnimationFrame?.(() => restoreGraphView(board, inspector, saved));
  }
  restoreGraphView(board, inspector, saved);
  const openFiles = createGraphBrowser(root, data, board, inspector);
  const openSettings = graphViewSettings(root, data, board, inspector, preferences, save);
  const openHelp = graphControlsHelp(root);
  const action = (label, callback) => controls.append(graphButton(document, label, callback));
  const zoom = (label, factor, title) => {
    const control = graphButton(document, label, () => { zoomGraphCamera(board, factor); save(); });
    control.setAttribute('aria-label', graphText(document, title)); control.title = graphText(document, title); controls.append(control);
  };
  zoom('−', 1.25, 'Zoom out'); zoom('+', 0.8, 'Zoom in');
  for (const [label, view] of [['Fit', 'reset'], ['Top', 'top'], ['ISO', 'iso']]) {
    action(label, () => root.querySelector(`[data-view="${view}"]`)?.click());
  }
  const mode = graphButton(document, 'Orbit', () => { preferences.pan = !preferences.pan; updateMode(); save(); });
  function updateMode() {
    mode.textContent = graphText(document, preferences.pan ? 'Pan' : 'Orbit');
    board.stopCameraFlight();
    const camera = board.getControls(); camera.mouseButtons.LEFT = preferences.pan ? 2 : 0;
    camera.touches.ONE = preferences.pan ? 1 : 0; mode.setAttribute('aria-pressed', String(preferences.pan));
  }
  updateMode(); controls.append(mode); action('Files', openFiles); action('Highlights', openSettings); action('Help', openHelp);
  action('Full screen', () => { save(); document.defaultView.webkit?.messageHandlers?.graphStatus?.postMessage('fullscreen'); });
  root.append(controls);
  root.addEventListener('graphselection', save); board.getControls().addEventListener?.('change', save);
  return { save, dispose() { root.removeEventListener('graphselection', save); board.getControls().removeEventListener?.('change', save); } };
}
