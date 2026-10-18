// Level files: validation, normalisation and serialisation for levels/<slug>.json, plus the
// game's group layout and movement math for the preview.
// Pure logic (no fs, no DOM) so it runs in the browser (window.LevelFormat), the server and node tests.
//
// Format (shared with the game; do not change):
//   { name, length, repeat, events: [{ time, type, lane, count, dir }] }
// Times are in seconds. Lane 0 enters at the left edge of the screen, lane 8 at the right edge.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.LevelFormat = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const SLUG_RE = /^[a-z0-9][a-z0-9_-]{0,39}$/;
  const TYPES = ['weaver', 'diver'];
  const LANES = 9;
  const MAX_NAME = 60;
  const MAX_EVENTS = 2000;
  const LENGTH_MIN = 1, LENGTH_MAX = 1800;
  const COUNT_MIN = 1, COUNT_MAX = 7;
  const TOP_KEYS = ['name', 'length', 'repeat', 'events'];
  const EVENT_KEYS = ['time', 'type', 'lane', 'count', 'dir'];
  const OLD_KEYS = ['bpm', 'beats_per_bar', 'bars'];

  // Game constants (scripts/enemy.gd, scripts/game.gd).
  const GAME = {
    width: 540, height: 960, spawnY: -40, edgeMargin: 20,
    weaverSpacing: 70, weaveAmplitude: 60, weaveFrequency: 2.5, weaverSpeed: 90,
    diverOffsetX: 50, diverOffsetY: 40, diverSpeed: 130, zigzagSpeed: 110, diverGroup: 3,
    rampStart: 0.5, rampTime: 1.0, weaverClamp: 20,
  };

  const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
  const isInt = (v) => Number.isInteger(v);

  function fail(msg) { throw new Error(msg); }

  function checkKeys(obj, allowed, where) {
    for (const k of Object.keys(obj)) if (!allowed.includes(k)) fail(where + ': unknown field "' + k + '"');
    for (const k of allowed) if (!(k in obj)) fail(where + ': missing field "' + k + '"');
  }

  // Seconds rounded to 2 decimals (the saved precision).
  const r2 = (v) => Math.round(v * 100) / 100;

  function validateEvent(e, i, length) {
    const where = 'events[' + i + ']';
    if (!e || typeof e !== 'object' || Array.isArray(e)) fail(where + ' must be an object');
    if ('beat' in e) fail(where + ': old score format ("beat"); events now use "time" in seconds');
    checkKeys(e, EVENT_KEYS, where);
    if (!isNum(e.time) || e.time < 0) fail(where + '.time must be a number of seconds >= 0');
    const time = r2(e.time);
    if (time >= length) fail(where + '.time ' + time + ' is at or past the end of the level (' + length + ' s)');
    if (!TYPES.includes(e.type)) fail(where + '.type must be "weaver" or "diver"');
    if (!isInt(e.lane) || e.lane < 0 || e.lane >= LANES) fail(where + '.lane must be an integer 0 to 8');
    if (!isInt(e.count) || e.count < COUNT_MIN || e.count > COUNT_MAX) fail(where + '.count must be an integer 1 to 7');
    if (e.dir !== 1 && e.dir !== -1) fail(where + '.dir must be 1 or -1');
    return { time, type: e.type, lane: e.lane, count: e.count, dir: e.dir };
  }

  function compareEvents(a, b) {
    return a.time - b.time || a.lane - b.lane;
  }

  // Throws an Error describing the first problem. Returns a normalised copy with events sorted.
  function validate(obj) {
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) fail('level must be an object');
    if (OLD_KEYS.some((k) => k in obj)) fail('old score format (bpm/beats_per_bar/bars); levels now use "length" and event "time" in seconds');
    checkKeys(obj, TOP_KEYS, 'level');
    if (typeof obj.name !== 'string' || obj.name.trim() === '') fail('name must be a non-empty string');
    if (obj.name.length > MAX_NAME) fail('name must be at most ' + MAX_NAME + ' characters');
    if (!isNum(obj.length) || obj.length < LENGTH_MIN || obj.length > LENGTH_MAX) fail('length must be a number of seconds from 1 to 1800');
    if (typeof obj.repeat !== 'boolean') fail('repeat must be true or false');
    if (!Array.isArray(obj.events)) fail('events must be an array');
    if (obj.events.length > MAX_EVENTS) fail('at most ' + MAX_EVENTS + ' events are allowed');
    const events = obj.events.map((e, i) => validateEvent(e, i, obj.length)).sort(compareEvents);
    return { name: obj.name, length: obj.length, repeat: obj.repeat, events };
  }

  // Pretty JSON (2-space indent, trailing newline), events sorted by time then lane.
  function serialize(obj) {
    return JSON.stringify(validate(obj), null, 2) + '\n';
  }

  function parse(text) {
    let obj;
    try { obj = JSON.parse(text); } catch (e) { fail('level file is not valid JSON'); }
    return validate(obj);
  }

  function empty(name) {
    return { name: name || 'New level', length: 32, repeat: true, events: [] };
  }

  function isSlug(s) { return typeof s === 'string' && SLUG_RE.test(s); }

  function slugify(name) {
    const s = String(name || '').toLowerCase().replace(/[^a-z0-9_-]+/g, '_').replace(/^[_-]+|[_-]+$/g, '').slice(0, 40);
    return isSlug(s) ? s : 'level';
  }

  // ---- Game layout and motion (preview) ----

  function groupHalfWidth(type, count) {
    if (type === 'diver') return GAME.diverOffsetX * Math.floor(count / 2);
    return GAME.weaverSpacing * (count - 1) / 2 + GAME.weaveAmplitude;
  }

  function groupCenterX(type, count, lane) {
    const margin = groupHalfWidth(type, count) + GAME.edgeMargin;
    return margin + (GAME.width - 2 * margin) * (lane / (LANES - 1));
  }

  // Spawn positions for a group (x, y), like Enemy.group_layout.
  function groupLayout(type, count, centerX) {
    const out = [];
    if (type === 'diver') {
      out.push({ x: centerX, y: GAME.spawnY });
      for (let i = 1; i < count; i++) {
        const rank = Math.ceil(i / 2);
        const side = i % 2 === 1 ? -1 : 1;
        out.push({ x: centerX + side * GAME.diverOffsetX * rank, y: GAME.spawnY - GAME.diverOffsetY * rank });
      }
    } else {
      const left = centerX - GAME.weaverSpacing * (count - 1) / 2;
      for (let i = 0; i < count; i++) out.push({ x: left + GAME.weaverSpacing * i, y: GAME.spawnY });
    }
    return out;
  }

  // Distance fallen after t seconds with the 50%→100% speed ramp over rampTime.
  function fallDistance(type, t) {
    const v = type === 'diver' ? GAME.diverSpeed : GAME.weaverSpeed;
    const r = GAME.rampTime, s = GAME.rampStart;
    if (t <= 0) return 0;
    if (t <= r) return v * (s * t + (1 - s) * t * t / (2 * r));
    return v * (s * r + (1 - s) * r / 2 + (t - r));
  }

  // Seconds for a group to fall `d` px (inverse of fallDistance).
  function timeToFall(type, d) {
    const v = type === 'diver' ? GAME.diverSpeed : GAME.weaverSpeed;
    const r = GAME.rampTime, s = GAME.rampStart;
    if (d <= 0) return 0;
    const dRamp = v * (s * r + (1 - s) * r / 2);
    if (d >= dRamp) return r + (d - dRamp) / v;
    const a = (1 - s) * v / (2 * r), b = s * v;
    return (-b + Math.sqrt(b * b + 4 * a * d)) / (2 * a);
  }

  // Approximate seconds from spawn until the group's back row has left the bottom of the screen.
  function crossTime(type, count) {
    const back = type === 'diver' ? GAME.diverOffsetY * Math.ceil((count - 1) / 2) : 0;
    return timeToFall(type, GAME.height - GAME.spawnY + back);
  }

  // Diver group center after t seconds: moves sideways and bounces, like Enemy.zigzag_center.
  function zigzagCenter(startX, dir, t) {
    const margin = groupHalfWidth('diver', GAME.diverGroup) + GAME.edgeMargin;
    const span = GAME.width - 2 * margin;
    if (span <= 0) return GAME.width / 2;
    const raw = startX - margin + Math.sign(dir) * GAME.zigzagSpeed * t;
    const m = ((raw % (2 * span)) + 2 * span) % (2 * span);
    return margin + (m <= span ? m : 2 * span - m);
  }

  // Ship positions of an event's group t seconds after it spawned.
  function shipsAt(ev, t) {
    const cx = groupCenterX(ev.type, ev.count, ev.lane);
    const dy = fallDistance(ev.type, t);
    const start = groupLayout(ev.type, ev.count, cx);
    if (ev.type === 'diver') {
      const c = zigzagCenter(cx, ev.dir, t);
      return start.map((p) => ({ x: c + (p.x - cx), y: p.y + dy }));
    }
    const w = GAME.weaveAmplitude * Math.sin(t * GAME.weaveFrequency);
    return start.map((p) => ({ x: Math.min(GAME.width - GAME.weaverClamp, Math.max(GAME.weaverClamp, p.x + w)), y: p.y + dy }));
  }

  return {
    SLUG_RE: SLUG_RE, TYPES: TYPES, LANES: LANES, MAX_NAME: MAX_NAME, MAX_EVENTS: MAX_EVENTS, LENGTH_MIN: LENGTH_MIN, LENGTH_MAX: LENGTH_MAX, GAME: GAME,
    round2: r2,
    validate: validate,
    serialize: serialize,
    parse: parse,
    empty: empty,
    isSlug: isSlug,
    slugify: slugify,
    compareEvents: compareEvents,
    groupHalfWidth: groupHalfWidth,
    groupCenterX: groupCenterX,
    groupLayout: groupLayout,
    fallDistance: fallDistance,
    timeToFall: timeToFall,
    crossTime: crossTime,
    zigzagCenter: zigzagCenter,
    shipsAt: shipsAt,
  };
});
