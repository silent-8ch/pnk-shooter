// Run: node --test tools/level-designer/
const test = require('node:test');
const assert = require('node:assert/strict');
const L = require('./level.js');

function level(over) {
  return Object.assign({
    name: 'Level 1', length: 32, repeat: true,
    events: [{ time: 0, type: 'weaver', lane: 4, count: 3, dir: 1 }],
  }, over);
}
const ev = (over) => Object.assign({ time: 0, type: 'weaver', lane: 4, count: 3, dir: 1 }, over);

test('validate accepts a good level and returns a normalised copy', () => {
  const src = level();
  const v = L.validate(src);
  assert.deepEqual(v, src);
  assert.notEqual(v, src);
  assert.notEqual(v.events[0], src.events[0]);
});

test('validate accepts boundary values', () => {
  L.validate(level({ name: 'x'.repeat(60), length: 1, repeat: false, events: [] }));
  L.validate(level({ length: 1800 }));
  L.validate(level({ length: 12.5 }));
  L.validate(level({ length: 4, events: [ev({ time: 3.99, lane: 0, count: 1, dir: -1 }), ev({ lane: 8, count: 7, type: 'diver' })] }));
  L.validate(level({ events: Array.from({ length: 2000 }, (_, i) => ev({ time: (i % 320) * 0.1 })) }));
});

test('validate sorts events by time then lane', () => {
  const v = L.validate(level({ events: [ev({ time: 2, lane: 1 }), ev({ time: 0.5, lane: 7 }), ev({ time: 0.5, lane: 2 }), ev({ time: 0, lane: 8 })] }));
  assert.deepEqual(v.events.map((e) => [e.time, e.lane]), [[0, 8], [0.5, 2], [0.5, 7], [2, 1]]);
});

test('validate rejects bad top-level fields with clear messages', () => {
  const cases = [
    [null, /object/], [[], /object/], ['x', /object/],
    [level({ name: '' }), /name/], [level({ name: '   ' }), /name/], [level({ name: 'x'.repeat(61) }), /60/], [level({ name: 5 }), /name/],
    [level({ length: 0.99 }), /length/], [level({ length: 1800.01 }), /length/], [level({ length: '32' }), /length/],
    [level({ length: NaN }), /length/], [level({ length: Infinity }), /length/], [level({ length: null }), /length/],
    [level({ repeat: 1 }), /repeat/], [level({ repeat: 'true' }), /repeat/],
    [level({ events: {} }), /events/], [level({ events: Array.from({ length: 2001 }, () => ev()) }), /2000/],
    [level({ extra: 1 }), /unknown field "extra"/],
  ];
  for (const [obj, re] of cases) assert.throws(() => L.validate(obj), re, JSON.stringify(obj && obj.name !== undefined ? Object.keys(obj) : obj));
  const missing = level(); delete missing.repeat;
  assert.throws(() => L.validate(missing), /missing field "repeat"/);
  const noLen = level(); delete noLen.length;
  assert.throws(() => L.validate(noLen), /missing field "length"/);
});

test('validate rejects the old score format with a clear message', () => {
  const old = {
    name: 'Level 1', bpm: 120, beats_per_bar: 4, bars: 16, repeat: true,
    events: [{ beat: 0, type: 'weaver', lane: 4, count: 3, dir: 1 }],
  };
  assert.throws(() => L.validate(old), /old score format/);
  assert.throws(() => L.validate(level({ bpm: 120 })), /old score format/);
  assert.throws(() => L.validate(level({ events: [{ beat: 0, type: 'weaver', lane: 4, count: 3, dir: 1 }] })), /events\[0\]: old score format/);
});

test('validate rejects bad events with their index', () => {
  const cases = [
    [ev({ time: -0.01 }), /events\[0\]\.time/], [ev({ time: '1' }), /time/], [ev({ time: NaN }), /time/],
    [ev({ time: 32 }), /past the end/], [ev({ time: 31.999 }), /past the end/], [ev({ time: 31.99 }), null], [ev({ time: 0.123 }), null],
    [ev({ type: 'boss' }), /type/], [ev({ type: undefined }), /type/],
    [ev({ lane: -1 }), /lane/], [ev({ lane: 9 }), /lane/], [ev({ lane: 1.5 }), /lane/],
    [ev({ count: 0 }), /count/], [ev({ count: 8 }), /count/], [ev({ count: 2.5 }), /count/],
    [ev({ dir: 0 }), /dir/], [ev({ dir: 2 }), /dir/], [ev({ dir: '1' }), /dir/],
    [ev({ speed: 3 }), /unknown field "speed"/], [null, /events\[0\] must be an object/], [[1], /object/],
  ];
  for (const [e, re] of cases) {
    const obj = level({ events: [e] });
    if (re) assert.throws(() => L.validate(obj), re, JSON.stringify(e));
    else L.validate(obj);
  }
  const noDir = ev(); delete noDir.dir;
  assert.throws(() => L.validate(level({ events: [noDir] })), /missing field "dir"/);
  assert.throws(() => L.validate(level({ events: [ev(), ev({ lane: 12 })] })), /events\[1\]\.lane/);
});

test('validate rounds times to 2 decimals', () => {
  const v = L.validate(level({ events: [ev({ time: 1.1 - 0.35 }), ev({ time: 2.3456, lane: 1 }), ev({ time: 2.344, lane: 2 })] }));
  assert.deepEqual(v.events.map((e) => e.time), [0.75, 2.34, 2.35]);
  assert.equal(L.round2(1.005 + 1e-9), 1.01);
});

test('serialize writes sorted, 2-space pretty JSON with a trailing newline', () => {
  const text = L.serialize(level({ events: [ev({ time: 1, lane: 2 }), ev({ time: 0, lane: 5, type: 'diver', dir: -1 })] }));
  assert.ok(text.endsWith('}\n'));
  assert.ok(!text.endsWith('\n\n'));
  const parsed = JSON.parse(text);
  assert.equal(text, JSON.stringify(parsed, null, 2) + '\n');
  assert.deepEqual(Object.keys(parsed), ['name', 'length', 'repeat', 'events']);
  assert.deepEqual(Object.keys(parsed.events[0]), ['time', 'type', 'lane', 'count', 'dir']);
  assert.deepEqual(parsed.events.map((e) => e.time), [0, 1]);
  assert.match(text, /^\{\n {2}"name": "Level 1",\n {2}"length": 32,\n/);
  assert.throws(() => L.serialize(level({ length: 0 })), /length/);
});

test('parse round-trips and rejects non-JSON', () => {
  const src = level();
  assert.deepEqual(L.parse(L.serialize(src)), src);
  assert.throws(() => L.parse('{nope'), /not valid JSON/);
});

test('slugs: isSlug, slugify, empty', () => {
  for (const s of ['a', 'level_01', '0-x', 'a'.repeat(40)]) assert.ok(L.isSlug(s), s);
  for (const s of ['', '_a', '-a', 'A', 'a.b', '../x', 'a/b', 'a'.repeat(41), 'é', null, 5]) assert.ok(!L.isSlug(s), String(s));
  assert.equal(L.slugify('Level 1: The Start!'), 'level_1_the_start');
  assert.equal(L.slugify('!!!'), 'level');
  assert.ok(L.isSlug(L.slugify('x'.repeat(100))));
  L.validate(L.empty());
  assert.equal(L.empty('Boss').name, 'Boss');
});

test('group layout matches the game', () => {
  assert.equal(L.groupHalfWidth('weaver', 1), 60);
  assert.equal(L.groupHalfWidth('weaver', 3), 130);
  assert.equal(L.groupHalfWidth('diver', 1), 0);
  assert.equal(L.groupHalfWidth('diver', 3), 50);
  assert.equal(L.groupHalfWidth('diver', 4), 100);
  // lane 0 = left edge, lane 8 = right edge, lane 4 = center
  assert.equal(L.groupCenterX('weaver', 3, 0), 150);
  assert.equal(L.groupCenterX('weaver', 3, 8), 390);
  assert.equal(L.groupCenterX('weaver', 3, 4), 270);
  assert.equal(L.groupCenterX('diver', 3, 0), 70);
  assert.equal(L.groupCenterX('diver', 3, 2), 70 + 400 * 0.25);
  const w = L.groupLayout('weaver', 3, 270);
  assert.deepEqual(w, [{ x: 200, y: -40 }, { x: 270, y: -40 }, { x: 340, y: -40 }]);
  const d = L.groupLayout('diver', 5, 270);
  assert.deepEqual(d, [{ x: 270, y: -40 }, { x: 220, y: -80 }, { x: 320, y: -80 }, { x: 170, y: -120 }, { x: 370, y: -120 }]);
});

test('timeToFall inverts fallDistance; crossTime covers the screen plus back rows', () => {
  for (const type of ['weaver', 'diver']) {
    for (const t of [0, 0.3, 1, 2.5, 11]) assert.ok(Math.abs(L.timeToFall(type, L.fallDistance(type, t)) - t) < 1e-9, type + ' ' + t);
  }
  assert.equal(L.timeToFall('weaver', 0), 0);
  assert.ok(Math.abs(L.crossTime('weaver', 3) - (1 + (1000 - 67.5) / 90)) < 1e-9);
  assert.equal(L.crossTime('weaver', 1), L.crossTime('weaver', 7));
  assert.ok(Math.abs(L.crossTime('diver', 3) - (1 + (1040 - 97.5) / 130)) < 1e-9);
  assert.ok(L.crossTime('diver', 7) > L.crossTime('diver', 3));
  assert.ok(L.crossTime('diver', 3) < L.crossTime('weaver', 3));
});

test('motion: speed ramp, weave and diver bounce', () => {
  assert.equal(L.fallDistance('weaver', 0), 0);
  assert.equal(L.fallDistance('weaver', 1), 90 * 0.75);
  assert.equal(L.fallDistance('weaver', 2), 90 * 1.75);
  assert.equal(L.fallDistance('diver', 0.5), 130 * (0.25 + 0.0625));
  assert.equal(L.zigzagCenter(270, 1, 0), 270);
  assert.equal(L.zigzagCenter(270, 1, 1), 380);
  assert.equal(L.zigzagCenter(270, -1, 1), 160);
  assert.equal(L.zigzagCenter(400, 1, 1), 470 - 40); // hits the right margin (470) and bounces back
  for (let t = 0; t < 20; t += 0.37) {
    const x = L.zigzagCenter(100, -1, t);
    assert.ok(x >= 70 - 1e-9 && x <= 470 + 1e-9, String(x));
  }
  const ships = L.shipsAt({ type: 'weaver', lane: 4, count: 1, dir: 1 }, Math.PI / 5);
  assert.ok(Math.abs(ships[0].x - 330) < 1e-9);
  const edge = L.shipsAt({ type: 'weaver', lane: 0, count: 1, dir: 1 }, -Math.PI / 5 + 2 * Math.PI / 2.5);
  assert.ok(edge[0].x >= 20);
  const v = L.shipsAt({ type: 'diver', lane: 4, count: 3, dir: 1 }, 1);
  assert.deepEqual(v.map((p) => p.x), [380, 330, 430]);
  assert.equal(v[0].y, -40 + 130 * 0.75);
});
