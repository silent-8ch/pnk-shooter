// Raster region helpers for the fill layer: dilate, flood fill, trace to vector loops, simplify.
// Masks are { w, h, data: Uint8Array } with 1 = set. Pure logic, no DOM.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.ShipRegions = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  function makeMask(w, h) {
    return { w: w, h: h, data: new Uint8Array(w * h) };
  }

  // Mask from RGBA pixels: alpha >= threshold is set.
  function maskFromAlpha(rgba, w, h, threshold) {
    const m = makeMask(w, h);
    for (let i = 0; i < w * h; i++) m.data[i] = rgba[i * 4 + 3] >= threshold ? 1 : 0;
    return m;
  }

  // Square-kernel dilation by r pixels (separable running window).
  function dilate(mask, r) {
    const w = mask.w, h = mask.h;
    if (r <= 0) return { w: w, h: h, data: mask.data.slice() };
    const tmp = new Uint8Array(w * h);
    const out = makeMask(w, h);
    for (let y = 0; y < h; y++) {
      const row = y * w;
      let count = 0;
      for (let x = 0; x <= Math.min(r, w - 1); x++) count += mask.data[row + x];
      for (let x = 0; x < w; x++) {
        tmp[row + x] = count > 0 ? 1 : 0;
        const add = x + r + 1, sub = x - r;
        if (add < w) count += mask.data[row + add];
        if (sub >= 0) count -= mask.data[row + sub];
      }
    }
    for (let x = 0; x < w; x++) {
      let count = 0;
      for (let y = 0; y <= Math.min(r, h - 1); y++) count += tmp[y * w + x];
      for (let y = 0; y < h; y++) {
        out.data[y * w + x] = count > 0 ? 1 : 0;
        const add = y + r + 1, sub = y - r;
        if (add < h) count += tmp[add * w + x];
        if (sub >= 0) count -= tmp[sub * w + x];
      }
    }
    return out;
  }

  // 4-connected flood fill of unset barrier pixels starting at (x, y).
  function floodFill(barrier, x, y) {
    const w = barrier.w, h = barrier.h;
    const region = makeMask(w, h);
    const result = { mask: region, count: 0, touchesEdge: false };
    if (x < 0 || y < 0 || x >= w || y >= h || barrier.data[y * w + x]) return result;
    const stack = new Int32Array(w * h);
    let sp = 0;
    stack[sp++] = y * w + x;
    region.data[y * w + x] = 1;
    while (sp > 0) {
      const i = stack[--sp];
      const px = i % w, py = (i - px) / w;
      result.count++;
      if (px === 0 || py === 0 || px === w - 1 || py === h - 1) result.touchesEdge = true;
      if (px > 0 && !barrier.data[i - 1] && !region.data[i - 1]) { region.data[i - 1] = 1; stack[sp++] = i - 1; }
      if (px < w - 1 && !barrier.data[i + 1] && !region.data[i + 1]) { region.data[i + 1] = 1; stack[sp++] = i + 1; }
      if (py > 0 && !barrier.data[i - w] && !region.data[i - w]) { region.data[i - w] = 1; stack[sp++] = i - w; }
      if (py < h - 1 && !barrier.data[i + w] && !region.data[i + w]) { region.data[i + w] = 1; stack[sp++] = i + w; }
    }
    return result;
  }

  const DX = [1, 0, -1, 0]; // right, down, left, up (screen coordinates, y down)
  const DY = [0, 1, 0, -1];

  // Trace pixel-edge boundaries into closed loops of grid-corner points.
  // Outer boundaries wind clockwise on screen and holes counter-clockwise, so nonzero fill is correct.
  function traceContours(mask) {
    const w = mask.w, h = mask.h, d = mask.data;
    const at = (x, y) => (x >= 0 && y >= 0 && x < w && y < h ? d[y * w + x] : 0);
    const ex = [], ey = [], edir = [];
    const byStart = new Map();
    const key = (x, y) => y * (w + 1) + x;
    function add(x, y, dir) {
      const id = ex.length;
      ex.push(x); ey.push(y); edir.push(dir);
      const k = key(x, y);
      const list = byStart.get(k);
      if (list) list.push(id); else byStart.set(k, [id]);
    }
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        if (!d[y * w + x]) continue;
        if (!at(x, y - 1)) add(x, y, 0);
        if (!at(x + 1, y)) add(x + 1, y, 1);
        if (!at(x, y + 1)) add(x + 1, y + 1, 2);
        if (!at(x - 1, y)) add(x, y + 1, 3);
      }
    }
    const used = new Uint8Array(ex.length);
    const loops = [];
    for (let first = 0; first < ex.length; first++) {
      if (used[first]) continue;
      const pts = [];
      let cur = first;
      for (;;) {
        used[cur] = 1;
        pts.push([ex[cur], ey[cur]]);
        const nx = ex[cur] + DX[edir[cur]], ny = ey[cur] + DY[edir[cur]];
        const cands = byStart.get(key(nx, ny)) || [];
        let next = -1;
        for (const turn of [1, 0, 3]) { // prefer right turn, then straight, then left
          const want = (edir[cur] + turn) % 4;
          const hit = cands.find((c) => edir[c] === want && (!used[c] || c === first));
          if (hit !== undefined) { next = hit; break; }
        }
        if (next === -1 || next === first) break;
        cur = next;
      }
      const simplified = dropCollinear(pts);
      if (simplified.length >= 3) loops.push(simplified);
    }
    return loops;
  }

  function dropCollinear(pts) {
    const out = [];
    const n = pts.length;
    for (let i = 0; i < n; i++) {
      const a = pts[(i + n - 1) % n], b = pts[i], c = pts[(i + 1) % n];
      const cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
      if (cross !== 0) out.push(b);
    }
    return out;
  }

  function perpDist(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const len = Math.hypot(dx, dy);
    if (len === 0) return Math.hypot(p[0] - a[0], p[1] - a[1]);
    return Math.abs(dy * p[0] - dx * p[1] + b[0] * a[1] - b[1] * a[0]) / len;
  }

  function rdp(pts, eps) {
    if (pts.length < 3) return pts.slice();
    const keep = new Uint8Array(pts.length);
    keep[0] = keep[pts.length - 1] = 1;
    const stack = [[0, pts.length - 1]];
    while (stack.length) {
      const [s, e] = stack.pop();
      let best = -1, bestD = eps;
      for (let i = s + 1; i < e; i++) {
        const dd = perpDist(pts[i], pts[s], pts[e]);
        if (dd > bestD) { bestD = dd; best = i; }
      }
      if (best !== -1) { keep[best] = 1; stack.push([s, best], [best, e]); }
    }
    return pts.filter((_, i) => keep[i]);
  }

  // Ramer-Douglas-Peucker on a closed loop. Loops that collapse below 3 points return [].
  function simplifyLoop(pts, eps) {
    if (pts.length <= 3 || eps <= 0) return pts.slice();
    let far = 0, farD = -1;
    for (let i = 1; i < pts.length; i++) {
      const dd = Math.hypot(pts[i][0] - pts[0][0], pts[i][1] - pts[0][1]);
      if (dd > farD) { farD = dd; far = i; }
    }
    const a = rdp(pts.slice(0, far + 1), eps);
    const b = rdp(pts.slice(far).concat([pts[0]]), eps);
    const out = a.slice(0, -1).concat(b.slice(0, -1));
    return out.length >= 3 ? out : [];
  }

  function fmt(n) {
    const r = Math.round(n * 100) / 100;
    return Object.is(r, -0) ? '0' : String(r);
  }

  // Loops in pixel space -> SVG path data in viewBox space. xf = { sx, sy, ox, oy }.
  function loopsToPathD(loops, xf) {
    xf = xf || { sx: 1, sy: 1, ox: 0, oy: 0 };
    return loops
      .filter((l) => l.length >= 3)
      .map((l) => 'M' + l.map((p) => fmt(xf.ox + p[0] * xf.sx) + ' ' + fmt(xf.oy + p[1] * xf.sy)).join('L') + 'Z')
      .join('');
  }

  // Full mask -> path pipeline used by bucket fill and brush strokes.
  function maskToPathD(mask, xf, eps) {
    const loops = traceContours(mask).map((l) => simplifyLoop(l, eps === undefined ? 0.75 : eps));
    return loopsToPathD(loops, xf);
  }

  // Bucket fill: barrier = outline mask; gap closes outline gaps; fill expands back under the outline.
  function bucketRegion(outline, x, y, gap) {
    const barrier = dilate(outline, gap);
    if (x < 0 || y < 0 || x >= outline.w || y >= outline.h) return { error: 'outside' };
    if (barrier.data[y * outline.w + x]) return { error: 'outline' };
    const fill = floodFill(barrier, x, y);
    if (fill.touchesEdge) return { error: 'open' };
    return { mask: dilate(fill.mask, gap + 1), count: fill.count };
  }

  return {
    makeMask: makeMask,
    maskFromAlpha: maskFromAlpha,
    dilate: dilate,
    floodFill: floodFill,
    traceContours: traceContours,
    simplifyLoop: simplifyLoop,
    loopsToPathD: loopsToPathD,
    maskToPathD: maskToPathD,
    bucketRegion: bucketRegion,
  };
});
