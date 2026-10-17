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


func test_bullet_and_explosion_use_new_effect_art() -> void:
	var bullet := Bullet.instantiate()
	autofree(bullet)
	var body: AnimatedSprite2D = bullet.get_node("Body")
	assert_eq(body.sprite_frames.resource_path, "res://assets/effects/bullet.tres")
	assert_true(body.sprite_frames.get_animation_loop("default"))
	assert_eq(Effect.EXPLOSION.resource_path, "res://assets/effects/explosion.tres")
	assert_eq(Effect.EXPLOSION.get_frame_count("default"), 4)


func test_effect_scale_matches_frame_height() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var boom := Effect.spawn(holder, Vector2.ZERO, Effect.EXPLOSION, 60.0)
	assert_almost_eq(boom.scale.x, 60.0 / 120.0, 0.0001)
	var muzzle := Effect.spawn(holder, Vector2.ZERO, Effect.MUZZLE, 64.0)
	assert_almost_eq(muzzle.scale.x, 64.0 / 128.0, 0.0001)
