import { findGraphFile, zoomGraphCamera } from './graph-inspection.js';
import { graphButton, graphText } from './graph-language.js';
import { createGraphBrowser } from './graph-browser.js';
import { graphViewSettings, graphControlsHelp } from './graph-view-settings.js';
import { graphViewState, restoreGraphView, currentGraphSelection, compatibleGraphViewport } from './graph-view-state.js';
import { fitGraphCamera, hasVisibleGraphSource, updateGraphFog } from './graph-camera-framing.js';
import { graphControlIcon } from './graph-control-icons.js';
import { layoutGraphLabels } from './graph-label-layout.js';

export function createGraphControls(root, data, board, inspector) {
  const document = root.ownerDocument, controls = document.createElement('nav');
  const tools = document.createElement('nav'); tools.className = 'graph-tools hud';
  controls.className = 'graph-camera hud'; controls.setAttribute('aria-label', graphText(document, 'Graph camera controls'));
  const store = graphViewState(document.defaultView, data);
  let saved = store.load();
  const sameViewport = compatibleGraphViewport(board.getCamera(), saved);
  if (saved) saved.selection = currentGraphSelection(data, saved.selection);
  if (saved && !saved.selection) {
    restoreGraphView(board, inspector, saved, sameViewport);
    if (!sameViewport || !hasVisibleGraphSource(board, data)) saved = { ...saved, refit: true };
  }
  const threshold = Number(saved?.preferences?.threshold);
  const preferences = { threshold: Number.isFinite(threshold) ? Math.min(300, Math.max(10, threshold)) : 100,
    pan: saved?.preferences?.pan === true };
  const save = () => store.save(board, inspector, preferences);
  const selected = saved?.selection && findGraphFile(data, saved.selection);
  let restoring = Boolean(selected);
  if (!saved || saved.refit || !sameViewport) fitGraphCamera(board, data, 'iso');
  if (selected) {
    if (saved.selection.index != null) board.focusSection(selected.id, saved.selection.index);
    else board.focusNode(selected.id);
    // Repo Lens lays out section labels on the next frame. Retain the user's
    // orbit after that layout instead of leaving the section's default flight.
    document.defaultView.requestAnimationFrame?.(() => {
      if (restoring) restoreGraphView(board, inspector, saved, sameViewport && !saved.refit);
      if (restoring && !sameViewport) inspector.frame();
      restoring = false;
    });
  }
  restoreGraphView(board, inspector, saved, sameViewport && !saved?.refit);
  const openFiles = createGraphBrowser(root, data, board, inspector);
  const openSettings = graphViewSettings(root, data, board, inspector, preferences, save);
  const openHelp = graphControlsHelp(root);
  const action = (label, callback, parent = controls, icon = false) => {
    const button = graphButton(document, label, () => { restoring = false; callback(); });
    if (icon) graphControlIcon(button, label);
    parent.append(button);
  };
  const zoom = (label, factor, title) => {
    const control = graphButton(document, label, () => { restoring = false; zoomGraphCamera(board, factor); save(); });
    control.textContent = graphText(document, title); control.title = control.textContent;
    graphControlIcon(control, title); controls.append(control);
  };
  zoom('−', 1.25, 'Zoom out'); zoom('+', 0.8, 'Zoom in');
  for (const [label, view] of [['Fit', 'reset'], ['Top', 'top'], ['ISO', 'iso']]) {
    action(label, () => {
      root.querySelector(`[data-view="${view}"]`)?.click();
      inspector.close();
      fitGraphCamera(board, data, view); save();
    }, controls, true);
  }
  const mode = graphButton(document, 'Orbit', () => { restoring = false; preferences.pan = !preferences.pan; updateMode(); save(); });
  function updateMode() {
    mode.textContent = graphText(document, preferences.pan ? 'Pan' : 'Orbit');
    board.stopCameraFlight();
    const camera = board.getControls(); camera.mouseButtons.LEFT = preferences.pan ? 2 : 0;
    camera.touches.ONE = preferences.pan ? 1 : 0; mode.setAttribute('aria-pressed', String(preferences.pan));
  }
  updateMode(); controls.append(mode);
  action('Files', openFiles, tools, true); action('Highlights', openSettings, tools, true); action('Help', openHelp, tools, true);
  action('Full screen', () => { save(); document.defaultView.webkit?.messageHandlers?.graphStatus?.postMessage('fullscreen'); }, tools, true);
  root.append(controls, tools);
  const measure = () => root.style.setProperty('--graph-dock-space',
    `${Math.max(64, Math.ceil(controls.getBoundingClientRect().height)) + 28}px`);
  const observer = document.defaultView.ResizeObserver && new document.defaultView.ResizeObserver(measure);
  observer?.observe(controls); measure();
  let labelFrame;
  const scheduleLabels = () => {
    if (labelFrame != null) return;
    labelFrame = document.defaultView.requestAnimationFrame?.(() => { labelFrame = null; layoutGraphLabels(root); });
  };
  const labelsObserver = document.defaultView.MutationObserver && new document.defaultView.MutationObserver(scheduleLabels);
  labelsObserver?.observe(root, { childList: true, subtree: true });
  const resized = () => document.defaultView.requestAnimationFrame?.(() => {
    if (inspector.selection()) inspector.frame();
    else fitGraphCamera(board, data);
    scheduleLabels();
  });
  document.defaultView.addEventListener('resize', resized); scheduleLabels();
  const moved = () => { updateGraphFog(board); save(); scheduleLabels(); };
  const selectedSource = () => { save(); scheduleLabels(); };
  root.addEventListener('graphselection', selectedSource); board.getControls().addEventListener?.('change', moved);
  return { save, dispose() {
    observer?.disconnect();
    labelsObserver?.disconnect(); document.defaultView.cancelAnimationFrame?.(labelFrame);
    document.defaultView.removeEventListener('resize', resized);
    root.removeEventListener('graphselection', selectedSource); board.getControls().removeEventListener?.('change', moved);
  } };
}
