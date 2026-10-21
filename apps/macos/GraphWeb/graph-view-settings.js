import { graphButton, graphText } from './graph-language.js';
import { graphControlIcon } from './graph-control-icons.js';
import { applyGraphHighlights } from './graph-highlights.js';
import { graphPreferences, sectionKinds, sectionKind, sectionChecks, checkColors, linkKinds } from './graph-highlight-policy.js';

function group(parent, name) {
  const document = parent.ownerDocument, fieldset = document.createElement('fieldset');
  const legend = document.createElement('legend'); legend.textContent = graphText(document, name);
  fieldset.append(legend); parent.append(fieldset); return fieldset;
}

function swatch(document, color) {
  const node = document.createElement('i'); node.className = 'graph-swatch';
  node.style.backgroundColor = `#${color.toString(16).padStart(6, '0')}`; return node;
}

function evidence(parent, data, preferences) {
  const document = parent.ownerDocument;
  const callables = data.files.filter(file => !file.symbolsUnavailable).flatMap(file => file.methods || [])
    .filter(section => !section.sourceRemainder && ['function', 'method'].includes(sectionKind(section)));
  const statuses = callables.map(section => sectionChecks(section, preferences).status);
  const summary = document.createElement('p'); summary.className = 'graph-measurement-summary';
  summary.textContent = `${statuses.filter(status => status !== 'unknown').length} ${graphText(document, 'of')} `
    + `${callables.length} ${graphText(document, 'callable sections measured')}`;
  parent.append(summary);
  if (preferences.mode === 'health') for (const [status, title] of [
    ['clear', 'Within selected code checks'], ['review', 'Code checks need review'], ['unknown', 'Code checks not measured'],
  ]) {
    const row = document.createElement('p'); row.className = 'graph-check-count';
    row.append(swatch(document, checkColors[status]), document.createTextNode(
      `${statuses.filter(value => value === status).length} · ${graphText(document, title)}`));
    parent.append(row);
  }
}

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

function checkbox(parent, key, checked, update, count, color) {
  const document = parent.ownerDocument, label = document.createElement('label'), input = document.createElement('input');
  label.className = 'graph-option'; input.type = 'checkbox'; input.checked = checked;
  input.setAttribute('aria-label', graphText(document, key));
  input.addEventListener('change', () => update(input.checked));
  label.append(input); if (color != null) label.append(swatch(document, color));
  label.append(document.createTextNode(graphText(document, key) + (count == null ? '' : ` · ${count}`)));
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
    panel.querySelectorAll('.graph-measurement-summary,.graph-check-count').forEach(node => node.remove());
    evidence(panel.querySelector('fieldset'), data, preferences);
  }
  function render() {
    panel.replaceChildren(); title(panel, 'View settings', 'Close settings');
    const colours = group(panel, 'Colour by');
    const mode = document.createElement('div'); mode.className = 'graph-colour-modes';
    mode.setAttribute('role', 'group'); mode.setAttribute('aria-label', graphText(document, 'Colour by'));
    for (const [value, name] of [['kind', 'Section kind'], ['size', 'Section size'], ['health', 'Code checks'], ['none', 'Neutral']]) {
      const option = graphButton(document, name, () => { preferences.mode = value; render(); update(); });
      option.dataset.colourMode = value; option.setAttribute('aria-pressed', String(preferences.mode === value));
      mode.append(option);
    }
    colours.append(mode);
    if (preferences.mode === 'kind') for (const [kind, metadata] of Object.entries(sectionKinds)) {
      const count = data.files.filter(file => !file.symbolsUnavailable).flatMap(file => file.methods || []).filter(section =>
        !section.sourceRemainder && sectionKind(section) === kind).length;
      if (count) checkbox(colours, metadata.title, preferences.kinds[kind], value => {
        preferences.kinds[kind] = value; update();
      }, count, metadata.color);
    }
    if (preferences.mode === 'size' || preferences.mode === 'health') {
      threshold(colours, 'Section size threshold', preferences.threshold, 500, value => {
        preferences.threshold = value; update();
      }, true);
    }
    if (preferences.mode === 'health') {
      threshold(colours, 'Cyclomatic complexity', preferences.maxComplexity, 100, value => {
        preferences.maxComplexity = value; update();
      });
      threshold(colours, 'Loop nesting', preferences.maxLoopDepth, 20, value => {
        preferences.maxLoopDepth = value; update();
      });
      const note = document.createElement('p'); note.textContent = graphText(document, 'Only measured static checks affect these colours. Unmeasured code stays unknown.');
      colours.append(note);
    }
    const source = group(panel, 'Source context');
    checkbox(source, 'Show other source lines', preferences.sourceBody, value => {
      preferences.sourceBody = value; update();
    });
    const labels = group(panel, 'Labels');
    for (const [key, name] of [['modules', 'Show module labels'], ['files', 'Show file labels'], ['sections', 'Show section labels']]) {
      checkbox(labels, name, preferences[key], value => { preferences[key] = value; update(); });
    }
    const links = group(panel, 'Links');
    checkbox(links, 'Only links of the selected file', preferences.relatedOnly, value => {
      preferences.relatedOnly = value; update();
    });
    if (data.files.some(file => file.isEndpoint)) checkbox(source, 'Show entry points', preferences.entryPoints, value => {
      preferences.entryPoints = value; update();
    });
    for (const [key, metadata] of Object.entries(linkKinds)) {
      const count = data.edges.filter(edge => edge.type === key).length;
      if (count) checkbox(links, metadata.title, preferences.edges[key] !== false, value => {
        preferences.edges[key] = value; update();
      }, count, metadata.color);
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
