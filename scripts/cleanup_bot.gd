class_name CleanupBot
extends Node2D
## A neutral station drone that tidies up an astronaut nobody rescued in time
## (Game.send_cleanup_bot): it flies in from the nearest side of the screen,
## grabs the astronaut (it leaves the field) and flies back out. Nobody gets
## credit. Local on every peer, following its own copy of the astronaut; the
## host has already marked it taken, so no drone goes for it.
## Drawn in code: a small grey hull with an orange beacon.

const SPEED := 170.0  # px/s
const REACH := 6.0  # px: close enough to grab
const OFFSCREEN := 30.0  # px past the edge it comes from and goes back to
const RADIUS := 7.0
const HULL := Color(0.72, 0.74, 0.78)
const TRIM := Color(0.35, 0.37, 0.42)
const BEACON := Color(1.0, 0.6, 0.15)
const BLINK := 3.0  # beacon blinks per second

var target: Node2D  # the astronaut it's after
var home := Vector2.ZERO  # where it came in from, and leaves by
var carrying := false
var _age := 0.0


## Off the side of the screen nearest `at`.
static func entry_for(at: Vector2, width: float) -> Vector2:
	var x := -OFFSCREEN if at.x < width / 2.0 else width + OFFSCREEN
	return Vector2(x, at.y)


func _process(delta: float) -> void:
	_age += delta
	var goal := home
	if not carrying:
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			carrying = true  # gone some other way: just leave
		else:
			goal = target.position
	position = position.move_toward(goal, SPEED * delta)
	if not carrying and position.distance_to(goal) <= REACH:
		_grab()
	elif carrying and position.distance_to(home) <= REACH:
		queue_free()
	queue_redraw()


func _grab() -> void:
	carrying = true
	if is_instance_valid(target):
		var parent := target.get_parent()
		if parent:
			parent.remove_child(target)
		target.queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 1.5, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, RADIUS, HULL)
	draw_rect(Rect2(-RADIUS - 3.0, -1.5, RADIUS * 2.0 + 6.0, 3.0), TRIM)  # side struts
	if fmod(_age * BLINK, 1.0) < 0.5:
		draw_circle(Vector2(0, -2), 2.0, BEACON)
	if carrying:
		var tex := preload("res://scripts/escape_pod.gd").astronaut_texture()
		draw_texture(tex, Vector2(-tex.get_width() / 2.0, RADIUS - 1.0))
