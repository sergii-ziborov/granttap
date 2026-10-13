import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from '../build/three/three.module.js';
import { boardData } from '../board-data.js';
import { findGraphFile, sourceSection, graphFileLinks, graphFileMatches,
  zoomGraphCamera, applySectionHighlights } from '../graph-inspection.js';

const reports = ['a', 'b'].map(repositoryId => ({ repositoryId, sourceRevision: 'git', revision: 'analysis',
  analysisStatus: 'INCOMPLETE', codeMap: { files: [{ path: 'src/file.swift', lineCount: 90,
    symbols: Array.from({ length: 36 }, (_, i) => ({ id: `symbol-${i}`, label: `run${i}()`,
      kind: 'function', startLine: i * 20 + 1, lineCount: i + 10 })) },
  { path: 'src/other.swift', lineCount: null, symbols: [] }], roads: [
    { source: 'src/file.swift', target: 'src/other.swift', relation: 'calls' }],
  totalFiles: 2, truncated: false } }));

test('inspecting the last section preserves its exact repository and source lines', () => {
  const data = boardData(reports), file = findGraphFile(data, { repositoryId: 'b', path: 'src/file.swift' });
  assert.equal(findGraphFile(data, { id: file.id }), file);
  assert.equal(findGraphFile(data, { repositoryId: 'missing', path: file._path }), undefined);
  const section = sourceSection(file, 35);
  assert.equal(section.id, 'symbol-35'); assert.equal(section.repositoryId, 'b');
  assert.equal(section.line, 701); assert.equal(section.endLine, 745);
  assert.equal(section.partial, true); assert.equal(section.sourceRevision, 'git');
  assert.equal(sourceSection(file, 99), null);
  assert.equal(sourceSection(data.files[1], 0), null);
  assert.equal(graphFileMatches(data, 'run35')[1].sections[0].index, 35);
  assert.equal(graphFileMatches(data, '').length, 4);
  assert.equal(graphFileMatches(data, 'no match').length, 0);
  assert.equal(graphFileLinks(data, file)[0].direction, 'out');
  assert.equal(graphFileLinks(data, data.files[3])[0].direction, 'in');
});

test('zoom moves a real perspective camera around its selected target and respects bounds', () => {
  const camera = new THREE.PerspectiveCamera(), target = new THREE.Vector3(8, 4, 2);
  camera.position.copy(target).add(new THREE.Vector3(0, 0, 100));
  const controls = { target, minDistance: 8, maxDistance: 200, update() {} };
  const board = { getCamera: () => camera, getControls: () => controls, stopCameraFlight() {} };
  assert.equal(zoomGraphCamera(board, 0.5), true);
  assert.equal(camera.position.distanceTo(target), 50);
  zoomGraphCamera(board, 0.0001); assert.equal(camera.position.distanceTo(target), 8);
  zoomGraphCamera(board, 100); assert.equal(camera.position.distanceTo(target), 200);
  assert.equal(zoomGraphCamera(board, NaN), false);
  camera.position.copy(target); assert.equal(zoomGraphCamera(board, 0.5), false);
});

test('changing a LOC warning threshold restores original colours without inventing a health score', () => {
  const data = boardData(reports), scene = new THREE.Scene();
  const node = new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshStandardMaterial({ color: 0x123456 }));
  node.userData = { fileId: 0, methodIndex: 35 }; scene.add(node);
  const board = { getScene: () => scene };
  applySectionHighlights(board, data, 40); assert.equal(node.material.color.getHex(), 0xffb454);
  applySectionHighlights(board, data, 100); assert.equal(node.material.color.getHex(), 0x123456);
  applySectionHighlights(board, data, 'bad'); assert.equal(node.material.color.getHex(), 0x123456);
  assert.equal(data.files[0].methods[35].health, null);
});
