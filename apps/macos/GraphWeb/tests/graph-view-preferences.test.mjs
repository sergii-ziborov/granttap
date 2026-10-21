import assert from 'node:assert/strict';
import test from 'node:test';
import { preferencesFixture } from './graph-preferences-fixture.mjs';

test('Legend opens independently without changing filters, camera, selection or section colours', () => {
  const f = preferencesFixture();
  f.inspector.openMethod({ id: 0, index: 0 });
  const before = { camera: f.board.getCamera().position.toArray(), selection: f.inspector.selection(),
    colours: f.segments.map(s => s.material.color.getHex()), filter: f.root.querySelector('.edge-toggle').className };
  f.click('Legend');
  const legend = f.root.querySelector('[aria-label="Map legend"]');
  assert.ok(legend && !legend.hidden);
  assert.match(legend.textContent, /Functions/);
  f.click('Close legend'); assert.equal(legend.hidden, true);
  assert.deepEqual(f.board.getCamera().position.toArray(), before.camera);
  assert.deepEqual(f.inspector.selection(), before.selection);
  assert.deepEqual(f.segments.map(s => s.material.color.getHex()), before.colours);
  assert.equal(f.root.querySelector('.edge-toggle').className, before.filter);
  f.host.dispose(); f.dom.window.close();
});

test('View separates kind, size and code checks and keeps unmeasured sections unknown', () => {
  const f = preferencesFixture(); f.click('View settings');
  f.change('Colour by', 'kind');
  assert.notEqual(f.segments[0].material.color.getHex(), f.segments[2].material.color.getHex());
  f.change('Functions', false);
  assert.ok(f.segments[0].material.opacity < f.segments[1].material.opacity);
  f.change('Functions', true); f.change('Colour by', 'health');
  const [good, bad, unmeasured] = f.segments.map(s => s.material.color);
  assert.ok(good.g > good.r, 'A measured function within all chosen checks is green');
  assert.ok(bad.r > bad.g, 'A measured threshold failure is red');
  assert.ok(unmeasured.g <= unmeasured.b, 'A constant without callable metrics is not called healthy');
  assert.match(f.root.textContent, /Cyclomatic complexity/);
  assert.match(f.root.textContent, /Loop nesting/);
  f.change('Show module labels', false);
  assert.equal(f.root.classList.contains('graph-hide-module-labels'), true);
  f.click('Reset view settings');
  assert.equal(f.root.classList.contains('graph-hide-module-labels'), false);
  f.host.dispose(); f.dom.window.close();
});

test('Health details explain actual checks and react to changed thresholds', () => {
  const f = preferencesFixture(); f.inspector.openMethod({ id: 0, index: 1 }); f.click('Health details');
  const status = () => f.root.querySelector('.graph-check-status');
  assert.equal(status()?.dataset.status, 'review');
  assert.match(f.root.querySelector('.granttap-inspector').textContent, /18/);
  f.click('View settings'); f.change('Colour by', 'health');
  f.change('Cyclomatic complexity', 30); f.change('Loop nesting', 5);
  const range = f.root.querySelector('input[type=range]'); range.value = 200;
  range.dispatchEvent(new f.dom.window.Event('input', { bubbles: true }));
  assert.equal(status()?.dataset.status, 'clear');
  f.inspector.openMethod({ id: 0, index: 2 }); f.click('Health details');
  assert.equal(status()?.dataset.status, 'unknown');
  f.host.dispose(); f.dom.window.close();
});

test('legend counts only received symbols rather than unavailable-file placeholders', () => {
  const f = preferencesFixture();
  f.data.files.push({ id: 99, symbolsUnavailable: true, methods: [{ name: 'Symbols unavailable', kind: 'unknown', loc: 5 }] });
  f.click('Legend');
  assert.doesNotMatch(f.root.querySelector('.graph-legend').textContent, /Other symbols/);
  f.host.dispose(); f.dom.window.close();
});

test('selected function checks precede long report provenance in the narrow inspector', () => {
  const f = preferencesFixture(); f.inspector.openMethod({ id: 0, index: 1 }); f.click('Health details');
  const text = f.root.querySelector('.graph-inspector-scroll').textContent;
  assert.ok(text.indexOf('Cyclomatic complexity estimate') < text.indexOf('Source revision'));
  assert.match(text, /complex/);
  f.host.dispose(); f.dom.window.close();
});

test('every colour mode is a directly tappable button with one selected state', () => {
  const f = preferencesFixture(); f.click('View settings');
  const modes = f.root.querySelectorAll('[data-colour-mode]');
  assert.equal(modes.length, 4);
  f.click('Code checks');
  assert.equal(f.root.querySelector('[data-colour-mode="health"]').getAttribute('aria-pressed'), 'true');
  assert.equal(f.root.querySelectorAll('[data-colour-mode][aria-pressed="true"]').length, 1);
  assert.ok(f.segments[0].material.color.g > f.segments[0].material.color.r);
  f.host.dispose(); f.dom.window.close();
});
