import { findGraphFile, sourceSection, graphFileLinks } from './graph-inspection.js';
import { graphText } from './graph-language.js';

const element = (document, tag, text, className) => {
  const node = document.createElement(tag);
  if (text != null) node.textContent = String(text);
  if (className) node.className = className;
  return node;
};

const interfaceElement = (document, tag, key, className) => element(document, tag,
  graphText(document, key), className);

function sections(content, context) {
  const { document, button, fact, data, board, state } = context;
  const { file, index, threshold } = state;
    const list = element(document, 'div', null, 'graph-sections');
    if (file.symbolsUnavailable || !file.methods?.length) {
      list.append(interfaceElement(document, 'p', 'No source sections were reported for this tower.'));
    } else file.methods.forEach((method, i) => {
      const row = button('', () => {
        state.index = i; board.focusSection(file.id, i); context.render();
      });
      row.dataset.sectionIndex = String(i); row.setAttribute('aria-pressed', String(index === i));
      row.classList.toggle('size-warning', method.loc > threshold);
      row.append(element(document, 'span', method.name), element(document, 'small',
        `${method.kind || 'symbol'} · L${method.line ?? '—'} · ${method.loc} LOC`));
      list.append(row);
    });
    content.append(list);
    const source = sourceSection(file, index);
    if (source) {
      const details = element(document, 'section', null, 'graph-source-details');
      details.append(element(document, 'h3', source.name), interfaceElement(document, 'h4', 'Observed source'));
      fact(details, 'File', source.path); fact(details, 'Kind', source.kind);
      fact(details, 'Lines', source.line == null ? null : `${source.line}–${source.endLine}`); fact(details, 'Section size', `${source.loc} LOC`);
      fact(details, 'Source revision', source.sourceRevision); fact(details, 'Analysis', source.analysisStatus);
      details.append(button('Health details', () => { state.tab = 'Health'; context.render(); }));
      content.prepend(details);
    }
  }


function links(content, context) {
  const { document, button, fact, data, board, state } = context;
  const { file, index, threshold } = state;
    const values = graphFileLinks(data, file);
    if (!values.length) content.append(interfaceElement(document, 'p', 'No links were observed in this report.'));
    values.forEach(link => {
      content.append(button(`${link.direction === 'out' ? '→' : '←'} ${link.relation} · ${link.neighbor.isExternal ? link.neighbor.name : link.neighbor._path || link.neighbor.name}`,
        () => { board.focusNode(link.neighbor.id); context.openFile({ id: link.neighbor.id }); }));
    });
  }


function health(content, context) {
  const { document, button, fact, data, board, state } = context;
  const { file, index, threshold } = state;
    const section = sourceSection(file, index);
    content.append(interfaceElement(document, 'h3', 'Health evidence'));
    fact(content, 'Kind', file.kind);
    fact(content, 'Analysis', file.analysisStatus); fact(content, 'Source revision', file.sourceRevision);
    fact(content, 'Analysis fingerprint', file.analysisRevision);
    fact(content, 'Reported file size', file.loc == null ? null : `${file.loc} LOC`);
    if (section) fact(content, 'Selected section', `${section.loc} LOC · ${section.kind}`);
    fact(content, 'Observed inbound links', file.fanIn); fact(content, 'Observed outbound links', file.fanOut);
    content.append(interfaceElement(document, 'p', file.partial ? 'Partial evidence: this map does not cover every input.' : 'The reported analysis is complete.'));
    content.append(interfaceElement(document, 'p', 'Coverage and complexity were not reported. Section-size highlights use measured LOC.'));
    fact(content, 'Size highlight threshold', `${threshold} LOC`);
  }


export function createGraphInspector(root, data, board) {
  const document = root.ownerDocument;
  const panel = element(document, 'aside', null, 'rel-method-panel granttap-inspector');
  panel.setAttribute('aria-label', graphText(document, 'Tower details')); panel.hidden = true; root.append(panel);
  const state = { file: null, index: null, tab: 'Sections', threshold: 100 };
  const context = { document, data, board, state };
  const button = (title, action) => {
    const node = element(document, 'button', graphText(document, title)); node.type = 'button';
    node.addEventListener('click', action); return node;
  };
  const fact = (parent, title, value) => {
    const row = element(document, 'div', null, 'graph-fact');
    row.append(interfaceElement(document, 'span', title), element(document, 'strong', value ?? graphText(document, 'Not reported')));
    parent.append(row);
  };

  function render() {
    const { file, tab } = state;
    if (!file) return;
    panel.replaceChildren(); panel.hidden = false;
    const head = element(document, 'header');
    head.append(element(document, 'h2', file.isExternal ? file.name : file._path || file.name), button('Close details', close));
    panel.append(head, element(document, 'p', file.repositoryId || file.module));
    const tabs = element(document, 'nav');
    for (const name of ['Sections', 'Links', 'Health']) {
      const control = button(name, () => { state.tab = name; render(); });
      control.setAttribute('aria-pressed', String(tab === name)); tabs.append(control);
    }
    panel.append(tabs);
    const content = element(document, 'div', null, 'graph-inspector-scroll');
    if (tab === 'Sections') sections(content, context);
    else if (tab === 'Links') links(content, context);
    else health(content, context);
    panel.append(content);
    root.dispatchEvent(new document.defaultView.Event('graphselection'));
  }

  function openFile(selection) {
    const selected = findGraphFile(data, selection);
    if (!selected) return false;
    state.file = selected; state.index = null; state.tab = 'Sections'; render(); return true;
  }

  function openMethod(selection) {
    if (!openFile(selection)) return false;
    state.index = selection.index; render(); return true;
  }

  function openEdge(selection) {
    if (!openFile(selection.from)) return false;
    state.tab = 'Links'; render(); return true;
  }

  function close() {
    panel.hidden = true;
    root.dispatchEvent(new document.defaultView.Event('graphselection'));
  }

  function restoreSelection(selection) {
    if (!openFile(selection)) return false;
    state.index = sourceSection(state.file, selection.index) ? selection.index : null;
    state.tab = ['Sections', 'Links', 'Health'].includes(selection.tab) ? selection.tab : 'Sections';
    render();
    panel.querySelector('.graph-inspector-scroll').scrollTop = Number.isFinite(selection.scrollTop)
      ? Math.max(0, selection.scrollTop) : 0;
    return true;
  }

  Object.assign(context, { button, fact, render, openFile });
  return { openFile, openMethod, openEdge, close, restoreSelection,
    setThreshold(value) {
      const offset = panel.querySelector('.graph-inspector-scroll')?.scrollTop || 0;
      state.threshold = value;
      if (state.file && !panel.hidden) { render(); panel.querySelector('.graph-inspector-scroll').scrollTop = offset; }
    },
    selection() { return state.file && !panel.hidden ? { repositoryId: state.file.repositoryId,
      path: state.file._path, index: state.index, symbolId: sourceSection(state.file, state.index)?.id ?? null,
      external: state.file.isExternal === true,
      tab: state.tab, scrollTop: panel.querySelector('.graph-inspector-scroll').scrollTop } : null; },
  };
}
