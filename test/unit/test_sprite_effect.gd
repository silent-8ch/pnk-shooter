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
