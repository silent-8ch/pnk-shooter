// Ship Painter core: parse a ship SVG, tag each shape with a color slot, export.
// Pure string logic (no DOM) so it runs in the browser (window.ShipPainter) and in node tests.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.ShipPainter = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const SHAPE_TAGS = ['path', 'polygon', 'polyline', 'rect', 'circle', 'ellipse'];
  const SHAPE_RE = new RegExp('<(' + SHAPE_TAGS.join('|') + ')\\b([^>]*?)(/?)>', 'g');
  const ROOT_RE = /<svg\b([^>]*?)(\/?)>/;
  // Fill layer: one group placed first inside <svg>, so it renders beneath the outlines.
  const FILLS_RE = /\n?<g data-layer="fills"[^>]*>([\s\S]*?)<\/g>/;
  const FILL_PATH_RE = /<path\b([^>]*?)\/?>/g;
  const DEFAULT_COLORS = ['#ffffff', '#ff7ad9', '#7ad9ff', '#ffd97a', '#9dff7a', '#d97aff', '#ff9d7a', '#7a7aff', '#ff4b4b'];
  const MAX_SLOTS = 9; // keyboard shortcuts 1-9

  function attrRe(name) {
    return new RegExp('(^|\\s)' + name + '\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')');
  }

  function getAttr(attrs, name) {
    const m = attrRe(name).exec(attrs);
    if (!m) return null;
    return m[2] !== undefined ? m[2] : m[3];
  }

  function setAttr(attrs, name, value) {
    const re = attrRe(name);
    const replacement = '$1' + name + '="' + value + '"';
    if (re.test(attrs)) return attrs.replace(re, replacement);
    return attrs.replace(/\s*$/, '') + ' ' + name + '="' + value + '"';
  }

  function removeAttr(attrs, name) {
    return attrs.replace(attrRe(name), '');
  }

  function escapeAttr(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function unescapeAttr(s) {
    return String(s).replace(/&quot;/g, '"').replace(/&gt;/g, '>').replace(/&lt;/g, '<').replace(/&amp;/g, '&');
  }

  function sanitizeName(s) {
    return String(s).replace(/,/g, ' ').replace(/\s+/g, ' ').trim();
  }

  function isHexColor(s) {
    return typeof s === 'string' && /^#[0-9a-fA-F]{6}$/.test(s);
  }

  function defaultColor(k) {
    return DEFAULT_COLORS[(k - 1) % DEFAULT_COLORS.length];
  }

  function suggestName(filename) {
    return String(filename || 'ship').replace(/^.*[\\/]/, '').replace(/\.svg$/i, '').replace(/\.skin$/i, '') || 'ship';
  }

  function findShapes(svg) {
    const out = [];
    const re = new RegExp(SHAPE_RE.source, 'g');
    let m;
    while ((m = re.exec(svg)) !== null) out.push({ tag: m[1], attrs: m[2] });
    return out;
  }

  function extractFills(svg) {
    const m = FILLS_RE.exec(svg);
    if (!m) return { svg: svg, fills: [] };
    const fills = [];
    const re = new RegExp(FILL_PATH_RE.source, 'g');
    let pm;
    while ((pm = re.exec(m[1])) !== null) {
      const d = getAttr(pm[1], 'd');
      if (!d) continue;
      const slot = parseInt(getAttr(pm[1], 'data-slot'), 10);
      fills.push({ slot: slot >= 1 ? slot : 1, d: unescapeAttr(d), fill: getAttr(pm[1], 'fill') });
    }
    return { svg: svg.replace(FILLS_RE, ''), fills: fills };
  }

  // Root viewBox as { x, y, w, h }; falls back to width/height.
  function getViewBox(svg) {
    const m = ROOT_RE.exec(svg);
    if (!m) throw new Error('Not an SVG document');
    const vb = getAttr(m[1], 'viewBox');
    if (vb) {
      const n = vb.trim().split(/[\s,]+/).map(Number);
      if (n.length === 4 && n.every(isFinite) && n[2] > 0 && n[3] > 0) return { x: n[0], y: n[1], w: n[2], h: n[3] };
    }
    const w = parseFloat(getAttr(m[1], 'width')), h = parseFloat(getAttr(m[1], 'height'));
    if (w > 0 && h > 0) return { x: 0, y: 0, w: w, h: h };
    throw new Error('SVG has no usable viewBox or width/height');
  }

  // Build editor state from an SVG string. Accepts raw potrace output or a previous export.
  function parseShip(text, name) {
    if (typeof text !== 'string' || !ROOT_RE.test(text)) throw new Error('Not an SVG document');
    const extracted = extractFills(text);
    const svg = extracted.svg;
    const rootAttrs = ROOT_RE.exec(svg)[1];
    const found = findShapes(svg);
    if (found.length === 0) throw new Error('SVG contains no shapes (path, polygon, rect, circle, ellipse)');

    let slotCount = parseInt(getAttr(rootAttrs, 'data-slots'), 10);
    if (!(slotCount >= 1)) slotCount = 1;

    const shapes = found.map(function (s) {
      const slot = parseInt(getAttr(s.attrs, 'data-slot'), 10);
      return { slot: slot >= 1 ? slot : 1, fill: getAttr(s.attrs, 'fill') };
    });
    const fills = extracted.fills;
    shapes.concat(fills).forEach(function (s) { if (s.slot > slotCount) slotCount = s.slot; });
    slotCount = Math.min(slotCount, MAX_SLOTS);
    shapes.concat(fills).forEach(function (s) { if (s.slot > slotCount) s.slot = 1; });

    const namesAttr = getAttr(rootAttrs, 'data-slot-names');
    const names = namesAttr ? unescapeAttr(namesAttr).split(',') : [];
    const slots = [];
    for (let k = 1; k <= slotCount; k++) {
      const first = shapes.concat(fills).find(function (s) { return s.slot === k && isHexColor(s.fill); });
      slots.push({
        name: sanitizeName(names[k - 1] || '') || 'Slot ' + k,
        color: first ? first.fill.toLowerCase() : defaultColor(k),
      });
    }

    return {
      name: suggestName(name),
      svg: svg,
      shapes: shapes.map(function (s) { return { slot: s.slot }; }),
      fills: fills.map(function (f) { return { slot: f.slot, d: f.d }; }),
      slots: slots,
    };
  }

  function clone(state) {
    return JSON.parse(JSON.stringify(state));
  }

  function setSlot(state, shapeIndex, slot) {
    if (shapeIndex < 0 || shapeIndex >= state.shapes.length) throw new RangeError('shape index out of range');
    if (slot < 1 || slot > state.slots.length) throw new RangeError('slot out of range');
    state.shapes[shapeIndex].slot = slot;
    return state;
  }

  // Add a fill path under the outlines. An identical path already present is re-slotted instead.
  function addFill(state, slot, d) {
    if (slot < 1 || slot > state.slots.length) throw new RangeError('slot out of range');
    if (typeof d !== 'string' || !/^\s*M/i.test(d)) throw new Error('fill needs path data');
    const existing = state.fills.findIndex(function (f) { return f.d === d; });
    if (existing !== -1) { state.fills[existing].slot = slot; return existing; }
    state.fills.push({ slot: slot, d: d });
    return state.fills.length - 1;
  }

  function setFillSlot(state, fillIndex, slot) {
    if (fillIndex < 0 || fillIndex >= state.fills.length) throw new RangeError('fill index out of range');
    if (slot < 1 || slot > state.slots.length) throw new RangeError('slot out of range');
    state.fills[fillIndex].slot = slot;
    return state;
  }

  function removeFill(state, fillIndex) {
    if (fillIndex < 0 || fillIndex >= state.fills.length) throw new RangeError('fill index out of range');
    state.fills.splice(fillIndex, 1);
    return state;
  }

  // Assign every outline shape (not fills) to one slot.
  function assignAll(state, slot) {
    if (slot < 1 || slot > state.slots.length) throw new RangeError('slot out of range');
    state.shapes.forEach(function (s) { s.slot = slot; });
    return state;
  }

  function addSlot(state, name, color) {
    if (state.slots.length >= MAX_SLOTS) throw new RangeError('at most ' + MAX_SLOTS + ' slots');
    const k = state.slots.length + 1;
    state.slots.push({
      name: sanitizeName(name || '') || 'Slot ' + k,
      color: isHexColor(color) ? color.toLowerCase() : defaultColor(k),
    });
    return k;
  }

  // Remove a slot; its shapes move to slot 1 (or the new slot 1), higher slots renumber down.
  function removeSlot(state, slot) {
    if (state.slots.length <= 1) throw new RangeError('cannot remove the last slot');
    if (slot < 1 || slot > state.slots.length) throw new RangeError('slot out of range');
    state.slots.splice(slot - 1, 1);
    state.shapes.concat(state.fills).forEach(function (s) {
      if (s.slot === slot) s.slot = 1;
      else if (s.slot > slot) s.slot -= 1;
    });
    return state;
  }

  function renameSlot(state, slot, name) {
    state.slots[slot - 1].name = sanitizeName(name) || 'Slot ' + slot;
    return state;
  }

  function setSlotColor(state, slot, color) {
    if (!isHexColor(color)) throw new Error('color must be #rrggbb');
    state.slots[slot - 1].color = color.toLowerCase();
    return state;
  }

  function countBySlot(state) {
    const counts = state.slots.map(function () { return 0; });
    state.shapes.forEach(function (s) { counts[s.slot - 1] += 1; });
    return counts;
  }

  function countFillsBySlot(state) {
    const counts = state.slots.map(function () { return 0; });
    state.fills.forEach(function (f) { counts[f.slot - 1] += 1; });
    return counts;
  }

  // Serialize the painted ship. Everything outside the root/shape tags is preserved byte-for-byte.
  // opts.indexAttr adds data-idx="i" to each shape and data-fidx="j" to each fill (editor hit-testing).
  // opts.outlinesOnly omits the fill layer; opts.solid paints every outline that color (for rasterizing).
  function exportSvg(state, opts) {
    opts = opts || {};
    const names = state.slots.map(function (s) { return s.name; }).join(',');
    let out = state.svg.replace(ROOT_RE, function (m, attrs, close) {
      attrs = setAttr(attrs, 'data-slots', String(state.slots.length));
      attrs = setAttr(attrs, 'data-slot-names', escapeAttr(names));
      return '<svg' + attrs + close + '>';
    });
    let i = 0;
    out = out.replace(new RegExp(SHAPE_RE.source, 'g'), function (m, tag, attrs, close) {
      const slot = state.shapes[i].slot;
      attrs = setAttr(attrs, 'data-slot', String(slot));
      attrs = setAttr(attrs, 'fill', opts.solid || state.slots[slot - 1].color);
      attrs = opts.indexAttr ? setAttr(attrs, 'data-idx', String(i)) : removeAttr(attrs, 'data-idx');
      i += 1;
      return '<' + tag + attrs + close + '>';
    });
    const fills = state.fills || [];
    if (fills.length && !opts.outlinesOnly) {
      const group = '\n<g data-layer="fills" stroke="none">' + fills.map(function (f, j) {
        return '\n<path data-slot="' + f.slot + '" fill="' + state.slots[f.slot - 1].color + '"' +
          (opts.indexAttr ? ' data-fidx="' + j + '"' : '') + ' d="' + escapeAttr(f.d) + '"/>';
      }).join('') + '\n</g>';
      out = out.replace(ROOT_RE, function (m) { return m + group; });
    }
    return out;
  }

  function exportManifest(state) {
    const counts = countBySlot(state);
    const fillCounts = countFillsBySlot(state);
    return {
      ship: state.name,
      file: state.name + '.svg',
      slots: state.slots.map(function (s, i) {
        return { index: i + 1, name: s.name, color: s.color, shapes: counts[i], fills: fillCounts[i] };
      }),
      shapes: state.shapes.map(function (s) { return s.slot; }),
      fills: state.fills.map(function (f) { return f.slot; }),
    };
  }

  return {
    SHAPE_TAGS: SHAPE_TAGS,
    DEFAULT_COLORS: DEFAULT_COLORS,
    MAX_SLOTS: MAX_SLOTS,
    parseShip: parseShip,
    getViewBox: getViewBox,
    addFill: addFill,
    setFillSlot: setFillSlot,
    removeFill: removeFill,
    countFillsBySlot: countFillsBySlot,
    clone: clone,
    setSlot: setSlot,
    assignAll: assignAll,
    addSlot: addSlot,
    removeSlot: removeSlot,
    renameSlot: renameSlot,
    setSlotColor: setSlotColor,
    countBySlot: countBySlot,
    exportSvg: exportSvg,
    exportManifest: exportManifest,
    suggestName: suggestName,
    escapeAttr: escapeAttr,
    _getAttr: getAttr,
    _setAttr: setAttr,
  };
});
