extends Node2D
## Looping engine flames under a ship's thrusters. Exhaust points come from the
## ship SVG's thruster slot (Ships.get_thrusters), so each ship gets one flame
## per nozzle. Not lit: flames stay full brightness under the ship shade.

const THRUST := preload("res://assets/filler/fx/thrust.tres")
const ART_SIZE := Vector2(32, 64)  # thrust frame canvas
const WIDTH_FACTOR := 1.1  # flame width relative to its nozzle
const LENGTH_FACTOR := 1.3  # stretch the flame a little longer than the art
const TINT_TO_WHITE := 0.4  # how far the slot color is lightened


## Adds one flame per thruster. body_scale is the Body sprite's scale; flipped
## ships (enemies, flip_v) get flames on the other end, pointing the other way.
func build(ship: int, body_scale: Vector2, thruster_color: Color, flipped: bool) -> void:
	for child in get_children():
		child.queue_free()
	scale = Vector2(1, -1) if flipped else Vector2.ONE
	var tint := thruster_color.lerp(Color.WHITE, TINT_TO_WHITE)
	for t in Ships.get_thrusters(ship):
		var flame := AnimatedSprite2D.new()
		flame.sprite_frames = THRUST
		flame.offset = Vector2(0, ART_SIZE.y / 2.0)  # top of the art at the nozzle
		flame.position = t.pos * body_scale
		var s: float = t.width * body_scale.x * WIDTH_FACTOR / ART_SIZE.x
		flame.scale = Vector2(s, s * LENGTH_FACTOR)
		flame.modulate = tint
		flame.frame = get_child_count() % THRUST.get_frame_count("default")  # out of step
		add_child(flame)
		flame.play()
