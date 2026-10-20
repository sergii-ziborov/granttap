import assert from 'node:assert/strict';
import test from 'node:test';
import { boardData } from '../board-data.js';
import { graphFileMatches, sourceSection } from '../graph-inspection.js';

function file(lineCount, symbols) {
  return boardData([{ repositoryId: 'portable-workspace', codeMap: {
    files: [{ path: 'src/context.rs', language: 'rust', lineCount, symbols }], roads: [],
  } }]).files[0];
}

const constants = [18, 19, 20].map((line, index) => ({ id: `constant-${index}`,
  label: `CONSTANT_${index}`, kind: 'constant', startLine: line, lineCount: 1 }));

test('a measured source body remains visible without inventing source sections', () => {
  const source = file(253, constants);
  assert.equal(source.methods.length, 4);
  assert.equal(source.methods.at(-1).sourceRemainder, true);
  assert.equal(source.methods.at(-1).loc, 250);
  assert.equal(source.reportedSectionCount, 3);
  assert.equal(sourceSection(source, 3), null);
  assert.equal(sourceSection(source, 0).id, 'constant-0');
  const data = { files: [source], exts: [] };
  assert.equal(graphFileMatches(data, 'Other source lines').length, 0);
  assert.equal(graphFileMatches(data, 'CONSTANT_').at(0).sections.length, 3);
});

test('overlapping section ranges count each covered source line once', () => {
  const source = file(100, [
    { id: 'outer', label: 'Outer', kind: 'struct', startLine: 10, lineCount: 60 },
    { id: 'inner', label: 'run', kind: 'method', startLine: 20, lineCount: 30 },
  ]);
  assert.equal(source.methods.at(-1).loc, 40);
  assert.equal(source.reportedSectionCount, 2);
});

test('absent locations and file measurements never create guessed source bodies', () => {
  const unknownSize = file(undefined, constants);
  assert.equal(unknownSize.methods.length, 3);
  const unknownLocation = file(100, [{ id: 'unknown', label: 'run', lineCount: 20 }]);
  assert.equal(unknownLocation.methods.length, 1);
  const absent = file(undefined, []);
  assert.equal(absent.symbolsUnavailable, true);
  assert.equal(absent.methods.length, 1);
  assert.equal(absent.reportedSectionCount, 0);
});

test('fully covered and bounded source ranges keep measured sections intact', () => {
  const complete = file(10, [{ id: 'all', label: 'all', startLine: 1, lineCount: 10 }]);
  assert.equal(complete.methods.length, 1);
  const clipped = file(10, [{ id: 'bounds', label: 'bounds', startLine: 5, lineCount: 60 }]);
  assert.equal(clipped.methods.at(-1).loc, 4);
  assert.equal(clipped.methods[0].loc, 60);
  assert.equal(file(0, []).methods.length, 1);
});
