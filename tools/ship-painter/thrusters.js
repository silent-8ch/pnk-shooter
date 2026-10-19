// Thruster layout editing for ships: place nozzles, aim flames, map preview clicks to viewBox units.
// Pure math (no DOM) so it runs in the browser (window.ShipThrusters) and in node tests.
// Thrusters are { x, y, angle, size, main } in viewBox units; angle is the direction the flame
// points, in degrees with y down (0 right, 90 down, 180 left, 270 up). The art faces up.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.ShipThrusters = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // Must match the registry contract (registry.js).
  const MAX = 12;
  const SIZE_MIN = 0.25;
  const SIZE_MAX = 3;
  const SIZE = 1;
  const MAIN_SIZE = 1.6;
  const DEFAULT_ANGLE = 90; // flame out the back: pushes the ship forward
  const MAIN_HIT_SCALE = 1.4; // the main booster's marker is drawn bigger
  const ALIGNS = ['xMinYMin', 'xMidYMin', 'xMaxYMin', 'xMinYMid', 'xMidYMid', 'xMaxYMid', 'xMinYMax', 'xMidYMax', 'xMaxYMax'];

  function normalizeAngle(a) {
    return ((a % 360) + 360) % 360 + 0; // + 0 turns -0 into 0
  }

  // Flame angle (whole degrees, [0, 360)) for a drag from the nozzle by (dx, dy), y down.
  function angleFromVector(dx, dy) {
    return normalizeAngle(Math.round(Math.atan2(dy, dx) * 180 / Math.PI));
  }

  function clampSize(s) {
    return Math.min(SIZE_MAX, Math.max(SIZE_MIN, Math.round(s * 20) / 20));
  }

  function round1(v) {
    return Math.round(v * 10) / 10 + 0;
  }

  // preserveAspectRatio as { align, slice }; anything unrecognized is the SVG default xMidYMid meet.
  function parseAspect(par) {
    const parts = String(par || '').trim().split(/\s+/);
    const align = parts[0] === 'none' || ALIGNS.indexOf(parts[0]) !== -1 ? parts[0] : 'xMidYMid';
    return { align: align, slice: parts[1] === 'slice' };
  }

  // Maps viewBox units to client pixels for an element drawn in rect ({ left, top, width, height }):
  // client = vb * scale + offset, per axis.
  function viewBoxTransform(rect, vb, par) {
    const a = parseAspect(par);
    let sx = rect.width / vb.w, sy = rect.height / vb.h;
    if (a.align !== 'none') sx = sy = a.slice ? Math.max(sx, sy) : Math.min(sx, sy);
    let tx = rect.left - vb.x * sx, ty = rect.top - vb.y * sy;
    if (a.align !== 'none') {
      const fx = a.align.indexOf('xMid') === 0 ? 0.5 : a.align.indexOf('xMax') === 0 ? 1 : 0;
      const fy = /YMid$/.test(a.align) ? 0.5 : /YMax$/.test(a.align) ? 1 : 0;
      tx += (rect.width - vb.w * sx) * fx;
      ty += (rect.height - vb.h * sy) * fy;
    }
    return { sx: sx, sy: sy, tx: tx, ty: ty };
  }

  function clientToViewBox(cx, cy, rect, vb, par) {
    const m = viewBoxTransform(rect, vb, par);
    return { x: (cx - m.tx) / m.sx, y: (cy - m.ty) / m.sy };
  }

  function viewBoxToClient(x, y, rect, vb, par) {
    const m = viewBoxTransform(rect, vb, par);
    return { x: x * m.sx + m.tx, y: y * m.sy + m.ty };
  }

  function inViewBox(vb, x, y) {
    return x >= vb.x && x <= vb.x + vb.w && y >= vb.y && y <= vb.y + vb.h;
  }

  // Index of the marker nearest (x, y) within radius (the main booster's is MAIN_HIT_SCALE bigger), or -1.
  function hitTest(list, x, y, radius) {
    let best = -1, bestD = Infinity;
    list.forEach(function (t, i) {
      const d = Math.hypot(t.x - x, t.y - y);
      if (d <= radius * (t.main ? MAIN_HIT_SCALE : 1) && d < bestD) { best = i; bestD = d; }
    });
    return best;
  }

  function check(list, i) {
    if (!(i >= 0 && i < list.length)) throw new RangeError('thruster index out of range');
  }

  // Adds a thruster at (x, y) firing backward. The first one on an empty layout is the main booster.
  function add(list, x, y) {
    if (list.length >= MAX) throw new RangeError('at most ' + MAX + ' thrusters');
    const main = list.length === 0;
    list.push({ x: round1(x), y: round1(y), angle: DEFAULT_ANGLE, size: main ? MAIN_SIZE : SIZE, main: main });
    return list.length - 1;
  }

  // Removing the main booster leaves none; the user picks the next one.
  function remove(list, i) {
    check(list, i);
    list.splice(i, 1);
    return list;
  }

  function setMain(list, i) {
    check(list, i);
    list.forEach(function (t, j) { t.main = j === i; });
    return list;
  }

  function setSize(list, i, s) {
    check(list, i);
    if (typeof s !== 'number' || !isFinite(s)) throw new Error('size must be a number');
    list[i].size = clampSize(s);
    return list;
  }

  // Points thruster i's flame at (x, y). Ignored closer than minDist (a click, not a drag). Returns true if it changed.
  function aim(list, i, x, y, minDist) {
    check(list, i);
    const t = list[i];
    const dx = x - t.x, dy = y - t.y;
    if (Math.hypot(dx, dy) < (minDist || 0)) return false;
    const a = angleFromVector(dx, dy);
    if (a === t.angle) return false;
    t.angle = a;
    return true;
  }

  // Flame triangle for display: base across the nozzle, tip len * size away in the flame direction.
  function flameWedge(t, len, halfWidth) {
    const r = t.angle * Math.PI / 180;
    const ux = Math.cos(r), uy = Math.sin(r);
    const l = len * t.size, w = halfWidth * t.size;
    return [[t.x - uy * w, t.y + ux * w], [t.x + ux * l, t.y + uy * l], [t.x + uy * w, t.y - ux * w]];
  }

  // What a flame at this angle does to a ship facing up: it pushes the opposite way.
  function describe(angle) {
    const a = normalizeAngle(angle);
    if (a >= 45 && a <= 135) return 'pushes forward';
    if (a >= 225 && a <= 315) return 'brakes / reverses';
    return a < 45 || a > 315 ? 'pushes left' : 'pushes right';
  }

  return {
    MAX: MAX,
    SIZE_MIN: SIZE_MIN,
    SIZE_MAX: SIZE_MAX,
    SIZE: SIZE,
    MAIN_SIZE: MAIN_SIZE,
    DEFAULT_ANGLE: DEFAULT_ANGLE,
    MAIN_HIT_SCALE: MAIN_HIT_SCALE,
    normalizeAngle: normalizeAngle,
    angleFromVector: angleFromVector,
    parseAspect: parseAspect,
    viewBoxTransform: viewBoxTransform,
    clientToViewBox: clientToViewBox,
    viewBoxToClient: viewBoxToClient,
    inViewBox: inViewBox,
    hitTest: hitTest,
    add: add,
    remove: remove,
    setMain: setMain,
    setSize: setSize,
    aim: aim,
    flameWedge: flameWedge,
    describe: describe,
  };
});
