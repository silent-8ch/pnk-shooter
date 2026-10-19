// Drawing sheets: a printable PDF of A4 pages to draw game art on, several items per page, and
// the reader that turns a scan of one back into straight, cropped PGMs for scan.js.
//   node tools/ship-painter/sheet.js pdf <out.pdf> [pages=all] [copy=0]   pages: comma-separated, from 1
//   node tools/ship-painter/sheet.js list                                  what is on each page
//   node tools/ship-painter/sheet.js read <scan.pgm> <out dir> [size=600]  one <key>.pgm per drawing
// The scan PGM must be the whole page at full resolution:
//   Godot --headless -s tools/scan_to_pgm.gd -- "Scan 6.jpeg" full.pgm 0
//   node tools/ship-painter/sheet.js read full.pgm out/
//   node tools/ship-painter/scan.js out/ship-1.pgm ship.svg
//
// Each page has four black corner squares (the top-left one has a white hole, so a scan that is
// rotated or upside down still reads), a light gray box, and a row of CODE_BITS cells under the
// box: the sheet number in ID_BITS bits then a CHECK_BITS checksum, filled = 1. The sheet number
// is the page's index in PAGES times COPIES plus a copy number, so reprints are told apart.
// In the box: a numbered note per item saying what to draw, and per item a dashed frame the size
// it has in game, at MM_PER_PX for every item, so the sheets show how big things are next to each
// other. Frames are packed onto the page in PAGES order (see place()).
// The reader finds the squares, maps the page onto the scan through them (a homography, so skew
// and perspective from a phone photo are fine), checks the code, and samples each frame:
//   fit 'frame' -> exactly the frame, OUT_SCALE px per game px (keeps frames of an animation and
//                  tile edges lined up, and the size true);
//   fit 'ink'   -> the drawing anywhere in the item's cell, cropped to the ink and scaled to `size` px
//                  on its longer side, like scan_to_pgm.gd (ships are scaled to a set height in game
//                  anyway, so the frame is only a guide).
// Light gray guides print above the ink level and are washed out to white.
// Layout is in mm, y down, on a 210 x 297 page. Node built-ins only.
'use strict';

const PAGE = { w: 210, h: 297 };
const MARKER = 12; // mm, side of a corner square
const HOLE = 5; // mm, side of the white hole in the top-left square
const MARKERS = [[16, 16], [194, 16], [194, 281], [16, 281]]; // centers: TL, TR, BR, BL
const BOX = { x0: 12, y0: 26, x1: 198, y1: 270 }; // the drawing area
const BOX_INSET = 2; // mm: frames and sampling stay this far inside the box line
const ID_BITS = 12;
const CHECK_BITS = 4;
const CODE_BITS = ID_BITS + CHECK_BITS;
const CELL = 7; // mm, code cell side
const CELL_PITCH = 9; // mm
const CELL_Y = 277.5; // mm, top of the code cells
const CELL_X = (PAGE.w - (CODE_BITS - 1) * CELL_PITCH - CELL) / 2;
const GUIDE_GRAY = 0.82; // fill of guides: lighter than INK_LEVEL so they never count as drawing
const TEXT_GRAY = 0.3;
const INK_LEVEL = 128; // gray below this is ink when finding marks
const GUIDE_LEVEL = 175; // gray above this is paper in the output
const MIN_INK_PIXELS = 6; // rows/columns with fewer dark pixels are dust (as in scan_to_pgm.gd)
const MARGIN = 0.04; // crop margin, of the ink's longer side (as in scan_to_pgm.gd)
const MAX_ID = (1 << ID_BITS) - 1;
const COPIES = 16; // sheet numbers per page
const MM_PER_PX = 1.25; // mm on paper per game px, the same for every item
const OUT_SCALE = 8; // px per game px in a 'frame' fit result
const HEADER_TOP = 10; // mm at the top of the box for the page title, above the notes
const HEADER_PAD = 2; // mm under the notes
const NOTE_SIZE = 6; // pt
const NOTE_LINE = 2.5; // mm between note lines
const NOTE_CHARS = 165; // a note line wraps at this many characters
const LABEL_H = 5; // mm above each frame for its number and size
const GAP = 4; // mm between packed items

// Everything there is to draw. size is in game px (w, h); obstacles take theirs from
// assets/obstacles/pieces.json. mm (optional) prints the frame at that size instead of at
// MM_PER_PX, for things the game scales anyway. cell (mm, optional) is room around the frame
// that is kept too.
const PIECES = require('../../assets/obstacles/pieces.json').pieces;
function piece(id) {
  const p = PIECES.find((q) => q.id === id);
  if (!p) throw new Error('no piece ' + id + ' in pieces.json');
  return { key: id, name: p.name, size: p.size, fit: 'frame', up: false, note: p.description };
}
function frames(key, name, size, note) {
  return [0, 1, 2, 3].map((i) => ({ key: key + '_' + i, name: name + ' frame ' + (i + 1) + ' of 4', size: size, fit: 'frame',
    up: true, note: note[i] }));
}
const ITEMS = [
  { key: 'ship', name: 'Player ship', size: [44, 44], fit: 'ink', up: true, mm: [182, 182],
    note: 'Your ship from above, nose pointing up. Draw it big: the game shrinks it to 44 px tall (enemies use ships ' +
      'too, at 36 px). Close every shape so it can be painted.' },
].concat(
  ['asteroid_s', 'asteroid_m', 'asteroid_l', 'debris', 'girder', 'girder_end_l', 'girder_end_r', 'hull', 'hull_end_l',
    'hull_end_r', 'solar_panel', 'ring_arc', 'reactor'].map(piece),
  frames('pickup', 'Pickup', [114, 68], [
    'A floating pickup the ship flies into. Loops at 12 frames a second; this is the starting pose.',
    'A little different from frame 1, same size and spot.',
    'Next step of the loop.',
    'Leads back into frame 1.']),
  frames('explosion', 'Explosion', [41, 56], [
    'Plays once at 12 frames a second. The first flash, small and bright.',
    'The fireball, biggest.',
    'Breaking up into flames.',
    'Last wisps of smoke.']),
  frames('bullet', 'Bullet', [18, 44], [
    'A laser bolt flying up. Loops at 12 frames a second. Tip at the top of the frame.',
    'Tip at the top of the frame.',
    'Tip at the top of the frame.',
    'Tip at the top of the frame.']));

// The pages, each a set of things that belong together, in sheet-number order. Only add pages at
// the end and never change one: a sheet's number names its page, and a page's items and their
// order fix where they are printed.
const PAGES = [
  { title: 'Ship', items: ['ship'] },
  { title: 'Asteroids', items: ['asteroid_l', 'asteroid_s', 'asteroid_m'] },
  { title: 'Station wreckage: hull and girders', items: ['hull', 'hull_end_l', 'hull_end_r', 'girder', 'girder_end_l',
    'girder_end_r', 'debris'] },
  { title: 'Station wreckage: parts', items: ['solar_panel', 'reactor', 'ring_arc'] },
  { title: 'Bullets and explosions', items: ['explosion_0', 'explosion_1', 'explosion_2', 'explosion_3', 'bullet_0', 'bullet_1',
    'bullet_2', 'bullet_3'] },
  { title: 'Pickups (1 of 2)', items: ['pickup_0', 'pickup_1'] },
  { title: 'Pickups (2 of 2)', items: ['pickup_2', 'pickup_3'] },
];

function item(key) {
  const it = ITEMS.find((i) => i.key === key);
  if (!it) throw new Error('unknown item ' + key);
  return it;
}

function sheetId(page, copy) {
  if (!Number.isInteger(page) || page < 0 || page >= PAGES.length) throw new Error('page must be 1..' + PAGES.length);
  if (!Number.isInteger(copy) || copy < 0 || copy >= COPIES) throw new Error('copy must be 0..' + (COPIES - 1));
  return page * COPIES + copy;
}

// What a sheet number is: { page, copy }, or null if no page has it.
function sheetPage(id) {
  const page = Math.floor(id / COPIES);
  return page < PAGES.length ? { page: page, copy: id % COPIES } : null;
}

// Where a page's items go: [{ n, item, out, frame, cell }] in mm, n numbering them from 1 and out
// naming the reader's file (key, plus -n when the key is on the page more than once).
// Guillotine packing in PAGES order: each item takes the topmost, then leftmost, free space it
// fits in, and that space splits into the strip to its right and the rest below. Each row is then
// centered across the box. Throws if the page is too full.
function place(page) {
  const keys = PAGES[page].items;
  const x0 = BOX.x0 + BOX_INSET, y0 = BOX.y0 + headerHeight(page), w = BOX.x1 - BOX.x0 - 2 * BOX_INSET;
  const h = BOX.y1 - BOX_INSET - y0;
  let free = [{ x: 0, y: 0, w: w + GAP, h: h + GAP }];
  const out = [];
  keys.forEach((key, i) => {
    const it = item(key);
    const fw = it.mm ? it.mm[0] : it.size[0] * MM_PER_PX, fh = it.mm ? it.mm[1] : it.size[1] * MM_PER_PX;
    const cw = it.cell ? it.cell[0] : fw, ch = it.cell ? it.cell[1] : fh;
    const pw = cw + GAP, ph = LABEL_H + ch + GAP;
    free.sort((a, b) => a.y - b.y || a.x - b.x);
    const k = free.findIndex((f) => f.w >= pw - 1e-9 && f.h >= ph - 1e-9);
    if (k < 0) throw new Error('page ' + (page + 1) + ' is too full for ' + key);
    const f = free.splice(k, 1)[0];
    free.push({ x: f.x + pw, y: f.y, w: f.w - pw, h: ph }, { x: f.x, y: f.y + ph, w: f.w, h: f.h - ph });
    const repeats = keys.filter((q) => q === key).length > 1;
    const n = keys.slice(0, i + 1).filter((q) => q === key).length;
    out.push({ n: i + 1, item: it, out: repeats ? key + '-' + n : key, x: f.x, y: f.y, cw: cw, ch: ch, fw: fw, fh: fh });
  });
  // Center each row (items that share a top) across the box.
  for (const y of new Set(out.map((o) => o.y))) {
    const row = out.filter((o) => o.y === y);
    const shift = (w - Math.max(...row.map((o) => o.x + o.cw))) / 2;
    for (const o of row) o.x += shift;
  }
  return out.map((o) => {
    const cell = { x: x0 + o.x, y: y0 + o.y + LABEL_H, w: o.cw, h: o.ch };
    const frame = { x: cell.x + (o.cw - o.fw) / 2, y: cell.y + (o.ch - o.fh) / 2, w: o.fw, h: o.fh };
    return { n: o.n, item: o.item, out: o.out, frame: frame, cell: cell };
  });
}

// A page's notes, one per distinct item, wrapped: ['1-4 Player ship (44 x 44 px): ...', ...].
// Items are numbered from 1 in PAGES order, as place() numbers them.
function notes(page) {
  const lines = [];
  const keys = PAGES[page].items;
  for (const key of new Set(keys)) {
    const it = item(key);
    const ns = keys.map((k, i) => (k === key ? i + 1 : 0)).filter((n) => n);
    const tag = ns.length > 1 ? ns[0] + '-' + ns[ns.length - 1] : String(ns[0]);
    lines.push(...wrap(tag + '  ' + it.name + ' (' + it.size[0] + ' x ' + it.size[1] + ' px' + (it.up ? ', this way up' : '') +
      '): ' + it.note, NOTE_CHARS));
  }
  return lines;
}

// mm at the top of the box for a page's title and notes: as much as they need.
function headerHeight(page) {
  return HEADER_TOP + notes(page).length * NOTE_LINE + HEADER_PAD;
}

function wrap(text, chars) {
  const lines = [];
  let line = '';
  for (const word of text.split(/\s+/)) {
    if (line && line.length + 1 + word.length > chars) { lines.push(line); line = word; } else line = line ? line + ' ' + word : word;
  }
  if (line) lines.push(line);
  return lines;
}

function checksum(id) {
  return ((id ^ (id >> 4) ^ (id >> 8)) & 15) ^ 0b1010;
}

// The code row for a sheet number, most significant bit first.
function codeBits(id) {
  if (!Number.isInteger(id) || id < 0 || id > MAX_ID) throw new Error('sheet number must be 0..' + MAX_ID);
  const v = (id << CHECK_BITS) | checksum(id);
  const bits = [];
  for (let i = CODE_BITS - 1; i >= 0; i--) bits.push((v >> i) & 1);
  return bits;
}

// Sheet number from a code row, or -1 if the checksum fails.
function decodeBits(bits) {
  let v = 0;
  for (const b of bits) v = (v << 1) | (b ? 1 : 0);
  const id = v >> CHECK_BITS;
  return (v & 15) === checksum(id) ? id : -1;
}

function cellRect(i) {
  return { x: CELL_X + i * CELL_PITCH, y: CELL_Y, w: CELL, h: CELL };
}

// Everything printed on a sheet, as shapes in page mm: {rect, gray, fill|stroke, dash?}, {line},
// {poly} and {text}.
function layout(id) {
  const sheet = sheetPage(id);
  if (!sheet) throw new Error('sheet ' + id + ' has no page');
  const shapes = [];
  for (const [cx, cy] of MARKERS) shapes.push({ rect: [cx - MARKER / 2, cy - MARKER / 2, MARKER, MARKER], gray: 0, fill: true });
  const [hx, hy] = MARKERS[0];
  shapes.push({ rect: [hx - HOLE / 2, hy - HOLE / 2, HOLE, HOLE], gray: 1, fill: true });
  codeBits(id).forEach((b, i) => {
    const c = cellRect(i);
    shapes.push({ rect: [c.x, c.y, c.w, c.h], gray: b ? 0 : GUIDE_GRAY, fill: !!b, width: 0.3 });
  });
  shapes.push({ rect: [BOX.x0, BOX.y0, BOX.x1 - BOX.x0, BOX.y1 - BOX.y0], gray: GUIDE_GRAY, fill: false, width: 0.4 });
  for (const s of place(sheet.page)) {
    const f = s.frame, c = s.cell;
    if (s.item.cell) shapes.push({ rect: [c.x, c.y, c.w, c.h], gray: GUIDE_GRAY, fill: false, width: 0.3 });
    shapes.push({ rect: [f.x, f.y, f.w, f.h], gray: GUIDE_GRAY, fill: false, width: 0.4, dash: 2 });
    const mx = f.x + f.w / 2, my = f.y + f.h / 2;
    shapes.push({ line: [[mx - 2, my], [mx + 2, my]], gray: GUIDE_GRAY, width: 0.3 });
    shapes.push({ line: [[mx, my - 2], [mx, my + 2]], gray: GUIDE_GRAY, width: 0.3 });
    const ly = c.y - 1.2;
    shapes.push({ text: String(s.n), x: c.x, y: ly, size: 8, gray: TEXT_GRAY, bold: true });
    const label = s.item.size[0] + 'x' + s.item.size[1];
    shapes.push({ text: label, x: c.x + 3.5, y: ly, size: 6, gray: TEXT_GRAY });
    if (s.item.up) {
      const ax = c.x + 3.5 + label.length * 1.2 + 2;
      shapes.push({ poly: [[ax, ly - 2.6], [ax - 1.4, ly], [ax + 1.4, ly]], gray: TEXT_GRAY });
    }
  }
  const n = String(id).padStart(4, '0');
  const p = sheetPage(id);
  shapes.push({ text: 'PNK SHOOTER  -  SHEET ' + n + '  -  PAGE ' + (p.page + 1) + ' OF ' + PAGES.length +
    (p.copy ? '  (COPY ' + (p.copy + 1) + ')' : ''), x: 26, y: 16.5, size: 12, gray: TEXT_GRAY, bold: true });
  shapes.push({ text: 'Fill each dashed frame: only what is inside it is kept. Keep the corner squares and code clear, scan the whole ' +
    'page. One scale on every page: ' + MM_PER_PX + ' mm = 1 px in game.', x: 26, y: 21, size: 6, gray: TEXT_GRAY });
  shapes.push({ text: PAGES[sheet.page].title, x: BOX.x0 + 3, y: BOX.y0 + 5.5, size: 10, gray: TEXT_GRAY, bold: true });
  notes(sheet.page).forEach((l, i) => {
    shapes.push({ text: l, x: BOX.x0 + 3, y: BOX.y0 + HEADER_TOP - 0.5 + i * NOTE_LINE, size: NOTE_SIZE, gray: TEXT_GRAY });
  });
  return shapes;
}

// --- PDF -------------------------------------------------------------------------------------

const PT = 72 / 25.4;

function num(v) {
  return (Math.round(v * 1000) / 1000).toString();
}

function pdfText(s) {
  return '(' + s.replace(/[\\()]/g, '\\$&') + ')';
}

function pageStream(id) {
  const X = (x) => num(x * PT), Y = (y) => num((PAGE.h - y) * PT);
  const ops = [];
  for (const s of layout(id)) {
    const g = num(s.gray);
    if (s.rect) {
      const [x, y, w, h] = s.rect;
      const r = X(x) + ' ' + Y(y + h) + ' ' + num(w * PT) + ' ' + num(h * PT) + ' re';
      const dash = s.dash ? '[' + num(s.dash * PT) + '] 0 d ' : '';
      ops.push(s.fill ? g + ' g ' + r + ' f' : g + ' G ' + num(s.width * PT) + ' w ' + dash + r + ' S' + (dash ? ' [] 0 d' : ''));
    } else if (s.line) {
      const [[x0, y0], [x1, y1]] = s.line;
      ops.push(g + ' G ' + num(s.width * PT) + ' w ' + X(x0) + ' ' + Y(y0) + ' m ' + X(x1) + ' ' + Y(y1) + ' l S');
    } else if (s.poly) {
      const pts = s.poly.map(([x, y], i) => X(x) + ' ' + Y(y) + (i ? ' l' : ' m'));
      ops.push(g + ' g ' + pts.join(' ') + ' h f');
    } else if (s.text) {
      ops.push('BT ' + g + ' g /' + (s.bold ? 'F2' : 'F1') + ' ' + num(s.size) + ' Tf ' + X(s.x) + ' ' + Y(s.y) + ' Td ' +
        pdfText(s.text) + ' Tj ET');
    }
  }
  return ops.join('\n') + '\n';
}

// A PDF with one sheet per number in `ids`.
function makePdf(ids) {
  if (!ids.length) throw new Error('no sheets');
  const objs = []; // objs[k] is object k + 1
  const add = (body) => { objs.push(body); return objs.length; };
  add('<< /Type /Catalog /Pages 2 0 R >>');
  add(null); // pages, filled in below
  const f1 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  const f2 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
  const kids = [];
  const box = '[0 0 ' + num(PAGE.w * PT) + ' ' + num(PAGE.h * PT) + ']';
  for (const id of ids) {
    const s = pageStream(id);
    const c = add('<< /Length ' + Buffer.byteLength(s) + ' >>\nstream\n' + s + 'endstream');
    kids.push(add('<< /Type /Page /Parent 2 0 R /MediaBox ' + box + ' /Contents ' + c + ' 0 R' +
      ' /Resources << /Font << /F1 ' + f1 + ' 0 R /F2 ' + f2 + ' 0 R >> >> >>'));
  }
  objs[1] = '<< /Type /Pages /Kids [' + kids.map((k) => k + ' 0 R').join(' ') + '] /Count ' + kids.length + ' >>';
  let out = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((body, i) => {
    offsets.push(Buffer.byteLength(out));
    out += (i + 1) + ' 0 obj\n' + body + '\nendobj\n';
  });
  const xref = Buffer.byteLength(out);
  out += 'xref\n0 ' + (objs.length + 1) + '\n0000000000 65535 f \n';
  for (const o of offsets) out += String(o).padStart(10, '0') + ' 00000 n \n';
  out += 'trailer\n<< /Size ' + (objs.length + 1) + ' /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF\n';
  return Buffer.from(out, 'latin1');
}

// --- Reading a scan --------------------------------------------------------------------------

// 4-connected dark blobs: [{count, cx, cy, x0, y0, x1, y1}]. One pass with a stack, so a
// full-page scan is fine.
function blobs(gray, level) {
  const { w, h, data } = gray;
  const label = new Int32Array(w * h);
  const stack = new Int32Array(w * h);
  const out = [];
  for (let start = 0; start < data.length; start++) {
    if (label[start] || data[start] >= level) continue;
    const b = { count: 0, cx: 0, cy: 0, x0: w, y0: h, x1: -1, y1: -1 };
    label[start] = out.length + 1;
    let top = 0;
    stack[top++] = start;
    while (top) {
      const i = stack[--top];
      const x = i % w, y = (i - x) / w;
      b.count++; b.cx += x; b.cy += y;
      if (x < b.x0) b.x0 = x; if (x > b.x1) b.x1 = x; if (y < b.y0) b.y0 = y; if (y > b.y1) b.y1 = y;
      const near = [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1];
      for (const j of near) {
        if (j >= 0 && !label[j] && data[j] < level) { label[j] = out.length + 1; stack[top++] = j; }
      }
    }
    b.cx /= b.count; b.cy /= b.count;
    out.push(b);
  }
  return out;
}

// Blobs shaped like corner squares, each marked ring (the hollow top-left one) or not.
// Size is judged against the scan: a page fills most of it, so a square is about
// MARKER / PAGE.h of its longer side; anything from a third to twice that is allowed.
function markerCandidates(gray) {
  const side = MARKER / PAGE.h * Math.max(gray.w, gray.h);
  const out = [];
  for (const b of blobs(gray, INK_LEVEL)) {
    const bw = b.x1 - b.x0 + 1, bh = b.y1 - b.y0 + 1;
    if (bw < side / 3 || bh < side / 3 || bw > side * 2 || bh > side * 2) continue;
    if (bw / bh > 1.5 || bh / bw > 1.5) continue;
    const fill = b.count / (bw * bh);
    const center = gray.data[Math.round(b.cy) * gray.w + Math.round(b.cx)];
    if (center >= INK_LEVEL && fill > 0.4) out.push({ x: b.cx, y: b.cy, ring: true, count: b.count });
    else if (center < INK_LEVEL && fill > 0.6) out.push({ x: b.cx, y: b.cy, ring: false, count: b.count });
  }
  return out;
}

function cross(o, a, b) {
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

function dist2(a, b) {
  return (a.x - b.x) ** 2 + (a.y - b.y) ** 2;
}

// The four corner squares in page order TL, TR, BR, BL, or null. The top-left is the ring;
// of the solid squares, the three spanning the biggest quad with it are the other corners.
function findMarkers(gray) {
  const cands = markerCandidates(gray);
  const rings = cands.filter((c) => c.ring).sort((a, b) => b.count - a.count);
  const solids = cands.filter((c) => !c.ring);
  let best = null, bestArea = 0;
  for (const tl of rings) {
    for (let i = 0; i < solids.length; i++) {
      for (let j = i + 1; j < solids.length; j++) {
        for (let k = j + 1; k < solids.length; k++) {
          const three = [solids[i], solids[j], solids[k]];
          three.sort((a, b) => dist2(tl, b) - dist2(tl, a));
          const br = three[0];
          const [a, b] = three.slice(1);
          const tr = cross(tl, a, br) > 0 ? a : b, bl = tr === a ? b : a;
          if (!(cross(tl, tr, br) > 0 && cross(tl, br, bl) > 0)) continue;
          const area = (cross(tl, tr, br) + cross(tl, br, bl)) / 2;
          if (area > bestArea) { bestArea = area; best = [tl, tr, br, bl]; }
        }
      }
    }
  }
  return best;
}

// Homography taking each src point to its dst point (4 pairs), as h[0..7] with h8 = 1.
function homography(src, dst) {
  const A = [];
  for (let i = 0; i < 4; i++) {
    const [x, y] = src[i], [u, v] = dst[i];
    A.push([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
    A.push([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
  }
  for (let c = 0; c < 8; c++) {
    let p = c;
    for (let r = c + 1; r < 8; r++) if (Math.abs(A[r][c]) > Math.abs(A[p][c])) p = r;
    if (Math.abs(A[p][c]) < 1e-12) throw new Error('corner squares are degenerate');
    [A[c], A[p]] = [A[p], A[c]];
    for (let r = 0; r < 8; r++) {
      if (r === c) continue;
      const f = A[r][c] / A[c][c];
      for (let k = c; k < 9; k++) A[r][k] -= f * A[c][k];
    }
  }
  return A.map((row, i) => row[8] / row[i]);
}

function project(H, x, y) {
  const d = H[6] * x + H[7] * y + 1;
  return [(H[0] * x + H[1] * y + H[2]) / d, (H[3] * x + H[4] * y + H[5]) / d];
}

function sample(gray, x, y) {
  const { w, h, data } = gray;
  if (x < 0 || y < 0 || x > w - 1 || y > h - 1) return 255;
  const x0 = Math.floor(x), y0 = Math.floor(y);
  const x1 = Math.min(x0 + 1, w - 1), y1 = Math.min(y0 + 1, h - 1);
  const fx = x - x0, fy = y - y0;
  const top = data[y0 * w + x0] * (1 - fx) + data[y0 * w + x1] * fx;
  const bot = data[y1 * w + x0] * (1 - fx) + data[y1 * w + x1] * fx;
  return top * (1 - fy) + bot * fy;
}

// Mean gray over the middle of each code cell -> bits.
function readBits(gray, H) {
  const bits = [];
  for (let i = 0; i < CODE_BITS; i++) {
    const c = cellRect(i);
    let sum = 0, n = 0;
    for (let v = 0.25; v <= 0.75; v += 0.05) {
      for (let u = 0.25; u <= 0.75; u += 0.05) {
        const [x, y] = project(H, c.x + u * c.w, c.y + v * c.h);
        sum += sample(gray, x, y); n++;
      }
    }
    bits.push(sum / n < INK_LEVEL ? 1 : 0);
  }
  return bits;
}

// Box-filter downscale (or plain resample when growing).
function resize(gray, w, h) {
  const out = new Uint8Array(w * h);
  const sx = gray.w / w, sy = gray.h / h;
  for (let y = 0; y < h; y++) {
    const ya = y * sy, yb = Math.max(ya + 1e-6, (y + 1) * sy);
    for (let x = 0; x < w; x++) {
      const xa = x * sx, xb = Math.max(xa + 1e-6, (x + 1) * sx);
      let sum = 0, area = 0;
      for (let yy = Math.floor(ya); yy < Math.ceil(yb) && yy < gray.h; yy++) {
        const wy = Math.min(yb, yy + 1) - Math.max(ya, yy);
        for (let xx = Math.floor(xa); xx < Math.ceil(xb) && xx < gray.w; xx++) {
          const wgt = wy * (Math.min(xb, xx + 1) - Math.max(xa, xx));
          sum += gray.data[yy * gray.w + xx] * wgt; area += wgt;
        }
      }
      out[y * w + x] = Math.round(sum / area);
    }
  }
  return { w: w, h: h, data: out };
}

// Bounding box of the ink, ignoring rows/columns with fewer than MIN_INK_PIXELS dark pixels.
function inkBox(gray) {
  const rows = new Int32Array(gray.h), cols = new Int32Array(gray.w);
  for (let y = 0; y < gray.h; y++) {
    for (let x = 0; x < gray.w; x++) if (gray.data[y * gray.w + x] < INK_LEVEL) { rows[y]++; cols[x]++; }
  }
  const first = (a) => a.findIndex((n) => n >= MIN_INK_PIXELS);
  const last = (a) => a.length - 1 - [...a].reverse().findIndex((n) => n >= MIN_INK_PIXELS);
  const x0 = first(cols), y0 = first(rows);
  if (x0 < 0 || y0 < 0) return null;
  return { x0: x0, y0: y0, x1: last(cols), y1: last(rows) };
}

// Page rect (mm) of the scan -> gray at the scan's own resolution, guides washed out to white.
function sampleRect(gray, H, pxPerMm, r) {
  const w = Math.max(1, Math.round(r.w * pxPerMm)), h = Math.max(1, Math.round(r.h * pxPerMm));
  const data = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [sx, sy] = project(H, r.x + (x + 0.5) / w * r.w, r.y + (y + 0.5) / h * r.h);
      const g = sample(gray, sx, sy);
      data[y * w + x] = g > GUIDE_LEVEL ? 255 : Math.round(g);
    }
  }
  return { w: w, h: h, data: data };
}

// The part of `gray` inside [x0, x1] x [y0, y1].
function crop(gray, x0, y0, x1, y1) {
  const cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  const data = new Uint8Array(cw * ch);
  for (let y = 0; y < ch; y++) data.set(gray.data.subarray((y0 + y) * gray.w + x0, (y0 + y) * gray.w + x0 + cw), y * cw);
  return { w: cw, h: ch, data: data };
}

// Scan of a sheet -> { id, page, copy, drawings: [{ n, item, out, gray }], empty: [n] }: each
// drawn item straightened with guides washed out. 'frame' items: the frame at OUT_SCALE px per
// game px. 'ink' items: their cell cropped to the ink plus a margin and scaled so the longer side
// is `size` px (like scan_to_pgm.gd). Items left blank are listed in `empty`.
function readSheet(gray, size) {
  size = size || 600;
  const m = findMarkers(gray);
  if (!m) throw new Error('corner squares not found');
  const H = homography(MARKERS, m.map((p) => [p.x, p.y]));
  const id = decodeBits(readBits(gray, H));
  if (id < 0) throw new Error('sheet code unreadable');
  const sheet = sheetPage(id);
  if (!sheet) throw new Error('sheet ' + id + ' is not a page this tool knows');
  const pxPerMm = Math.sqrt(dist2(m[0], m[1])) / (MARKERS[1][0] - MARKERS[0][0]);
  const drawings = [], empty = [];
  for (const s of place(sheet.page)) {
    const it = s.item;
    const g = sampleRect(gray, H, pxPerMm, it.fit === 'frame' ? s.frame : s.cell);
    const ink = inkBox(g);
    if (!ink) { empty.push(s.n); continue; }
    let res;
    if (it.fit === 'frame') {
      res = resize(g, it.size[0] * OUT_SCALE, it.size[1] * OUT_SCALE);
    } else {
      const pad = Math.round(Math.max(ink.x1 - ink.x0 + 1, ink.y1 - ink.y0 + 1) * MARGIN);
      const c = crop(g, Math.max(0, ink.x0 - pad), Math.max(0, ink.y0 - pad), Math.min(g.w - 1, ink.x1 + pad),
        Math.min(g.h - 1, ink.y1 + pad));
      const k = size / Math.max(c.w, c.h);
      res = resize(c, Math.max(1, Math.round(c.w * k)), Math.max(1, Math.round(c.h * k)));
    }
    drawings.push({ n: s.n, item: it, out: s.out, gray: res });
  }
  return { id: id, page: sheet.page, copy: sheet.copy, drawings: drawings, empty: empty };
}

function writePgm(gray) {
  return Buffer.concat([Buffer.from('P5\n' + gray.w + ' ' + gray.h + '\n255\n'), Buffer.from(gray.data)]);
}

module.exports = {
  PAGE: PAGE, MARKERS: MARKERS, MARKER: MARKER, HOLE: HOLE, BOX: BOX, NOTE_LINE: NOTE_LINE,
  CODE_BITS: CODE_BITS, MAX_ID: MAX_ID, COPIES: COPIES, MM_PER_PX: MM_PER_PX, OUT_SCALE: OUT_SCALE, ITEMS: ITEMS,
  PAGES: PAGES, headerHeight: headerHeight, codeBits: codeBits, decodeBits: decodeBits, sheetId: sheetId, sheetPage: sheetPage, place: place,
  notes: notes, wrap: wrap, cellRect: cellRect, layout: layout, makePdf: makePdf, blobs: blobs, findMarkers: findMarkers,
  homography: homography, project: project, resize: resize, readSheet: readSheet, writePgm: writePgm };

if (require.main === module) {
  const fs = require('fs');
  const path = require('path');
  const [cmd, ...args] = process.argv.slice(2);
  const usage = 'usage: node tools/ship-painter/sheet.js pdf <out.pdf> [pages=all] [copy=0]\n' +
    '       node tools/ship-painter/sheet.js list\n' +
    '       node tools/ship-painter/sheet.js read <scan.pgm> <out dir> [size=600]';
  try {
    if (cmd === 'pdf' && args[0]) {
      const pages = args[1] && args[1] !== 'all' ? args[1].split(',').map((p) => Number(p) - 1) : PAGES.map((_, i) => i);
      const copy = args[2] === undefined ? 0 : Number(args[2]);
      const ids = pages.map((p) => sheetId(p, copy));
      fs.writeFileSync(args[0], makePdf(ids));
      console.log(ids.length + ' sheets (copy ' + copy + ') -> ' + args[0]);
    } else if (cmd === 'list') {
      PAGES.forEach((p, i) => console.log('page ' + (i + 1) + ' ' + p.title + ': ' + place(i).map((s) => s.n + ' ' + s.out).join(', ')));
    } else if (cmd === 'read' && args[1]) {
      const S = require('./scan.js');
      const size = args[2] === undefined ? 600 : Number(args[2]);
      if (!Number.isInteger(size) || size < 16) throw new Error('size must be a whole number of px, at least 16');
      const r = readSheet(S.parsePgm(fs.readFileSync(args[0])), size);
      fs.mkdirSync(args[1], { recursive: true });
      console.log('sheet ' + r.id + ': page ' + (r.page + 1) + ', copy ' + r.copy);
      for (const d of r.drawings) {
        const file = path.join(args[1], d.out + (r.copy ? '-copy' + r.copy : '') + '.pgm');
        fs.writeFileSync(file, writePgm(d.gray));
        console.log('  ' + d.n + ' ' + d.item.name + ' -> ' + file + ' (' + d.gray.w + 'x' + d.gray.h + ')');
      }
      if (r.empty.length) console.log('  blank: ' + r.empty.join(', '));
    } else {
      console.error(usage);
      process.exit(1);
    }
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
