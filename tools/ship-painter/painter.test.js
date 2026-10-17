// Run: node --test tools/ship-painter/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const P = require('./painter.js');

const SAMPLE = `<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 20010904//EN"
 "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">
<svg version="1.0" xmlns="http://www.w3.org/2000/svg"
 width="20" height="10" viewBox="0 0 20 10"
 preserveAspectRatio="xMidYMid meet">
<g transform="translate(0.000000,10.000000) scale(0.100000,-0.100000)"
fill="#ffffff" stroke="none">
<path d="M0 0 l100 0 l0 100
l-100 0 z"/>
<path d="M100 0 l100 0 l0 100 l-100 0 z"/>
<rect x="5" y="5" width="2" height="2"/>
</g>
</svg>
`;

function painted() {
  const s = P.parseShip(SAMPLE, 'sample.svg');
  P.addSlot(s, 'Trim', '#ff0000');
  P.setSlot(s, 1, 2);
  return s;
}

test('parseShip: raw potrace output gets one white slot and every shape in it', () => {
  const s = P.parseShip(SAMPLE, 'sample.svg');
  assert.equal(s.name, 'sample');
  assert.equal(s.shapes.length, 3);
  assert.deepEqual(s.slots, [{ name: 'Slot 1', color: '#ffffff' }]);
  assert.deepEqual(s.shapes.map((x) => x.slot), [1, 1, 1]);
});

test('parseShip: rejects non-SVG and shape-less input', () => {
  assert.throws(() => P.parseShip('hello', 'x'), /Not an SVG/);
  assert.throws(() => P.parseShip('<svg></svg>', 'x'), /no shapes/);
});

test('parseShip: handles the real ship assets', () => {
  for (const [file, n] of [['ship01.svg', 9], ['ship02.svg', 6]]) {
    const svg = fs.readFileSync(path.join(__dirname, '../../assets', file), 'utf8');
    const s = P.parseShip(svg, file);
    assert.equal(s.shapes.length, n, file);
    assert.equal(s.name, file.replace('.svg', ''));
  }
});

test('exportSvg: adds only slot attributes, preserves everything else byte-for-byte', () => {
  const s = P.parseShip(SAMPLE, 'sample.svg');
  const out = P.exportSvg(s);
  const stripped = out
    .replace(/ data-slots="1" data-slot-names="Slot 1"/, '')
    .replace(/ data-slot="1" fill="#ffffff"/g, '');
  assert.equal(stripped, SAMPLE);
  assert.ok(!out.includes('data-idx'));
});

test('exportSvg: writes slot index and slot color onto each shape', () => {
  const out = P.exportSvg(painted());
  assert.match(out, /<svg[^>]* data-slots="2" data-slot-names="Slot 1,Trim"/);
  const shapes = out.match(/<(path|rect)\b[^>]*>/g);
  assert.equal(shapes.length, 3);
  assert.match(shapes[0], /data-slot="1" fill="#ffffff"/);
  assert.match(shapes[1], /data-slot="2" fill="#ff0000"/);
  assert.match(shapes[2], /data-slot="1" fill="#ffffff"/);
  assert.match(shapes[1], /\/>$/, 'self-closing tag kept');
});

test('exportSvg: indexAttr adds data-idx and a later export without it removes it', () => {
  const s = painted();
  const withIdx = P.exportSvg(s, { indexAttr: true });
  assert.equal((withIdx.match(/data-idx="\d+"/g) || []).length, 3);
  assert.match(withIdx, /data-idx="2"/);
  const re = P.parseShip(withIdx, 'sample.svg');
  assert.ok(!P.exportSvg(re).includes('data-idx'));
});

test('round trip: parsing an export restores slots, names, colors and assignments', () => {
  const s = painted();
  P.renameSlot(s, 1, 'Hull');
  const re = P.parseShip(P.exportSvg(s), 'sample.svg');
  assert.deepEqual(re.slots, s.slots);
  assert.deepEqual(re.shapes, s.shapes);
  assert.equal(P.exportSvg(re), P.exportSvg(s));
});

test('round trip: slot names with special characters survive', () => {
  const s = painted();
  P.renameSlot(s, 2, 'A&B <"x">, y');
  assert.equal(s.slots[1].name, 'A&B <"x"> y'); // commas are stripped
  const re = P.parseShip(P.exportSvg(s), 'sample.svg');
  assert.equal(re.slots[1].name, 'A&B <"x"> y');
});

test('exportSvg: replaces an existing fill rather than duplicating it', () => {
  const svg = '<svg><path fill="#123456" d="M0 0"/><circle fill-rule="evenodd" r="1"/></svg>';
  const s = P.parseShip(svg, 'x');
  const out = P.exportSvg(s);
  assert.equal((out.match(/ fill="/g) || []).length, 2);
  assert.equal(s.slots[0].color, '#123456', 'slot color adopted from first existing fill');
  P.setSlotColor(s, 1, '#00ff00');
  const out2 = P.exportSvg(s);
  assert.match(out2, /<path fill="#00ff00" d="M0 0" data-slot="1"\/>/);
  assert.match(out2, /<circle fill-rule="evenodd" r="1" data-slot="1" fill="#00ff00"\/>/);
});

test('parseShip: slot color comes from the first shape in that slot, else a default', () => {
  const svg = '<svg data-slots="3"><path data-slot="2" fill="#abcdef"/><path data-slot="2" fill="#000000"/></svg>';
  const s = P.parseShip(svg, 'x');
  assert.equal(s.slots.length, 3);
  assert.equal(s.slots[1].color, '#abcdef');
  assert.equal(s.slots[0].color, P.DEFAULT_COLORS[0]);
  assert.equal(s.slots[2].color, P.DEFAULT_COLORS[2]);
});

test('parseShip: data-slot beyond data-slots grows the slot list; junk values fall back to 1', () => {
  const svg = '<svg data-slots="1"><path data-slot="3"/><path data-slot="abc"/><path data-slot="0"/></svg>';
  const s = P.parseShip(svg, 'x');
  assert.equal(s.slots.length, 3);
  assert.deepEqual(s.shapes.map((x) => x.slot), [3, 1, 1]);
});

test('addSlot / removeSlot renumber and reassign shapes', () => {
  const s = P.parseShip(SAMPLE, 'x');
  assert.equal(P.addSlot(s), 2);
  assert.equal(P.addSlot(s, 'Glass'), 3);
  assert.equal(s.slots[2].name, 'Glass');
  assert.equal(s.slots[1].color, P.DEFAULT_COLORS[1]);
  P.setSlot(s, 0, 2);
  P.setSlot(s, 1, 3);
  P.removeSlot(s, 2);
  assert.equal(s.slots.length, 2);
  assert.equal(s.slots[1].name, 'Glass');
  assert.deepEqual(s.shapes.map((x) => x.slot), [1, 2, 1]);
  P.removeSlot(s, 1);
  assert.deepEqual(s.shapes.map((x) => x.slot), [1, 1, 1]);
  assert.throws(() => P.removeSlot(s, 1), /last slot/);
});

test('addSlot caps at MAX_SLOTS', () => {
  const s = P.parseShip(SAMPLE, 'x');
  while (s.slots.length < P.MAX_SLOTS) P.addSlot(s);
  assert.throws(() => P.addSlot(s), /at most/);
});

test('setSlot / assignAll / setSlotColor validate their arguments', () => {
  const s = painted();
  assert.throws(() => P.setSlot(s, 5, 1), RangeError);
  assert.throws(() => P.setSlot(s, 0, 3), RangeError);
  assert.throws(() => P.assignAll(s, 0), RangeError);
  assert.throws(() => P.setSlotColor(s, 1, 'red'), /rrggbb/);
  P.setSlotColor(s, 1, '#ABCDEF');
  assert.equal(s.slots[0].color, '#abcdef');
  P.assignAll(s, 2);
  assert.deepEqual(P.countBySlot(s), [0, 3]);
});

test('exportManifest summarizes slots and per-shape assignment', () => {
  const m = P.exportManifest(painted());
  assert.deepEqual(m, {
    ship: 'sample',
    file: 'sample.svg',
    slots: [
      { index: 1, name: 'Slot 1', color: '#ffffff', shapes: 2, fills: 0 },
      { index: 2, name: 'Trim', color: '#ff0000', shapes: 1, fills: 0 },
    ],
    shapes: [1, 2, 1],
    fills: [],
  });
});

test('clone is a deep copy', () => {
  const s = painted();
  const c = P.clone(s);
  P.setSlot(c, 0, 2);
  assert.equal(s.shapes[0].slot, 1);
});

test('suggestName strips directories and extensions', () => {
  assert.equal(P.suggestName('/a/b/ship01.svg'), 'ship01');
  assert.equal(P.suggestName('ship01.skin.svg'), 'ship01');
  assert.equal(P.suggestName(''), 'ship');
});

// --- fill layer -----------------------------------------------------------------

const SQ = 'M2 2L8 2L8 8L2 8Z';

test('exportSvg: fills go in a group right after <svg>, beneath the outlines', () => {
  const s = painted();
  assert.equal(P.addFill(s, 2, SQ), 0);
  P.addFill(s, 1, 'M10 2L12 2L12 4Z');
  const out = P.exportSvg(s);
  const svgOpen = out.indexOf('<svg');
  const group = out.indexOf('<g data-layer="fills"');
  const firstOutline = out.search(/<g transform/);
  assert.ok(svgOpen < group && group < firstOutline, 'fill group sits before outline groups');
  assert.match(out, /<path data-slot="2" fill="#ff0000" d="M2 2L8 2L8 8L2 8Z"\/>/);
  assert.match(out, /<path data-slot="1" fill="#ffffff" d="M10 2L12 2L12 4Z"\/>/);
  assert.ok(!out.includes('data-fidx'));
  assert.match(P.exportSvg(s, { indexAttr: true }), /data-fidx="1"/);
  assert.ok(!P.exportSvg(s, { outlinesOnly: true }).includes('data-layer'));
});

test('round trip: fills survive parse/export and are not treated as outline shapes', () => {
  const s = painted();
  P.addFill(s, 2, SQ);
  const text = P.exportSvg(s);
  const re = P.parseShip(text, 'sample.svg');
  assert.equal(re.shapes.length, 3);
  assert.deepEqual(re.fills, [{ slot: 2, d: SQ }]);
  assert.equal(P.exportSvg(re), text);
});

test('parseShip: a fill-only slot takes its color from the fill', () => {
  const s = P.parseShip(SAMPLE, 'x');
  P.addSlot(s, 'Glass', '#00ffcc');
  P.addFill(s, 2, SQ);
  const re = P.parseShip(P.exportSvg(s), 'x');
  assert.equal(re.slots[1].color, '#00ffcc');
});

test('addFill dedupes identical paths; setFillSlot / removeFill validate', () => {
  const s = painted();
  P.addFill(s, 1, SQ);
  assert.equal(P.addFill(s, 2, SQ), 0);
  assert.equal(s.fills.length, 1);
  assert.equal(s.fills[0].slot, 2);
  assert.throws(() => P.addFill(s, 1, ''), /path data/);
  assert.throws(() => P.addFill(s, 9, SQ), RangeError);
  P.setFillSlot(s, 0, 1);
  assert.equal(s.fills[0].slot, 1);
  assert.throws(() => P.setFillSlot(s, 3, 1), RangeError);
  P.removeFill(s, 0);
  assert.equal(s.fills.length, 0);
  assert.throws(() => P.removeFill(s, 0), RangeError);
});

test('removeSlot renumbers fills; assignAll leaves fills alone', () => {
  const s = painted();
  P.addSlot(s);
  P.addFill(s, 2, SQ);
  P.addFill(s, 3, 'M0 0L1 0L1 1Z');
  P.assignAll(s, 1);
  assert.deepEqual(s.fills.map((f) => f.slot), [2, 3]);
  P.removeSlot(s, 2);
  assert.deepEqual(s.fills.map((f) => f.slot), [1, 2]);
  assert.deepEqual(P.countFillsBySlot(s), [1, 1]);
});

test('getViewBox reads viewBox, falls back to width/height', () => {
  assert.deepEqual(P.getViewBox(SAMPLE), { x: 0, y: 0, w: 20, h: 10 });
  assert.deepEqual(P.getViewBox('<svg width="30px" height="12"><path/></svg>'), { x: 0, y: 0, w: 30, h: 12 });
  assert.throws(() => P.getViewBox('<svg><path/></svg>'), /viewBox/);
});

test('parseShip: fill="none" shapes are locked and exported untouched', () => {
  const svg = '<svg><path fill="none" stroke="#fff" d="M0 0"/><path fill="#ff0000" d="M1 1"/></svg>';
  const s = P.parseShip(svg, 'x');
  assert.deepEqual(s.shapes, [{ slot: 1, locked: true }, { slot: 1 }]);
  assert.throws(() => P.setSlot(s, 0, 1), /cannot be slotted/);
  P.addSlot(s, 'B', '#00ff00');
  P.assignAll(s, 2);
  assert.deepEqual(s.shapes.map((x) => x.slot), [1, 2]);
  assert.deepEqual(P.countBySlot(s), [0, 1]);
  const out = P.exportSvg(s);
  assert.match(out, /<path fill="none" stroke="#fff" d="M0 0"\/>/);
  assert.match(out, /<path fill="#00ff00" d="M1 1" data-slot="2"\/>/);
  assert.deepEqual(P.exportManifest(s).shapes, [0, 2]);
  const re = P.parseShip(out, 'x');
  assert.ok(re.shapes[0].locked);
});

test('parseShip: slotByColor gives an unpainted SVG one slot per distinct fill', () => {
  const svg = '<svg><path fill="#FF0000"/><path fill="#00ff00"/><path fill="#ff0000"/><path fill="none"/><path/></svg>';
  const s = P.parseShip(svg, 'x', { slotByColor: true });
  assert.deepEqual(s.slots.map((x) => x.color), ['#ff0000', '#00ff00']);
  assert.deepEqual(s.shapes.map((x) => x.slot), [1, 2, 1, 1, 1]);
  assert.ok(s.shapes[3].locked);
  const out = P.exportSvg(s);
  assert.equal(P.exportSvg(P.parseShip(out, 'x', { slotByColor: true })), out, 'painted SVGs keep their slots');
});

test('parseShip: slotByColor caps at MAX_SLOTS and ignores painted SVGs', () => {
  const many = '<svg>' + Array.from({ length: 11 }, (_, i) => '<path fill="#0000' + (10 + i) + '"/>').join('') + '</svg>';
  const s = P.parseShip(many, 'x', { slotByColor: true });
  assert.equal(s.slots.length, P.MAX_SLOTS);
  assert.deepEqual(s.shapes.slice(9).map((x) => x.slot), [1, 1]);
  const painted = '<svg><path data-slot="1" fill="#ff0000"/><path fill="#00ff00"/></svg>';
  assert.equal(P.parseShip(painted, 'x', { slotByColor: true }).slots.length, 1);
});

test('parseShip: slotByColor on outlined multi-color art keeps its colors', () => {
  const stroke = ' stroke="#ffffff" stroke-width="5"';
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n' +
    ['#8075ff', '#a5ff7a', '#ff7ad9', '#7ad9f5', '#ff9d7a', '#ff9d7a', '#ffdc7a']
      .map((c, i) => '<path d="M' + i + ' 0 L9 9Z" fill="' + c + '"' + stroke + '/>').join('\n') + '\n</svg>\n';
  const s = P.parseShip(svg, 'scout.svg', { slotByColor: true });
  assert.equal(s.slots.length, 6);
  const out = P.exportSvg(s);
  const before = svg.match(/fill="#[0-9a-f]{6}"/g);
  const after = out.match(/fill="#[0-9a-f]{6}"/g);
  assert.deepEqual(after, before);
});
