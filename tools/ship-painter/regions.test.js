// Run: node --test tools/ship-painter/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const R = require('./regions.js');

// Build a mask from rows of '#' (set) and '.' (unset).
function m(rows) {
  const h = rows.length, w = rows[0].length;
  const mask = R.makeMask(w, h);
  rows.forEach((r, y) => [...r].forEach((c, x) => { mask.data[y * w + x] = c === '#' ? 1 : 0; }));
  return mask;
}
function rows(mask) {
  const out = [];
  for (let y = 0; y < mask.h; y++) {
    let r = '';
    for (let x = 0; x < mask.w; x++) r += mask.data[y * mask.w + x] ? '#' : '.';
    out.push(r);
  }
  return out;
}
// Signed area (shoelace); positive = clockwise on screen (y down).
function area(loop) {
  let a = 0;
  for (let i = 0; i < loop.length; i++) {
    const [x1, y1] = loop[i], [x2, y2] = loop[(i + 1) % loop.length];
    a += x1 * y2 - x2 * y1;
  }
  return a / 2;
}

const RING = [
  '.......',
  '.#####.',
  '.#...#.',
  '.#...#.',
  '.#####.',
  '.......',
];

test('maskFromAlpha thresholds the alpha channel', () => {
  const rgba = new Uint8ClampedArray([0, 0, 0, 10, 0, 0, 0, 200, 0, 0, 0, 64, 0, 0, 0, 63]);
  assert.deepEqual([...R.maskFromAlpha(rgba, 4, 1, 64).data], [0, 1, 1, 0]);
});

test('dilate grows by a square kernel and r=0 copies', () => {
  const src = m(['.....', '.....', '..#..', '.....', '.....']);
  assert.deepEqual(rows(R.dilate(src, 1)), ['.....', '.###.', '.###.', '.###.', '.....']);
  assert.deepEqual(rows(R.dilate(src, 5)), Array(5).fill('#####'));
  const copy = R.dilate(src, 0);
  assert.deepEqual(rows(copy), rows(src));
  assert.notEqual(copy.data, src.data);
});

test('floodFill fills an enclosed region and reports it closed', () => {
  const f = R.floodFill(m(RING), 3, 2);
  assert.equal(f.count, 6);
  assert.equal(f.touchesEdge, false);
  assert.deepEqual(rows(f.mask), ['.......', '.......', '..###..', '..###..', '.......', '.......']);
});

test('floodFill from outside touches the edge; on a barrier pixel fills nothing', () => {
  assert.equal(R.floodFill(m(RING), 0, 0).touchesEdge, true);
  assert.equal(R.floodFill(m(RING), 1, 1).count, 0);
  assert.equal(R.floodFill(m(RING), -1, 0).count, 0);
});

test('floodFill is 4-connected: diagonal gaps do not leak', () => {
  const diag = m(['.#.', '#.#', '.#.']);
  assert.equal(R.floodFill(diag, 1, 1).count, 1);
});

test('traceContours: a solid block becomes one clockwise rectangle', () => {
  const loops = R.traceContours(m(['....', '.##.', '.##.', '....']));
  assert.equal(loops.length, 1);
  assert.equal(loops[0].length, 4);
  assert.equal(area(loops[0]), 4);
  assert.deepEqual(new Set(loops[0].map(String)), new Set(['1,1', '3,1', '3,3', '1,3']));
});

test('traceContours: a ring yields an outer loop and a counter-wound hole', () => {
  const loops = R.traceContours(m(RING));
  assert.equal(loops.length, 2);
  const areas = loops.map(area).sort((a, b) => a - b);
  assert.deepEqual(areas, [-6, 20]);
});

test('traceContours: diagonal-touching pixels make separate loops', () => {
  const loops = R.traceContours(m(['#.', '.#']));
  assert.equal(loops.length, 2);
  loops.forEach((l) => assert.equal(area(l), 1));
});

test('traceContours: empty mask has no loops', () => {
  assert.deepEqual(R.traceContours(m(['...', '...'])), []);
});

test('simplifyLoop collapses a staircase into a diagonal', () => {
  const stair = [[0, 0], [1, 0], [1, 1], [2, 1], [2, 2], [3, 2], [3, 3], [0, 3]];
  const s = R.simplifyLoop(stair, 0.75);
  assert.ok(s.length < stair.length);
  assert.ok(s.length >= 3);
  assert.deepEqual(R.simplifyLoop(stair, 0), stair);
});

test('loopsToPathD maps pixels to viewBox space and drops degenerate loops', () => {
  const d = R.loopsToPathD([[[0, 0], [2, 0], [2, 2]], [[0, 0], [1, 1]]], { sx: 0.5, sy: 0.25, ox: 10, oy: -1 });
  assert.equal(d, 'M10 -1L11 -1L11 -0.5Z');
  assert.equal(R.loopsToPathD([[[0.333, 0], [1, 0], [1, 1]]]), 'M0.33 0L1 0L1 1Z');
});

test('bucketRegion fills inside, expands under the outline, and reports errors', () => {
  const ring = m(RING);
  const r = R.bucketRegion(ring, 3, 2, 0);
  assert.equal(r.count, 6);
  // grown by gap+1 = 1px, so it reaches into the outline stroke
  assert.deepEqual(rows(r.mask), ['.......', '.#####.', '.#####.', '.#####.', '.#####.', '.......']);
  assert.equal(R.bucketRegion(ring, 0, 0, 0).error, 'open');
  assert.equal(R.bucketRegion(ring, 1, 1, 0).error, 'outline');
  assert.equal(R.bucketRegion(ring, 99, 0, 0).error, 'outside');
});

test('bucketRegion gap-close seals a 1px gap in the outline', () => {
  const leaky = m([
    '.........',
    '.#######.',
    '.#.....#.',
    '.#.....#.',
    '.#.....#.',
    '.###.###.',
    '.........',
  ]);
  assert.equal(R.bucketRegion(leaky, 4, 3, 0).error, 'open');
  const sealed = R.bucketRegion(leaky, 4, 3, 1);
  assert.equal(sealed.error, undefined);
  assert.ok(sealed.count > 0);
});

test('maskToPathD produces a closed path for a filled region', () => {
  const d = R.maskToPathD(m(['....', '.##.', '.##.', '....']), { sx: 1, sy: 1, ox: 0, oy: 0 });
  assert.match(d, /^M[\d. L]+Z$/);
});
