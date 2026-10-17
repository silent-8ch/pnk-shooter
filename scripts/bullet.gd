extends Area2D
## Player bullet. Server-simulated; position replicated.
## Carries a PointLight2D tinted to `color` that lights ship bodies only
## (Ships.LIGHT_MASK); any bullet using this scene gets the same light.
## The body is the painted bullet animation recolored: slot 1 (outline) stays
## white, slot 2 (core) takes `color`.
## Shrinks with Depth as it flies toward the vanishing point, and vanishes at its height.

const SPEED := 420.0
const HEIGHT := 44.0  # on-screen height in px
const RENDER_SCALE := 1.5  # SVG -> texture, sharper than 1:1 on high-DPI phones
const FRAMES := preload("res://assets/effects/bullet.tres")

@export var color := Color.YELLOW


func _ready() -> void:
	var frames := frames_for(color)
	$Body.sprite_frames = frames
	$Body.scale = Vector2.ONE * (HEIGHT / frames.get_frame_texture(&"default", 0).get_height())
	_apply_depth()
	$Body.play()
	$Light.color = color
	$Light.range_item_cull_mask = Ships.LIGHT_MASK


static func frames_for(c: Color) -> SpriteFrames:
	return PaletteFrames.recolor(FRAMES, [Color.WHITE, c], RENDER_SCALE)


## Every peer sizes the bullet from its replicated screen position.
func _process(_delta: float) -> void:
	_apply_depth()


func _apply_depth() -> void:
	scale = Vector2.ONE * Depth.scale_at(position.y)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	position.y -= SPEED * delta
	if position.y < Depth.VANISH_Y:
		queue_free()
