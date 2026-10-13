import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';
import * as THREE from '../build/three/three.module.js';
import { graphViewState, restoreGraphView } from '../graph-view-state.js';

test('corrupt or inaccessible view preferences cannot prevent opening the source map', () => {
  const dom = new JSDOM('', { url: 'https://graph.local' }), data = { files: [
    { repositoryId: 'a', _path: 'main.swift', methods: [{ id: 'symbol' }] },
  ] };
  const store = graphViewState(dom.window, data), position = new THREE.Vector3(20, 30, 40);
  const board = { getCamera: () => ({ position }), getControls: () => ({ target: new THREE.Vector3() }) };
  store.save(board, { selection: () => null }, {});
  const key = dom.window.localStorage.key(0);
  for (const value of ['{', '{}', 'null', '{"position":[1,2,13000],"target":[0,0,0]}',
    '{"position":[1,2,"3"],"target":[0,0,0]}', '{"position":[1,2],"target":[0,0,0]}']) {
    dom.window.localStorage.setItem(key, value); assert.equal(store.load(), null);
  }
  const blocked = graphViewState({ get localStorage() { throw new Error('Unavailable'); } }, data);
  assert.equal(blocked.load(), null); assert.doesNotThrow(() => blocked.save(board, { selection: () => null }, {}));
  assert.doesNotThrow(() => restoreGraphView({}, {}, null));
});

test('restored file identity stays within its repository and never moves another map', () => {
  const dom = new JSDOM('', { url: 'https://graph.local' });
  const make = repositoryId => ({ files: [{ repositoryId, _path: 'main.swift', methods: [{ id: 'same' }] }] });
  const camera = new THREE.PerspectiveCamera(); camera.position.set(20, 30, 40);
  const controls = { target: new THREE.Vector3(), update() {} };
  const board = { getCamera: () => camera, getControls: () => controls, stopCameraFlight() {} };
  const state = graphViewState(dom.window, make('a'));
  state.save(board, { selection: () => ({ repositoryId: 'a', path: 'main.swift', index: null }) }, {});
  assert.equal(graphViewState(dom.window, make('b')).load(), null);
  const received = [];
  restoreGraphView(board, { openFile(value) { received.push(value); } }, state.load());
  assert.equal(received[0].repositoryId, 'a'); assert.deepEqual(camera.position.toArray(), [20, 30, 40]);
  state.save(board, { selection: () => null }, {}); restoreGraphView(board, {}, state.load());
});
