import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from '../build/three/three.module.js';
import { JSDOM } from 'jsdom';
import { boardData } from '../board-data.js';
import { hasVisibleGraphSource } from '../graph-camera-framing.js';
import { createGraphControls } from '../graph-controls.js';
import { createGraphInspector } from '../graph-inspector.js';

function report(folders = 1) {
  return { repositoryId: 'example.org/team/portable', codeMap: {
    files: Array.from({ length: folders }, (_, index) => ({
      path: `area${index}/file.swift`, lineCount: 80, symbols: [],
    })), externals: [{ id: 'service', label: 'Database', kind: 'db' }], roads: [],
  } };
}

for (const folders of [1, 25, 100]) {
  test(`external services sit beside the actual ${folders}-module board without a fixed origin`, () => {
    const data = boardData([report(folders)]);
    const left = Math.min(...data.MODULES.map(module => module._cx - module._half));
    const service = data.exts[0];
    assert.ok(service.x < left - 12, 'service geometry must clear every source plate');
    assert.ok(left - service.x <= 64, 'small maps must not include an arbitrary empty service corridor');
  });
}

test('an overview with just one visible tower is not a usable restored map', () => {
  const data = { files: Array.from({ length: 10 }, (_, id) => ({ x: id * 100, z: 0, height: 20 })) };
  const camera = new THREE.PerspectiveCamera(50, 0.5, 0.5, 2000);
  camera.position.set(0, 15, 40);
  const controls = { target: new THREE.Vector3(0, 10, 0) };
  assert.equal(hasVisibleGraphSource({ getCamera: () => camera, getControls: () => controls }, data), false);
});

function workspace(aspect = 1.8) {
  const dom = new JSDOM('<main></main>', { url: 'https://viewer.test' });
  const root = dom.window.document.querySelector('main'), data = boardData([report(12)]);
  const camera = new THREE.PerspectiveCamera(50, aspect, 0.5, 4000);
  camera.position.set(0, 100, 100);
  const controls = { target: new THREE.Vector3(), mouseButtons: {}, touches: {},
    update() { camera.lookAt(this.target); camera.updateMatrixWorld(); } };
  const scene = new THREE.Scene();
  const board = { getCamera: () => camera, getControls: () => controls, getScene: () => scene,
    stopCameraFlight() {}, focusNode() {}, focusSection() {} };
  const inspector = createGraphInspector(root, data, board);
  const host = createGraphControls(root, data, board, inspector);
  return { dom, root, data, camera, controls, board, inspector, host };
}

test('a saved landscape overview refits every source after reopening in portrait', () => {
  const value = workspace(); value.host.save(); value.host.dispose();
  value.camera.aspect = 0.45; value.camera.updateProjectionMatrix();
  const root = value.dom.window.document.createElement('main');
  const inspector = createGraphInspector(root, value.data, value.board);
  const next = createGraphControls(root, value.data, value.board, inspector);
  for (const file of value.data.files) {
    const p = new THREE.Vector3(file.x, file.height, file.z).project(value.camera);
    assert.ok(Math.abs(p.x) <= 1 && Math.abs(p.y) <= 1, 'old orientation must not crop the map');
  }
  next.dispose(); value.dom.window.close();
});

test('manual camera and selected source survive a same-viewport report refresh', () => {
  const value = workspace(); value.inspector.openFile({ id: 0 });
  value.camera.position.set(35, 45, 55); value.controls.target.set(1, 2, 3);
  value.host.save(); value.host.dispose();
  const root = value.dom.window.document.createElement('main');
  const inspector = createGraphInspector(root, value.data, value.board);
  const next = createGraphControls(root, value.data, value.board, inspector);
  assert.deepEqual(value.camera.position.toArray(), [35, 45, 55]);
  assert.equal(inspector.selection().path, value.data.files[0]._path);
  next.dispose(); value.dom.window.close();
});

test('compact camera presets retain accessible names and do not compete for text width', () => {
  const value = workspace();
  for (const name of ['Top', 'ISO']) {
    const control = [...value.root.querySelectorAll('.graph-camera button')]
      .find(button => button.getAttribute('aria-label') === name);
    assert.ok(control?.querySelector('svg'), `${name} remains a named camera preset`);
  }
  value.host.dispose(); value.dom.window.close();
});

test('opening help replaces the settings popover and preserves the selected source', () => {
  const value = workspace(); value.inspector.openFile({ id: 0 });
  const click = name => [...value.root.querySelectorAll('button')]
    .find(button => button.getAttribute('aria-label') === name || button.textContent === name).click();
  click('Highlights'); click('Help');
  assert.equal(value.root.querySelectorAll('.graph-view-settings:not([hidden])').length, 1);
  assert.match(value.root.querySelector('.graph-view-settings:not([hidden])').textContent, /Graph controls/);
  assert.equal(value.inspector.selection().path, value.data.files[0]._path);
  value.host.dispose(); value.dom.window.close();
});

test('a distant map remains unusable even when its tiny cluster is off centre', () => {
  const value = workspace(); value.camera.position.set(0, 10_000, 10_000);
  value.camera.far = 100_000; value.camera.updateProjectionMatrix();
  value.controls.target.set(2000, 0, 0); value.controls.update();
  assert.equal(hasVisibleGraphSource(value.board, value.data), false);
  value.host.dispose(); value.dom.window.close();
});

test('a selected source reopens in the free portrait area after its elevation frame settles', () => {
  const value = workspace(); value.inspector.openFile({ id: 0 });
  value.camera.position.set(300, 400, 500); value.host.save(); value.host.dispose();
  value.camera.aspect = 390 / 700; value.camera.updateProjectionMatrix();
  const frames = []; value.dom.window.requestAnimationFrame = callback => { frames.push(callback); return frames.length; };
  const root = value.dom.window.document.createElement('main');
  root.getBoundingClientRect = () => ({ left: 0, top: 0, right: 390, bottom: 700, width: 390, height: 700 });
  const inspector = createGraphInspector(root, value.data, value.board);
  root.querySelector('.granttap-inspector').getBoundingClientRect = () => ({ left: 10, top: 370, right: 380, bottom: 620 });
  const next = createGraphControls(root, value.data, value.board, inspector);
  while (frames.length) frames.shift()();
  assert.equal(inspector.selection().path, value.data.files[0]._path);
  assert.notDeepEqual(value.camera.position.toArray(), [300, 400, 500]);
  for (const y of [0, value.data.files[0].height]) {
    const p = new THREE.Vector3(value.data.files[0].x, y, value.data.files[0].z).project(value.camera);
    const screenY = (1 - p.y) * 350;
    assert.ok(screenY > 74 && screenY < 370, 'selected source clears its restored inspector');
  }
  next.dispose(); value.dom.window.close();
});

test('rebuilt tower callouts get a new collision pass without camera movement', async () => {
  const value = workspace(), frames = [];
  value.dom.window.requestAnimationFrame = callback => { frames.push(callback); return frames.length; };
  value.root.getBoundingClientRect = () => ({ left: 0, top: 0, right: 390, bottom: 700 });
  const labels = Array.from({ length: 2 }, () => {
    const label = value.dom.window.document.createElement('i'); label.className = 'lbl callout';
    label.getBoundingClientRect = () => ({ left: 100, right: 200, top: 100, bottom: 120, width: 100, height: 20 });
    value.root.append(label); return label;
  });
  await Promise.resolve();
  while (frames.length) frames.shift()();
  assert.equal(labels.filter(label => label.style.visibility === 'visible').length, 1);
  assert.equal(labels.filter(label => label.style.visibility === 'hidden').length, 1);
  value.host.dispose(); value.dom.window.close();
});
