import { graphFileMatches } from './graph-inspection.js';
import { graphButton, graphText } from './graph-language.js';

export function createGraphBrowser(root, data, board, inspector) {
  const document = root.ownerDocument, panel = document.createElement('aside');
  panel.className = 'graph-browser'; panel.hidden = true; root.append(panel);
  const title = document.createElement('header'); title.textContent = graphText(document, 'Files and sections');
  title.append(graphButton(document, 'Close files', () => { panel.hidden = true; }));
  const search = document.createElement('input'); search.type = 'search';
  search.placeholder = graphText(document, 'Find a file or symbol'); search.setAttribute('aria-label', search.placeholder);
  const list = document.createElement('div'); list.className = 'graph-browser-scroll';
  function render() {
    list.replaceChildren();
    const groups = new Map();
    for (const match of graphFileMatches(data, search.value)) {
      let group = groups.get(match.file.module);
      if (!group) {
        group = document.createElement('details'); group.open = true;
        const label = document.createElement('summary'); label.textContent = match.file.module;
        group.append(label); groups.set(match.file.module, group); list.append(group);
      }
      group.append(graphButton(document, match.file._path, () => {
        board.focusNode(match.file.id); inspector.openFile({ id: match.file.id }); panel.hidden = true;
      }, true));
      match.sections.forEach(item => {
        const row = graphButton(document, `${item.section.name} · L${item.section.line ?? '—'}`, () => {
          panel.hidden = true; board.focusSection(match.file.id, item.index);
          inspector.openMethod({ id: match.file.id, index: item.index });
        }, true);
        row.className = 'graph-browser-symbol'; group.append(row);
      });
    }
    if (!groups.size) list.textContent = graphText(document, 'No matching files or symbols.');
  }
  search.addEventListener('input', render); panel.append(title, search, list); render();
  return () => { panel.hidden = !panel.hidden; if (!panel.hidden) search.focus(); };
}
