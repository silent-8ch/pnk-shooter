extends GutTest

const Effect := preload("res://scripts/sprite_effect.gd")
const Bullet := preload("res://scenes/bullet.tscn")


func test_bullet_animates_in_its_color() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var bullet := Bullet.instantiate()
	bullet.set_physics_process(false)
	holder.add_child(bullet)
	assert_is(bullet.get_node("Body"), AnimatedSprite2D)
	assert_true(bullet.get_node("Body").is_playing())
	assert_same(bullet.get_node("Body").sprite_frames, bullet.frames_for(bullet.color), "painted bullet in its color")
	assert_eq(bullet.get_node("Body").modulate, Color.WHITE, "colored by palette, not modulate")
	assert_eq(holder.get_child_count(), 1, "no muzzle flash until new art exists")
	var tex: Texture2D = bullet.get_node("Body").sprite_frames.get_frame_texture(&"default", 0)
	assert_almost_eq(tex.get_height() * bullet.get_node("Body").scale.y, bullet.HEIGHT, 0.01, "on-screen height")
	assert_gt(tex.get_height(), int(bullet.HEIGHT), "rendered sharper than it is drawn")


func test_one_shot_effects_finish_and_free() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	for frames in [Effect.EXPLOSION]:
		var effect := Effect.spawn(holder, Vector2.ZERO, frames, 48.0)
		assert_false(frames.get_animation_loop("default"))
		assert_true(effect.is_playing())
	await wait_seconds(0.8)
	assert_eq(holder.get_child_count(), 0, "all effects clean up")


func test_spawn_scales_by_frame_height() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var effect := Effect.spawn(holder, Vector2.ZERO, Effect.EXPLOSION, 60.0)
	var h := Effect.frame_height(Effect.EXPLOSION)
	assert_almost_eq(effect.scale.y * h, 60.0, 0.001)


func test_explosion_frames_follow_ramp() -> void:
	var a := Effect.explosion_frames([Color.WHITE, Color.RED, Color.BLUE, Color(0, 1, 0, 0)])
	var b := Effect.explosion_frames([Color.WHITE, Color.RED, Color.BLUE, Color(0, 1, 0, 0)])
	var c := Effect.explosion_frames([Color.WHITE, Color.YELLOW, Color.BLUE, Color(0, 1, 0, 0)])
	assert_same(a, b, "cached per ramp")
	assert_not_same(a, c)
	assert_eq(a.get_frame_count(&"default"), Effect.EXPLOSION.get_frame_count(&"default"))
	assert_false(a.get_animation_loop(&"default"))
