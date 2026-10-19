class_name CleanupBot
extends Node2D
## A neutral station drone that tidies up an astronaut nobody rescued in time
## (Game.send_cleanup_bot): it flies in from the nearest side of the screen,
## grabs the astronaut (it leaves the field) and flies back out. Nobody gets
## credit. Local on every peer, following its own copy of the astronaut; the
## host has already marked it taken, so no drone goes for it.
## It looks like a small copy of a random ship (picked from its name, so
## every peer sees the same one) in the plain Factory palette, with red and blue
## emergency lights flashing in turn, facing the way it flies.

const SPEED := 170.0  # px/s
const REACH := 6.0  # px: close enough to grab
const OFFSCREEN := 30.0  # px past the edge it comes from and goes back to
const RADIUS := 7.0
const SCALE := 0.5  # of a player's ship, like an option
const PlayerScript := preload("res://scripts/player.gd")

var target: Node2D  # the astronaut it's after
var home := Vector2.ZERO  # where it came in from, and leaves by
var carrying := false
var _age := 0.0
var body := Sprite2D.new()


func _ready() -> void:
	var ship := posmod(hash([String(name), "cleanup"]), Ships.count())
	body.texture = Ships.get_lit_texture(ship, 0)  # Factory: nobody's colors
	body.scale = Ships.get_scale(ship, 0) * SCALE
	body.light_mask = Ships.LIGHT_MASK
	body.show_behind_parent = true  # the beacon and its cargo on top
	add_child(body)


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
	var before := position
	position = position.move_toward(goal, SPEED * delta)
	if position != before:
		body.rotation = Vector2.UP.angle_to(position - before)  # the art faces up
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


## Red and blue emergency lights, flashing in turn like a rescue drone's.
func _draw() -> void:
	var lit := PlayerScript.drone_light(_age)
	for k in 2:
		var at := Vector2(PlayerScript.DRONE_LIGHT_GAP * (-1.0 if k == 0 else 1.0), -2)
		var c: Color = PlayerScript.DRONE_RED if k == 0 else PlayerScript.DRONE_BLUE
		if k == lit:
			draw_circle(at, 5.0, Color(c, 0.35))
			draw_circle(at, 2.2, c.lightened(0.4))
		else:
			draw_circle(at, 1.6, Color(c, 0.45))
	if carrying:
		var tex := preload("res://scripts/escape_pod.gd").astronaut_texture()
		draw_texture(tex, Vector2(-tex.get_width() / 2.0, RADIUS - 1.0))
