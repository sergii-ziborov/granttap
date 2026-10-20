import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import * as THREE from '../build/three/three.module.js';
import { boardData } from '../board-data.js';
import { createGraphControls } from '../graph-controls.js';
import { createGraphInspector } from '../graph-inspector.js';

function workspace(aspect) {
  const dom = new JSDOM('<main><button data-view="reset"></button><button data-view="top"></button><button data-view="iso"></button></main>',
    { url: 'https://viewer.test' });
  const root = dom.window.document.querySelector('main');
  const data = boardData([{ projectId: 'portable-project', repositoryId: 'example.org/team/project',
    analysisStatus: 'COMPLETE', codeMap: { files: Array.from({ length: 73 }, (_, i) => ({
      path: `Sources/Area${i % 8}/File${i}.swift`, lineCount: 240,
      symbols: [{ id: `function-${i}`, label: `Function ${i}`, lineCount: 80, startLine: 1, kind: 'function' }],
    })), externals: [{ id: 'ext:database', label: 'Database', kind: 'database' }], roads: [] } }]);
  const camera = new THREE.PerspectiveCamera(50, aspect, 0.5, 2000);
  camera.position.set(0, 20, 100);
  const controls = { target: new THREE.Vector3(), mouseButtons: {}, touches: {},
    update() { camera.lookAt(this.target); camera.updateMatrixWorld(); } };
  controls.update();
  const scene = new THREE.Scene(); scene.fog = new THREE.FogExp2(0x060a10, 0.0035);
  const board = { getCamera: () => camera, getControls: () => controls, getScene: () => scene,
    stopCameraFlight() {}, focusNode() {}, focusSection() {} };
  const inspector = createGraphInspector(root, data, board);
  const host = createGraphControls(root, data, board, inspector);
  return { dom, root, data, camera, controls, host, board, inspector };
}

test('rotation refits an overview and keeps a selected source framed beside its inspector', () => {
  const value = workspace(1.8);
  value.dom.window.requestAnimationFrame = callback => { callback(); return 1; };
  value.camera.aspect = 0.5; value.camera.updateProjectionMatrix();
  value.dom.window.dispatchEvent(new value.dom.window.Event('resize'));
  assertVisible(value);
  value.inspector.openFile({ id: 0 });
  value.dom.window.dispatchEvent(new value.dom.window.Event('resize'));
  value.inspector.close(); value.host.dispose(); value.dom.window.close();
});

test('portrait framing keeps source geometry visible through the scene fog', () => {
  const value = workspace(0.5), density = value.board.getScene().fog.density;
  for (const file of value.data.files) {
    const center = new THREE.Vector3(file.x, file.height / 2, file.z);
    const distance = value.camera.position.distanceTo(center);
    assert.ok(Math.exp(-Math.pow(density * distance, 2)) > 0.5, 'source towers must not disappear into fog');
  }
  value.host.dispose(); value.dom.window.close();
});

test('an old camera pointing away from a changed map returns to received source', () => {
  const value = workspace(0.5);
  value.camera.position.set(10_000, 9_000, 10_000);
  value.controls.target.set(9_000, 0, 9_000);
  value.controls.update(); value.host.save(); value.host.dispose();
  const root = value.dom.window.document.createElement('main');
  const host = createGraphControls(root, value.data, value.board,
    createGraphInspector(root, value.data, value.board));
  assertVisible(value);
  host.dispose(); value.dom.window.close();
});

function assertVisible(value) {
  const points = value.data.MODULES.flatMap(m => [-1, 1].flatMap(dx => [-1, 1].map(dz =>
    new THREE.Vector3(m._cx + dx * m._half, 0, m._cz + dz * m._half))));
  for (const file of [...value.data.files, ...value.data.exts]) {
    points.push(new THREE.Vector3(file.x, file.height, file.z));
  }
  value.camera.updateMatrixWorld();
  for (const point of points) {
    const projected = point.clone().project(value.camera);
    assert.ok(Math.abs(projected.x) <= 1 && Math.abs(projected.y) <= 1
      && projected.z >= -1 && projected.z <= 1, `clipped source ${point.toArray()} at aspect ${value.camera.aspect}`);
  }
}

for (const aspect of [0.5, 0.75, 1.8]) {
  test(`initial view and Fit/Top/ISO contain all received towers at aspect ${aspect}`, () => {
    const value = workspace(aspect);
    assertVisible(value);
    for (const label of ['Fit', 'Top', 'ISO']) {
      value.camera.position.multiplyScalar(0.08); value.controls.update();
      [...value.root.querySelectorAll('button')].find(button => button.textContent === label).click();
      assertVisible(value);
    }
    value.host.dispose(); value.dom.window.close();
  });
}
