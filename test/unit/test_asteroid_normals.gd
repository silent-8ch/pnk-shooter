extends GutTest
## Asteroid normal maps (tools/bake_asteroid_normals.gd): very round, with the slot 3
## spots pressed in as craters, and the game lights asteroids with them.

const Bake := preload("res://tools/bake_asteroid_normals.gd")
const Baker := preload("res://tools/bake_normals.gd")
const ObstacleScript := preload("res://scripts/obstacle.gd")


func _n(img: Image, x: int, y: int) -> Vector3:
	var c := img.get_pixel(x, y)
	return Vector3(c.r * 2.0 - 1.0, c.g * 2.0 - 1.0, c.b * 2.0 - 1.0)


func test_every_asteroid_has_a_matching_normal_map() -> void:
	for id in Bake.PIECES:
		var normal := ObstacleScript.normal_art(id)
		assert_not_null(normal, id)
		assert_eq(normal.get_size(), ObstacleScript.art(id).get_size(), id + " lines up with its art")


func test_baked_file_matches_a_fresh_bake() -> void:
	var fresh := Bake.bake(FileAccess.get_file_as_string("res://assets/obstacles/asteroid_s.svg"))
	var saved := ObstacleScript.normal_art("asteroid_s").get_image()
	saved.convert(Image.FORMAT_RGBA8)
	assert_eq(fresh.get_size(), saved.get_size())
	var off := 0
	for y in range(0, fresh.get_height(), 3):
		for x in range(0, fresh.get_width(), 3):
			var a := fresh.get_pixel(x, y)
			var b := saved.get_pixel(x, y)
			if a.a < 0.5:
				continue  # the import's alpha-border fix recolors see-through pixels
			if absf(a.r - b.r) > 0.02 or absf(a.g - b.g) > 0.02 or absf(a.b - b.b) > 0.02:
				off += 1
	assert_eq(off, 0, "rebake after changing the art")


func test_round_like_a_sphere() -> void:
	# A plain disc (no craters): normals tilt outward, more the farther from the middle.
	var size := Vector2i(81, 81)
	var alpha := PackedFloat32Array()
	var slot := PackedInt32Array()
	for y in size.y:
		for x in size.x:
			var inside := Vector2(x, y).distance_to(Vector2(40, 40)) <= 36.0
			alpha.append(1.0 if inside else 0.0)
			slot.append(2 if inside else 0)
	var img := Baker.normal_map(Bake.height(slot, alpha, size), alpha, size)
	assert_gt(_n(img, 40, 40).z, 0.98, "faces straight up in the middle")
	assert_gt(_n(img, 70, 40).x, 0.3, "right side faces right")
	assert_lt(_n(img, 10, 40).x, -0.3, "left side faces left")
	assert_gt(absf(_n(img, 70, 40).x), absf(_n(img, 55, 40).x), "steeper toward the edge")
	assert_gt(absf(_n(img, 40, 70).y), 0.3, "round top to bottom too")


func test_craters_are_bowls() -> void:
	# A disc with a crater patch right of the middle: the crater's near wall faces
	# away from the middle of the crater, unlike the dome around it.
	var size := Vector2i(121, 121)
	var alpha := PackedFloat32Array()
	var slot := PackedInt32Array()
	for y in size.y:
		for x in size.x:
			var p := Vector2(x, y)
			var inside := p.distance_to(Vector2(60, 60)) <= 56.0
			alpha.append(1.0 if inside else 0.0)
			slot.append((3 if p.distance_to(Vector2(80, 60)) <= 12.0 else 2) if inside else 0)
	var with_crater := Bake.height(slot, alpha, size)
	var plain_slot := slot.duplicate()
	for i in plain_slot.size():
		if plain_slot[i] == 3:
			plain_slot[i] = 2
	var plain := Bake.height(plain_slot, alpha, size)
	var c := 60 * size.x + 80
	assert_lt(with_crater[c], plain[c] - 3.0, "pressed in at the crater's middle")
	var far := 60 * size.x + 30
	assert_almost_eq(with_crater[far], plain[far], 0.5, "the rest of the rock is untouched")


func test_asteroids_are_lit_like_ships() -> void:
	for id in Bake.PIECES:
		var lit := ObstacleScript.lit_art(id)
		assert_is(lit, CanvasTexture, id)
		assert_same(lit, ObstacleScript.lit_art(id), "shared")
		assert_same((lit as CanvasTexture).normal_texture, ObstacleScript.normal_art(id))
	assert_null(ObstacleScript.normal_art("girder"), "no normal map without art")
	assert_null(ObstacleScript.lit_art("girder"))
