extends GutTest
## Station wreckage normal maps (tools/bake_station_normals.gd): the pieces have girth
## (rolled edges, a domed reactor, sunken cells and windows), and the game lights them.

const Bake := preload("res://tools/bake_station_normals.gd")
const Baker := preload("res://tools/bake_normals.gd")
const ObstacleScript := preload("res://scripts/obstacle.gd")


func _n(img: Image, x: int, y: int) -> Vector3:
	var c := img.get_pixel(x, y)
	return Vector3(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0, c.b * 2.0 - 1.0)


## A horizontal band 20 px tall, slot 2, with a slot 3 window in the middle.
func _band() -> Dictionary:
	var size := Vector2i(81, 41)
	var alpha := PackedFloat32Array()
	var slot := PackedInt32Array()
	for y in size.y:
		for x in size.x:
			var inside := y >= 10 and y < 30 and x >= 4 and x < 77
			alpha.append(1.0 if inside else 0.0)
			var window := absi(x - 40) <= 4 and absi(y - 20) <= 4
			slot.append((3 if window else 2) if inside else 0)
	return {"size": size, "alpha": alpha, "slot": slot}


func test_every_piece_has_a_matching_normal_map() -> void:
	for id in Bake.PIECES:
		var normal := ObstacleScript.normal_art(id)
		assert_not_null(normal, id)
		assert_eq(normal.get_size(), ObstacleScript.art(id).get_size(), id + " lines up with its art")


func test_baked_files_match_a_fresh_bake() -> void:
	for id in Bake.PIECES:
		var fresh := Bake.bake(id, FileAccess.get_file_as_string("res://assets/obstacles/%s.svg" % id))
		var saved := ObstacleScript.normal_art(id).get_image()
		saved.convert(Image.FORMAT_RGBA8)
		assert_eq(fresh.get_size(), saved.get_size(), id)
		var off := 0
		for y in range(0, fresh.get_height(), 3):
			for x in range(0, fresh.get_width(), 3):
				var a := fresh.get_pixel(x, y)
				var b := saved.get_pixel(x, y)
				if a.a < 0.5:
					continue  # the import's alpha-border fix recolors see-through pixels
				if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
					off += 1
		assert_eq(off, 0, id + ": rebake after changing the art")


func test_a_full_round_band_is_a_tube() -> void:
	var b := _band()
	var img := Baker.normal_map(Bake.height({"round": 1.0, "inset": []}, b.slot, b.alpha, b.size), b.alpha, b.size)
	assert_gt(_n(img, 20, 20).z, 0.95, "faces up along its middle")
	assert_gt(absf(_n(img, 20, 12).y), 0.3, "rolls away at the top edge")
	assert_gt(absf(_n(img, 20, 28).y), 0.3, "and at the bottom edge")
	assert_lt(_n(img, 20, 12).y * _n(img, 20, 28).y, 0.0, "the two edges face opposite ways")


func test_insets_sink_in() -> void:
	var b := _band()
	var plain := Bake.height({"round": 1.0, "inset": []}, b.slot, b.alpha, b.size)
	var sunk := Bake.height({"round": 1.0, "inset": [3]}, b.slot, b.alpha, b.size)
	var mid: int = 20 * b.size.x + 40
	assert_lt(sunk[mid], plain[mid] - 1.0, "the window is pressed in")
	var away: int = 20 * b.size.x + 15
	assert_almost_eq(sunk[away], plain[away], 0.01, "the band around it is untouched")


func test_the_reactor_is_domed() -> void:
	var size := Vector2i(61, 61)
	var alpha := PackedFloat32Array()
	var slot := PackedInt32Array()
	for y in size.y:
		for x in size.x:
			var inside := Vector2(x, y).distance_to(Vector2(30, 30)) <= 28.0
			alpha.append(1.0 if inside else 0.0)
			slot.append(2 if inside else 0)
	var flat := Bake.height({"round": 0.4, "inset": []}, slot, alpha, size)
	var dome := Bake.height(Bake.PIECES.reactor, slot, alpha, size)
	var mid: int = 30 * size.x + 30
	var part: int = 30 * size.x + 15
	assert_gt(dome[mid] - dome[part], flat[mid] - flat[part] + 2.0, "rises toward the middle")


func test_pieces_are_lit_like_ships() -> void:
	for id in Bake.PIECES:
		var lit := ObstacleScript.lit_art(id)
		assert_is(lit, CanvasTexture, id)
		assert_same((lit as CanvasTexture).normal_texture, ObstacleScript.normal_art(id))
