extends AnimatedSprite2D
## Cosmetic one-shot effect; runs locally on every peer and frees itself.

const MUZZLE := preload("res://assets/filler/fx/muzzle.tres")
const EXPLOSION := preload("res://assets/filler/fx/explosion.tres")
const SMOKE := preload("res://assets/filler/fx/smoke.tres")
const HIT := preload("res://assets/filler/fx/hit.tres")
const PLAYER_HIT := preload("res://assets/filler/fx/player_hit.tres")


static func spawn(parent: Node, at: Vector2, frames: SpriteFrames, height: float,
		tint: Color = Color.WHITE) -> AnimatedSprite2D:
	var effect := AnimatedSprite2D.new()
	effect.sprite_frames = frames
	effect.position = at
	effect.scale = Vector2.ONE * (height / 128.0)
	effect.modulate = tint
	effect.z_index = 5
	effect.animation_finished.connect(effect.queue_free)
	parent.add_child(effect)
	if frames == SMOKE:
		var tween := effect.create_tween().set_parallel(true)
		tween.tween_property(effect, "position:y", at.y - 24.0, 0.6)
		tween.tween_property(effect, "modulate:a", 0.0, 0.6)
	effect.play()
	return effect
