import { findGraphFile, sourceSection, graphFileLinks } from './graph-inspection.js';
import { graphButton, graphText } from './graph-language.js';
import { graphControlIcon } from './graph-control-icons.js';
import { frameGraphSource } from './graph-source-framing.js';
import { codeCheckDetails, decorateSectionRow } from './graph-code-checks.js';
import { graphPreferences } from './graph-highlight-policy.js';

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
      if (method.sourceRemainder) return;
      const row = button('', () => {
        state.index = i; board.focusSection(file.id, i); context.render();
      });
      row.dataset.sectionIndex = String(i); row.setAttribute('aria-pressed', String(index === i));
      decorateSectionRow(row, method, state);
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
    if (section) content.append(element(document, 'h3', section.name));
    codeCheckDetails(content, context, section);
    content.append(interfaceElement(document, 'h3', 'Health evidence'));
    fact(content, 'Kind', file.kind);
    fact(content, 'Analysis', file.analysisStatus); fact(content, 'Source revision', file.sourceRevision);
    fact(content, 'Analysis fingerprint', file.analysisRevision);
    fact(content, 'Reported file size', file.loc == null ? null : `${file.loc} LOC`);
    if (section) fact(content, 'Selected section', `${section.loc} LOC · ${section.kind}`);
    fact(content, 'Observed inbound links', file.fanIn); fact(content, 'Observed outbound links', file.fanOut);
    content.append(interfaceElement(document, 'p', file.partial ? 'Partial evidence: this map does not cover every input.' : 'The reported analysis is complete.'));
    fact(content, 'Size highlight threshold', `${threshold} LOC`);
  }


export function createGraphInspector(root, data, board) {
  const document = root.ownerDocument;
  // Repo Lens excludes HUD surfaces from its capture-phase tower gestures.
  const panel = element(document, 'aside', null, 'rel-method-panel granttap-inspector hud');
  panel.setAttribute('aria-label', graphText(document, 'Tower details')); panel.hidden = true; root.append(panel);
  const state = { file: null, index: null, tab: 'Sections', threshold: 100, preferences: graphPreferences() };
  let frameGeneration = 0;
  const frame = () => {
    const generation = ++frameGeneration;
    document.defaultView.requestAnimationFrame?.(() => document.defaultView.requestAnimationFrame(() => {
      if (generation === frameGeneration && !panel.hidden) frameGraphSource(board, root, panel, state.file);
    }));
  };
  const context = { document, data, board, state };
  const button = (title, action) => graphButton(document, title, action);
  const fact = (parent, title, value) => {
    const row = element(document, 'div', null, 'graph-fact');
    row.append(interfaceElement(document, 'span', title), element(document, 'strong', value ?? graphText(document, 'Not reported')));
    parent.append(row);
  };

  function render() {
    const { file, tab } = state;
    if (!file) return;
    panel.replaceChildren(); panel.hidden = false; root.classList.add('graph-inspecting');
    const head = element(document, 'header');
    const dismiss = button('Close details', close); graphControlIcon(dismiss, 'Close details');
    head.append(element(document, 'h2', file.isExternal ? file.name.split(' · ')[0] : file.name), dismiss);
    const path = element(document, 'p', file.isExternal ? file.repositoryId : file._path || file.name);
    path.title = file.repositoryId || file.module;
    panel.append(head, path);
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
    state.file = selected; state.index = null; state.tab = 'Sections'; render(); frame(); return true;
  }

  function openMethod(selection) {
    if (!openFile(selection)) return false;
    state.index = selection.index; render(); frame(); return true;
  }

  function openEdge(selection) {
    if (!openFile(selection.from)) return false;
    state.tab = 'Links'; render(); return true;
  }

  function close() {
    frameGeneration += 1;
    panel.hidden = true; root.classList.remove('graph-inspecting');
    board.getCamera?.().clearViewOffset?.();
    root.dispatchEvent(new document.defaultView.Event('graphselection'));
  }

  function restoreSelection(selection) {
    if (!openFile(selection)) return false;
    frameGeneration += 1;
    state.index = sourceSection(state.file, selection.index) ? selection.index : null;
    state.tab = ['Sections', 'Links', 'Health'].includes(selection.tab) ? selection.tab : 'Sections';
    render();
    panel.querySelector('.graph-inspector-scroll').scrollTop = Number.isFinite(selection.scrollTop)
      ? Math.max(0, selection.scrollTop) : 0;
    return true;
  }

  Object.assign(context, { button, fact, render, openFile });
  return { openFile, openMethod, openEdge, close, restoreSelection, frame,
    setPreferences(preferences) {
      const offset = panel.querySelector('.graph-inspector-scroll')?.scrollTop || 0;
      state.preferences = { ...preferences }; state.threshold = preferences.threshold;
      if (state.file && !panel.hidden) { render(); panel.querySelector('.graph-inspector-scroll').scrollTop = offset; }
    },
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
