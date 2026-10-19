// Run: node --test tools/ship-painter/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const T = require('./thrusters.js');
const Registry = require('./registry.js');

const VB = { x: 0, y: 0, w: 869, h: 600 };

test('limits match the registry contract', () => {
  assert.equal(T.MAX, Registry.MAX_THRUSTERS);
  assert.equal(T.SIZE_MIN, Registry.THRUSTER_SIZE_MIN);
  assert.equal(T.SIZE_MAX, Registry.THRUSTER_SIZE_MAX);
  assert.equal(T.SIZE, Registry.THRUSTER_SIZE);
  assert.equal(T.MAIN_SIZE, Registry.MAIN_THRUSTER_SIZE);
});

test('angleFromVector: screen convention, y down, whole degrees in [0, 360)', () => {
  assert.equal(T.angleFromVector(1, 0), 0);
  assert.equal(T.angleFromVector(0, 1), 90, 'down: a normal main booster');
  assert.equal(T.angleFromVector(-1, 0), 180);
  assert.equal(T.angleFromVector(0, -1), 270, 'up: nose / brake jets');
  assert.equal(T.angleFromVector(1, -1), 315);
  assert.equal(T.angleFromVector(1, -0.0001), 0, 'rounds 359.99 to 0, not 360');
  assert.equal(T.normalizeAngle(-90), 270);
  assert.equal(T.normalizeAngle(720), 0);
  assert.ok(!Object.is(T.normalizeAngle(-0), -0));
});

test('parseAspect: defaults to xMidYMid meet', () => {
  assert.deepEqual(T.parseAspect(null), { align: 'xMidYMid', slice: false });
  assert.deepEqual(T.parseAspect('xMidYMid meet'), { align: 'xMidYMid', slice: false });
  assert.deepEqual(T.parseAspect('xMinYMax slice'), { align: 'xMinYMax', slice: true });
  assert.deepEqual(T.parseAspect('none'), { align: 'none', slice: false });
  assert.deepEqual(T.parseAspect('bogus'), { align: 'xMidYMid', slice: false });
});

test('clientToViewBox: xMidYMid meet letterboxes and centers', () => {
  // 869x600 art in a 400x400 box: scale 400/869, drawn 400 wide and ~276 tall, centered vertically.
  const rect = { left: 100, top: 50, width: 400, height: 400 };
  const s = 400 / 869, padY = (400 - 600 * s) / 2;
  const p = T.clientToViewBox(100, 50 + padY, rect, VB, 'xMidYMid meet');
  assert.ok(Math.abs(p.x) < 1e-9 && Math.abs(p.y) < 1e-9, 'top-left of the art');
  const c = T.clientToViewBox(300, 250, rect, VB, 'xMidYMid meet');
  assert.ok(Math.abs(c.x - 434.5) < 1e-9 && Math.abs(c.y - 300) < 1e-9, 'center maps to center');
  const out = T.clientToViewBox(300, 51, rect, VB);
  assert.ok(!T.inViewBox(VB, out.x, out.y), 'letterbox band is outside the art');
  // Tall box: pillarboxed horizontally.
  const tall = { left: 0, top: 0, width: 869, height: 1000 };
  const t = T.clientToViewBox(0, 200, tall, VB);
  assert.ok(Math.abs(t.x) < 1e-9 && Math.abs(t.y) < 1e-9);
});

test('clientToViewBox: respects a viewBox origin, other aligns, slice and none; round-trips', () => {
  const vb = { x: -50, y: 10, w: 100, h: 50 };
  const rect = { left: 10, top: 20, width: 200, height: 200 };
  for (const par of ['xMidYMid meet', 'xMinYMin meet', 'xMaxYMax meet', 'xMidYMid slice', 'none']) {
    const c = T.viewBoxToClient(-20, 30, rect, vb, par);
    const back = T.clientToViewBox(c.x, c.y, rect, vb, par);
    assert.ok(Math.abs(back.x + 20) < 1e-9 && Math.abs(back.y - 30) < 1e-9, par);
  }
  assert.deepEqual(T.viewBoxToClient(-50, 10, rect, vb, 'xMinYMin meet'), { x: 10, y: 20 });
  assert.deepEqual(T.viewBoxToClient(-50, 10, rect, vb, 'xMinYMax meet'), { x: 10, y: 120 });
  assert.deepEqual(T.viewBoxToClient(50, 60, rect, vb, 'none'), { x: 210, y: 220 });
  assert.deepEqual(T.viewBoxToClient(-50, 10, rect, vb, 'xMidYMid slice'), { x: -90, y: 20 });
});

test('add: first on an empty layout is the main booster; later ones are normal; capped at MAX', () => {
  const list = [];
  assert.equal(T.add(list, 434.46, 560.04), 0);
  assert.deepEqual(list[0], { x: 434.5, y: 560, angle: 90, size: T.MAIN_SIZE, main: true });
  T.add(list, 400, 100);
  assert.deepEqual(list[1], { x: 400, y: 100, angle: 90, size: T.SIZE, main: false });
  while (list.length < T.MAX) T.add(list, 1, 1);
  assert.throws(() => T.add(list, 1, 1), /at most 12/);
  T.remove(list, 0);
  assert.ok(list.every((t) => !t.main), 'removing the main leaves none');
  assert.throws(() => T.remove(list, 99), RangeError);
});

test('setMain keeps exactly one main; setSize clamps and rounds', () => {
  const list = [];
  T.add(list, 0, 0); T.add(list, 1, 1); T.add(list, 2, 2);
  T.setMain(list, 2);
  assert.deepEqual(list.map((t) => t.main), [false, false, true]);
  T.setSize(list, 1, 9); assert.equal(list[1].size, 3);
  T.setSize(list, 1, 0); assert.equal(list[1].size, 0.25);
  T.setSize(list, 1, 1.13); assert.equal(list[1].size, 1.15);
  assert.throws(() => T.setSize(list, 1, NaN), /number/);
  assert.throws(() => T.setMain(list, -1), RangeError);
  assert.deepEqual(Registry.cleanThrusters(list), list, 'edited layouts are already clean');
});

test('aim: points the flame at the drag point, ignores tiny drags', () => {
  const list = [];
  T.add(list, 100, 100);
  assert.equal(T.aim(list, 0, 101, 100, 5), false, 'too close');
  assert.equal(list[0].angle, 90);
  assert.equal(T.aim(list, 0, 100, 50, 5), true);
  assert.equal(list[0].angle, 270);
  assert.equal(T.aim(list, 0, 100, 0, 5), false, 'same angle is no change');
  assert.equal(T.aim(list, 0, 50, 100), true);
  assert.equal(list[0].angle, 180);
});

test('hitTest: nearest marker within radius; main marker is bigger', () => {
  const list = [];
  T.add(list, 100, 100); T.add(list, 120, 100); T.add(list, 300, 300);
  assert.equal(T.hitTest(list, 112, 100, 10), 1, 'nearest wins');
  assert.equal(T.hitTest(list, 100, 113, 10), 0, 'main reaches radius * MAIN_HIT_SCALE');
  assert.equal(T.hitTest(list, 300, 313, 10), -1);
  assert.equal(T.hitTest([], 0, 0, 10), -1);
});

test('flameWedge: tip in the flame direction, scaled by size', () => {
  const w = T.flameWedge({ x: 10, y: 10, angle: 90, size: 2, main: false }, 5, 1);
  const r = (p) => p.map((v) => Math.round(v * 1e9) / 1e9 + 0);
  assert.deepEqual(w.map(r), [[8, 10], [10, 20], [12, 10]]);
});

test('describe: flames push the ship the opposite way', () => {
  assert.equal(T.describe(90), 'pushes forward');
  assert.equal(T.describe(270), 'brakes / reverses');
  assert.equal(T.describe(0), 'pushes left');
  assert.equal(T.describe(180), 'pushes right');
});
