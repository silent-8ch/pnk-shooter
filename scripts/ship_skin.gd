class_name ShipSkin
## Applies a color palette to a painted ship SVG and renders it to a texture.
##
## Ships are painted with tools/ship-painter: each shape carries data-slot="k" (1-based)
## plus a default fill, and the root <svg> carries data-slots="n" and data-slot-names.
## apply_palette() swaps every shape's fill for palette[k - 1]; slots beyond the palette
## keep their default fill. Unpainted SVGs (no data-slot) pass through unchanged.
## Fill regions live in <g data-layer="fills"> placed first in the SVG, so they render under
## the outlines; they carry data-slot like any other shape and are recolored the same way.

const SHAPE_PATTERN := "<(?:path|polygon|polyline|rect|circle|ellipse)\\b[^>]*>"
const SLOT_PATTERN := "\\sdata-slot=\"(\\d+)\""
const FILL_PATTERN := "(\\s)fill=\"[^\"]*\""
const SLOTS_PATTERN := "<svg\\b[^>]*?\\sdata-slots=\"(\\d+)\""
const NAMES_PATTERN := "<svg\\b[^>]*?\\sdata-slot-names=\"([^\"]*)\""


static func _re(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


static func _shapes(svg: String) -> Array[RegExMatch]:
	return _re(SHAPE_PATTERN).search_all(svg)


static func _slot_of(tag: String) -> int:
	var m := _re(SLOT_PATTERN).search(tag)
	return int(m.get_string(1)) if m else 0


static func _fill_of(tag: String) -> String:
	var m := _re(FILL_PATTERN).search(tag)
	return m.get_string().split("\"")[1] if m else ""


## Number of color slots; 0 for an unpainted SVG.
static func slot_count(svg: String) -> int:
	var m := _re(SLOTS_PATTERN).search(svg)
	var n := int(m.get_string(1)) if m else 0
	for shape in _shapes(svg):
		n = maxi(n, _slot_of(shape.get_string()))
	return n


## Slot names as written by the painter, padded with "Slot k" when missing.
static func slot_names(svg: String) -> PackedStringArray:
	var names := PackedStringArray()
	var m := _re(NAMES_PATTERN).search(svg)
	if m and m.get_string(1) != "":
		names = m.get_string(1).xml_unescape().split(",")
	var n := slot_count(svg)
	while names.size() < n:
		names.append("Slot %d" % (names.size() + 1))
	names.resize(n)
	return names


## The colors the painter saved: the fill of the first shape in each slot (white if none).
static func default_palette(svg: String) -> Array[Color]:
	var out: Array[Color] = []
	for i in slot_count(svg):
		out.append(Color.WHITE)
	var seen := {}
	for shape in _shapes(svg):
		var tag := shape.get_string()
		var k := _slot_of(tag)
		if k < 1 or k > out.size() or seen.has(k):
			continue
		var fill := _fill_of(tag)
		if Color.html_is_valid(fill):
			out[k - 1] = Color.html(fill)
			seen[k] = true
	return out


## Returns the SVG text with each painted shape filled from palette[slot - 1].
static func apply_palette(svg: String, palette: Array[Color]) -> String:
	var out := ""
	var pos := 0
	for shape in _shapes(svg):
		var tag := shape.get_string()
		var k := _slot_of(tag)
		if k >= 1 and k <= palette.size():
			tag = _set_fill(tag, "#" + palette[k - 1].to_html(false))
		out += svg.substr(pos, shape.get_start() - pos) + tag
		pos = shape.get_end()
	return out + svg.substr(pos)


static func _set_fill(tag: String, color: String) -> String:
	var m := _re(FILL_PATTERN).search(tag)
	if m:
		return tag.substr(0, m.get_start()) + m.get_string(1) + "fill=\"%s\"" % color + tag.substr(m.get_end())
	var close := tag.length() - 2 if tag.ends_with("/>") else tag.length() - 1
	return tag.substr(0, close) + " fill=\"%s\"" % color + tag.substr(close)


## Rasterizes the painted SVG with the given palette. scale 1.0 = the SVG's own width/height.
static func render(svg: String, palette: Array[Color], scale: float = 1.0) -> ImageTexture:
	var img := Image.new()
	var err := img.load_svg_from_string(apply_palette(svg, palette), scale)
	if err != OK:
		push_error("ShipSkin: could not rasterize SVG (error %d)" % err)
		return null
	return ImageTexture.create_from_image(img)


## Convenience: read an SVG from res:// or user:// and render it.
static func render_file(path: String, palette: Array[Color], scale: float = 1.0) -> ImageTexture:
	var svg := FileAccess.get_file_as_string(path)
	if svg == "":
		push_error("ShipSkin: could not read %s" % path)
		return null
	return render(svg, palette, scale)
