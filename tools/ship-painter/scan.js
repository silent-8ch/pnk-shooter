// Scanned line drawing -> paintable ship SVG with a first pass of slot colors.
// Input is a grayscale PGM (P5) from tools/scan_to_pgm.gd (Godot decodes the scan).
// Run: node tools/ship-painter/scan.js <in.pgm> <out.svg>
//   or: node tools/ship-painter/scan.js --svg <traced.svg> <render.pgm> <out.svg>
// The --svg form keeps already-traced line art as the outline (its paths become slot 1) and only
// adds the fills under it; the PGM must be a render of that SVG's whole viewBox (scan_to_pgm.gd does it).
//
// The ink becomes slot 1 (outline). Every area the ink encloses becomes its own fill,
// tucked under the outline like a bucket fill, and gets a guessed slot. Inside areas that leak
// out through a break in the lines are still filled (hull) as long as the break is under
// SILHOUETTE_GAP, so the ship is solid. Slots:
//   largest area -> 2 hull; topmost central area -> 9 nose; areas low in the drawing -> 4 thrusters;
//   areas far out to the sides -> 8 wings; small central areas -> 3 glass; other small areas ->
//   5 accents; the rest alternate 6 panels / 7 trim.
// Repaint in the Ship Painter as needed. Pure logic plus a small CLI; Node built-ins only.
'use strict';

const R = require('./regions.js');

const INK_LEVEL = 140; // gray below this is ink
const GAP = 3; // px: closes small gaps in the lines (like the painter's bucket gap)
const SILHOUETTE_GAP = 10; // px: closes bigger gaps when finding the outside, so the whole ship is solid
const MIN_INK = 40; // px: smaller ink specks are dust
const MIN_REGION = 60; // px: smaller enclosed areas are left to the outline
// Painted colors per slot: the game's Factory palette (scripts/ships.gd).
const SLOT_COLORS = ['#e6e8eb', '#4a4f57', '#bfe3f2', '#8c939c', '#d0d4d9', '#b8bec6', '#ffffff', '#5d636b', '#9aa1aa'];
const SLOT_NAMES = ['Slot 1', 'Slot 2', 'Slot 3', 'Slot 4', 'Slot 5', 'Slot 6', 'Slot 7', 'Slot 8', 'Slot 9'];

function parsePgm(buf) {
  // Header: "P5" width height maxval, whitespace separated, then one byte per pixel.
  let pos = 0;
  const tokens = [];
  while (tokens.length < 4) {
    while (pos < buf.length && /\s/.test(String.fromCharCode(buf[pos]))) pos++;
    if (buf[pos] === 0x23) { while (pos < buf.length && buf[pos] !== 0x0a) pos++; continue; } // # comment
    let t = '';
    while (pos < buf.length && !/\s/.test(String.fromCharCode(buf[pos]))) t += String.fromCharCode(buf[pos++]);
    if (t === '') throw new Error('truncated PGM header');
    tokens.push(t);
  }
  pos++; // single whitespace after maxval
  if (tokens[0] !== 'P5') throw new Error('not a binary PGM (P5)');
  const w = parseInt(tokens[1], 10), h = parseInt(tokens[2], 10), max = parseInt(tokens[3], 10);
  if (!(w > 0 && h > 0) || max !== 255) throw new Error('unsupported PGM size or depth');
  if (buf.length - pos < w * h) throw new Error('truncated PGM data');
  return { w: w, h: h, data: Uint8Array.from(buf.subarray(pos, pos + w * h)) };
}

// 4-connected components of set pixels in `mask`, as floodFill results, biggest first.
function components(mask, minCount) {
  const inverse = R.makeMask(mask.w, mask.h);
  for (let i = 0; i < mask.data.length; i++) inverse.data[i] = mask.data[i] ? 0 : 1;
  const seen = new Uint8Array(mask.data.length);
  const out = [];
  for (let i = 0; i < mask.data.length; i++) {
    if (!mask.data[i] || seen[i]) continue;
    const c = R.floodFill(inverse, i % mask.w, Math.floor(i / mask.w));
    for (let j = 0; j < c.mask.data.length; j++) if (c.mask.data[j]) seen[j] = 1;
    if (c.count >= minCount) out.push(c);
  }
  return out.sort((a, b) => b.count - a.count);
}

function stats(mask) {
  let n = 0, sx = 0, sy = 0, x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let y = 0; y < mask.h; y++) {
    for (let x = 0; x < mask.w; x++) {
      if (!mask.data[y * mask.w + x]) continue;
      n++; sx += x; sy += y;
      if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
  }
  return { count: n, cx: n ? sx / n : 0, cy: n ? sy / n : 0, x0: x0, y0: y0, x1: x1, y1: y1 };
}

// Ink mask (dust removed) and the enclosed areas, each with its stats.
function analyze(gray, opts) {
  opts = opts || {};
  const level = opts.inkLevel || INK_LEVEL, gap = opts.gap === undefined ? GAP : opts.gap;
  const raw = R.makeMask(gray.w, gray.h);
  for (let i = 0; i < gray.data.length; i++) raw.data[i] = gray.data[i] < level ? 1 : 0;
  const ink = R.makeMask(gray.w, gray.h);
  for (const c of components(raw, opts.minInk || MIN_INK)) {
    for (let i = 0; i < ink.data.length; i++) if (c.mask.data[i]) ink.data[i] = 1;
  }
  const barrier = R.dilate(ink, gap);
  const open = R.makeMask(gray.w, gray.h);
  for (let i = 0; i < open.data.length; i++) open.data[i] = barrier.data[i] ? 0 : 1;
  const regions = components(open, opts.minRegion || MIN_REGION)
    .filter((c) => !c.touchesEdge) // the outside
    .map((c) => ({ mask: R.dilate(c.mask, gap + 1), stats: stats(c.mask) }));
  // Leftover inside the closed silhouette: areas whose lines don't quite meet.
  const solid = silhouette(ink, opts.silhouetteGap === undefined ? SILHOUETTE_GAP : opts.silhouetteGap);
  const rest = R.makeMask(gray.w, gray.h);
  for (let i = 0; i < rest.data.length; i++) {
    rest.data[i] = solid.data[i] && !ink.data[i] && !regions.some((r) => r.mask.data[i]) ? 1 : 0;
  }
  const leftover = stats(rest).count >= (opts.minRegion || MIN_REGION) ? R.dilate(rest, 1) : null;
  return { ink: ink, inkStats: stats(ink), regions: regions, leftover: leftover };
}

// Dilation by `r` px with a roughly round (octagonal) brush: alternating square and plus steps,
// so closing gaps doesn't leave square corners sticking out past the lines.
function roundDilate(mask, r) {
  let cur = mask;
  for (let k = 0; k < r; k++) {
    if (k % 2 === 0) { cur = R.dilate(cur, 1); continue; }
    const w = cur.w, h = cur.h, d = cur.data, out = R.makeMask(w, h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        out.data[i] = d[i] || (x > 0 && d[i - 1]) || (x < w - 1 && d[i + 1]) || (y > 0 && d[i - w]) || (y < h - 1 && d[i + w]) ? 1 : 0;
      }
    }
    cur = out;
  }
  return cur;
}

// Everything not reachable from outside once gaps under `gap` px are closed.
function silhouette(ink, gap) {
  // Work on a copy padded by gap + 1 so the outside connects all the way around, even when the
  // drawing runs close to the image edges.
  const pad = gap + 1, w = ink.w + 2 * pad, h = ink.h + 2 * pad;
  const big = R.makeMask(w, h);
  for (let y = 0; y < ink.h; y++) big.data.set(ink.data.subarray(y * ink.w, (y + 1) * ink.w), (y + pad) * w + pad);
  const barrier = roundDilate(big, gap);
  const outside = R.floodFill(barrier, 0, 0).mask;
  // Shrink back by `gap` (erode = dilate the outside) so the outline isn't fattened.
  const grown = roundDilate(outside, gap);
  const inside = R.makeMask(ink.w, ink.h);
  for (let y = 0; y < ink.h; y++) {
    for (let x = 0; x < ink.w; x++) {
      const i = (y + pad) * w + x + pad;
      inside.data[y * ink.w + x] = !outside.data[i] && !(grown.data[i] && !big.data[i]) ? 1 : 0;
    }
  }
  return inside;
}

// Guessed slot per region (same order as `regions`), see the header comment.
function guessSlots(inkStats, regions) {
  const width = Math.max(1, inkStats.x1 - inkStats.x0), height = Math.max(1, inkStats.y1 - inkStats.y0);
  const midX = (inkStats.x0 + inkStats.x1) / 2;
  const total = regions.reduce((s, r) => s + r.stats.count, 0) || 1;
  const slots = regions.map(() => 0);
  if (!regions.length) return slots;
  slots[0] = 2; // largest: hull (regions are biggest first)
  let nose = -1;
  regions.forEach((r, i) => {
    if (i === 0 || Math.abs(r.stats.cx - midX) > width * 0.15) return;
    if (nose === -1 || r.stats.cy < regions[nose].stats.cy) nose = i;
  });
  if (nose !== -1 && (regions[nose].stats.cy - inkStats.y0) < height * 0.35) slots[nose] = 9;
  let alt = 0;
  regions.forEach((r, i) => {
    if (slots[i]) return;
    const share = r.stats.count / total;
    const fromMid = Math.abs(r.stats.cx - midX) / width;
    const down = (r.stats.cy - inkStats.y0) / height;
    if (down > 0.8) slots[i] = 4;
    else if (fromMid > 0.3) slots[i] = 8;
    else if (share < 0.03 && fromMid < 0.15 && down < 0.6) slots[i] = 3;
    else if (share < 0.03) slots[i] = 5;
    else slots[i] = (alt++ % 2) ? 7 : 6;
  });
  return slots;
}

// Region fills (hull first) as [{slot, d}], path data mapped through xf (see regions.loopsToPathD).
function regionFills(a, xf) {
  const slots = guessSlots(a.inkStats, a.regions);
  const fills = [];
  if (a.leftover) fills.push({ slot: 2, d: R.maskToPathD(a.leftover, xf) }); // under the areas
  a.regions.forEach((r, i) => fills.push({ slot: slots[i], d: R.maskToPathD(r.mask, xf) }));
  return fills.filter((f) => f.d);
}

function fillPaths(fills) {
  return fills.map((f) =>
    '\n<path data-slot="' + f.slot + '" fill="' + SLOT_COLORS[f.slot - 1] + '" d="' + f.d + '"/>').join('');
}

// Paintable ship SVG (the format the Ship Painter saves): fills only, outline on top.
function scanToSvg(gray, opts) {
  const a = analyze(gray, opts);
  const fills = regionFills(a);
  const ink = R.maskToPathD(a.ink);
  if (ink) fills.push({ slot: 1, d: ink });
  const paths = fillPaths(fills);
  return '<?xml version="1.0" standalone="no"?>\n' +
    '<svg version="1.0" xmlns="http://www.w3.org/2000/svg"\n' +
    ' width="' + gray.w + '" height="' + gray.h + '" viewBox="0 0 ' + gray.w + ' ' + gray.h + '"\n' +
    ' preserveAspectRatio="xMidYMid meet" data-slots="9" data-slot-names="' + SLOT_NAMES.join(',') + '">\n' +
    '<g data-layer="fills" stroke="none">' + paths + '\n</g>\n</svg>\n';
}

// Traced line art + a render of it -> the same SVG with its shapes as slot 1 (outline) and a
// fills layer under them, as if painted in the Ship Painter. Repainting a result works too
// (old fills are replaced).
function paintTracedSvg(svg, gray, opts) {
  const root = svg.match(/<svg\b[^>]*>/);
  if (!root) throw new Error('not an SVG');
  const vb = (root[0].match(/viewBox="([^"]+)"/) || [])[1];
  if (!vb) throw new Error('SVG has no viewBox');
  const [vx, vy, vw, vh] = vb.trim().split(/[\s,]+/).map(Number);
  // The result's viewBox starts at 0 0 (the game reads fill coordinates that way, e.g. for
  // thruster anchors): the traced shapes move into a translate group, fills are made in place.
  const xf = { sx: vw / gray.w, sy: vh / gray.h, ox: 0, oy: 0 };
  const fills = regionFills(analyze(gray, opts), xf);
  let attrs = root[0].replace(/\s*data-slots?(-names)?="[^"]*"/g, '');
  attrs = attrs.replace(/viewBox="[^"]*"/, 'viewBox="0 0 ' + vw + ' ' + vh + '"');
  attrs = attrs.replace(/>$/, ' data-slots="9" data-slot-names="' + SLOT_NAMES.join(',') + '">');
  const body = svg.slice(root.index + root[0].length, svg.lastIndexOf('</svg>'))
    .replace(/<g data-layer="fills"[\s\S]*?<\/g>/, '') // repainting: drop old fills
    .replace(/<path\b(?![^>]*data-slot)/g, '<path data-slot="1" fill="' + SLOT_COLORS[0] + '"');
  const shapes = vx || vy ? '\n<g transform="translate(' + -vx + ',' + -vy + ')">' + body + '</g>\n' : body;
  return svg.slice(0, root.index) + attrs + '\n<g data-layer="fills" stroke="none">' + fillPaths(fills) + '\n</g>' +
    shapes + '</svg>\n';
}

module.exports = {
  paintTracedSvg: paintTracedSvg, parsePgm: parsePgm, components: components, analyze: analyze, silhouette: silhouette, roundDilate: roundDilate, guessSlots: guessSlots, scanToSvg: scanToSvg };

if (require.main === module) {
  const fs = require('fs');
  const args = process.argv.slice(2);
  if (args[0] === '--svg' && args.length === 4) {
    fs.writeFileSync(args[3], paintTracedSvg(fs.readFileSync(args[1], 'utf8'), parsePgm(fs.readFileSync(args[2]))));
    process.exit(0);
  }
  const [src, dst] = args;
  if (!src || !dst) {
    console.error('usage: node tools/ship-painter/scan.js <in.pgm> <out.svg>  or  --svg <traced.svg> <render.pgm> <out.svg>');
    process.exit(1);
  }
  fs.writeFileSync(dst, scanToSvg(parsePgm(fs.readFileSync(src))));
}
