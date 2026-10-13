import { applySectionHighlights } from './graph-inspection.js';
import { graphButton, graphText } from './graph-language.js';

export function graphViewSettings(root, data, board, inspector, preferences, save) {
  const document = root.ownerDocument, panel = document.createElement('aside');
  panel.className = 'graph-view-settings'; panel.hidden = true; root.append(panel);
  const title = document.createElement('header'); title.textContent = graphText(document, 'Highlight settings');
  title.append(graphButton(document, 'Close settings', () => { panel.hidden = true; })); panel.append(title);
  const label = document.createElement('label'); label.textContent = graphText(document, 'Highlight sections above');
  const input = document.createElement('input'); input.type = 'range'; input.min = '10'; input.max = '300';
  input.step = '10'; input.value = String(preferences.threshold);
  input.setAttribute('aria-label', graphText(document, 'Section size threshold'));
  const value = document.createElement('output');
  function update() {
    preferences.threshold = Number(input.value); value.textContent = `${input.value} LOC`;
    applySectionHighlights(board, data, preferences.threshold); inspector.setThreshold(preferences.threshold); save();
  }
  input.addEventListener('input', update); label.append(input, value); panel.append(label);
  const note = document.createElement('p');
  note.textContent = graphText(document, 'Size uses measured source lines. A health score is not inferred.'); panel.append(note);
  const legend = root.querySelector('#cb-legend');
  if (legend) { legend.classList.add('collapsed'); panel.append(graphButton(document, 'Link and marker filters', () => {
    legend.classList.toggle('collapsed'); panel.hidden = true;
  })); }
  update();
  return () => { panel.hidden = !panel.hidden; };
}

export function graphControlsHelp(root) {
  const document = root.ownerDocument, panel = document.createElement('aside');
  panel.className = 'graph-view-settings'; panel.hidden = true; root.append(panel);
  const title = document.createElement('header'); title.textContent = graphText(document, 'Graph controls');
  title.append(graphButton(document, 'Close help', () => { panel.hidden = true; })); panel.append(title);
  for (const key of ['Drag to orbit; choose Pan to move the scene.', 'Pinch or use the zoom buttons to change scale.',
    'Click a tower or a labelled section to open its details.', 'Scroll Sections to reach every reported symbol.',
    'The tower label rail scrolls with your finger or mouse wheel.', 'Fit restores the whole map.']) {
    const row = document.createElement('p'); row.textContent = graphText(document, key); panel.append(row);
  }
  return () => { panel.hidden = !panel.hidden; };
}
