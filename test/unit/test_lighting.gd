extends GutTest
## Ship normal maps and the ship-only lighting: bullet lights, the dimming shade,
## and light masks that keep background, stars, bullets and UI at full brightness.

const Baker := preload("res://tools/bake_normals.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")


## Bullets drop a muzzle flash into their parent, so give them a freed holder.
func _holder() -> Node2D:
	var h := Node2D.new()
	add_child_autofree(h)
	return h
const GameScene := preload("res://scenes/game.tscn")


func _image(path: String) -> Image:
	var img: Image = load(path).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _game() -> Node2D:
	var game: Node2D = GameScene.instantiate()
	add_child_autofree(game)
	return game


## Every Light2D under `node` that targets the ship bit.
func _ship_lights(node: Node) -> Array[Light2D]:
	var out: Array[Light2D] = []
	for n in node.find_children("*", "Light2D", true, false):
		if n.range_item_cull_mask & Ships.LIGHT_MASK:
			out.append(n)
	return out


# --- Baked normal maps ------------------------------------------------------

func test_normal_maps_match_runtime_texture_size() -> void:
	for i in Ships.count():
		var normal := Ships.get_normal_texture(i)
		assert_not_null(normal, "ship %d normal map" % i)
		assert_eq(normal.get_size(), Ships.get_texture(i, 0).get_size(), "ship %d" % i)
		assert_eq(normal.get_size(), Ships.get_enemy_texture(i).get_size(), "ship %d enemy" % i)


func test_known_sizes() -> void:
	assert_eq(Ships.get_normal_texture(0).get_size(), Vector2(174, 120))
	assert_eq(Ships.get_normal_texture(1).get_size(), Vector2(120, 118))


func test_bake_is_reproducible_at_runtime_scale() -> void:
	var baked := Baker.bake(Ships.get_svg(1), Ships.RENDER_SCALE)
	assert_eq(Vector2(baked.get_size()), Ships.get_texture(1, 0).get_size())


func test_normal_pixels_are_unit_normals_and_alpha_matches() -> void:
	for i in Ships.count():
		var normal := _image(Ships.LIST[i].normal)
		var diffuse := Ships.get_texture(i, 0).get_image()
		var bad := 0
		var tilted := 0
		for y in normal.get_height():
			for x in normal.get_width():
				var c := normal.get_pixel(x, y)
				var a := diffuse.get_pixel(x, y).a
				if absf(c.a - a) > 2.0 / 255.0:
					bad += 1
				if a < Baker.EMPTY_ALPHA:
					continue
				var n := Vector3(c.r, c.g, c.b) * 2.0 - Vector3.ONE
				if absf(n.length() - 1.0) > 0.03 or n.z <= 0.0:
					bad += 1
				if n.z < 0.95:
					tilted += 1
		assert_eq(bad, 0, "ship %d: bad normal / alpha pixels" % i)
		assert_gt(tilted, 100, "ship %d has relief" % i)


func test_slot_heights_cover_all_slots() -> void:
	for i in Ships.count():
		assert_eq(Baker.SLOT_HEIGHTS.size(), ShipSkin.slot_count(Ships.get_svg(i)))
	assert_eq(Baker.SLOT_HEIGHTS.size(), 9)
	for h in Baker.SLOT_HEIGHTS:
		assert_between(h, 0.0, 1.0)
	assert_eq(Baker.SLOT_HEIGHTS.min(), Baker.SLOT_HEIGHTS[0], "outline is lowest")
	assert_eq(Baker.SLOT_HEIGHTS.max(), Baker.SLOT_HEIGHTS[2], "glass is highest")


func test_normal_maps_import_lossless_and_export() -> void:
	for ship in Ships.LIST:
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(ship.normal + ".import"), OK)
		assert_eq(cfg.get_value("remap", "importer"), "texture", ship.normal)
		assert_eq(cfg.get_value("params", "compress/mode"), 0, "lossless")
		assert_false(cfg.get_value("params", "mipmaps/generate"))


func test_distance_to_empty() -> void:
	# 5x1 strip: empty, then four opaque pixels; the right edge is the image border.
	var alpha := PackedFloat32Array([0.0, 1.0, 1.0, 1.0, 1.0])
	var d := Baker.distance_to_empty(alpha, Vector2i(5, 1))
	assert_eq(Array(d), [0.0, 1.0, 1.0, 1.0, 1.0], "1px strip touches the border above and below")


# --- Lit textures -----------------------------------------------------------

func test_lit_textures_are_cached_canvas_textures() -> void:
	var lit := Ships.get_lit_texture(1, 3)
	assert_is(lit, CanvasTexture)
	assert_same(Ships.get_lit_texture(1, 3), lit)
	assert_same(lit.diffuse_texture, Ships.get_texture(1, 3))
	assert_same(lit.normal_texture, Ships.get_normal_texture(1))
	assert_eq(lit.get_size(), Ships.get_texture(1, 3).get_size())
	var enemy := Ships.get_lit_enemy_texture(0)
	assert_same(enemy.diffuse_texture, Ships.get_enemy_texture(0))
	assert_same(enemy.normal_texture, Ships.get_normal_texture(0))
	assert_not_same(enemy, Ships.get_lit_texture(0, 0))


func test_player_body_is_lit_on_ship_bit() -> void:
	var p: Area2D = PlayerScene.instantiate()
	p.ship = 1
	add_child_autofree(p)
	var body: Sprite2D = p.get_node("Body")
	assert_is(body.texture, CanvasTexture)
	assert_not_null(body.texture.normal_texture)
	assert_eq(body.light_mask, Ships.LIGHT_MASK)
	assert_ne(p.get_node("Label").light_mask & Ships.LIGHT_MASK, Ships.LIGHT_MASK, "label not lit")


func test_enemy_body_is_lit_on_ship_bit() -> void:
	var e: Area2D = EnemyScene.instantiate()
	add_child_autofree(e)
	var body: Sprite2D = e.get_node("Body")
	assert_is(body.texture, CanvasTexture)
	assert_not_null(body.texture.normal_texture)
	assert_eq(body.light_mask, Ships.LIGHT_MASK)
	assert_true(body.flip_v)


# --- Lights -----------------------------------------------------------------

func test_bullet_light_takes_bullet_color_and_hits_ships_only() -> void:
	var b: Area2D = BulletScene.instantiate()
	b.color = Color("8dff7a")
	_holder().add_child(b)
	var light: PointLight2D = b.get_node("Light")
	assert_eq(light.color, Color("8dff7a"))
	assert_eq(light.range_item_cull_mask, Ships.LIGHT_MASK)
	assert_eq(light.blend_mode, Light2D.BLEND_MODE_ADD)
	assert_false(light.shadow_enabled)
	assert_almost_eq(light.energy, 1.0, 0.01)
	assert_is(light.texture, GradientTexture2D)
	assert_almost_eq(light.texture.get_width() * light.texture_scale / 2.0, 90.0, 5.0, "radius")
	assert_ne(b.get_node("Body").light_mask & Ships.LIGHT_MASK, Ships.LIGHT_MASK, "bullet itself not lit")


func test_bullet_light_texture_is_shared() -> void:
	var a: Area2D = BulletScene.instantiate()
	var b: Area2D = BulletScene.instantiate()
	var h := _holder()
	h.add_child(a)
	h.add_child(b)
	assert_same(a.get_node("Light").texture, b.get_node("Light").texture)


func test_game_has_subtractive_ship_shade() -> void:
	var game := _game()
	var shade: Light2D = game.get_node("ShipShade")
	assert_eq(shade.blend_mode, Light2D.BLEND_MODE_SUB)
	assert_eq(shade.range_item_cull_mask, Ships.LIGHT_MASK)
	assert_almost_eq(shade.energy, 0.55, 0.01, "ships sit at ~45% brightness")
	assert_false(shade.shadow_enabled)
	# The shade must cover the whole arena plus the spawn/exit margins.
	var half: Vector2 = shade.texture.get_size() * shade.texture_scale / 2.0
	var covered := Rect2(shade.position - half, half * 2.0)
	assert_true(covered.encloses(game.ARENA.grow(60)), "covers arena")
	assert_gt(shade.height, 1000.0, "near-vertical so it subtracts evenly")


func test_no_canvas_modulate() -> void:
	var game := _game()
	assert_eq(game.find_children("*", "CanvasModulate", true, false).size(), 0)


func test_non_ship_items_are_off_the_ship_bit() -> void:
	var game := _game()
	for path in ["Background", "Starfield", "HUD/ScoreLabel", "HUD/HPLabel", "HUD/InfoLabel", "PointerControls/Control"]:
		var item: CanvasItem = game.get_node(path)
		assert_eq(item.light_mask & Ships.LIGHT_MASK, 0, path)


func test_ship_lights_only_target_the_ship_bit() -> void:
	var game := _game()
	var bullet: Area2D = BulletScene.instantiate()
	game.get_node("Bullets").add_child(bullet)
	var lights := _ship_lights(game)
	assert_eq(lights.size(), 2, "shade + bullet light")
	for light in lights:
		assert_eq(light.range_item_cull_mask, Ships.LIGHT_MASK, str(light.get_path()))
		for path in ["Background", "Starfield"]:
			assert_eq(light.range_item_cull_mask & game.get_node(path).light_mask, 0, path)


# --- Body volume ------------------------------------------------------------

## alpha for a w x h image with an opaque rectangle covering columns [x0, x1).
func _strip(w: int, h: int, x0: int, x1: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(w * h)
	for y in h:
		for x in range(x0, x1):
			a[y * w + x] = 1.0
	return a


func _body_for(alpha: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	return Baker.body_field(Baker.distance_to_empty(alpha, size), alpha, size)


func test_body_rises_toward_the_middle() -> void:
	var size := Vector2i(41, 41)
	var alpha := _strip(41, 41, 0, 41)
	var body := _body_for(alpha, size)
	var row := 20 * 41
	assert_gt(body[row + 20], body[row + 10])
	assert_gt(body[row + 10], body[row + 1])


func test_wide_parts_are_thicker_than_thin_parts() -> void:
	var size := Vector2i(60, 30)
	var wide := _body_for(_strip(60, 30, 5, 45), size)
	var thin := _body_for(_strip(60, 30, 50, 56), size)
	assert_gt(Array(wide).max(), Array(thin).max() * 2.0)


func test_body_is_zero_outside_the_ship() -> void:
	var size := Vector2i(20, 20)
	var alpha := _strip(20, 20, 5, 15)
	var body := _body_for(alpha, size)
	for i in alpha.size():
		if alpha[i] < Baker.EMPTY_ALPHA:
			assert_eq(body[i], 0.0)


func test_baked_ships_have_overall_volume() -> void:
	# Away from the middle the normals should lean outward: left half tilts left, right half right.
	for i in Ships.count():
		var n := _image(Ships.LIST[i].normal)
		var w := n.get_width()
		var left := 0.0
		var right := 0.0
		for y in n.get_height():
			for x in w:
				var c := n.get_pixel(x, y)
				if c.a < Baker.EMPTY_ALPHA:
					continue
				if x < w / 3:
					left += c.r - 0.5
				elif x > w * 2 / 3:
					right += c.r - 0.5
		assert_lt(left, 0.0, "ship %d left side faces left" % i)
		assert_gt(right, 0.0, "ship %d right side faces right" % i)
