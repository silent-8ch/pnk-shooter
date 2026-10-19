// Run: node --test tools/ship-painter/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const Sh = require('./sheet.js');

const PX = 4; // px per mm for rendered test sheets

// A sheet as a scanner would see it, at PX px/mm: the layout's filled shapes and outlines
// (text left out), plus `marks` [x, y, w, h] in mm drawn in ink.
function render(id, marks) {
  const w = Sh.PAGE.w * PX, h = Sh.PAGE.h * PX;
  const data = new Uint8Array(w * h).fill(255);
  const fill = (x, y, rw, rh, g) => {
    for (let yy = Math.round(y * PX); yy < Math.round((y + rh) * PX); yy++) {
      for (let xx = Math.round(x * PX); xx < Math.round((x + rw) * PX); xx++) data[yy * w + xx] = Math.round(g * 255);
    }
  };
  for (const s of Sh.layout(id)) {
    if (!s.rect) continue;
    const [x, y, rw, rh] = s.rect;
    if (s.fill) { fill(x, y, rw, rh, s.gray); continue; }
    const t = 0.5;
    fill(x, y, rw, t, s.gray); fill(x, y + rh - t, rw, t, s.gray); fill(x, y, t, rh, s.gray); fill(x + rw - t, y, t, rh, s.gray);
  }
  for (const m of marks || []) fill(m[0], m[1], m[2], m[3], 0);
  return { w: w, h: h, data: data };
}

// `gray` seen through a map from output pixel to source pixel, on a light gray background.
function warp(gray, w, h, map) {
  const data = new Uint8Array(w * h).fill(230);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [sx, sy] = map(x, y).map(Math.round);
      if (sx >= 0 && sy >= 0 && sx < gray.w && sy < gray.h) data[y * w + x] = gray.data[sy * gray.w + sx];
    }
  }
  return { w: w, h: h, data: data };
}

function rotate(gray, deg) {
  const a = deg * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
  const W = Math.round(Math.abs(gray.w * c) + Math.abs(gray.h * s)) + 40;
  const H = Math.round(Math.abs(gray.w * s) + Math.abs(gray.h * c)) + 40;
  return warp(gray, W, H, (x, y) => {
    const dx = x - W / 2, dy = y - H / 2;
    return [c * dx + s * dy + gray.w / 2, -s * dx + c * dy + gray.h / 2];
  });
}

// Mean x/y of the ink in a result, as fractions of its size.
function inkCenter(g) {
  let n = 0, sx = 0, sy = 0;
  for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) if (g.data[y * g.w + x] < 128) { n++; sx += x; sy += y; }
  return { n: n, x: sx / n / g.w, y: sy / n / g.h };
}

// The ship page; a ship drawing that is heavy at the top (a bar over a thin stem) and taller than wide.
const SHIP_ID = Sh.sheetId(0, 0);
const shipSlots = Sh.place(0);
const sf = shipSlots[0].frame;
const SHIP = [[sf.x + sf.w * 0.2, sf.y + 2, sf.w * 0.6, sf.h * 0.25], [sf.x + sf.w * 0.45, sf.y + sf.h * 0.25, sf.w * 0.1, sf.h * 0.7]];

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

test('code bits round trip and the checksum catches a flipped bit', () => {
  for (const id of [0, 1, 42, 1234, Sh.MAX_ID]) {
    const bits = Sh.codeBits(id);
    assert.equal(bits.length, Sh.CODE_BITS);
    assert.equal(Sh.decodeBits(bits), id);
    for (let i = 0; i < bits.length; i++) {
      const bad = bits.slice();
      bad[i] ^= 1;
      assert.notEqual(Sh.decodeBits(bad), id);
    }
  }
  assert.ok(Sh.codeBits(0).includes(1)); // sheet 0 still prints some filled cells
  assert.throws(() => Sh.codeBits(-1), /0\.\./);
  assert.throws(() => Sh.codeBits(Sh.MAX_ID + 1), /0\.\./);
  assert.throws(() => Sh.codeBits(1.5), /0\.\./);
});

test('every page has its own sheet numbers and round trips through them', () => {
  Sh.PAGES.forEach((_, page) => {
    for (const copy of [0, Sh.COPIES - 1]) {
      const id = Sh.sheetId(page, copy);
      assert.ok(id <= Sh.MAX_ID);
      assert.deepEqual(Sh.sheetPage(id), { page: page, copy: copy });
    }
  });
  assert.equal(Sh.sheetPage(Sh.PAGES.length * Sh.COPIES), null);
  assert.throws(() => Sh.sheetId(Sh.PAGES.length, 0), /page must be/);
  assert.throws(() => Sh.sheetId(0, Sh.COPIES), /copy/);
  assert.throws(() => Sh.layout(Sh.PAGES.length * Sh.COPIES), /no page/);
});

test('every item is on a page, and pages use only known items', () => {
  const used = new Set(Sh.PAGES.flatMap((p) => p.items));
  for (const it of Sh.ITEMS) assert.ok(used.has(it.key), it.key);
  for (const key of used) assert.ok(Sh.ITEMS.some((it) => it.key === key), key);
});

test('frames share one scale and pack into the box without overlapping', () => {
  Sh.PAGES.forEach((_, page) => {
    const top = Sh.BOX.y0 + Sh.headerHeight(page);
    const inner = { x: Sh.BOX.x0, y: top, w: Sh.BOX.x1 - Sh.BOX.x0, h: Sh.BOX.y1 - top };
    const slots = Sh.place(page);
    slots.forEach((s, i) => {
      const f = s.frame, c = s.cell, it = s.item;
      const want = it.mm || [it.size[0] * Sh.MM_PER_PX, it.size[1] * Sh.MM_PER_PX];
      assert.ok(Math.abs(f.w - want[0]) < 1e-9 && Math.abs(f.h - want[1]) < 1e-9, it.key);
      assert.ok(f.x >= c.x - 1e-9 && f.y >= c.y - 1e-9 && f.x + f.w <= c.x + c.w + 1e-9 && f.y + f.h <= c.y + c.h + 1e-9);
      const label = { x: c.x, y: c.y - 5, w: c.w, h: c.h + 5 }; // with its number above
      assert.ok(label.x >= inner.x && label.y >= inner.y && label.x + label.w <= inner.x + inner.w &&
        label.y + label.h <= inner.y + inner.h, 'page ' + (page + 1) + ' ' + it.key + ' leaves the box');
      for (const o of slots.slice(i + 1)) {
        assert.ok(!overlaps(label, { x: o.cell.x, y: o.cell.y - 5, w: o.cell.w, h: o.cell.h + 5 }), it.key + ' / ' + o.item.key);
      }
    });
  });
  assert.throws(() => { Sh.PAGES.push({ title: 'x', items: ['asteroid_l', 'asteroid_l', 'asteroid_l'] }); try { Sh.place(Sh.PAGES.length - 1); } finally { Sh.PAGES.pop(); } },
    /too full/);
});

test('each page is labeled: a number per frame and a note per item, inside the header', () => {
  Sh.PAGES.forEach(({ items: keys }, page) => {
    const shapes = Sh.layout(Sh.sheetId(page, 0));
    const texts = shapes.filter((s) => s.text).map((s) => s.text);
    keys.forEach((_, i) => assert.ok(texts.includes(String(i + 1)), 'page ' + (page + 1) + ' number ' + (i + 1)));
    const notes = Sh.notes(page);
    const lastNote = shapes.filter((s) => s.text && notes.includes(s.text)).reduce((y, s) => Math.max(y, s.y), 0);
    assert.ok(lastNote < Sh.BOX.y0 + Sh.headerHeight(page), 'page ' + (page + 1) + ' notes overflow the header');
    assert.ok(texts.includes(Sh.PAGES[page].title));
    const all = notes.join(' ');
    for (const key of new Set(keys)) {
      const it = Sh.ITEMS.find((x) => x.key === key);
      assert.ok(all.includes(it.name + ' (' + it.size[0] + ' x ' + it.size[1] + ' px'), key);
    }
  });
  assert.ok(Sh.notes(0)[0].startsWith('1 Player ship'));
  const ship = Sh.place(0)[0].frame;
  assert.equal(ship.w, ship.h); // square, and the whole page wide
  assert.ok(ship.w >= Sh.BOX.x1 - Sh.BOX.x0 - 5);
  assert.ok(Sh.layout(Sh.sheetId(2, 2)).some((s) => s.text && s.text.endsWith('(COPY 3)')));
  assert.deepEqual(Sh.wrap('aa bb cc dd', 5), ['aa bb', 'cc dd']);
});

test('layout keeps marks, box and code apart', () => {
  const half = Sh.MARKER / 2;
  for (const [cx, cy] of Sh.MARKERS) {
    const overlapsBox = cx + half > Sh.BOX.x0 && cx - half < Sh.BOX.x1 && cy + half > Sh.BOX.y0 && cy - half < Sh.BOX.y1;
    assert.ok(!overlapsBox);
    assert.ok(cx - half >= 8 && cy - half >= 8 && cx + half <= Sh.PAGE.w - 8 && cy + half <= Sh.PAGE.h - 8);
  }
  const first = Sh.cellRect(0), last = Sh.cellRect(Sh.CODE_BITS - 1);
  assert.ok(first.y > Sh.BOX.y1);
  assert.ok(first.x > Sh.MARKERS[3][0] + half && last.x + last.w < Sh.MARKERS[2][0] - half);
});

test('makePdf writes one page per sheet with a valid xref', () => {
  const pdf = Sh.makePdf([0, 16, 32]).toString('latin1');
  assert.ok(pdf.startsWith('%PDF-1.4'));
  assert.ok(pdf.trimEnd().endsWith('%%EOF'));
  assert.equal((pdf.match(/\/Type \/Page\b/g) || []).length, 3);
  assert.match(pdf, /\/Count 3/);
  assert.match(pdf, /\(PNK SHOOTER  -  SHEET 0016  -  PAGE 2 OF \d+\)/);
  assert.match(pdf, /\[[\d.]+\] 0 d /); // dashed frame
  const xref = Number(pdf.match(/startxref\n(\d+)/)[1]);
  assert.ok(pdf.startsWith('xref', xref));
  const offsets = pdf.slice(xref).match(/^\d{10} 00000 n $/gm).map((l) => Number(l.slice(0, 10)));
  offsets.forEach((o, i) => assert.ok(pdf.startsWith((i + 1) + ' 0 obj', o)));
  const len = Number(pdf.match(/\/Length (\d+) >>\nstream\n/)[1]);
  const start = pdf.indexOf('stream\n') + 7;
  assert.ok(pdf.startsWith('endstream', start + len));
  assert.throws(() => Sh.makePdf([]), /no sheets/);
});

test('homography maps the four points exactly', () => {
  const src = [[0, 0], [10, 0], [10, 20], [0, 20]], dst = [[5, 7], [40, 2], [44, 61], [3, 50]];
  const H = Sh.homography(src, dst);
  src.forEach((p, i) => {
    const [x, y] = Sh.project(H, p[0], p[1]);
    assert.ok(Math.abs(x - dst[i][0]) < 1e-6 && Math.abs(y - dst[i][1]) < 1e-6);
  });
});

test('resize averages blocks', () => {
  const g = { w: 4, h: 2, data: Uint8Array.from([0, 0, 255, 255, 0, 0, 255, 255]) };
  assert.deepEqual([...Sh.resize(g, 2, 1).data], [0, 255]);
  assert.deepEqual([...Sh.resize(g, 1, 1).data], [128]);
});

test('reads the ship page: drawing cropped and scaled, guides gone', () => {
  const r = Sh.readSheet(render(SHIP_ID, SHIP), 200);
  assert.equal(r.id, SHIP_ID);
  assert.deepEqual(r.drawings.map((d) => d.out), ['ship']);
  assert.deepEqual(r.empty, []);
  const g = r.drawings[0].gray;
  assert.equal(Math.max(g.w, g.h), 200);
  assert.ok(g.h > g.w); // the drawing is taller than wide
  const c = inkCenter(g);
  assert.ok(c.n > 0 && c.y < 0.5); // heavy at the top, so still nose up
  // No light gray guides left: anything not ink is paper, apart from the ink's own soft edge.
  const ink = (x, y) => g.data[y * g.w + x] < 128;
  for (let y = 1; y < g.h - 1; y++) {
    for (let x = 1; x < g.w - 1; x++) {
      if (g.data[y * g.w + x] === 255 || ink(x, y)) continue;
      assert.ok(ink(x - 1, y) || ink(x + 1, y) || ink(x, y - 1) || ink(x, y + 1), 'stray gray at ' + x + ',' + y);
    }
  }
});

test('reads rotated and skewed scans the right way up', () => {
  const upright = inkCenter(Sh.readSheet(render(SHIP_ID + 7, SHIP), 200).drawings[0].gray);
  for (const deg of [90, 180, 270, 3, 184]) {
    const r = Sh.readSheet(rotate(render(SHIP_ID + 7, SHIP), deg), 200);
    assert.equal(r.id, SHIP_ID + 7, deg + ' deg');
    assert.deepEqual(r.drawings.map((d) => d.out), ['ship'], deg + ' deg');
    const c = inkCenter(r.drawings[0].gray);
    assert.ok(Math.abs(c.x - upright.x) < 0.05 && Math.abs(c.y - upright.y) < 0.05, deg + ' deg');
  }
  // A phone photo: the bottom of the page farther away than the top.
  const g = render(SHIP_ID + 9, SHIP);
  const k = 0.15;
  const keystone = warp(g, g.w, g.h, (x, y) => {
    const t = y / g.h, s = 1 + k * t; // rows lower down are shrunk toward the middle
    return [(x - g.w / 2) * s + g.w / 2, y];
  });
  assert.equal(Sh.readSheet(keystone, 200).id, SHIP_ID + 9);
});

test('a black square in the drawing does not fool the corner search', () => {
  const r = Sh.readSheet(render(SHIP_ID + 5, SHIP.concat([[sf.x + sf.w + 2, sf.y, 12, 12]])), 200);
  assert.equal(r.id, SHIP_ID + 5);
});

test('frame items come back as exactly their frames, at OUT_SCALE', () => {
  const page = Sh.PAGES.findIndex((p) => p.items.includes('asteroid_l'));
  const id = Sh.sheetId(page, 1);
  const slots = Sh.place(page);
  const big = slots.find((s) => s.item.key === 'asteroid_l').frame;
  const small = slots.find((s) => s.item.key === 'asteroid_s').frame;
  // Ink in the left of the big asteroid's frame, a dot in the small asteroid, and a scribble between frames
  // (just below the big one's frame) that must be dropped.
  const r = Sh.readSheet(rotate(render(id, [[big.x + 2, big.y + 2, big.w * 0.3, big.h - 4],
    [small.x + small.w / 2 - 3, small.y + small.h / 2 - 3, 6, 6], [big.x + 10, big.y + big.h + 0.8, 30, 2]]), 180));
  assert.equal(r.copy, 1);
  assert.deepEqual(r.drawings.map((d) => d.item.key).sort(), ['asteroid_l', 'asteroid_s']);
  const g = r.drawings.find((d) => d.item.key === 'asteroid_l').gray;
  assert.equal(g.w, 100 * Sh.OUT_SCALE);
  assert.equal(g.h, 100 * Sh.OUT_SCALE);
  const c = inkCenter(g);
  assert.ok(Math.abs(c.x - (2 + big.w * 0.15) / big.w) < 0.03 && Math.abs(c.y - 0.5) < 0.03);
  const a = inkCenter(r.drawings.find((d) => d.item.key === 'asteroid_s').gray);
  assert.ok(Math.abs(a.x - 0.5) < 0.03 && Math.abs(a.y - 0.5) < 0.03);
});

test('reports what is wrong with a bad scan', () => {
  const blank = { w: 840, h: 1188, data: new Uint8Array(840 * 1188).fill(255) };
  assert.throws(() => Sh.readSheet(blank), /corner squares not found/);
  const none = Sh.readSheet(render(3, []));
  assert.deepEqual(none.drawings, []);
  assert.deepEqual(none.empty, [1]);
  const smudged = render(3, SHIP);
  const c = Sh.cellRect(0); // the top id bit of sheet 3 is 0: fill it in
  for (let y = c.y * PX; y < (c.y + c.h) * PX; y++) for (let x = c.x * PX; x < (c.x + c.w) * PX; x++) smudged.data[y * smudged.w + x] = 0;
  assert.throws(() => Sh.readSheet(smudged), /sheet code unreadable/);
  const unknown = Sh.PAGES.length * Sh.COPIES;
  const g = render(3, SHIP); // repaint the code cells as a sheet number no page has
  Sh.codeBits(unknown).forEach((b, i) => {
    const r = Sh.cellRect(i);
    for (let y = r.y * PX; y < (r.y + r.h) * PX; y++) for (let x = r.x * PX; x < (r.x + r.w) * PX; x++) g.data[y * g.w + x] = b ? 0 : 255;
  });
  assert.throws(() => Sh.readSheet(g), /not a page/);
});
