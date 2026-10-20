import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { layoutGraphLabels } from '../graph-label-layout.js';

test('dense city labels do not overlap and return when the camera separates them', () => {
  const dom = new JSDOM('<main><i class="lbl module">Core</i><i class="lbl module">API</i><i class="lbl ext">Database</i></main>');
  const root = dom.window.document.querySelector('main');
  root.getBoundingClientRect = () => ({ left: 0, top: 0, right: 400, bottom: 700 });
  const labels = [...root.children];
  let separated = false;
  labels.forEach((label, index) => {
    label.getBoundingClientRect = () => ({ left: 40, right: 140,
      top: separated ? 100 + index * 40 : 100, bottom: separated ? 118 + index * 40 : 118,
      width: 100, height: 18 });
  });
  layoutGraphLabels(root);
  assert.equal(labels.filter(label => label.style.visibility !== 'hidden').length, 1);
  separated = true; layoutGraphLabels(root);
  assert.equal(labels.filter(label => label.style.visibility !== 'hidden').length, 3);
  labels[0].getBoundingClientRect = () => ({ left: -200, right: -100, top: 100, bottom: 118, width: 100, height: 18 });
  layoutGraphLabels(root);
  assert.equal(labels[0].style.visibility, 'hidden');
  dom.window.close();
});

test('zero-sized renderer labels stay hidden until the renderer lays them out', () => {
  const dom = new JSDOM('<main><i class="lbl module">Core</i></main>');
  layoutGraphLabels(dom.window.document.querySelector('main'));
  assert.equal(dom.window.document.querySelector('i').style.visibility, 'hidden');
  dom.window.close();
});

test('focused tower facts do not collide with each other or obscure their inspector', () => {
  const dom = new JSDOM('<main><i class="lbl module">Core</i><i class="lbl ring">LOC 200</i><i class="lbl ring">HEALTH n/a</i><aside class="granttap-inspector"></aside></main>');
  const root = dom.window.document.querySelector('main');
  root.getBoundingClientRect = () => ({ left: 0, top: 0, right: 400, bottom: 700 });
  const module = root.querySelector('.module'), rings = [...root.querySelectorAll('.ring')];
  const rect = (top, bottom) => ({ left: 40, right: 140, top, bottom, width: 100, height: bottom - top });
  module.getBoundingClientRect = () => rect(100, 118);
  rings[0].getBoundingClientRect = () => rect(100, 118);
  rings[1].getBoundingClientRect = () => rect(110, 128);
  root.querySelector('aside').getBoundingClientRect = () => rect(370, 620);
  layoutGraphLabels(root);
  assert.equal(rings[0].style.visibility, 'visible', 'selected source facts take priority over area labels');
  assert.equal(rings[1].style.visibility, 'hidden', 'overlapping facts remain available in the inspector');
  assert.equal(module.style.visibility, 'hidden');
  rings[0].getBoundingClientRect = () => rect(400, 418);
  layoutGraphLabels(root);
  assert.equal(rings[0].style.visibility, 'hidden', 'world-space text must clear the detail panel');
  assert.equal(rings[1].style.visibility, 'visible', 'facts return when their projected bounds separate');
  dom.window.close();
});

test('a 37-section tower keeps readable callouts, paging and every inspector section', () => {
  const dom = new JSDOM('<main><aside class="granttap-inspector"></aside></main>');
  const root = dom.window.document.querySelector('main'), panel = root.querySelector('aside');
  root.getBoundingClientRect = () => ({ left: 0, top: 0, right: 390, bottom: 700 });
  panel.getBoundingClientRect = () => ({ left: 10, top: 400, right: 380, bottom: 620 });
  for (let index = 0; index < 37; index++) {
    const row = dom.window.document.createElement('button'); row.textContent = `section${index}`; panel.append(row);
    const label = dom.window.document.createElement('i'); label.className = `lbl callout${index === 36 ? ' active' : ''}`;
    label.textContent = row.textContent; root.append(label);
    label.getBoundingClientRect = () => ({ left: 230, right: 370, top: 100 + index * 3,
      bottom: 120 + index * 3, width: 140, height: 20 });
  }
  const more = dom.window.document.createElement('button'); more.className = 'lbl callout elev-more';
  more.textContent = '15 more'; root.append(more);
  more.getBoundingClientRect = () => ({ left: 230, right: 370, top: 65, bottom: 85, width: 140, height: 20 });
  layoutGraphLabels(root);
  const visible = [...root.querySelectorAll('.callout')].filter(label => label.style.visibility !== 'hidden');
  assert.ok(visible.length > 2 && visible.length < 38);
  assert.equal(more.style.visibility, 'visible', 'paging remains an accessible route through the tower');
  assert.equal(root.querySelector('.active').style.visibility, 'visible', 'the selected section has priority');
  for (let index = 0; index < visible.length; index++) for (const other of visible.slice(index + 1)) {
    const a = visible[index].getBoundingClientRect(), b = other.getBoundingClientRect();
    assert.ok(a.bottom <= b.top || b.bottom <= a.top, 'world-space section labels must not overlap');
  }
  assert.equal(panel.querySelectorAll('button').length, 37);
  assert.equal(root.querySelectorAll('.callout').length, 38, 'collision layout does not discard received sections');
  dom.window.close();
});

test('the selected filename takes priority over a neighboring source label', () => {
  const dom = new JSDOM('<main><i class="lbl neighbor">project.rs</i><i class="lbl filename">graph.rs</i></main>');
  const root = dom.window.document.querySelector('main');
  root.getBoundingClientRect = () => ({ left: 0, top: 0, right: 400, bottom: 700 });
  for (const label of root.children) label.getBoundingClientRect = () => ({
    left: 100, right: 220, top: 100, bottom: 120, width: 120, height: 20,
  });
  layoutGraphLabels(root);
  assert.equal(root.querySelector('.filename').style.visibility, 'visible');
  assert.equal(root.querySelector('.neighbor').style.visibility, 'hidden');
  assert.match(root.textContent, /project.rs.*graph.rs/);
  dom.window.close();
});
