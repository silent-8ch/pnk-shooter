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

test('new enemy types: constants match scripts/enemy.gd', () => {
  const src = require('node:fs').readFileSync(require('node:path').join(__dirname, '../../scripts/enemy.gd'), 'utf8');
  const num = (name) => Number(new RegExp('const ' + name + ' := ([0-9.]+)').exec(src)[1]);
  const vec = (name) => new RegExp('const ' + name + ' := Vector2\\(([0-9.]+), ([0-9.]+)\\)').exec(src).slice(1).map(Number);
  const speed = (ship) => Number(new RegExp('"ship": ' + ship + ', [^\\n]*"speed": ([0-9.]+)').exec(src)[1]);
  assert.deepEqual([L.GAME.strikerGapX, L.GAME.strikerGapY], vec('STRIKER_GAP'));
  assert.equal(L.GAME.lungeTime, num('LUNGE_TIME'));
  assert.equal(L.GAME.lungeStagger, num('LUNGE_STAGGER'));
  assert.equal(L.GAME.lungeSpeed, num('LUNGE_SPEED'));
  assert.equal(L.GAME.tankSpacing, num('TANK_SPACING'));
  assert.equal(L.GAME.tankSway, num('TANK_SWAY'));
  assert.equal(L.GAME.tankSwayFrequency, num('TANK_SWAY_FREQUENCY'));
  assert.equal(L.GAME.orbitRadius, num('ORBIT_RADIUS'));
  assert.equal(L.GAME.orbitSpeed, num('ORBIT_SPEED'));
  assert.deepEqual([L.GAME.weaverSpeed, L.GAME.diverSpeed, L.GAME.strikerSpeed, L.GAME.tankSpeed, L.GAME.orbiterSpeed], [0, 1, 2, 3, 4].map(speed));
});

test('new enemy types: layout and motion', () => {
  assert.deepEqual(L.TYPES, ['weaver', 'diver', 'striker', 'tank', 'orbiter']);
  assert.deepEqual(L.groupLayout('striker', 3, 270), [{ x: 230, y: -40 }, { x: 270, y: -100 }, { x: 310, y: -160 }]);
  assert.deepEqual(L.groupLayout('tank', 2, 270), [{ x: 210, y: -40 }, { x: 330, y: -40 }]);
  const ring = L.groupLayout('orbiter', 4, 270);
  for (const p of ring) assert.ok(Math.abs(Math.hypot(p.x - 270, p.y + 90) - 50) < 1e-9);
  assert.equal(L.groupHalfWidth('orbiter', 4), 50);
  assert.equal(L.groupHalfWidth('tank', 2), 85);
  // Strikers: the front one lunges at 1.6 s, the next 0.35 s later.
  const at = (t) => L.shipsAt({ type: 'striker', lane: 4, count: 2, dir: 1 }, t);
  const fast = at(1.7)[0].y - at(1.6)[0].y, slow = at(1.7)[1].y - at(1.6)[1].y;
  assert.ok(Math.abs(fast - 38) < 1e-9, String(fast));
  assert.ok(slow < 10);
  // Orbiters stay on a ring around the falling center.
  const o = L.shipsAt({ type: 'orbiter', lane: 4, count: 4, dir: 1 }, 2);
  const cy = -90 + L.fallDistance('orbiter', 2);
  for (const p of o) assert.ok(Math.abs(Math.hypot(p.x - 270, p.y - cy) - 50) < 1e-9);
  // crossTime: every ship is past the bottom by then.
  for (const type of ['striker', 'tank', 'orbiter']) {
    const t = L.crossTime(type, 4);
    for (const p of L.shipsAt({ type, lane: 4, count: 4, dir: 1 }, t)) assert.ok(p.y >= 960 - 50 - 1e-6, type + ' ' + p.y);
  }
  L.validate({ name: 'x', length: 10, repeat: false, events: [{ time: 0, type: 'tank', lane: 4, count: 2, dir: 1 }] });
});

// ---- Obstacles ----
const CATALOG = JSON.parse(require('node:fs').readFileSync(require('node:path').join(__dirname, '../../assets/obstacles/pieces.json'), 'utf8'));
const MINI = {
  scroll_speed: 50,
  pieces: [
    { id: 'rock', name: 'Rock', size: [40, 30], shape: 'circle', hp: 3, outline: [[0, -15], [20, 0], [0, 15], [-20, 0]] },
    { id: 'bar', name: 'Bar', size: [64, 18], shape: 'rect', hp: 0, tile: true, caps: ['bar_l', 'bar_r'], outline: [[-32, -9], [32, -9], [32, 9], [-32, 9]] },
    { id: 'bar_l', name: 'Bar L', size: [24, 18], shape: 'rect', hp: 0, cap: true, outline: [[-12, -9], [12, -9], [12, 9], [-12, 9]] },
    { id: 'bar_r', name: 'Bar R', size: [10, 18], shape: 'rect', hp: 0, cap: true, outline: [[-5, -9], [5, -9], [5, 9], [-5, 9]] },
    { id: 'plain', name: 'Plain tile', size: [30, 10], shape: 'rect', hp: 0, tile: true, outline: [[-15, -5], [15, -5], [15, 5], [-15, 5]] },
    { id: 'huge', name: 'Huge', size: [520, 40], shape: 'rect', hp: 0, outline: [[-260, -20], [260, -20], [260, 20], [-260, 20]] },
  ],
};
const ob = (over) => Object.assign({ time: 1, type: 'obstacle', piece: 'rock', lane: 2, count: 3, dir: -1 }, over);

test('obstacle events validate with and without a catalog', () => {
  L.setPieces(null);
  try {
    const v = L.validate(level({ events: [ob(), ob({ piece: 'anything_9', count: 7, dir: 1, lane: 8 })] }));
    assert.deepEqual(v.events[0], ob());
    for (const piece of ['', 'Rock', 'a-b', 'x'.repeat(41), 5, null]) assert.throws(() => L.validate(level({ events: [ob({ piece })] })), /piece/, String(piece));
    // explicit catalog param
    L.validate(level({ events: [ob({ piece: 'bar' })] }), MINI);
    assert.throws(() => L.validate(level({ events: [ob({ piece: 'nope' })] }), MINI), /events\[0\]\.piece "nope" is not in the piece catalog/);
    assert.throws(() => L.validate(level({ events: [ob({ piece: 'bar_l' })] }), MINI), /end cap/);
    // catalog set with setPieces
    L.setPieces(CATALOG);
    L.validate(level({ events: [ob({ piece: 'girder' }), ob({ piece: 'asteroid_l' })] }));
    assert.throws(() => L.validate(level({ events: [ob({ piece: 'rock' })] })), /not in the piece catalog/);
    assert.throws(() => L.validate(level({ events: [ob({ piece: 'hull_end_r' })] })), /end cap/);
    assert.throws(() => L.parse(L.serialize(level()).replace('"weaver"', '"obstacle", "piece": "girder_end_l"')), /end cap/);
    // null overrides the set catalog
    L.validate(level({ events: [ob({ piece: 'rock' })] }), null);
  } finally { L.setPieces(null); }
});

test('obstacle field rules: piece only on obstacles, all fields required', () => {
  assert.throws(() => L.validate(level({ events: [ev({ piece: 'rock' })] })), /"piece" is only allowed on obstacle events/);
  assert.throws(() => L.validate(level({ events: [ev({ type: 'diver', piece: 'rock' })] })), /only allowed on obstacle/);
  const noPiece = ob(); delete noPiece.piece;
  assert.throws(() => L.validate(level({ events: [noPiece] })), /missing field "piece"/);
  assert.throws(() => L.validate(level({ events: [ob({ spin: true })] })), /unknown field "spin"/);
  for (const [over, re] of [[{ lane: 9 }, /lane/], [{ count: 0 }, /count/], [{ count: 8 }, /count/], [{ dir: 0 }, /dir/], [{ time: 32 }, /past the end/], [{ type: 'Obstacle' }, /type must be one of weaver, diver, striker, tank, orbiter, obstacle/]]) {
    assert.throws(() => L.validate(level({ events: [ob(over)] })), re, JSON.stringify(over));
  }
});

test('serialize writes obstacle keys in order: time, type, piece, lane, count, dir', () => {
  const src = level({ events: [{ dir: 1, count: 2, lane: 0, piece: 'bar', type: 'obstacle', time: 2 }, { dir: 1, count: 1, lane: 3, type: 'weaver', time: 0 }] });
  const text = L.serialize(src, MINI);
  const parsed = JSON.parse(text);
  assert.deepEqual(Object.keys(parsed.events[0]), ['time', 'type', 'lane', 'count', 'dir']);
  assert.deepEqual(Object.keys(parsed.events[1]), ['time', 'type', 'piece', 'lane', 'count', 'dir']);
  assert.match(text, /"time": 2,\n {6}"type": "obstacle",\n {6}"piece": "bar",\n {6}"lane": 0,/);
  assert.deepEqual(L.parse(text, MINI), parsed);
});

test('catalog indexing: placeable pieces, scroll speed, bad catalogs', () => {
  const c = L.indexCatalog(CATALOG);
  assert.equal(c.scrollSpeed, 60);
  assert.ok(c.placeable.every((p) => !p.cap));
  assert.ok(c.placeable.some((p) => p.id === 'girder'));
  assert.ok(!c.placeable.some((p) => p.id === 'girder_end_l'));
  assert.equal(L.indexCatalog(c), c);
  assert.equal(L.indexCatalog({ pieces: [] }).scrollSpeed, 60);
  assert.throws(() => L.indexCatalog({}), /pieces/);
  assert.throws(() => L.indexCatalog({ pieces: [{ id: 'A', size: [1, 1] }] }), /bad piece id/);
  assert.throws(() => L.indexCatalog({ pieces: [{ id: 'a', size: [1, 1] }, { id: 'a', size: [1, 1] }] }), /duplicate/);
  assert.throws(() => L.indexCatalog({ pieces: [{ id: 'a', size: [1] }] }), /size/);
  assert.throws(() => L.indexCatalog({ pieces: [{ id: 'a', size: [1, 1], caps: ['a', 'zz'] }] }), /caps/);
});

test('obstacle layout: half width, center x, spawn y, time on screen', () => {
  // tile with caps: (count*w + capsWidth)/2
  assert.equal(L.obstacleHalfWidth('bar', 3, MINI), (3 * 64 + 24 + 10) / 2);
  assert.equal(L.obstacleHalfWidth('plain', 2, MINI), 30);
  assert.equal(L.obstacleHalfWidth('rock', 1, MINI), 20);
  assert.equal(L.obstacleHalfWidth('rock', 4, MINI), 80);
  // lerp(margin, width - margin, lane/8), margin = half + 20
  assert.equal(L.obstacleCenterX('rock', 1, 0, MINI), 40);
  assert.equal(L.obstacleCenterX('rock', 1, 8, MINI), 500);
  assert.equal(L.obstacleCenterX('rock', 3, 4, MINI), 270);
  assert.equal(L.obstacleCenterX('rock', 3, 2, MINI), 100 + 340 * 0.25);
  assert.equal(L.obstacleCenterX('huge', 1, 0, MINI), 270);
  assert.equal(L.obstacleCenterX('bar', 7, 0, MINI), 261); // 7*64+34 = 482 → margin 261, 522 < 540
  assert.equal(L.obstacleCenterX('bar', 7, 8, MINI), 279);
  assert.equal(L.obstacleSpawnY('rock', MINI), -25);
  assert.equal(L.obstacleCrossTime('rock', MINI), (960 + 30 + 20) / 50);
  assert.equal(L.obstacleCrossTime('girder', CATALOG), (960 + 18 + 20) / 60);
  assert.equal(L.eventCrossTime(ob({ piece: 'rock' }), MINI), L.obstacleCrossTime('rock', MINI));
  assert.equal(L.eventCrossTime(ev()), L.crossTime('weaver', 3));
  // unknown piece / no catalog falls back to a 40x40 box at 60 px/s
  assert.equal(L.obstacleCrossTime('mystery', null), (960 + 40 + 20) / 60);
  assert.ok(L.pieceOf('mystery', null).unknown);
});

test('obstacle parts: tiled runs with caps, clusters, mirroring and falling', () => {
  const run = L.obstacleParts('bar', 2, MINI);
  assert.deepEqual(run.map((q) => [q.piece.id, q.x, q.y]), [['bar_l', -69, 0], ['bar', -25, 0], ['bar', 39, 0], ['bar_r', 76, 0]]);
  assert.deepEqual(L.obstacleParts('plain', 3, MINI).map((q) => q.x), [-30, 0, 30]);
  assert.deepEqual(L.obstacleParts('rock', 1, MINI).map((q) => [q.x, q.y]), [[0, 0]]);
  const cl = L.obstacleParts('rock', 7, MINI);
  assert.equal(cl.length, 7);
  for (const q of cl) assert.ok(Math.hypot(q.x, q.y) <= 60 + 1e-9);
  const ev2 = { time: 0, type: 'obstacle', piece: 'bar', lane: 4, count: 2, dir: -1 };
  const a = L.obstaclesAt(ev2, 0, MINI), b = L.obstaclesAt({ ...ev2, dir: 1 }, 2, MINI);
  const cx = L.obstacleCenterX('bar', 2, 4, MINI);
  assert.deepEqual(a.map((q) => q.x), run.map((q) => cx - q.x));
  assert.ok(a.every((q) => q.flip === -1 && q.y === -19));
  assert.ok(b.every((q) => q.flip === 1 && q.y === -19 + 100));
});
