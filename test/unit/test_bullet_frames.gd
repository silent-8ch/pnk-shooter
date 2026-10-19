extends GutTest
## Bullets start on a random frame of their animation, so a volley doesn't all look the same.

const BulletScene := preload("res://scenes/bullet.tscn")


func _bullet() -> Area2D:
	var h := Node2D.new()
	add_child_autofree(h)
	var b: Area2D = BulletScene.instantiate()
	h.add_child(b)
	return b


func test_bullets_start_on_different_frames() -> void:
	seed(1234)
	var seen := {}
	for i in 40:
		var body: AnimatedSprite2D = _bullet().get_node("Body")
		assert_true(body.is_playing())
		seen[body.frame] = true
	assert_gt(seen.size(), 1, "40 bullets all started on one frame")


func test_start_frame_is_in_range() -> void:
	for i in 40:
		var body: AnimatedSprite2D = _bullet().get_node("Body")
		assert_between(body.frame, 0, body.sprite_frames.get_frame_count(&"default") - 1)
