extends SceneTree
## Scanned drawing -> cropped, scaled grayscale PGM for tools/ship-painter/scan.js.
## Run from the project root:
##   Godot --headless -s tools/scan_to_pgm.gd -- <in.jpeg|png> <out.pgm> [size]
## Crops to the ink (pixels darker than INK) plus MARGIN, then scales so the
## longer side is `size` px (default 600, like the other ships).
## Size 0 keeps the whole scan as is, for drawing sheets (tools/ship-painter/sheet.js read).
## An .svg input (line art already traced) is rendered whole instead, no crop,
## onto white, so scan.js --svg can paint fills under its own paths.

const INK := 0.5
const MARGIN := 0.04  # of the ink's longer side
const MIN_INK_PIXELS := 6  # rows/columns with fewer dark pixels are dust, not drawing


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <in image> <out.pgm> [size]")
		quit(1)
		return
	var size := int(args[2]) if args.size() > 2 else 600
	var err := scan_to_pgm(args[0], args[1], size)
	if err != "":
		printerr(err)
		quit(1)
		return
	quit(0)


## Returns "" on success, else what went wrong.
static func scan_to_pgm(src: String, dst: String, size: int) -> String:
	if src.get_extension().to_lower() == "svg":
		return _svg_to_pgm(src, dst, size)
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		return "can't read " + src
	img.convert(Image.FORMAT_L8)
	if size <= 0:
		return _write_pgm(img, dst)
	var box := ink_box(img)
	if box.size.x <= 0 or box.size.y <= 0:
		return "no ink found in " + src
	var pad := int(maxf(box.size.x, box.size.y) * MARGIN)
	box = box.grow(pad).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(box)
	var s := float(size) / maxf(box.size.x, box.size.y)
	crop.resize(maxi(1, roundi(box.size.x * s)), maxi(1, roundi(box.size.y * s)), Image.INTERPOLATE_LANCZOS)
	return _write_pgm(crop, dst)


static func _svg_to_pgm(src: String, dst: String, size: int) -> String:
	var svg := FileAccess.get_file_as_string(src)
	var probe := Image.new()
	if svg == "" or probe.load_svg_from_string(svg, 1.0) != OK:
		return "can't read " + src
	var img := Image.new()
	var scale := 1.0 if size <= 0 else float(size) / maxf(probe.get_width(), probe.get_height())
	img.load_svg_from_string(svg, scale)
	img.convert(Image.FORMAT_RGBA8)
	var paper := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	paper.fill(Color.WHITE)
	paper.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	paper.convert(Image.FORMAT_L8)
	return _write_pgm(paper, dst)


static func _write_pgm(img: Image, dst: String) -> String:
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return "can't write " + dst
	f.store_string("P5\n%d %d\n255\n" % [img.get_width(), img.get_height()])
	f.store_buffer(img.get_data())
	f.close()
	return ""


## Bounding box of the ink, ignoring rows/columns with only a few dark specks.
static func ink_box(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var limit := int(INK * 255.0)
	var rows := PackedInt32Array()
	rows.resize(h)
	var cols := PackedInt32Array()
	cols.resize(w)
	for y in h:
		var row := y * w
		for x in w:
			if data[row + x] < limit:
				rows[y] += 1
				cols[x] += 1
	var y0 := _first(rows, MIN_INK_PIXELS)
	var y1 := _last(rows, MIN_INK_PIXELS)
	var x0 := _first(cols, MIN_INK_PIXELS)
	var x1 := _last(cols, MIN_INK_PIXELS)
	if y0 < 0 or x0 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _first(counts: PackedInt32Array, at_least: int) -> int:
	for i in counts.size():
		if counts[i] >= at_least:
			return i
	return -1


static func _last(counts: PackedInt32Array, at_least: int) -> int:
	for i in range(counts.size() - 1, -1, -1):
		if counts[i] >= at_least:
			return i
	return -1
