import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { createGraphInspector } from '../graph-inspector.js';
import { boardData } from '../board-data.js';

test('the inspector scrolls every section and opens source, links and honest health evidence', () => {
  const dom = new JSDOM('<main></main>'), root = dom.window.document.querySelector('main');
  const data = boardData([{ repositoryId: 'repo', sourceRevision: 'git-a', revision: 'analysis-a',
    analysisStatus: 'INCOMPLETE', codeMap: { files: [{ path: 'src/main.swift', lineCount: 200,
      symbols: Array.from({ length: 36 }, (_, i) => ({ id: `s${i}`, label: `method${i}`, kind: 'function',
        startLine: i * 5 + 1, lineCount: i + 10 })) }, { path: 'src/store.swift', symbols: [] }],
    roads: [{ source: 'src/main.swift', target: 'src/store.swift', relation: 'calls' }] } }]);
  const selected = [];
  const board = { focusSection(id, index) { selected.push([id, index]); }, focusNode(id) { selected.push(id); } };
  const inspector = createGraphInspector(root, data, board);
  assert.equal(inspector.openFile({ id: 99 }), false);
  assert.equal(inspector.selection(), null);
  inspector.openFile({ id: 0 });
  const rows = root.querySelectorAll('[data-section-index]'); assert.equal(rows.length, 36);
  rows[35].click(); assert.deepEqual(selected[0], [0, 35]);
  assert.match(root.textContent, /Observed source/); assert.match(root.textContent, /176–220/);
  assert.equal(inspector.selection().index, 35);
  inspector.setThreshold(40); assert.ok(root.querySelector('[data-section-index="35"]').classList.contains('size-warning'));
  [...root.querySelectorAll('button')].find(button => button.textContent === 'Health details').click();
  assert.match(root.textContent, /Partial evidence/); assert.match(root.textContent, /not reported/);
  assert.match(root.textContent, /git-a/); assert.match(root.textContent, /40 LOC/);
  [...root.querySelectorAll('button')].find(button => button.textContent === 'Links').click();
  [...root.querySelectorAll('button')].find(button => button.textContent.includes('src/store.swift')).click();
  assert.equal(selected[1], 1); assert.match(root.textContent, /No source sections/);
  [...root.querySelectorAll('button')].find(button => button.textContent === 'Links').click();
  assert.match(root.textContent, /← calls/);
  inspector.openMethod({ id: 0, index: 1 }); assert.match(root.textContent, /method1/);
  inspector.openEdge({ from: { id: 0 } }); assert.match(root.textContent, /→ calls/);
  assert.equal(inspector.openMethod({ id: 100 }), false);
  assert.equal(inspector.openEdge({ from: { id: 100 } }), false);
  inspector.close(); assert.equal(root.querySelector('aside').hidden, true);
  inspector.setThreshold(150); assert.equal(root.querySelector('aside').hidden, true);
  assert.equal(inspector.selection(), null);
});

test('complete and unmeasured file reports do not claim fabricated health scores', () => {
  const dom = new JSDOM('<main></main>'), root = dom.window.document.querySelector('main');
  const data = boardData([{ repositoryId: 'repo', analysisStatus: 'COMPLETE', codeMap: {
    files: [{ path: 'empty.swift', symbols: [] }, { path: 'other.swift', symbols: [
      { id: 's', label: '<script>alert(1)</script>', lineCount: 2 },
    ] }] } }]);
  const inspector = createGraphInspector(root, data, {});
  inspector.openFile({ id: 0 }); inspector.setThreshold(80);
  const health = [...root.querySelectorAll('button')].find(value => value.textContent === 'Health'); health.click();
  assert.match(root.textContent, /The reported analysis is complete/);
  assert.match(root.textContent, /Not reported/); assert.match(root.textContent, /0/);
  [...root.querySelectorAll('button')].find(value => value.textContent === 'Links').click();
  assert.match(root.textContent, /No links were observed/);
  inspector.openMethod({ id: 1, index: 0 }); assert.equal(root.querySelector('script'), null);
  assert.match(root.textContent, /<script>alert\(1\)<\/script>/);
  assert.match(root.textContent, /Not reported/);
});

test('Russian interface labels leave source identifiers and source names verbatim', () => {
  const dom = new JSDOM('<main></main>'); dom.window.document.documentElement.lang = 'ru';
  const root = dom.window.document.querySelector('main');
  const data = boardData([{ repositoryId: 'File', sourceRevision: 'Health', analysisStatus: 'COMPLETE',
    codeMap: { files: [{ path: 'Health', lineCount: 10, symbols: [
      { id: 'method', label: 'Health', kind: 'function', startLine: 1, lineCount: 10 },
    ] }] } }]);
  const inspector = createGraphInspector(root, data, {}); inspector.openMethod({ id: 0, index: 0 });
  assert.equal(root.querySelector('header h2').textContent, 'Health');
  assert.equal(root.querySelector('.graph-source-details h3').textContent, 'Health');
  assert.match(root.textContent, /Данные исходника/);
  assert.match(root.querySelector('.graph-source-details').textContent, /Health/);
});
