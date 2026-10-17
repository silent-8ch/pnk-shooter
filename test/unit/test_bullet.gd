extends GutTest
## Bullet size and travel speed: big enough to read the shot animation on a phone.

const BulletScene := preload("res://scenes/bullet.tscn")
const BulletScript := preload("res://scripts/bullet.gd")


func test_bullet_sprite_is_large() -> void:
	var b: Area2D = BulletScene.instantiate()
	var body: AnimatedSprite2D = b.get_node("Body")
	var tex: Texture2D = body.sprite_frames.get_frame_texture(&"default", 0)
	assert_gte(tex.get_height() * body.scale.y, 40.0, "bullet sprite at least 40px tall")
	b.free()


func test_bullet_hitbox_matches_sprite() -> void:
	var b: Area2D = BulletScene.instantiate()
	var shape: RectangleShape2D = b.get_node("Shape").shape
	assert_gte(shape.size.y, 30.0)
	assert_gte(shape.size.x, 6.0)
	b.free()


func test_bullet_moves_slower() -> void:
	assert_lte(BulletScript.SPEED, 400.0)
	assert_gt(BulletScript.SPEED, 0.0)
