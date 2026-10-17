extends Area2D
## Player bullet. Server-simulated; position replicated.
## Carries a PointLight2D tinted to `color` that lights ship bodies only
## (Ships.LIGHT_MASK); any bullet using this scene gets the same light.

const SPEED := 700.0
const SpriteEffect := preload("res://scripts/sprite_effect.gd")

@export var color := Color.YELLOW


func _ready() -> void:
	$Body.modulate = color
	$Body.play()
	SpriteEffect.spawn(get_parent(), position + Vector2(0, 8), SpriteEffect.MUZZLE, 26.0)
	$Light.color = color
	$Light.range_item_cull_mask = Ships.LIGHT_MASK


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	position.y -= SPEED * delta
	if position.y < -40.0:
		queue_free()
