import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import { graphButton } from '../graph-language.js';

function fixture() {
  const dom = new JSDOM('<main></main>');
  let calls = 0;
  const button = graphButton(dom.window.document, 'Files', () => { calls += 1; });
  dom.window.document.querySelector('main').append(button);
  const pointer = (type, x = 10) => {
    const event = new dom.window.Event(type, { bubbles: true, cancelable: true });
    Object.assign(event, { pointerType: 'touch', pointerId: 1, clientX: x, clientY: 10 });
    button.dispatchEvent(event);
  };
  return { dom, button, pointer, calls: () => calls };
}

test('touch controls activate on release and ignore the delayed compatibility click', () => {
  const value = fixture();
  value.pointer('pointerdown'); assert.equal(value.calls(), 0);
  value.pointer('pointerup'); assert.equal(value.calls(), 1);
  value.pointer('click'); assert.equal(value.calls(), 1);
  value.button.click(); assert.equal(value.calls(), 2, 'Keyboard and accessibility click remain available');
  value.dom.window.close();
});

test('scrolling and cancelled touches never activate a section or navigation control', () => {
  const value = fixture();
  value.pointer('pointerdown'); value.pointer('pointerup', 50);
  assert.equal(value.calls(), 0);
  value.pointer('pointerdown'); value.pointer('pointercancel'); value.pointer('pointerup');
  assert.equal(value.calls(), 0);
  value.dom.window.close();
});

test('older WebKit mouse compatibility clicks cannot repeat a touch action', () => {
  const value = fixture();
  value.pointer('pointerdown'); value.pointer('pointerup');
  value.button.dispatchEvent(new value.dom.window.MouseEvent('click', { bubbles: true, detail: 1 }));
  assert.equal(value.calls(), 1);
  value.dom.window.close();
});

test('a delayed touch click cannot activate a replacement control after rendering a new panel', () => {
  const dom = new JSDOM('<main></main>'), root = dom.window.document.querySelector('main');
  const calls = [];
  const next = graphButton(dom.window.document, 'Next', () => calls.push('next'));
  const first = graphButton(dom.window.document, 'First', () => { calls.push('first'); root.replaceChildren(next); });
  root.append(first);
  for (const type of ['pointerdown', 'pointerup']) {
    const event = new dom.window.Event(type, { bubbles: true, cancelable: true });
    Object.assign(event, { pointerType: 'touch', pointerId: 1, clientX: 10, clientY: 10 }); first.dispatchEvent(event);
  }
  next.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true, detail: 1, clientX: 10, clientY: 10 }));
  assert.deepEqual(calls, ['first']);
  next.click(); assert.deepEqual(calls, ['first', 'next']);
  dom.window.close();
});
