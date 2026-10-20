extends GutTest
## explosion2.tres: the second painted explosion set, from Scan 6's drawing sheet.

const FRAMES := preload("res://assets/effects/explosion2.tres")
const Effect := preload("res://scripts/sprite_effect.gd")


func test_four_frames_on_a_shared_canvas() -> void:
	assert_eq(FRAMES.get_frame_count(&"default"), 4)
	for i in 4:
		var tex := FRAMES.get_frame_texture(&"default", i)
		assert_eq(tex.get_size(), Vector2(150, 205))
		assert_eq(PaletteFrames.source_svg(tex), "res://assets/effects/explosion2_%02d.svg" % i)


func test_every_frame_has_ink_and_grows() -> void:
	var last := 0
	for i in 4:
		var img := FRAMES.get_frame_texture(&"default", i).get_image()
		img.convert(Image.FORMAT_RGBA8)
		var used := img.get_used_rect()
		assert_gt(used.size.x, 0, "frame %d is empty" % i)
		assert_gt(used.size.y, last, "frame %d is bigger than the one before" % i)
		last = used.size.y


func test_plays_once_at_12_fps() -> void:
	assert_false(FRAMES.get_animation_loop(&"default"))
	assert_eq(FRAMES.get_animation_speed(&"default"), 12.0)


func test_is_the_second_explosion_set() -> void:
	assert_eq(Effect.EXPLOSIONS.size(), 2)
	assert_same(Effect.EXPLOSIONS[1], FRAMES)
	assert_same(Effect.EXPLOSIONS[0], Effect.EXPLOSION)


func test_explosion_frames_pick_a_set() -> void:
	var ramp := [Color.WHITE, Color.RED, Color.BLUE, Color(0, 1, 0, 0)]
	var a := Effect.explosion_frames(ramp, 0)
	var b := Effect.explosion_frames(ramp, 1)
	assert_not_same(a, b, "a different set")
	assert_same(b, Effect.explosion_frames(ramp, 1), "cached per set")
	assert_same(a, Effect.explosion_frames(ramp), "set 0 is the default")
	assert_same(b, Effect.explosion_frames(ramp, 3), "wraps around")
	assert_eq(b.get_frame_count(&"default"), 4)
	assert_false(b.get_animation_loop(&"default"))
	assert_eq(b.get_frame_texture(&"default", 0).get_size(), Vector2(150, 205))


func test_random_set_stays_in_range_and_varies() -> void:
	var seen := {}
	for s in [-7, -1, 0, 1, 2, 3, 100, hash("Pod3"), hash(Vector2(12, 34))]:
		var k := Effect.random_set(s)
		assert_between(k, 0, Effect.EXPLOSIONS.size() - 1)
		seen[k] = true
	assert_eq(seen.size(), Effect.EXPLOSIONS.size())
