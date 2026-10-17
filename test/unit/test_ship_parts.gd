extends GutTest
## Splitting painted ship SVGs into parts and cracked shards.


func _analysis(ship: int) -> Dictionary:
	var colors: Array[Color] = []
	colors.assign(Ships.ENEMY_PALETTES[ship].colors)
	return ShipParts.analyze(Ships.get_svg(ship), colors, Ships.RENDER_SCALE,
			Ships.ENEMY_PART_MAX, Ships.ENEMY_PART_MIN_AREA)


func _opaque(img: Image) -> int:
	var n := 0
	var data := img.get_data()
	for i in range(3, data.size(), 4):
		if data[i] >= ShipParts.ALPHA_MIN:
			n += 1
	return n


func test_analysis_covers_opaque_pixels() -> void:
	# Isolated specks with no opaque neighbour are dropped; nothing else.
	for ship in Ships.count():
		var a := _analysis(ship)
		var img: Image = a.image
		var covered := 0
		for id in a.comp:
			if id != -1:
				covered += 1
		var opaque := _opaque(img)
		assert_between(covered, opaque - opaque / 1000, opaque, "ship %d" % ship)


func test_parts_limited_and_not_tiny() -> void:
	for ship in Ships.count():
		var parts := ShipParts.pieces(_analysis(ship), _analysis(ship).comp)
		assert_between(parts.size(), 2, Ships.ENEMY_PART_MAX, "ship %d" % ship)
		for p in parts:
			assert_gte(p.area, Ships.ENEMY_PART_MIN_AREA)


func test_crack_adds_shards() -> void:
	var a := _analysis(0)
	var base := ShipParts.pieces(a, a.comp).size()
	assert_eq(ShipParts.pieces(a, ShipParts.crack(a, 1, 5)).size(), base + 1)
	assert_eq(ShipParts.pieces(a, ShipParts.crack(a, 2, 5)).size(), base + 2)


func test_crack_leaves_analysis_untouched() -> void:
	var a := _analysis(1)
	var before: PackedInt32Array = a.comp.duplicate()
	ShipParts.crack(a, 2, 9)
	assert_eq(a.comp, before)


func test_crack_is_deterministic() -> void:
	var a := _analysis(0)
	assert_eq(ShipParts.crack(a, 2, 7), ShipParts.crack(a, 2, 7))
	assert_ne(ShipParts.crack(a, 2, 7), ShipParts.crack(a, 2, 8))


func test_pieces_reassemble_the_ship() -> void:
	var a := _analysis(0)
	var img: Image = a.image
	var w: int = a.w
	var h: int = a.h
	var canvas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var center := Vector2(w, h) / 2.0
	var total := 0
	for p in ShipParts.pieces(a, ShipParts.crack(a, 2, 3)):
		var pi: Image = p.texture.get_image()
		var pos := Vector2i((center + p.offset - Vector2(pi.get_size()) / 2.0).round())
		canvas.blend_rect(pi, Rect2i(Vector2i.ZERO, pi.get_size()), pos)
		total += p.area
	assert_almost_eq(total, _opaque(img), _opaque(img) / 1000)
	for probe in [Vector2i(w / 2, h / 2), Vector2i(w / 3, h / 2), Vector2i(w / 2, h / 3)]:
		assert_eq(canvas.get_pixelv(probe), img.get_pixelv(probe), "pixel %s" % probe)


func test_label_colors_distinct() -> void:
	var colors := ShipParts.label_colors(9)
	for i in colors.size():
		for j in range(i + 1, colors.size()):
			assert_ne(colors[i], colors[j])


func test_enemy_parts_cached_per_variant() -> void:
	var a := Ships.get_enemy_parts(0, 0)
	assert_same(Ships.get_enemy_parts(0, 0), a)
	assert_same(Ships.get_enemy_parts(0, Ships.ENEMY_PART_VARIANTS), a, "variant wraps")
	assert_ne(Ships.get_enemy_parts(0, 1).size(), 0)


func test_bad_svg_gives_no_parts() -> void:
	var colors: Array[Color] = [Color.WHITE]
	assert_eq(ShipParts.split("not an svg", colors, 1.0, 5, 10, 1, 1), [])
	assert_engine_error_count(2, "rasterizer rejects the SVG")
