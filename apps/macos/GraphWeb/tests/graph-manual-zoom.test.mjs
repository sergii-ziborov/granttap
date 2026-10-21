import assert from 'node:assert/strict';
import test from 'node:test';
import { preferencesFixture } from './graph-preferences-fixture.mjs';
import { readFile } from 'node:fs/promises';
import { zoomGraphCamera } from '../graph-inspection.js';

test('one zoom tap makes a small reversible step and cancels pending source framing', () => {
  const f = preferencesFixture(), frames = [];
  f.dom.window.requestAnimationFrame = callback => { frames.push(callback); return frames.length; };
  f.root.getBoundingClientRect = () => ({ left: 0, top: 0, right: 390, bottom: 700, width: 390, height: 700 });
  f.root.querySelector('.granttap-inspector').getBoundingClientRect = () =>
    ({ left: 10, top: 370, right: 380, bottom: 620 });
  f.inspector.openMethod({ id: 0, index: 0 });
  const camera = f.board.getCamera(), controls = f.board.getControls();
  camera.position.set(20, 40, 100); controls.target.set(2, 3, 4);
  const original = camera.position.clone(), target = controls.target.clone();
  const distance = camera.position.distanceTo(target);
  f.click('Zoom in');
  const zoomed = camera.position.clone();
  while (frames.length) frames.shift()();
  assert.ok(camera.position.distanceTo(zoomed) < 1e-8, 'a delayed inspector layout cannot undo manual zoom');
  assert.deepEqual(controls.target.toArray(), target.toArray());
  assert.ok(Math.abs(camera.position.distanceTo(target) / distance - 0.9) < 1e-8);
  f.click('Zoom out'); assert.ok(camera.position.distanceTo(original) < 1e-8);
  f.host.dispose(); f.dom.window.close();
});

test('zoom after a damped orbit keeps the current direction, target and viewport offset', async () => {
  const moduleUrl = new URL('../build/three/three.module.js', import.meta.url).href;
  const source = (await readFile(new URL('../build/three/addons/controls/OrbitControls.js', import.meta.url), 'utf8'))
    .replace("from 'three'", `from '${moduleUrl}'`);
  const { OrbitControls } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
  const f = preferencesFixture(), camera = f.board.getCamera();
  const canvas = f.dom.window.document.createElement('canvas');
  Object.defineProperty(canvas, 'clientHeight', { value: 700 });
  const controls = new OrbitControls(camera, canvas); controls.enableDamping = true;
  controls.target.set(3, 4, 5); controls.update();
  controls.listenToKeyEvents(canvas);
  canvas.dispatchEvent(new f.dom.window.KeyboardEvent('keydown', { code: 'ArrowLeft', ctrlKey: true }));
  const target = controls.target.clone(), direction = camera.position.clone().sub(target).normalize();
  camera.setViewOffset(390, 700, 0, 100, 390, 700); const offset = { ...camera.view };
  const distance = camera.position.distanceTo(target);
  zoomGraphCamera({ ...f.board, getControls: () => controls }, 0.9);
  for (let i = 0; i < 20; i++) controls.update();
  assert.ok(camera.position.clone().sub(target).normalize().distanceTo(direction) < 1e-8,
    'residual orbit damping must not rotate a manual zoom');
  assert.ok(Math.abs(camera.position.distanceTo(target) - distance * 0.9) < 1e-8);
  assert.deepEqual(controls.target.toArray(), target.toArray());
  assert.deepEqual(camera.view, offset);
  assert.equal(controls.enableDamping, true);
  controls.dispose(); f.host.dispose(); f.dom.window.close();
});

test('plus keeps zooming inward after a pinch closer than eight world units', () => {
  const f = preferencesFixture(), camera = f.board.getCamera(), controls = f.board.getControls();
  controls.minDistance = 0; controls.maxDistance = Infinity;
  camera.position.copy(controls.target).addScalar(1);
  const before = camera.position.distanceTo(controls.target);
  f.click('Zoom in');
  assert.ok(Math.abs(camera.position.distanceTo(controls.target) - before * 0.9) < 1e-8,
    'OrbitControls zero minimum is valid; plus must not jump outward to eight units');
  f.host.dispose(); f.dom.window.close();
});
