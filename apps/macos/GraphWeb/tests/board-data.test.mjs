import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { boardData } from '../board-data.js';

test('module labels use relative source folders while routing keeps full repository identity', () => {
  const data = boardData([{ repositoryId: 'example.org/company/portable-repository', codeMap: {
    files: [{ path: 'Sources/Networking/Client.swift', lineCount: 20, symbols: [] }], roads: [],
  } }]);
  assert.equal(data.MODULES[0].displayName, 'Sources/Networking');
  assert.equal(data.files[0].repositoryId, 'example.org/company/portable-repository');
  assert.equal(data.files[0].module, data.MODULES[0].name);
});

test('repositories share one board without merging equal native node IDs', () => {
  const data = boardData(['api', 'worker'].map(repositoryId => ({
    repositoryId,
    nodes: [{ id: 'service', label: `${repositoryId} service`, kind: 'component' },
      { id: 'client', label: `${repositoryId} client`, kind: 'component' }],
    relations: [{ source: 'service', target: 'client', relation: 'calls', evidenceCount: 2 }],
  })));
  assert.equal(data.MODULES.length, 2);
  assert.equal(data.files.length, 4);
  assert.deepEqual(data.edges.map(edge => [edge.a, edge.b]), [[0, 1], [2, 3]]);
  assert.equal(data.files[0].coverage, null);
  assert.equal(data.files[0].methods[0].health, null);
});

test('empty and dangling reports never create demo nodes or invented edges', () => {
  assert.equal(boardData([]).files.length, 0);
  const data = boardData([{ repositoryId: 'api', nodes: [{ id: 'a', label: 'A' }],
    relations: [{ source: 'a', target: 'missing', relation: 'calls' }] }]);
  assert.equal(data.files.length, 1);
  assert.equal(data.edges.length, 0);
});

test('code map keeps real file sizes and symbol names across linked repositories', () => {
  const data = boardData(['api', 'client'].map(repositoryId => ({
    repositoryId,
    codeMap: {
      files: [{ path: 'src/Service.swift', lineCount: 80,
        symbols: [{ id: 's1', label: 'run()', startLine: 12, lineCount: 22 }] },
      { path: 'src/Store.swift', lineCount: 40, symbols: [] }],
      roads: [{ source: 'src/Service.swift', target: 'src/Store.swift', relation: 'calls' }],
    },
  })));
  assert.equal(data.MODULES.length, 2);
  assert.equal(data.files[0].methods[0].name, 'run()');
  assert.equal(data.files[0].loc, 80);
  assert.equal(data.files[1].methods[0].name, 'Symbols unavailable');
  assert.deepEqual(data.edges.map(edge => [edge.a, edge.b]), [[0, 1], [2, 3]]);
});

test('observed external services keep their evidenced roads', () => {
  const data = boardData([{ repositoryId: 'api', codeMap: {
    files: [{ path: 'src/server.ts', lineCount: 60, symbols: [] }],
    externals: [{ id: 'ext:postgres', label: 'Postgres', kind: 'service' }],
    roads: [{ source: 'src/server.ts', target: 'ext:postgres', relation: 'consumes' }],
  } }]);
  assert.equal(data.exts.length, 1);
  assert.equal(data.exts[0].name, 'Postgres · api');
  assert.deepEqual(data.edges.map(edge => [edge.a, edge.b, edge.type]), [[0, 1, 'io']]);
});

test('a file map retains architecture components and their evidenced service links', () => {
  const data = boardData([{ repositoryId: 'api', codeMap: {
    files: [{ path: 'src/server.ts', lineCount: 60, symbols: [] }],
    externals: [{ id: 'ext:postgres', label: 'Postgres', kind: 'db' }],
    roads: [{ source: 'src/server.ts', target: 'ext:postgres', relation: 'reads' }],
  }, nodes: [{ id: 'route', label: 'HTTP router', kind: 'service' },
    { id: 'store', label: 'Store', kind: 'component' }],
  relations: [{ source: 'route', target: 'store', relation: 'calls', evidenceCount: 3 }],
  }]);
  assert.equal(data.files.length, 1);
  assert.deepEqual(data.exts.map(item => item.name),
    ['Postgres · api', 'HTTP router · api', 'Store · api']);
  assert.deepEqual(data.edges.map(edge => [edge.a, edge.b, edge.type]),
    [[0, 1, 'io'], [2, 3, 'call']]);
  assert.equal(data.edges[1].payload, 3);
});

test('section selection retains repository, revision, symbol identity and kind', () => {
  const data = boardData([{ repositoryId: 'repo', sourceRevision: 'commit-a', revision: 'analysis-a',
    analysisStatus: 'INCOMPLETE', codeMap: { files: [{ path: 'src/file.swift', language: 'swift',
      lineCount: 90, symbols: [{ id: 'symbol-1', label: 'run()', kind: 'function', startLine: 12, lineCount: 22 }],
    }], roads: [], totalFiles: 1, truncated: false } }]);
  const file = data.files[0];
  assert.equal(file.repositoryId, 'repo');
  assert.equal(file.sourceRevision, 'commit-a');
  assert.equal(file.analysisStatus, 'INCOMPLETE');
  assert.equal(file.methods[0].id, 'symbol-1');
  assert.equal(file.methods[0].kind, 'function');
  assert.equal(file.language, 'swift');
});

test('a large module leaves space for its neighbouring module plate', () => {
  const files = Array.from({ length: 400 }, (_, i) => ({ path: `large/file${i}.swift`, symbols: [] }));
  files.push({ path: 'small/only.swift', symbols: [] });
  const data = boardData([{ repositoryId: 'repo', codeMap: { files, roads: [] } }]);
  const [a, b] = data.MODULES;
  assert.ok(Math.abs(a._cx - b._cx) >= a._half + b._half + 20);
});
