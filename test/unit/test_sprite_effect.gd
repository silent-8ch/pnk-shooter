extends GutTest

const Effect := preload("res://scripts/sprite_effect.gd")
const Bullet := preload("res://scenes/bullet.tscn")


func test_bullet_animates_and_launches_flash() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var bullet := Bullet.instantiate()
	bullet.set_physics_process(false)
	holder.add_child(bullet)
	assert_is(bullet.get_node("Body"), AnimatedSprite2D)
	assert_true(bullet.get_node("Body").is_playing())
	assert_eq(bullet.get_node("Body").sprite_frames.resource_path, "res://assets/effects/bullet.tres")
	assert_eq(holder.get_child_count(), 2, "bullet plus muzzle flash")
	var flash := holder.get_child(1)
	assert_same(flash.sprite_frames, Effect.MUZZLE)
	assert_eq(flash.position, bullet.position + Vector2(0, 8))


func test_one_shot_effects_finish_and_free() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	for frames in [Effect.MUZZLE, Effect.EXPLOSION, Effect.SMOKE]:
		var effect := Effect.spawn(holder, Vector2.ZERO, frames, 48.0)
		assert_false(frames.get_animation_loop("default"))
		assert_true(effect.is_playing())
	await wait_seconds(0.8)
	assert_eq(holder.get_child_count(), 0, "all effects clean up")


func test_effects_art_is_white_ink_so_tints_apply() -> void:
	for frames in [Effect.EXPLOSION, preload("res://assets/effects/bullet.tres")]:
		var img: Image = frames.get_frame_texture(&"default", 0).get_image()
		img.decompress()
		var brightest := 0.0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.9:
					brightest = maxf(brightest, c.get_luminance())
		assert_gt(brightest, 0.9, "%s ink is white" % frames.resource_path)
