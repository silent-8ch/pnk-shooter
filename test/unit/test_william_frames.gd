extends GutTest
## william.tres: the 4-frame animation cut from william.svg.

const FRAMES := preload("res://assets/effects/william.tres")


func test_four_frames_on_a_shared_canvas() -> void:
	assert_eq(FRAMES.get_frame_count(&"default"), 4)
	for i in 4:
		var tex := FRAMES.get_frame_texture(&"default", i)
		assert_eq(tex.get_size(), Vector2(456, 272))
		assert_eq(PaletteFrames.source_svg(tex), "res://assets/effects/william_%02d.svg" % i)


func test_every_frame_has_ink() -> void:
	for i in 4:
		var img := FRAMES.get_frame_texture(&"default", i).get_image()
		img.convert(Image.FORMAT_RGBA8)
		assert_true(img.get_used_rect().size.x > 0, "frame %d is empty" % i)


func test_plays_once_at_12_fps() -> void:
	assert_false(FRAMES.get_animation_loop(&"default"))
	assert_eq(FRAMES.get_animation_speed(&"default"), 12.0)
