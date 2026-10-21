import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import * as THREE from '../build/three/three.module.js';
import { boardData } from '../board-data.js';
import { createGraphInspector } from '../graph-inspector.js';
import { createGraphControls } from '../graph-controls.js';

function fixture(language = 'en') {
  const dom = new JSDOM('<main><button data-view="reset"></button><button data-view="top"></button><button data-view="iso"></button><aside id="cb-legend"></aside></main>', { url: 'https://graph.local' });
  dom.window.document.documentElement.lang = language;
  const root = dom.window.document.querySelector('main'), selected = [], messages = [];
  const data = boardData([{ projectId: 'project', repositoryId: 'repo', sourceRevision: 'git-a', revision: 'analysis-a', analysisStatus: 'COMPLETE',
    codeMap: { files: [{ path: 'main.swift', lineCount: 200, symbols: [
      { id: 'small', label: 'short', kind: 'function', startLine: 1, lineCount: 10 },
      { id: 'large', label: 'long', kind: 'function', startLine: 11, lineCount: 190 },
    ] }] } }]);
  const camera = new THREE.PerspectiveCamera(); camera.position.set(0, 20, 100);
  const controls = { target: new THREE.Vector3(), mouseButtons: {}, touches: {}, update() {} };
  const scene = new THREE.Scene(), segment = new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshStandardMaterial({ color: 0x123456 }));
  segment.userData = { fileId: 0, methodIndex: 1 }; scene.add(segment);
  const board = { getCamera: () => camera, getControls: () => controls, getScene: () => scene, stopCameraFlight() {},
    focusNode(id) { selected.push([id]); }, focusSection(id, index) { selected.push([id, index]); } };
  dom.window.webkit = { messageHandlers: { graphStatus: { postMessage: value => messages.push(value) } } };
  const inspector = createGraphInspector(root, data, board), host = createGraphControls(root, data, board, inspector);
  const click = title => { const button = [...root.querySelectorAll('button')].find(value => value.textContent === title || value.getAttribute('aria-label') === title); assert.ok(button, title); button.click(); };
  return { dom, root, board, data, inspector, host, camera, controls, segment, selected, messages, click };
}

test('camera controls, section search and measured highlights work through the visible UI', () => {
  const value = fixture(); const { root, click, camera, controls, selected, segment } = value;
  const distance = camera.position.distanceTo(controls.target);
  click('Zoom in'); assert.ok(Math.abs(camera.position.distanceTo(controls.target) - distance * 0.9) < 1e-8);
  click('Zoom out'); assert.ok(Math.abs(camera.position.distanceTo(controls.target) - distance) < 1e-8);
  for (const title of ['Fit', 'Top', 'ISO']) click(title);
  click('Orbit'); assert.equal(controls.mouseButtons.LEFT, 2); assert.equal(controls.touches.ONE, 1);
  click('Pan'); assert.equal(controls.mouseButtons.LEFT, 0);
  click('Files'); const search = root.querySelector('input[type=search]');
  search.value = 'long'; search.dispatchEvent(new value.dom.window.Event('input'));
  click('long · L11'); assert.deepEqual(selected.at(-1), [0, 1]);
  click('Files'); search.value = 'missing'; search.dispatchEvent(new value.dom.window.Event('input'));
  assert.match(root.textContent, /No matching files/);
  click('Clear search'); assert.equal(search.value, '');
  assert.equal(root.querySelector('.graph-browser details button').textContent, 'main.swift');
  click('Close files');
  click('View settings'); click('Section size'); const slider = root.querySelector('input[type=range]');
  slider.value = '200'; slider.dispatchEvent(new value.dom.window.Event('input'));
  assert.equal(segment.material.color.getHex(), 0x123456);
  click('Close settings'); click('Legend');
  assert.equal(root.querySelector('[aria-label="Map legend"]').hidden, false); click('Close legend');
  click('Help'); assert.match(root.textContent, /Drag to orbit/); click('Close help');
  click('Files'); search.value = ''; search.dispatchEvent(new value.dom.window.Event('input'));
  click('main.swift'); assert.deepEqual(selected.at(-1), [0]);
  value.host.dispose();
});

test('full screen restores camera, selected source section and highlight preferences', () => {
  const value = fixture();
  assert.equal(value.segment.material.color.getHex(), 0x26d7ed);
  value.click('View settings'); value.click('Section size'); value.click('Close settings');
  assert.equal(value.segment.material.color.getHex(), 0xffb454);
  value.inspector.openMethod({ id: 0, index: 1 });
  value.camera.position.set(30, 40, 50); value.controls.target.set(2, 3, 4);
  value.camera.setViewOffset(390, 700, 0, 140, 390, 700);
  value.click('Full screen'); assert.deepEqual(value.messages, ['fullscreen']);
  const camera = new THREE.PerspectiveCamera(50, 390 / 700), controls = { target: new THREE.Vector3(), mouseButtons: {}, touches: {}, update() {} };
  const next = { ...value.board, getCamera: () => camera, getControls: () => controls };
  const secondRoot = value.dom.window.document.createElement('main');
  const inspector = createGraphInspector(secondRoot, value.data, next);
  createGraphControls(secondRoot, value.data, next, inspector);
  assert.deepEqual(camera.position.toArray(), [30, 40, 50]); assert.deepEqual(controls.target.toArray(), [2, 3, 4]);
  assert.equal(camera.view.offsetY / camera.view.fullHeight, 0.2);
  assert.equal(camera.aspect, 390 / 700, 'a saved offset must not restore the previous viewport aspect');
  assert.equal(inspector.selection().index, 1); assert.match(secondRoot.textContent, /Observed source/);
  inspector.close(); inspector.setThreshold(150); assert.equal(inspector.selection(), null);
});

test('Russian controls and invalid saved preferences remain usable', () => {
  const value = fixture('ru');
  value.click('Файлы'); assert.match(value.root.textContent, /Файлы и секции/);
  value.click('Закрыть файлы'); value.click('Справка'); assert.match(value.root.textContent, /Перетаскивайте/);
});

test('Fit dismisses source details so the whole city can be inspected', () => {
  const value = fixture();
  value.inspector.openMethod({ id: 0, index: 1 });
  assert.ok(value.inspector.selection());
  value.click('Fit');
  assert.equal(value.inspector.selection(), null);
  assert.equal(value.root.querySelector('.granttap-inspector').hidden, true);
  value.host.dispose(); value.dom.window.close();
});

test('an updated report retains the selected symbol when files and sections are inserted', () => {
  const value = fixture(); value.inspector.openMethod({ id: 0, index: 1 });
  value.camera.position.set(30, 40, 50); value.host.save();
  const nextData = structuredClone(value.data), selectedFile = nextData.files[0];
  selectedFile.id = 1;
  selectedFile.methods.unshift({ id: 'new-method', name: 'new method', kind: 'function', line: 1, loc: 5, health: null });
  nextData.files.unshift({ ...selectedFile, id: 0, _path: 'added.swift', methods: [], symbolsUnavailable: true });
  const root = value.dom.window.document.createElement('main');
  const camera = new THREE.PerspectiveCamera(), board = { ...value.board, getCamera: () => camera };
  const inspector = createGraphInspector(root, nextData, board);
  createGraphControls(root, nextData, board, inspector);
  assert.deepEqual(camera.position.toArray(), [30, 40, 50]);
  assert.equal(inspector.selection().index, 2); assert.match(root.textContent, /long/);
  assert.deepEqual(value.selected.at(-1), [1, 2]);
});

test('updated evidence retains the Health tab and falls back to the file after a selected symbol is removed', () => {
  const value = fixture(); value.inspector.openMethod({ id: 0, index: 1 });
  value.click('Health'); value.root.querySelector('.graph-inspector-scroll').scrollTop = 80; value.host.save();
  const nextData = structuredClone(value.data); nextData.files[0].methods.pop();
  const root = value.dom.window.document.createElement('main'), inspector = createGraphInspector(root, nextData, value.board);
  createGraphControls(root, nextData, value.board, inspector);
  assert.equal(inspector.selection().index, null); assert.equal(inspector.selection().tab, 'Health');
  assert.equal(root.querySelector('.graph-inspector-scroll').scrollTop, 80);
  assert.match(root.textContent, /Health evidence/); assert.equal(inspector.restoreSelection({ id: 999 }), false);
});

test('external resources keep their identity and Health evidence across a rebuilt viewer', () => {
  const value = fixture();
  const report = { projectId: 'project', repositoryId: 'repo', sourceRevision: 'git-a', revision: 'analysis-a',
    analysisStatus: 'COMPLETE', codeMap: { files: [{ path: 'main.swift', lineCount: 10, symbols: [] }],
      externals: [{ id: 'ext:storage', label: 'Storage', kind: 'database' }] } };
  const data = boardData([report]), root = value.dom.window.document.createElement('main');
  const inspector = createGraphInspector(root, data, value.board), host = createGraphControls(root, data, value.board, inspector);
  inspector.openFile({ id: 1 });
  [...root.querySelectorAll('button')].find(button => button.textContent === 'Health').click(); host.save();
  const nextRoot = value.dom.window.document.createElement('main'), next = createGraphInspector(nextRoot, data, value.board);
  createGraphControls(nextRoot, data, value.board, next);
  assert.equal(next.selection().external, true); assert.equal(next.selection().path, 'ext:storage');
  assert.match(nextRoot.textContent, /Storage/); assert.match(nextRoot.textContent, /database/);
  assert.match(nextRoot.textContent, /git-a/);
});
