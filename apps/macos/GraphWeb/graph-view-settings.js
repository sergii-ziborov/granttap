import { graphButton, graphText } from './graph-language.js';
import { graphControlIcon } from './graph-control-icons.js';
import { applyGraphHighlights } from './graph-highlights.js';
import { graphPreferences, sectionKinds, sectionKind, linkKinds } from './graph-highlight-policy.js';

function toggleGraphPopover(root, panel) {
  const opening = panel.hidden;
  root.querySelectorAll('.graph-view-settings').forEach(value => { value.hidden = true; });
  root.querySelector('#cb-legend')?.classList.add('collapsed');
  panel.hidden = !opening;
}

function title(panel, name, closeName) {
  const document = panel.ownerDocument, header = document.createElement('header');
  header.textContent = graphText(document, name);
  const close = graphButton(document, closeName, () => { panel.hidden = true; });
  graphControlIcon(close, 'Close details'); header.append(close); panel.append(header);
}

function checkbox(parent, key, checked, update, count) {
  const document = parent.ownerDocument, label = document.createElement('label'), input = document.createElement('input');
  label.className = 'graph-option'; input.type = 'checkbox'; input.checked = checked;
  input.setAttribute('aria-label', graphText(document, key));
  input.addEventListener('change', () => update(input.checked));
  label.append(input, document.createTextNode(graphText(document, key) + (count == null ? '' : ` · ${count}`)));
  parent.append(label);
}

function threshold(parent, key, value, maximum, update, range = false) {
  const document = parent.ownerDocument, label = document.createElement('label'), input = document.createElement('input');
  label.className = 'graph-threshold'; label.append(document.createTextNode(graphText(document, key)));
  input.type = range ? 'range' : 'number'; input.min = range ? '10' : '1'; input.max = String(maximum); input.step = '1';
  input.value = String(value); input.setAttribute('aria-label', graphText(document, key));
  const output = document.createElement('output'); output.textContent = String(value);
  input.addEventListener(range ? 'input' : 'change', () => {
    const next = Number(input.value);
    if (!Number.isFinite(next) || next < 1 || next > maximum) return;
    output.textContent = String(next); update(next);
  });
  label.append(input); if (range) label.append(output); parent.append(label);
}

export function graphViewSettings(root, data, board, inspector, preferences, save) {
  const document = root.ownerDocument, panel = document.createElement('aside');
  panel.className = 'graph-view-settings hud'; panel.hidden = true;
  panel.setAttribute('aria-label', graphText(document, 'View settings')); root.append(panel);
  function update() {
    applyGraphHighlights(root, board, data, preferences, inspector.selection());
    inspector.setPreferences?.(preferences); save();
  }
  function render() {
    panel.replaceChildren(); title(panel, 'View settings', 'Close settings');
    const label = document.createElement('p'); label.textContent = graphText(document, 'Colour by');
    const mode = document.createElement('div'); mode.className = 'graph-colour-modes';
    mode.setAttribute('role', 'group'); mode.setAttribute('aria-label', graphText(document, 'Colour by'));
    for (const [value, name] of [['kind', 'Section kind'], ['size', 'Section size'], ['health', 'Code checks'], ['none', 'Neutral']]) {
      const option = graphButton(document, name, () => { preferences.mode = value; render(); update(); });
      option.dataset.colourMode = value; option.setAttribute('aria-pressed', String(preferences.mode === value));
      mode.append(option);
    }
    panel.append(label, mode);
    if (preferences.mode === 'kind') for (const [kind, metadata] of Object.entries(sectionKinds)) {
      const count = data.files.filter(file => !file.symbolsUnavailable).flatMap(file => file.methods || []).filter(section =>
        !section.sourceRemainder && sectionKind(section) === kind).length;
      if (count) checkbox(panel, metadata.title, preferences.kinds[kind], value => {
        preferences.kinds[kind] = value; update();
      }, count);
    }
    if (preferences.mode === 'size' || preferences.mode === 'health') {
      threshold(panel, 'Section size threshold', preferences.threshold, 500, value => {
        preferences.threshold = value; update();
      }, true);
    }
    if (preferences.mode === 'health') {
      threshold(panel, 'Cyclomatic complexity', preferences.maxComplexity, 100, value => {
        preferences.maxComplexity = value; update();
      });
      threshold(panel, 'Loop nesting', preferences.maxLoopDepth, 20, value => {
        preferences.maxLoopDepth = value; update();
      });
      const note = document.createElement('p'); note.textContent = graphText(document, 'Only measured static checks affect these colours. Unmeasured code stays unknown.');
      panel.append(note);
    }
    for (const [key, name] of [['modules', 'Show module labels'], ['files', 'Show file labels'], ['sections', 'Show section labels']]) {
      checkbox(panel, name, preferences[key], value => { preferences[key] = value; update(); });
    }
    checkbox(panel, 'Only links of the selected file', preferences.relatedOnly, value => {
      preferences.relatedOnly = value; update();
    });
    if (data.files.some(file => file.isEndpoint)) checkbox(panel, 'Show entry points', preferences.entryPoints, value => {
      preferences.entryPoints = value; update();
    });
    for (const [key, metadata] of Object.entries(linkKinds)) {
      const count = data.edges.filter(edge => edge.type === key).length;
      if (count) checkbox(panel, metadata.title, preferences.edges[key] !== false, value => {
        preferences.edges[key] = value; update();
      }, count);
    }
    panel.append(graphButton(document, 'Reset view settings', () => {
      Object.assign(preferences, graphPreferences({ pan: preferences.pan })); render(); update();
    }));
  }
  render(); update();
  return () => toggleGraphPopover(root, panel);
}

export function graphControlsHelp(root) {
  const document = root.ownerDocument, panel = document.createElement('aside');
  panel.className = 'graph-view-settings hud'; panel.hidden = true; root.append(panel);
  title(panel, 'Graph controls', 'Close help');
  for (const key of ['Drag to orbit; choose Pan to move the scene.', 'Pinch or use the zoom buttons to change scale.',
    'Click a tower or a labelled section to open its details.', 'Scroll Sections to reach every reported symbol.',
    'The tower label rail scrolls with your finger or mouse wheel.', 'Fit restores the whole map.',
    'Legend explains the current colours without changing filters.',
    'Code checks compare measured source size, complexity and nesting with your thresholds. They do not prove correctness or test coverage.']) {
    const row = document.createElement('p'); row.textContent = graphText(document, key); panel.append(row);
  }
  return () => toggleGraphPopover(root, panel);
}
