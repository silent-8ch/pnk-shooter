extends GutTest
## PaletteFrames: recolors painted SVG animations, keeps timing, caches.

const BULLET := preload("res://assets/effects/bullet.tres")
const EXPLOSION := preload("res://assets/effects/explosion.tres")
const RED := Color(1, 0, 0)
const GREEN := Color(0, 1, 0)


func _has_color(tex: Texture2D, c: Color) -> bool:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.95 and absf(p.r - c.r) < 0.05 and absf(p.g - c.g) < 0.05 and absf(p.b - c.b) < 0.05:
				return true
	return false


func test_keeps_frames_speed_and_loop() -> void:
	for src in [BULLET, EXPLOSION]:
		var out := PaletteFrames.recolor(src, [Color.WHITE, RED])
		for anim in src.get_animation_names():
			assert_eq(out.get_frame_count(anim), src.get_frame_count(anim))
			assert_eq(out.get_animation_speed(anim), src.get_animation_speed(anim))
			assert_eq(out.get_animation_loop(anim), src.get_animation_loop(anim))
			assert_eq(out.get_frame_texture(anim, 0).get_size(), src.get_frame_texture(anim, 0).get_size())


func test_slots_take_palette_colors() -> void:
	var red := PaletteFrames.recolor(BULLET, [Color.WHITE, RED])
	var green := PaletteFrames.recolor(BULLET, [Color.WHITE, GREEN])
	assert_true(_has_color(red.get_frame_texture(&"default", 0), RED))
	assert_false(_has_color(red.get_frame_texture(&"default", 0), GREEN))
	assert_true(_has_color(green.get_frame_texture(&"default", 0), GREEN))


func test_cached_per_palette() -> void:
	var a := PaletteFrames.recolor(BULLET, [Color.WHITE, RED])
	assert_same(PaletteFrames.recolor(BULLET, [Color.WHITE, RED]), a)
	assert_not_same(PaletteFrames.recolor(BULLET, [Color.WHITE, GREEN]), a)
	assert_not_same(PaletteFrames.recolor(BULLET, [Color.WHITE, RED], 0.5), a)


func test_non_svg_frames_pass_through() -> void:
	var src := SpriteFrames.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	src.add_frame(&"default", tex)
	var out := PaletteFrames.recolor(src, [RED])
	assert_same(out.get_frame_texture(&"default", 0), tex)


func test_painted_effect_art_is_registered_as_palette() -> void:
	var db: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/assets.json"))
	for src in [BULLET, EXPLOSION]:
		for i in src.get_frame_count(&"default"):
			var res := PaletteFrames.source_svg(src.get_frame_texture(&"default", i))
			assert_ne(res, "", "frame %d has a painted SVG" % i)
			var path := res.trim_prefix("res://")
			assert_eq(db.assets[path].strategy, "palette", path)
			assert_true(FileAccess.get_file_as_string(res).contains("data-slot="), path + " is painted")
			assert_eq(ConfigFile.new().load(res + ".import"), OK)
			var cfg := ConfigFile.new()
			cfg.load(res + ".import")
			assert_eq(cfg.get_value("remap", "importer"), "keep", path + " keeps its raw SVG for export")
