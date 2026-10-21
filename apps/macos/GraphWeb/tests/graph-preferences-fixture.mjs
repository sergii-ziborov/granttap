import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import * as THREE from '../build/three/three.module.js';
import { boardData } from '../board-data.js';
import { createGraphControls } from '../graph-controls.js';
import { createGraphInspector } from '../graph-inspector.js';

export function preferencesFixture() {
  const dom = new JSDOM('<main><aside id="cb-legend"><button class="edge-toggle on" data-edge="call">Calls</button></aside></main>',
    { url: 'https://graph.local' });
  const root = dom.window.document.querySelector('main');
  const data = boardData([{ projectId: 'project', repositoryId: 'repo', analysisStatus: 'COMPLETE',
    codeMap: { files: [{ path: 'main.swift', lineCount: 180, symbols: [
      { id: 'simple', label: 'simple', kind: 'function', startLine: 1, lineCount: 10,
        metrics: { sourceLines: 10, cyclomatic: 1, maxLoopDepth: 0, callers: 1, measured: true } },
      { id: 'complex', label: 'complex', kind: 'method', startLine: 20, lineCount: 120,
        metrics: { sourceLines: 120, cyclomatic: 18, maxLoopDepth: 4, callers: 3, measured: true } },
      { id: 'constant', label: 'version', kind: 'constant', startLine: 150, lineCount: 1 },
    ] }], roads: [], truncated: false } }]);
  const camera = new THREE.PerspectiveCamera(50, 390 / 700); camera.position.set(0, 40, 100);
  const controls = { target: new THREE.Vector3(), mouseButtons: {}, touches: {}, update() {} };
  const scene = new THREE.Scene(), segments = data.files[0].methods.map((_, index) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(), new THREE.MeshStandardMaterial({ color: 0x456789 }));
    mesh.userData = { fileId: 0, methodIndex: index }; scene.add(mesh); return mesh;
  });
  const board = { getCamera: () => camera, getControls: () => controls, getScene: () => scene,
    stopCameraFlight() {}, focusNode() {}, focusSection() {} };
  const inspector = createGraphInspector(root, data, board);
  const host = createGraphControls(root, data, board, inspector);
  const click = name => {
    const button = [...root.querySelectorAll('button')].find(b => b.getAttribute('aria-label') === name || b.textContent === name);
    assert.ok(button, `Missing visible action: ${name}`); button.click();
  };
  const change = (label, value) => {
    const input = root.querySelector(`[aria-label="${label}"]`); assert.ok(input, label);
    if (input.classList.contains('graph-colour-modes')) { input.querySelector(`[data-colour-mode="${value}"]`).click(); return; }
    if (input.type === 'checkbox') input.checked = value; else input.value = value;
    input.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
  };
  return { dom, root, data, board, inspector, host, segments, click, change };
}
