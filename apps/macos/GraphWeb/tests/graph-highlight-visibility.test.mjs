import assert from 'node:assert/strict';
import test from 'node:test';
import { preferencesFixture } from './graph-preferences-fixture.mjs';
import * as THREE from '../build/three/three.module.js';

test('focus glow cannot bleach semantic colours or make the neutral source body dominant', () => {
  const f = preferencesFixture();
  f.change('Colour by', 'health');
  const [good, bad, , body] = f.segments;
  for (const mesh of [good, bad, body]) {
    mesh.material.emissiveIntensity = 2.35;
    mesh.material.opacity = 1;
    mesh.onBeforeRender();
  }
  assert.ok(good.material.emissiveIntensity <= 0.5, 'selected green remains green after vendor focus');
  assert.ok(bad.material.emissiveIntensity <= 0.5, 'selected red remains red after vendor focus');
  assert.ok(body.material.emissiveIntensity < good.material.emissiveIntensity);
  assert.ok(body.material.opacity < good.material.opacity);
  assert.notEqual(body.material.color.getHex(), good.material.color.getHex());
  f.change('Colour by', 'kind'); f.change('Functions', false);
  good.material.opacity = 1; good.onBeforeRender();
  assert.equal(good.material.opacity, 0.18, 'vendor focus cannot remove the selected kind dimming');
  f.change('Show other source lines', false);
  assert.equal(body.visible, false);
  const ray = new THREE.Raycaster(new THREE.Vector3(0, 0, 5), new THREE.Vector3(0, 0, -1));
  body.updateMatrixWorld();
  assert.equal(ray.intersectObject(body).length, 0, 'hidden source context cannot intercept tower taps');
  f.change('Colour by', 'kind');
  assert.equal(body.visible, false, 'changing colour mode retains the source-body setting');
  f.click('Reset view settings'); assert.equal(body.visible, true);
  assert.ok(ray.intersectObject(body).length > 0, 'restoring source context restores file picking');
  f.host.dispose(); f.dom.window.close();
});

test('settings group measured colour evidence, source context, labels and links', () => {
  const f = preferencesFixture(); f.click('View settings');
  const panel = f.root.querySelector('[aria-label="View settings"]');
  assert.deepEqual([...panel.querySelectorAll('fieldset>legend')].map(node => node.textContent),
    ['Colour by', 'Source context', 'Labels', 'Links']);
  assert.match(panel.textContent, /2 of 2 callable sections measured/);
  const functions = panel.querySelector('[aria-label="Functions"]').closest('label');
  assert.ok(functions.querySelector('.graph-swatch'), 'kind filter has a matching visible swatch');
  f.click('Code checks');
  assert.match(panel.textContent, /1.*Within selected code checks/);
  assert.match(panel.textContent, /1.*Code checks need review/);
  f.host.dispose(); f.dom.window.close();
});
