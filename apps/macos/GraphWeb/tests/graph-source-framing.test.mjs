import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from '../build/three/three.module.js';
import { frameGraphSource } from '../graph-source-framing.js';

for (const [width, height, panel] of [[390, 700, { left: 10, top: 370, right: 380, bottom: 620 }],
  [800, 300, { left: 10, top: 10, right: 300, bottom: 290 }]]) {
  test(`a selected tower stays inside the visible scene at ${width}×${height}`, () => {
    const camera = new THREE.PerspectiveCamera(50, width / height, 0.5, 2000);
    camera.position.set(0, 40, 60);
    camera.setViewOffset(width, height, -width * 0.4, 0, width, height);
    const controls = { target: new THREE.Vector3(), update() { camera.lookAt(this.target); camera.updateMatrixWorld(); } };
    const board = { getCamera: () => camera, getControls: () => controls, stopCameraFlight() {} };
    const root = { getBoundingClientRect: () => ({ left: 0, top: 0, right: width, bottom: height, width, height }) };
    const source = { x: 18, z: -32, height: 120 };
    assert.equal(frameGraphSource(board, root, { getBoundingClientRect: () => panel }, source), true);
    for (const y of [0, 120]) {
      const ndc = new THREE.Vector3(source.x, y, source.z).project(camera);
      const x = (ndc.x + 1) * width / 2, screenY = (1 - ndc.y) * height / 2;
      assert.ok(x > 20 && x < width - 20 && screenY > 50 && screenY < height - 50);
      assert.ok(x > panel.right || screenY < panel.top, 'source must clear its inspector');
    }
  });
}

test('transient zero-sized viewports do not change the camera', () => {
  assert.equal(frameGraphSource({}, { getBoundingClientRect: () => ({ width: 0, height: 0 }) }, {}, {}), false);
});

test('a short selected file uses the free viewport rather than fitting a large empty module tile', () => {
  const camera = new THREE.PerspectiveCamera(50, 390 / 700, 0.5, 2000);
  camera.position.set(0, 40, 60);
  const controls = { target: new THREE.Vector3(), update() { camera.lookAt(this.target); camera.updateMatrixWorld(); } };
  const board = { getCamera: () => camera, getControls: () => controls, stopCameraFlight() {} };
  const root = { getBoundingClientRect: () => ({ left: 0, top: 0, right: 390, bottom: 700, width: 390, height: 700 }) };
  const panel = { getBoundingClientRect: () => ({ left: 10, top: 370, right: 380, bottom: 620 }) };
  const file = { x: 18, z: -32, height: 8 };
  frameGraphSource(board, root, panel, file);
  const top = new THREE.Vector3(file.x, 8, file.z).project(camera);
  const bottom = new THREE.Vector3(file.x, 0, file.z).project(camera);
  assert.ok(Math.abs(top.y - bottom.y) * 350 > 80, 'small source sections must be readable after file focus');
});
