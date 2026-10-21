import { graphButton, graphText } from './graph-language.js';
import { sectionKinds, sectionKind, checkColors, linkKinds } from './graph-highlight-policy.js';
import { graphControlIcon } from './graph-control-icons.js';

export function graphLegend(root, data, preferences) {
  const document = root.ownerDocument, panel = document.createElement('aside');
  panel.className = 'graph-view-settings graph-legend hud'; panel.hidden = true;
  panel.setAttribute('aria-label', graphText(document, 'Map legend')); root.append(panel);
  function row(title, color, count) {
    const item = document.createElement('p'), swatch = document.createElement('i');
    swatch.className = 'graph-swatch'; swatch.style.backgroundColor = `#${color.toString(16).padStart(6, '0')}`;
    item.append(swatch, document.createTextNode(graphText(document, title) + (count == null ? '' : ` · ${count}`)));
    panel.append(item);
  }
  function render() {
    panel.replaceChildren();
    const header = document.createElement('header'); header.textContent = graphText(document, 'Map legend');
    const close = graphButton(document, 'Close legend', () => { panel.hidden = true; });
    graphControlIcon(close, 'Close details'); header.append(close); panel.append(header);
    const methods = data.files.filter(file => !file.symbolsUnavailable)
      .flatMap(file => file.methods || []).filter(method => !method.sourceRemainder);
    if (preferences.mode === 'kind') for (const [key, kind] of Object.entries(sectionKinds)) {
      const count = methods.filter(method => sectionKind(method) === key).length;
      if (count) row(kind.title, kind.color, count);
    }
    if (preferences.mode === 'size') row('Above the selected size threshold', 0xffb454);
    if (preferences.mode === 'health') {
      row('Within selected code checks', checkColors.clear);
      row('Code checks need review', checkColors.review);
      row('Code checks not measured', checkColors.unknown);
    }
    row('Other source lines', 0x71b7d0);
    if (data.files.some(file => file.isEndpoint)) row('Entry points', 0x2fe6a0);
    for (const [key, kind] of Object.entries(linkKinds)) {
      const count = data.edges.filter(edge => edge.type === key).length;
      if (count) row(kind.title, kind.color, count);
    }
    const note = document.createElement('p'); note.className = 'graph-legend-note';
    note.textContent = graphText(document, 'Opening this legend does not change filters.'); panel.append(note);
  }
  return () => {
    const opening = panel.hidden;
    root.querySelectorAll('.graph-view-settings').forEach(value => { value.hidden = true; });
    root.querySelector('#cb-legend')?.classList.add('collapsed');
    if (opening) render();
    panel.hidden = !opening;
  };
}
