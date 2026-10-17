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

test('classify: the real repo assets', () => {
  const read = (p) => fs.readFileSync(path.join(__dirname, '../..', p), 'utf8');
  assert.equal(R.classify(read('assets/ship01.svg')), 'palette');
  assert.equal(R.classify(read('assets/ship02.svg')), 'palette');
  assert.equal(R.classify(read('assets/effects/bullet_00.svg')), 'palette');
  assert.equal(R.classify(read('assets/effects/explosion_00.svg')), 'palette');
});
