extends AnimatedSprite2D
## Cosmetic one-shot effect; runs locally on every peer and frees itself.

const EXPLOSION := preload("res://assets/effects/explosion.tres")  # painted; see explosion_frames()


static func spawn(parent: Node, at: Vector2, frames: SpriteFrames, height: float,
		tint: Color = Color.WHITE) -> AnimatedSprite2D:
	var effect := AnimatedSprite2D.new()
	effect.sprite_frames = frames
	effect.position = at
	effect.scale = Vector2.ONE * (height / frame_height(frames))
	effect.modulate = tint
	effect.z_index = 5
	effect.animation_finished.connect(effect.queue_free)
	parent.add_child(effect)
	effect.play()
	return effect


## Height of the first frame in px; `height` passed to spawn() is the on-screen size.
static func frame_height(frames: SpriteFrames) -> float:
	var tex := frames.get_frame_texture(&"default", 0)
	return float(tex.get_height()) if tex else 128.0


## The painted explosion recolored from a fire ramp (Wreck.FIRE_RAMPS entry):
## outline, inner fire, outer fire, then the ramp's last color made opaque.
static func explosion_frames(ramp: Array) -> SpriteFrames:
	var palette: Array[Color] = [ramp[0], ramp[1], ramp[2], Color(ramp[3], 1.0)]
	return PaletteFrames.recolor(EXPLOSION, palette)
