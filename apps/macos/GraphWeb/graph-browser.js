import { graphFileMatches } from './graph-inspection.js';
import { graphButton, graphText } from './graph-language.js';
import { graphControlIcon } from './graph-control-icons.js';

export function createGraphBrowser(root, data, board, inspector) {
  const document = root.ownerDocument, panel = document.createElement('aside');
  panel.className = 'graph-browser hud'; panel.hidden = true; root.append(panel);
  const title = document.createElement('header'); title.textContent = graphText(document, 'Files and sections');
  const dismiss = graphButton(document, 'Close files', close); graphControlIcon(dismiss, 'Close files'); title.append(dismiss);
  const search = document.createElement('input'); search.type = 'search';
  search.placeholder = graphText(document, 'Find a file or symbol'); search.setAttribute('aria-label', search.placeholder);
  const clear = graphButton(document, 'Clear search', () => { search.value = ''; render(); search.focus(); });
  clear.setAttribute('aria-label', graphText(document, 'Clear search')); clear.textContent = '×';
  const searchRow = document.createElement('div'); searchRow.className = 'graph-browser-search';
  searchRow.append(search, clear);
  const list = document.createElement('div'); list.className = 'graph-browser-scroll';
  function close() {
    search.blur(); panel.hidden = true; root.classList.remove('graph-browser-open');
  }
  function render() {
    clear.hidden = !search.value;
    list.replaceChildren();
    const groups = new Map();
    for (const match of graphFileMatches(data, search.value)) {
      const groupName = match.file.module || `${match.file.repositoryId} · ${graphText(document, 'External services')}`;
      let group = groups.get(groupName);
      if (!group) {
        group = document.createElement('details'); group.open = true;
        const label = document.createElement('summary');
        label.textContent = data.MODULES.find(module => module.name === groupName)?.displayName || groupName;
        group.append(label); groups.set(groupName, group); list.append(group);
      }
      group.append(graphButton(document, match.file.isExternal ? match.file.name : match.file._path, () => {
        close(); board.focusNode(match.file.id); inspector.openFile({ id: match.file.id });
      }, true));
      match.sections.forEach(item => {
        const row = graphButton(document, `${item.section.name} · L${item.section.line ?? '—'}`, () => {
          close(); board.focusSection(match.file.id, item.index);
          inspector.openMethod({ id: match.file.id, index: item.index });
        }, true);
        row.className = 'graph-browser-symbol'; group.append(row);
      });
    }
    if (!groups.size) list.textContent = graphText(document, 'No matching files or symbols.');
  }
  search.addEventListener('input', render);
  search.addEventListener('keydown', event => { if (event.key === 'Enter') search.blur(); });
  panel.append(title, searchRow, list); render();
  return () => {
    panel.hidden = !panel.hidden;
    root.classList.toggle('graph-browser-open', !panel.hidden);
    if (!panel.hidden) search.focus(); else search.blur();
  };
}
