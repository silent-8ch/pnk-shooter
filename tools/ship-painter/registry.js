// Asset registry: how every SVG in assets/ is meant to be colored, stored in assets/assets.json.
// Pure logic (no fs, no DOM) so it runs in the browser (window.AssetRegistry), the server and node tests.
//
// Strategies:
//   palette     painted with color slots (data-slot) and recolored at runtime (ShipSkin)
//   tint        drawn white / light gray and modulated at runtime
//   fixed       colors baked into the art
//   unassigned  not decided yet
// Status is computed from the entry and the SVG text, never stored.
//
// Ships may carry a thruster layout, read by the game (fixed contract):
//   thrusters: [{ x, y, angle, size, main }]   x, y in viewBox units (art faces up), angle = flame
//   direction in degrees with y down (0 right, 90 down), size 0.25..3, at most one main booster.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.AssetRegistry = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const VERSION = 1;
  const STRATEGIES = ['palette', 'tint', 'fixed', 'unassigned'];
  const STATUSES = ['ok', 'needs-strategy', 'needs-paint', 'needs-tint-art', 'missing-file'];
  const MAX_ROLE = 40;
  const MAX_NOTES = 2000;
  const TINT_MIN = 0x80;     // every channel at least this light
  const TINT_SPREAD = 0x18;  // and channels this close together (gray)
  const MAX_THRUSTERS = 12;
  const THRUSTER_SIZE_MIN = 0.25;
  const THRUSTER_SIZE_MAX = 3;
  const THRUSTER_SIZE = 1;       // default size
  const MAIN_THRUSTER_SIZE = 1.6; // default size of the main booster

  const SLOTS_RE = /<svg\b[^>]*?\sdata-slots\s*=\s*"(\d+)"/;
  const SLOT_RE = /\sdata-slot\s*=\s*"\d+"/;
  const NAMES_RE = /<svg\b[^>]*?\sdata-slot-names\s*=\s*"([^"]*)"/;
  const COLOR_RE = /(?:\b(?:fill|stroke|stop-color)\s*=\s*"|\b(?:fill|stroke|stop-color)\s*:\s*)(#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?)\b/g;

  function empty() {
    return { version: VERSION, assets: {} };
  }

  // Parse assets.json text; tolerates a missing file (pass null) but not a malformed one.
  function parse(text) {
    if (text === null || text === undefined || String(text).trim() === '') return empty();
    const data = JSON.parse(text);
    if (!data || typeof data !== 'object' || typeof data.assets !== 'object' || Array.isArray(data.assets)) {
      throw new Error('assets.json: expected { version, assets: {...} }');
    }
    const db = empty();
    Object.keys(data.assets).forEach(function (p) { db.assets[p] = cleanEntry(data.assets[p]); });
    return db;
  }

  // Stable JSON: sorted paths, fixed key order, 2-space indent, trailing newline.
  function serialize(db) {
    const assets = {};
    Object.keys(db.assets).sort().forEach(function (p) {
      const e = cleanEntry(db.assets[p]);
      const out = { strategy: e.strategy };
      if (e.role) out.role = e.role;
      if (e.slots && e.slots.length) out.slots = e.slots;
      if (e.thrusters && e.thrusters.length) out.thrusters = e.thrusters;
      if (e.notes) out.notes = e.notes;
      assets[p] = out;
    });
    return JSON.stringify({ version: VERSION, assets: assets }, null, 2) + '\n';
  }

  function cleanEntry(e) {
    e = e && typeof e === 'object' ? e : {};
    const out = {
      strategy: STRATEGIES.indexOf(e.strategy) !== -1 ? e.strategy : 'unassigned',
      role: typeof e.role === 'string' ? e.role.trim().slice(0, MAX_ROLE) : '',
      notes: typeof e.notes === 'string' ? e.notes.slice(0, MAX_NOTES) : '',
    };
    if (Array.isArray(e.slots)) out.slots = e.slots.filter(function (s) { return typeof s === 'string'; });
    const thrusters = cleanThrusters(e.thrusters);
    if (thrusters.length) out.thrusters = thrusters;
    return out;
  }

  function isNum(v) {
    return typeof v === 'number' && isFinite(v);
  }

  function normalizeAngle(a) {
    return ((a % 360) + 360) % 360 + 0; // + 0 turns -0 into 0
  }

  // Sanitized thruster list: drops malformed items, rounds, clamps, keeps at most
  // MAX_THRUSTERS and only the first main booster.
  function cleanThrusters(list) {
    if (!Array.isArray(list)) return [];
    const out = [];
    let hasMain = false;
    list.forEach(function (t) {
      if (out.length >= MAX_THRUSTERS || !t || typeof t !== 'object' || Array.isArray(t)) return;
      if (!isNum(t.x) || !isNum(t.y)) return;
      if (t.angle !== undefined && !isNum(t.angle)) return;
      if (t.size !== undefined && !isNum(t.size)) return;
      const main = t.main === true && !hasMain;
      if (main) hasMain = true;
      const size = t.size === undefined ? (main ? MAIN_THRUSTER_SIZE : THRUSTER_SIZE) : t.size;
      out.push({
        x: Math.round(t.x * 10) / 10 + 0,
        y: Math.round(t.y * 10) / 10 + 0,
        angle: normalizeAngle(Math.round(t.angle === undefined ? 90 : t.angle)),
        size: Math.min(THRUSTER_SIZE_MAX, Math.max(THRUSTER_SIZE_MIN, Math.round(size * 20) / 20)),
        main: main,
      });
    });
    return out;
  }

  function validateThrusters(list) {
    if (!Array.isArray(list)) throw new Error('thrusters must be an array');
    if (list.length > MAX_THRUSTERS) throw new Error('at most ' + MAX_THRUSTERS + ' thrusters');
    let mains = 0;
    list.forEach(function (t, i) {
      if (!t || typeof t !== 'object' || Array.isArray(t)) throw new Error('thruster ' + i + ' must be an object');
      ['x', 'y', 'angle'].forEach(function (k) {
        if (!isNum(t[k])) throw new Error('thruster ' + i + ': ' + k + ' must be a number');
      });
      if (t.size !== undefined && !isNum(t.size)) throw new Error('thruster ' + i + ': size must be a number');
      if (t.main !== undefined && typeof t.main !== 'boolean') throw new Error('thruster ' + i + ': main must be true or false');
      if (t.main) mains += 1;
    });
    if (mains > 1) throw new Error('at most one main thruster');
  }

  // Validates an entry sent by a client; throws on bad input instead of silently fixing it.
  function validateEntry(e) {
    if (!e || typeof e !== 'object' || Array.isArray(e)) throw new Error('entry must be an object');
    if (STRATEGIES.indexOf(e.strategy) === -1) throw new Error('strategy must be one of ' + STRATEGIES.join(', '));
    if (e.role !== undefined && (typeof e.role !== 'string' || e.role.length > MAX_ROLE)) throw new Error('role must be a string of at most ' + MAX_ROLE + ' chars');
    if (e.notes !== undefined && (typeof e.notes !== 'string' || e.notes.length > MAX_NOTES)) throw new Error('notes must be a string of at most ' + MAX_NOTES + ' chars');
    if (e.thrusters !== undefined) validateThrusters(e.thrusters);
    return cleanEntry(e);
  }

  function isPainted(svg) {
    return SLOTS_RE.test(svg) || SLOT_RE.test(svg);
  }

  function slotNames(svg) {
    const m = NAMES_RE.exec(svg);
    if (!m || m[1] === '') return [];
    return m[1].replace(/&quot;/g, '"').replace(/&gt;/g, '>').replace(/&lt;/g, '<').replace(/&amp;/g, '&').split(',');
  }

  function hex6(c) {
    c = c.toLowerCase();
    return c.length === 4 ? '#' + c[1] + c[1] + c[2] + c[2] + c[3] + c[3] : c;
  }

  // Distinct colors named in fill / stroke / stop-color attributes or style properties.
  function colors(svg) {
    const seen = [];
    const re = new RegExp(COLOR_RE.source, 'g');
    let m;
    while ((m = re.exec(svg)) !== null) {
      const c = hex6(m[1]);
      if (seen.indexOf(c) === -1) seen.push(c);
    }
    return seen;
  }

  function isTintColor(c) {
    const r = parseInt(c.slice(1, 3), 16), g = parseInt(c.slice(3, 5), 16), b = parseInt(c.slice(5, 7), 16);
    return Math.min(r, g, b) >= TINT_MIN && Math.max(r, g, b) - Math.min(r, g, b) <= TINT_SPREAD;
  }

  function isTintArt(svg) {
    const cs = colors(svg);
    return cs.length > 0 && cs.every(isTintColor);
  }

  // Best guess for an asset nobody has classified yet.
  function classify(svg) {
    if (isPainted(svg)) return 'palette';
    if (isTintArt(svg)) return 'tint';
    return 'unassigned';
  }

  function guessRole(p) {
    const name = p.replace(/^.*\//, '');
    if (/^ship\d*\.svg$/i.test(name)) return 'ship';
    if (/^pickup_/i.test(name)) return 'pickup';
    if (/\/(fx|effects)\//i.test(p)) return 'fx';
    return '';
  }

  // svg is the file's text, or null when the file is missing.
  function statusOf(entry, svg) {
    if (svg === null || svg === undefined) return 'missing-file';
    if (!entry || entry.strategy === 'unassigned') return 'needs-strategy';
    if (entry.strategy === 'palette' && !isPainted(svg)) return 'needs-paint';
    if (entry.strategy === 'tint' && !isTintArt(svg)) return 'needs-tint-art';
    return 'ok';
  }

  // Applies an entry for path p, refreshing derived fields (slot names) from the SVG.
  function setEntry(db, p, entry, svg) {
    const e = cleanEntry(entry);
    if (e.strategy === 'palette' && typeof svg === 'string') e.slots = slotNames(svg);
    else delete e.slots;
    db.assets[p] = e;
    return e;
  }

  // Adds a classified entry for every file without one. Never touches existing entries.
  // files: { path: svgText }. Returns the paths added.
  function seed(db, files) {
    const added = [];
    Object.keys(files).sort().forEach(function (p) {
      if (db.assets[p]) return;
      setEntry(db, p, { strategy: classify(files[p]), role: guessRole(p) }, files[p]);
      added.push(p);
    });
    return added;
  }

  // One row per known path (on disk or in the registry), sorted by path.
  // files: { path: svgText }.
  function list(db, files) {
    const paths = Object.keys(files).concat(Object.keys(db.assets).filter(function (p) { return !(p in files); }));
    return paths.sort().map(function (p) {
      const svg = p in files ? files[p] : null;
      const entry = db.assets[p] || null;
      return {
        path: p,
        strategy: entry ? entry.strategy : 'unassigned',
        role: entry ? entry.role : '',
        notes: entry ? entry.notes : '',
        thrusters: entry && entry.thrusters ? entry.thrusters : [],
        registered: !!entry,
        suggested: svg !== null ? classify(svg) : null,
        status: statusOf(entry, svg),
      };
    });
  }

  function needsAttention(row) {
    return row.status !== 'ok';
  }

  return {
    VERSION: VERSION,
    STRATEGIES: STRATEGIES,
    STATUSES: STATUSES,
    MAX_THRUSTERS: MAX_THRUSTERS,
    THRUSTER_SIZE_MIN: THRUSTER_SIZE_MIN,
    THRUSTER_SIZE_MAX: THRUSTER_SIZE_MAX,
    THRUSTER_SIZE: THRUSTER_SIZE,
    MAIN_THRUSTER_SIZE: MAIN_THRUSTER_SIZE,
    empty: empty,
    parse: parse,
    serialize: serialize,
    validateEntry: validateEntry,
    cleanThrusters: cleanThrusters,
    isPainted: isPainted,
    slotNames: slotNames,
    colors: colors,
    isTintArt: isTintArt,
    classify: classify,
    guessRole: guessRole,
    statusOf: statusOf,
    setEntry: setEntry,
    seed: seed,
    list: list,
    needsAttention: needsAttention,
  };
});
