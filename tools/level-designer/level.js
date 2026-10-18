// Level files: validation, normalisation and serialisation for levels/<slug>.json, plus the
// game's group layout and movement math for the preview.
// Pure logic (no fs, no DOM) so it runs in the browser (window.LevelFormat), the server and node tests.
//
// Format (shared with the game; do not change):
//   { name, length, repeat, events: [{ time, type, lane, count, dir }] }
//   enemy events:    { time, type: "weaver"|"diver"|"striker"|"tank"|"orbiter", lane, count, dir }
//   obstacle events: { time, type: "obstacle", piece, lane, count, dir }
// Times are in seconds. Lane 0 enters at the left edge of the screen, lane 8 at the right edge.
// `piece` is a non-cap id from assets/obstacles/pieces.json. For a tile piece, count is the number
// of segments in the run (caps added at the ends); otherwise count copies form a loose cluster.
// dir -1 mirrors the obstacle horizontally.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.LevelFormat = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const SLUG_RE = /^[a-z0-9][a-z0-9_-]{0,39}$/;
  const TYPES = ['weaver', 'diver', 'striker', 'tank', 'orbiter'];
  const OBSTACLE = 'obstacle';
  const ALL_TYPES = TYPES.concat([OBSTACLE]);
  const PIECE_RE = /^[a-z0-9_]{1,40}$/;
  const LANES = 9;
  const MAX_NAME = 60;
  const MAX_EVENTS = 2000;
  const LENGTH_MIN = 1, LENGTH_MAX = 1800;
  const COUNT_MIN = 1, COUNT_MAX = 7;
  const TOP_KEYS = ['name', 'length', 'repeat', 'events'];
  const EVENT_KEYS = ['time', 'type', 'lane', 'count', 'dir'];
  const OBSTACLE_KEYS = ['time', 'type', 'piece', 'lane', 'count', 'dir'];
  const OLD_KEYS = ['bpm', 'beats_per_bar', 'bars'];

  // Game constants (scripts/enemy.gd, scripts/game.gd).
  const GAME = {
    width: 540, height: 960, spawnY: -40, edgeMargin: 20,
    weaverSpacing: 70, weaveAmplitude: 60, weaveFrequency: 2.5, weaverSpeed: 90,
    diverOffsetX: 50, diverOffsetY: 40, diverSpeed: 130, zigzagSpeed: 110, diverGroup: 3,
    rampStart: 0.5, rampTime: 1.0, weaverClamp: 20,
    strikerSpeed: 70, strikerGapX: 40, strikerGapY: 60, lungeTime: 1.6, lungeStagger: 0.35, lungeSpeed: 380,
    tankSpeed: 50, tankSpacing: 120, tankSway: 25, tankSwayFrequency: 1.2,
    orbiterSpeed: 80, orbitRadius: 50, orbitSpeed: 2.2,
    scrollSpeed: 60, clusterSpread: 60, obstacleSpawnGap: 10, obstacleExitGap: 20,
  };

  // ---- Obstacle piece catalog (assets/obstacles/pieces.json) ----
  // A catalog is { scroll_speed, pieces: [{ id, name, size: [w, h], tile?, caps?, cap?, outline, ... }] }.
  // indexCatalog turns it into { scrollSpeed, byId: Map, placeable: [piece] } (throws on a malformed catalog).
  let activePieces = null;

  function indexCatalog(cat) {
    if (!cat) return null;
    if (cat.byId instanceof Map) return cat;
    if (typeof cat !== 'object' || !Array.isArray(cat.pieces)) fail('piece catalog must have a "pieces" array');
    const byId = new Map();
    for (const p of cat.pieces) {
      if (!p || typeof p !== 'object' || !PIECE_RE.test(p.id)) fail('piece catalog: bad piece id ' + JSON.stringify(p && p.id));
      if (byId.has(p.id)) fail('piece catalog: duplicate piece id "' + p.id + '"');
      if (!Array.isArray(p.size) || p.size.length !== 2 || !p.size.every((v) => isNum(v) && v > 0)) fail('piece catalog: ' + p.id + '.size must be [w, h]');
      byId.set(p.id, p);
    }
    for (const p of byId.values()) {
      if (p.caps !== undefined && (!Array.isArray(p.caps) || p.caps.length !== 2 || !p.caps.every((c) => byId.has(c)))) fail('piece catalog: ' + p.id + '.caps must name two pieces');
    }
    const speed = isNum(cat.scroll_speed) && cat.scroll_speed > 0 ? cat.scroll_speed : GAME.scrollSpeed;
    return { scrollSpeed: speed, byId, placeable: [...byId.values()].filter((p) => !p.cap) };
  }

  // Sets the catalog used by validate/parse and the obstacle layout helpers (null clears it:
  // then any id matching PIECE_RE is accepted). Returns the indexed catalog.
  function setPieces(cat) {
    activePieces = indexCatalog(cat);
    return activePieces;
  }
  function getPieces() { return activePieces; }
  const catalogOf = (cat) => (cat === undefined ? activePieces : indexCatalog(cat));

  const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
  const isInt = (v) => Number.isInteger(v);

  function fail(msg) { throw new Error(msg); }

  function checkKeys(obj, allowed, where) {
    for (const k of Object.keys(obj)) if (!allowed.includes(k)) fail(where + ': unknown field "' + k + '"');
    for (const k of allowed) if (!(k in obj)) fail(where + ': missing field "' + k + '"');
  }

  // Seconds rounded to 2 decimals (the saved precision).
  const r2 = (v) => Math.round(v * 100) / 100;

  function validateEvent(e, i, length, cat) {
    const where = 'events[' + i + ']';
    if (!e || typeof e !== 'object' || Array.isArray(e)) fail(where + ' must be an object');
    if ('beat' in e) fail(where + ': old score format ("beat"); events now use "time" in seconds');
    if (!ALL_TYPES.includes(e.type)) fail(where + '.type must be one of ' + ALL_TYPES.join(', '));
    const isObstacle = e.type === OBSTACLE;
    if (!isObstacle && 'piece' in e) fail(where + ': "piece" is only allowed on obstacle events');
    checkKeys(e, isObstacle ? OBSTACLE_KEYS : EVENT_KEYS, where);
    if (!isNum(e.time) || e.time < 0) fail(where + '.time must be a number of seconds >= 0');
    const time = r2(e.time);
    if (time >= length) fail(where + '.time ' + time + ' is at or past the end of the level (' + length + ' s)');
    if (isObstacle) {
      if (typeof e.piece !== 'string' || !PIECE_RE.test(e.piece)) fail(where + '.piece must be a piece id (a-z, 0-9, _; max 40)');
      if (cat) {
        const p = cat.byId.get(e.piece);
        if (!p) fail(where + '.piece "' + e.piece + '" is not in the piece catalog');
        if (p.cap) fail(where + '.piece "' + e.piece + '" is an end cap and cannot be placed on its own');
      }
    }
    if (!isInt(e.lane) || e.lane < 0 || e.lane >= LANES) fail(where + '.lane must be an integer 0 to 8');
    if (!isInt(e.count) || e.count < COUNT_MIN || e.count > COUNT_MAX) fail(where + '.count must be an integer 1 to 7');
    if (e.dir !== 1 && e.dir !== -1) fail(where + '.dir must be 1 or -1');
    if (isObstacle) return { time, type: e.type, piece: e.piece, lane: e.lane, count: e.count, dir: e.dir };
    return { time, type: e.type, lane: e.lane, count: e.count, dir: e.dir };
  }

  function compareEvents(a, b) {
    return a.time - b.time || a.lane - b.lane;
  }

  // Throws an Error describing the first problem. Returns a normalised copy with events sorted.
  // `pieces` (optional) is a piece catalog to check obstacle ids against; omitted, the one from
  // setPieces is used; null (or no catalog set) accepts any well-formed id.
  function validate(obj, pieces) {
    const cat = catalogOf(pieces);
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) fail('level must be an object');
    if (OLD_KEYS.some((k) => k in obj)) fail('old score format (bpm/beats_per_bar/bars); levels now use "length" and event "time" in seconds');
    checkKeys(obj, TOP_KEYS, 'level');
    if (typeof obj.name !== 'string' || obj.name.trim() === '') fail('name must be a non-empty string');
    if (obj.name.length > MAX_NAME) fail('name must be at most ' + MAX_NAME + ' characters');
    if (!isNum(obj.length) || obj.length < LENGTH_MIN || obj.length > LENGTH_MAX) fail('length must be a number of seconds from 1 to 1800');
    if (typeof obj.repeat !== 'boolean') fail('repeat must be true or false');
    if (!Array.isArray(obj.events)) fail('events must be an array');
    if (obj.events.length > MAX_EVENTS) fail('at most ' + MAX_EVENTS + ' events are allowed');
    const events = obj.events.map((e, i) => validateEvent(e, i, obj.length, cat)).sort(compareEvents);
    return { name: obj.name, length: obj.length, repeat: obj.repeat, events };
  }

  // Pretty JSON (2-space indent, trailing newline), events sorted by time then lane.
  function serialize(obj, pieces) {
    return JSON.stringify(validate(obj, pieces), null, 2) + '\n';
  }

  function parse(text, pieces) {
    let obj;
    try { obj = JSON.parse(text); } catch (e) { fail('level file is not valid JSON'); }
    return validate(obj, pieces);
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

  function speedOf(type) {
    return { diver: GAME.diverSpeed, striker: GAME.strikerSpeed, tank: GAME.tankSpeed, orbiter: GAME.orbiterSpeed }[type] || GAME.weaverSpeed;
  }

  function groupHalfWidth(type, count) {
    if (type === 'diver') return GAME.diverOffsetX * Math.floor(count / 2);
    if (type === 'striker') return GAME.strikerGapX * (count - 1) / 2;
    if (type === 'tank') return GAME.tankSpacing * (count - 1) / 2 + GAME.tankSway;
    if (type === 'orbiter') return GAME.orbitRadius;
    return GAME.weaverSpacing * (count - 1) / 2 + GAME.weaveAmplitude;
  }

  function groupCenterX(type, count, lane) {
    const margin = groupHalfWidth(type, count) + GAME.edgeMargin;
    return margin + (GAME.width - 2 * margin) * (lane / (LANES - 1));
  }

  // Spawn positions for a group (x, y), like Enemy.group_layout.
  function groupLayout(type, count, centerX) {
    const out = [];
    if (type === 'striker') {
      for (let i = 0; i < count; i++) out.push({ x: centerX + GAME.strikerGapX * (i - (count - 1) / 2), y: GAME.spawnY - GAME.strikerGapY * i });
    } else if (type === 'orbiter') {
      const cy = GAME.spawnY - GAME.orbitRadius;
      for (let i = 0; i < count; i++) {
        const a = 2 * Math.PI * i / count - Math.PI / 2;
        out.push({ x: centerX + Math.cos(a) * GAME.orbitRadius, y: cy + Math.sin(a) * GAME.orbitRadius });
      }
    } else if (type === 'tank') {
      const left = centerX - GAME.tankSpacing * (count - 1) / 2;
      for (let i = 0; i < count; i++) out.push({ x: left + GAME.tankSpacing * i, y: GAME.spawnY });
    } else if (type === 'diver') {
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
    const v = speedOf(type);
    const r = GAME.rampTime, s = GAME.rampStart;
    if (t <= 0) return 0;
    if (t <= r) return v * (s * t + (1 - s) * t * t / (2 * r));
    return v * (s * r + (1 - s) * r / 2 + (t - r));
  }

  // Seconds for a group to fall `d` px (inverse of fallDistance).
  function timeToFall(type, d) {
    const v = speedOf(type);
    const r = GAME.rampTime, s = GAME.rampStart;
    if (d <= 0) return 0;
    const dRamp = v * (s * r + (1 - s) * r / 2);
    if (d >= dRamp) return r + (d - dRamp) / v;
    const a = (1 - s) * v / (2 * r), b = s * v;
    return (-b + Math.sqrt(b * b + 4 * a * d)) / (2 * a);
  }

  // Approximate seconds from spawn until the group's back row has left the bottom of the screen.
  function crossTime(type, count) {
    if (type === 'striker') {
      // The back ship is last off screen: it creeps, then lunges.
      const i = count - 1, lunge = GAME.lungeTime + GAME.lungeStagger * i;
      const d = GAME.height - GAME.spawnY + GAME.strikerGapY * i, dLunge = fallDistance(type, lunge);
      return d <= dLunge ? timeToFall(type, d) : lunge + (d - dLunge) / GAME.lungeSpeed;
    }
    if (type === 'orbiter') return timeToFall(type, GAME.height - GAME.spawnY + 2 * GAME.orbitRadius);
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
    if (ev.type === 'striker') {
      return start.map((p, i) => {
        const lunge = GAME.lungeTime + GAME.lungeStagger * i;
        const y = t <= lunge ? fallDistance('striker', t) : fallDistance('striker', lunge) + GAME.lungeSpeed * (t - lunge);
        return { x: p.x, y: p.y + y };
      });
    }
    if (ev.type === 'orbiter') {
      const cy = GAME.spawnY - GAME.orbitRadius + dy;
      return start.map((p) => {
        const a = Math.atan2(p.y - (GAME.spawnY - GAME.orbitRadius), p.x - cx) + Math.sign(ev.dir) * GAME.orbitSpeed * t;
        return { x: cx + Math.cos(a) * GAME.orbitRadius, y: cy + Math.sin(a) * GAME.orbitRadius };
      });
    }
    if (ev.type === 'tank') {
      const w = GAME.tankSway * Math.sin(t * GAME.tankSwayFrequency);
      return start.map((p) => ({ x: p.x + w, y: p.y + dy }));
    }
    if (ev.type === 'diver') {
      const c = zigzagCenter(cx, ev.dir, t);
      return start.map((p) => ({ x: c + (p.x - cx), y: p.y + dy }));
    }
    const w = GAME.weaveAmplitude * Math.sin(t * GAME.weaveFrequency);
    return start.map((p) => ({ x: Math.min(GAME.width - GAME.weaverClamp, Math.max(GAME.weaverClamp, p.x + w)), y: p.y + dy }));
  }

  // ---- Obstacles (preview) ----
  // Without a catalog (or for an unknown id) a piece is drawn as a 40x40 box.
  function pieceOf(id, cat) {
    const c = catalogOf(cat);
    const p = c && c.byId.get(id);
    if (p) return p;
    return { id: id, name: id, size: [40, 40], shape: 'rect', outline: [[-20, -20], [20, -20], [20, 20], [-20, 20]], unknown: true };
  }
  function scrollSpeed(cat) {
    const c = catalogOf(cat);
    return c ? c.scrollSpeed : GAME.scrollSpeed;
  }
  function capsOf(p, cat) {
    if (!p.tile || !Array.isArray(p.caps)) return null;
    const c = catalogOf(cat);
    if (!c) return null;
    const l = c.byId.get(p.caps[0]), r = c.byId.get(p.caps[1]);
    return l && r ? [l, r] : null;
  }

  function obstacleHalfWidth(id, count, cat) {
    const p = pieceOf(id, cat);
    const w = p.size[0];
    if (p.tile) {
      const caps = capsOf(p, cat);
      return (count * w + (caps ? caps[0].size[0] + caps[1].size[0] : 0)) / 2;
    }
    return count > 1 ? w / 2 + GAME.clusterSpread : w / 2;
  }

  function obstacleCenterX(id, count, lane, cat) {
    const margin = obstacleHalfWidth(id, count, cat) + GAME.edgeMargin;
    if (margin * 2 >= GAME.width) return GAME.width / 2;
    return margin + (GAME.width - 2 * margin) * (lane / (LANES - 1));
  }

  const obstacleSpawnY = (id, cat) => -pieceOf(id, cat).size[1] / 2 - GAME.obstacleSpawnGap;

  // Seconds an obstacle is on screen (from spawn until it has left the bottom).
  function obstacleCrossTime(id, cat) {
    return (GAME.height + pieceOf(id, cat).size[1] + GAME.obstacleExitGap) / scrollSpeed(cat);
  }

  // Seconds an event's clip lasts on the timeline.
  function eventCrossTime(ev, cat) {
    return ev.type === OBSTACLE ? obstacleCrossTime(ev.piece, cat) : crossTime(ev.type, ev.count);
  }

  // Parts of an obstacle event relative to its center, before mirroring: [{ piece, x, y }].
  // Tile pieces form a run of `count` segments with caps at the ends; other pieces form a
  // deterministic stand-in for the game's random cluster (within clusterSpread of the center).
  function obstacleParts(id, count, cat) {
    const p = pieceOf(id, cat);
    const w = p.size[0];
    const out = [];
    if (p.tile) {
      const caps = capsOf(p, cat);
      let x = -obstacleHalfWidth(id, count, cat);
      if (caps) { out.push({ piece: caps[0], x: x + caps[0].size[0] / 2, y: 0 }); x += caps[0].size[0]; }
      for (let i = 0; i < count; i++) { out.push({ piece: p, x: x + w / 2, y: 0 }); x += w; }
      if (caps) out.push({ piece: caps[1], x: x + caps[1].size[0] / 2, y: 0 });
      return out;
    }
    for (let i = 0; i < count; i++) {
      if (count === 1) { out.push({ piece: p, x: 0, y: 0 }); break; }
      const a = i * 2.39996; // golden angle
      const r = Math.sqrt((i + 0.5) / count);
      out.push({ piece: p, x: Math.cos(a) * r * GAME.clusterSpread, y: Math.sin(a) * r * GAME.clusterSpread * 0.6 });
    }
    return out;
  }

  // Parts of an obstacle event t seconds after it spawned, in screen px:
  // [{ piece, x, y, flip }] where flip = -1 when the part is drawn mirrored.
  function obstaclesAt(ev, t, cat) {
    const cx = obstacleCenterX(ev.piece, ev.count, ev.lane, cat);
    const cy = obstacleSpawnY(ev.piece, cat) + scrollSpeed(cat) * Math.max(0, t);
    const d = ev.dir === -1 ? -1 : 1;
    return obstacleParts(ev.piece, ev.count, cat).map((q) => ({ piece: q.piece, x: cx + d * q.x, y: cy + q.y, flip: d }));
  }

  return {
    SLUG_RE: SLUG_RE, TYPES: TYPES, OBSTACLE: OBSTACLE, ALL_TYPES: ALL_TYPES, PIECE_RE: PIECE_RE, LANES: LANES, MAX_NAME: MAX_NAME, MAX_EVENTS: MAX_EVENTS, LENGTH_MIN: LENGTH_MIN, LENGTH_MAX: LENGTH_MAX, GAME: GAME,
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
    setPieces: setPieces,
    getPieces: getPieces,
    indexCatalog: indexCatalog,
    pieceOf: pieceOf,
    scrollSpeed: scrollSpeed,
    obstacleHalfWidth: obstacleHalfWidth,
    obstacleCenterX: obstacleCenterX,
    obstacleSpawnY: obstacleSpawnY,
    obstacleCrossTime: obstacleCrossTime,
    eventCrossTime: eventCrossTime,
    obstacleParts: obstacleParts,
    obstaclesAt: obstaclesAt,
  };
});
