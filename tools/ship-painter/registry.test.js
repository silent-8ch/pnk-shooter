// Run: node --test tools/ship-painter/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const R = require('./registry.js');

const PAINTED = '<svg data-slots="2" data-slot-names="Hull,A&amp;B"><path data-slot="1" fill="#ff0000"/></svg>';
const WHITE = '<svg><path fill="#ffffff" stroke="#EEE"/><path style="fill:#d0d0d0"/></svg>';
const COLORED = '<svg><path fill="#8075ff" stroke="#ffffff"/></svg>';
const DARK = '<svg><g fill="#000000"><path d="M0 0"/></g></svg>';

test('classify: painted → palette, white/light gray → tint, anything else → unassigned', () => {
  assert.equal(R.classify(PAINTED), 'palette');
  assert.equal(R.classify(WHITE), 'tint');
  assert.equal(R.classify(COLORED), 'unassigned');
  assert.equal(R.classify(DARK), 'unassigned', 'black art cannot be tinted');
  assert.equal(R.classify('<svg><path/></svg>'), 'unassigned', 'no colors at all');
});

test('colors: reads attributes and style properties, expands #rgb, dedupes', () => {
  assert.deepEqual(R.colors(WHITE), ['#ffffff', '#eeeeee', '#d0d0d0']);
  assert.deepEqual(R.colors('<svg><stop stop-color="#abc"/><path fill="#AABBCC"/></svg>'), ['#aabbcc']);
});

test('slotNames: unescapes and splits data-slot-names', () => {
  assert.deepEqual(R.slotNames(PAINTED), ['Hull', 'A&B']);
  assert.deepEqual(R.slotNames(WHITE), []);
});

test('statusOf: every status', () => {
  assert.equal(R.statusOf({ strategy: 'palette' }, null), 'missing-file');
  assert.equal(R.statusOf(null, COLORED), 'needs-strategy');
  assert.equal(R.statusOf({ strategy: 'unassigned' }, COLORED), 'needs-strategy');
  assert.equal(R.statusOf({ strategy: 'palette' }, COLORED), 'needs-paint');
  assert.equal(R.statusOf({ strategy: 'palette' }, PAINTED), 'ok');
  assert.equal(R.statusOf({ strategy: 'tint' }, COLORED), 'needs-tint-art');
  assert.equal(R.statusOf({ strategy: 'tint' }, WHITE), 'ok');
  assert.equal(R.statusOf({ strategy: 'fixed' }, COLORED), 'ok');
});

test('seed: classifies new files, guesses roles, never overwrites existing entries', () => {
  const db = R.empty();
  db.assets['assets/ship01.svg'] = { strategy: 'fixed', role: 'mine', notes: 'keep' };
  const added = R.seed(db, {
    'assets/ship01.svg': PAINTED,
    'assets/ship02.svg': PAINTED,
    'assets/filler/fx/spark.svg': WHITE,
    'assets/filler/pickup_health.svg': COLORED,
    'assets/filler/scout.svg': COLORED,
  });
  assert.deepEqual(added, ['assets/filler/fx/spark.svg', 'assets/filler/pickup_health.svg', 'assets/filler/scout.svg', 'assets/ship02.svg']);
  assert.deepEqual(db.assets['assets/ship01.svg'], { strategy: 'fixed', role: 'mine', notes: 'keep' });
  assert.deepEqual(db.assets['assets/ship02.svg'], { strategy: 'palette', role: 'ship', notes: '', slots: ['Hull', 'A&B'] });
  assert.equal(db.assets['assets/filler/fx/spark.svg'].strategy, 'tint');
  assert.equal(db.assets['assets/filler/fx/spark.svg'].role, 'fx');
  assert.equal(db.assets['assets/filler/pickup_health.svg'].role, 'pickup');
  assert.equal(db.assets['assets/filler/scout.svg'].strategy, 'unassigned');
});

test('list: merges disk and registry, flags missing files and unregistered ones', () => {
  const db = R.empty();
  R.setEntry(db, 'assets/a.svg', { strategy: 'palette' }, PAINTED);
  R.setEntry(db, 'assets/gone.svg', { strategy: 'tint' }, null);
  const rows = R.list(db, { 'assets/a.svg': PAINTED, 'assets/new.svg': COLORED });
  assert.deepEqual(rows.map((r) => [r.path, r.status, r.registered]), [
    ['assets/a.svg', 'ok', true],
    ['assets/gone.svg', 'missing-file', true],
    ['assets/new.svg', 'needs-strategy', false],
  ]);
  assert.equal(rows[2].suggested, 'unassigned');
  assert.equal(rows[1].suggested, null);
  assert.ok(!R.needsAttention(rows[0]));
  assert.ok(R.needsAttention(rows[1]));
});

test('setEntry: slot names only for palette assets', () => {
  const db = R.empty();
  assert.deepEqual(R.setEntry(db, 'assets/a.svg', { strategy: 'palette' }, PAINTED).slots, ['Hull', 'A&B']);
  assert.equal(R.setEntry(db, 'assets/a.svg', { strategy: 'fixed', slots: ['x'] }, PAINTED).slots, undefined);
});

test('serialize: sorted, stable, omits empty fields, round-trips through parse', () => {
  const db = R.empty();
  R.setEntry(db, 'assets/z.svg', { strategy: 'tint', role: 'fx' }, WHITE);
  R.setEntry(db, 'assets/a.svg', { strategy: 'palette', notes: 'n' }, PAINTED);
  const text = R.serialize(db);
  assert.ok(text.endsWith('}\n'));
  assert.ok(text.indexOf('assets/a.svg') < text.indexOf('assets/z.svg'));
  assert.deepEqual(JSON.parse(text).assets['assets/z.svg'], { strategy: 'tint', role: 'fx' });
  assert.equal(R.serialize(R.parse(text)), text);
});

test('parse: missing file is an empty registry; malformed JSON or shape throws; junk fields are cleaned', () => {
  assert.deepEqual(R.parse(null), R.empty());
  assert.deepEqual(R.parse(''), R.empty());
  assert.throws(() => R.parse('{'));
  assert.throws(() => R.parse('{"assets": []}'), /expected/);
  const db = R.parse('{"version":1,"assets":{"assets/a.svg":{"strategy":"bogus","role":5,"extra":1}}}');
  assert.deepEqual(db.assets['assets/a.svg'], { strategy: 'unassigned', role: '', notes: '' });
});

test('validateEntry: rejects bad input from clients', () => {
  assert.throws(() => R.validateEntry(null), /object/);
  assert.throws(() => R.validateEntry([]), /object/);
  assert.throws(() => R.validateEntry({ strategy: 'nope' }), /strategy/);
  assert.throws(() => R.validateEntry({ strategy: 'tint', role: 3 }), /role/);
  assert.throws(() => R.validateEntry({ strategy: 'tint', role: 'x'.repeat(41) }), /role/);
  assert.throws(() => R.validateEntry({ strategy: 'tint', notes: 'x'.repeat(2001) }), /notes/);
  assert.deepEqual(R.validateEntry({ strategy: 'fixed', role: ' prop ', notes: 'n' }), { strategy: 'fixed', role: 'prop', notes: 'n' });
});

test('thrusters: round-trip through serialize and parse, key order, after slots and before notes', () => {
  const db = R.empty();
  R.setEntry(db, 'assets/ship01.svg', { strategy: 'palette', role: 'ship', notes: 'n', thrusters: [
    { main: true, size: 1.6, angle: 90, y: 560.04, x: 434.46 },
    { x: 300, y: 100, angle: 270, size: 0.5 },
  ] }, PAINTED);
  const text = R.serialize(db);
  const entry = JSON.parse(text).assets['assets/ship01.svg'];
  assert.deepEqual(Object.keys(entry), ['strategy', 'role', 'slots', 'thrusters', 'notes']);
  assert.deepEqual(entry.thrusters, [
    { x: 434.5, y: 560, angle: 90, size: 1.6, main: true },
    { x: 300, y: 100, angle: 270, size: 0.5, main: false },
  ]);
  assert.deepEqual(Object.keys(entry.thrusters[0]), ['x', 'y', 'angle', 'size', 'main']);
  assert.equal(R.serialize(R.parse(text)), text);
});

test('thrusters: rounding, clamping, angle normalization and defaults', () => {
  const t = R.cleanThrusters([
    { x: 1.26, y: -2.04, angle: -90, size: 9 },
    { x: 0, y: 0, angle: 359.6, size: 0.01 },
    { x: 0, y: 0, angle: 725, size: 1.13 },
    { x: 5, y: 5 },
    { x: 5, y: 5, main: true },
    { x: -0.01, y: 0, angle: -0.2 },
  ]);
  assert.deepEqual(t, [
    { x: 1.3, y: -2, angle: 270, size: 3, main: false },
    { x: 0, y: 0, angle: 0, size: 0.25, main: false },
    { x: 0, y: 0, angle: 5, size: 1.15, main: false },
    { x: 5, y: 5, angle: 90, size: 1, main: false },
    { x: 5, y: 5, angle: 90, size: 1.6, main: true },
    { x: 0, y: 0, angle: 0, size: 1, main: false },
  ]);
  assert.ok(t.every((x) => !Object.is(x.x, -0) && !Object.is(x.angle, -0)), 'no negative zeros');
});

test('thrusters: malformed items and unknown keys are dropped; at most 12 and one main', () => {
  const t = R.cleanThrusters([null, 5, [], { x: '1', y: 2 }, { x: 1 }, { x: 1, y: 2, angle: 'up' }, { x: NaN, y: 1 },
    { x: 1, y: 2, size: null }, { x: 1, y: 2, main: true, color: 'red' }, { x: 3, y: 4, main: true }]);
  assert.deepEqual(t, [
    { x: 1, y: 2, angle: 90, size: 1.6, main: true },
    { x: 3, y: 4, angle: 90, size: 1, main: false },
  ]);
  assert.equal(R.cleanThrusters(Array.from({ length: 20 }, (_, i) => ({ x: i, y: 0 }))).length, 12);
  assert.deepEqual(R.cleanThrusters('nope'), []);
  const db = R.parse('{"version":1,"assets":{"assets/ship01.svg":{"strategy":"fixed","thrusters":[{"x":1,"y":2,"angle":90,"size":1,"main":false,"extra":1}],"junk":1}}}');
  assert.deepEqual(db.assets['assets/ship01.svg'], { strategy: 'fixed', role: '', notes: '', thrusters: [{ x: 1, y: 2, angle: 90, size: 1, main: false }] });
});

test('thrusters: key omitted when the list is empty or all junk', () => {
  const db = R.empty();
  R.setEntry(db, 'assets/a.svg', { strategy: 'fixed', thrusters: [] }, COLORED);
  R.setEntry(db, 'assets/b.svg', { strategy: 'fixed', thrusters: [{ x: 'a' }] }, COLORED);
  const assets = JSON.parse(R.serialize(db)).assets;
  assert.deepEqual(assets['assets/a.svg'], { strategy: 'fixed' });
  assert.deepEqual(assets['assets/b.svg'], { strategy: 'fixed' });
  assert.equal(db.assets['assets/a.svg'].thrusters, undefined);
});

test('thrusters: list rows carry them', () => {
  const db = R.empty();
  R.setEntry(db, 'assets/ship01.svg', { strategy: 'palette', thrusters: [{ x: 1, y: 2, angle: 90 }] }, PAINTED);
  const rows = R.list(db, { 'assets/ship01.svg': PAINTED, 'assets/new.svg': COLORED });
  assert.equal(rows[0].thrusters.length, 0);
  assert.deepEqual(rows[1].thrusters, [{ x: 1, y: 2, angle: 90, size: 1, main: false }]);
});

test('validateEntry: rejects bad thrusters', () => {
  const v = (thrusters) => R.validateEntry({ strategy: 'palette', role: 'ship', thrusters });
  const ok = { x: 1, y: 2, angle: 90, size: 1, main: false };
  assert.throws(() => v({}), /array/);
  assert.throws(() => v('x'), /array/);
  assert.throws(() => v(Array.from({ length: 13 }, () => ok)), /at most 12/);
  assert.throws(() => v([null]), /object/);
  assert.throws(() => v([{ ...ok, x: '1' }]), /x must be a number/);
  assert.throws(() => v([{ ...ok, angle: undefined }]), /angle must be a number/);
  assert.throws(() => v([{ ...ok, y: Infinity }]), /y must be a number/);
  assert.throws(() => v([{ ...ok, size: 'big' }]), /size/);
  assert.throws(() => v([{ ...ok, main: 1 }]), /main/);
  assert.throws(() => v([{ ...ok, main: true }, { ...ok, main: true }]), /one main/);
  assert.deepEqual(v([{ ...ok, main: true, size: 7 }]).thrusters, [{ ...ok, main: true, size: 3 }], 'out-of-range size is clamped, not rejected');
  assert.equal(v([]).thrusters, undefined);
});

test('classify: the real repo assets', () => {
  const read = (p) => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8');
  assert.equal(R.classify(read('assets/ship01.svg')), 'palette');
  assert.equal(R.classify(read('assets/ship02.svg')), 'palette');
  assert.equal(R.classify(read('assets/effects/bullet_00.svg')), 'palette');
  assert.equal(R.classify(read('assets/effects/explosion_00.svg')), 'palette');
});
