// Run: node --test tools/ship-painter/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const S = require('./scan.js');

// Gray image from rows: '#' = ink (black), '.' = paper (white).
function gray(rows) {
  const h = rows.length, w = rows[0].length;
  const data = new Uint8Array(w * h);
  rows.forEach((r, y) => [...r].forEach((c, x) => { data[y * w + x] = c === '#' ? 0 : 255; }));
  return { w: w, h: h, data: data };
}

// A box outline with a divider: two enclosed areas, top one larger. Padded with paper.
function boxes(size, split, opts) {
  opts = opts || {};
  const rows = [];
  for (let y = 0; y < size; y++) {
    let r = '';
    for (let x = 0; x < size; x++) {
      const edge = x === 4 || x === 5 || x === size - 5 || x === size - 6 || y === 4 || y === 5 || y === size - 5 || y === size - 6;
      const inside = x >= 4 && x <= size - 5 && y >= 4 && y <= size - 5;
      const divider = (y === split || y === split + 1) && inside;
      const gap = opts.gapAt && x === opts.gapAt[0] && y >= opts.gapAt[1] && y < opts.gapAt[1] + opts.gapAt[2];
      r += inside && (edge || divider) && !gap ? '#' : '.';
    }
    rows.push(r);
  }
  return gray(rows);
}

test('parsePgm reads a binary PGM and rejects others', () => {
  const buf = Buffer.concat([Buffer.from('P5\n# scan\n3 2\n255\n'), Buffer.from([0, 1, 2, 3, 4, 5])]);
  const g = S.parsePgm(buf);
  assert.equal(g.w, 3);
  assert.equal(g.h, 2);
  assert.deepEqual([...g.data], [0, 1, 2, 3, 4, 5]);
  assert.throws(() => S.parsePgm(Buffer.from('P2\n1 1\n255\n0')), /P5/);
  assert.throws(() => S.parsePgm(Buffer.from('P5\n2 2\n255\n\x00')), /truncated/);
});

test('enclosed areas become regions, biggest first, the outside does not', () => {
  const a = S.analyze(boxes(60, 36), { minRegion: 10, minInk: 5, silhouetteGap: 0 });
  assert.equal(a.regions.length, 2);
  assert.ok(a.regions[0].stats.count > a.regions[1].stats.count);
  assert.equal(a.leftover, null);
});

test('dust specks are dropped from the ink', () => {
  const g = boxes(60, 36);
  g.data[2 * 60 + 2] = 0; // a lone dark pixel outside
  const a = S.analyze(g, { minRegion: 10, minInk: 5 });
  assert.equal(a.ink.data[2 * 60 + 2], 0);
});

test('slot guesses: largest is hull, low area is thrusters', () => {
  const a = S.analyze(boxes(60, 36), { minRegion: 10, minInk: 5 });
  const slots = S.guessSlots(a.inkStats, a.regions);
  assert.equal(slots[0], 2);
  assert.ok(slots[1] >= 3 && slots[1] <= 9);
});

test('an area leaking through a small break in the lines is still filled', () => {
  // Break the left wall of the lower box for 6 px: too wide for the line gap, closed by the silhouette.
  const g = boxes(60, 30, { gapAt: [4, 40, 6] });
  for (let y = 40; y < 46; y++) g.data[y * 60 + 5] = 255;
  const open = S.analyze(g, { minRegion: 10, minInk: 5, gap: 1, silhouetteGap: 0 });
  assert.equal(open.regions.length, 1, 'lower area leaks out');
  const closed = S.analyze(g, { minRegion: 10, minInk: 5, gap: 1, silhouetteGap: 5 });
  assert.ok(closed.leftover, 'leftover inside the silhouette');
  assert.equal(closed.leftover.data[42 * 60 + 30], 1);
});

test('scanToSvg writes a 9-slot paintable ship with the outline on top', () => {
  const svg = S.scanToSvg(boxes(60, 36), { minRegion: 10, minInk: 5 });
  assert.match(svg, /data-slots="9"/);
  assert.match(svg, /viewBox="0 0 60 60"/);
  assert.match(svg, /<g data-layer="fills" stroke="none">/);
  const slots = [...svg.matchAll(/data-slot="(\d)"/g)].map((m) => +m[1]);
  assert.equal(slots[slots.length - 1], 1, 'outline last');
  assert.ok(slots.includes(2));
  assert.ok(slots.every((s) => s >= 1 && s <= 9));
});

test('roundDilate grows less at the corners than a square brush', () => {
  const R = require('./regions.js');
  const m = R.makeMask(21, 21);
  m.data[10 * 21 + 10] = 1;
  const round = S.roundDilate(m, 6);
  assert.equal(round.data[10 * 21 + 16], 1, 'reaches out along the axis');
  assert.equal(round.data[4 * 21 + 4], 0, 'but not the full square corner');
});

test('silhouette fills a drawing that runs right up to the image edge', () => {
  const g = boxes(30, 18);
  const a = S.analyze(g, { minRegion: 5, minInk: 5 });
  // crop so the outline touches the edges
  const R = require('./regions.js');
  const crop = R.makeMask(22, 22);
  for (let y = 0; y < 22; y++) for (let x = 0; x < 22; x++) crop.data[y * 22 + x] = a.ink.data[(y + 4) * 30 + x + 4];
  const inside = S.silhouette(crop, 4);
  assert.equal(inside.data[11 * 22 + 11], 1, 'middle is inside');
  assert.equal(inside.data[0], 1, 'corner ink counts as inside');
  let outsideCorner = 0;
  for (let i = 0; i < inside.data.length; i++) if (!inside.data[i] && crop.data[i]) outsideCorner++;
  assert.equal(outsideCorner, 0, 'no ink is outside');
});

test('paintTracedSvg keeps traced paths as the outline and adds fills under them', () => {
  const traced = '<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="10 20 30 30">\n' +
    '<g fill="#000000"><path d="M1 1L2 2Z"/><path d="M3 3L4 4Z"/></g>\n</svg>\n';
  const out = S.paintTracedSvg(traced, boxes(60, 36), { minRegion: 10, minInk: 5 });
  assert.match(out, /data-slots="9"/);
  assert.equal((out.match(/<path data-slot="1" fill="#e6e8eb" d="M[13] /g) || []).length, 2, 'both traced paths are slot 1');
  assert.ok(out.indexOf('data-layer="fills"') < out.indexOf('d="M1 1'), 'fills under the outline');
  // 60 px render of a 30-unit viewBox at (10, 20): fills land inside the viewBox
  const nums = [...out.matchAll(/data-slot="[2-9]"[^>]*d="([^"]+)"/g)].flatMap((m) => m[1].match(/-?[\d.]+/g).map(Number));
  assert.ok(nums.length > 0);
  for (let i = 0; i < nums.length; i += 2) {
    assert.ok(nums[i] >= 0 && nums[i] <= 30, 'x in the 0-based viewBox');
    assert.ok(nums[i + 1] >= 0 && nums[i + 1] <= 30, 'y in the 0-based viewBox');
  }
  assert.match(out, /viewBox="0 0 30 30"/, 'viewBox moved to 0 0');
  assert.match(out, /<g transform="translate\(-10,-20\)">/, 'traced shapes shifted to match');
  assert.ok(out.trim().endsWith('</svg>'));
  const again = S.paintTracedSvg(out, boxes(60, 36), { minRegion: 10, minInk: 5 });
  assert.equal((again.match(/data-layer="fills"/g) || []).length, 1, 'repainting replaces the fills');
});
