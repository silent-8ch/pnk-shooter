class_name Sparks
extends Node2D
## A burst of sparks where something hit something: short bright streaks that
## fly out (mostly back along `dir`, the way the hit came from), slow, shrink
## and fade. Local only, drawn in code; every peer makes its own from the hits
## it sees.

const LIFE := 0.28  # s
const SPEED := Vector2(90, 260)  # px/s, slowest and fastest spark
const SPREAD := 1.1  # rad either side of the way it bounces off
const DRAG := 5.0  # how quickly they slow
const LENGTH := 0.035  # s of travel each streak shows

var color := Color("ffd45a")
var _sparks: Array = []  # {pos, vel}
var _age := 0.0


## `count` sparks at `at` (in `parent`'s space), thrown off away from `dir`
## (the way the hitting thing was going; Vector2.ZERO: every way).
static func spawn(parent: Node, at: Vector2, dir := Vector2.ZERO, c := Color("ffd45a"), count := 7) -> Sparks:
	var s := Sparks.new()
	s.position = at
	s.color = c
	s.z_index = 30
	var back := -dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO
	for i in count:
		var a := back.angle() + randf_range(-SPREAD, SPREAD) if back != Vector2.ZERO else randf() * TAU
		s._sparks.append({"pos": Vector2.ZERO, "vel": Vector2.from_angle(a) * randf_range(SPEED.x, SPEED.y)})
	parent.add_child(s)
	return s


## Sparks in the game's effects layer, if there's a game (`from`: any node in it).
static func at_hit(from: Node, at: Vector2, dir := Vector2.ZERO, c := Color("ffd45a"), count := 7) -> void:
	if from == null or not from.is_inside_tree():
		return
	var game := from.get_tree().get_first_node_in_group("game")
	if game and game.get("effects"):
		spawn(game.effects, at, dir, c, count)


func spark_count() -> int:
	return _sparks.size()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	for sp in _sparks:
		sp.pos += sp.vel * delta
		sp.vel *= maxf(0.0, 1.0 - DRAG * delta)
	queue_redraw()


func _draw() -> void:
	var t := _age / LIFE
	var c := Color(color.lightened(0.4 * (1.0 - t)), 1.0 - t)
	for sp in _sparks:
		draw_line(sp.pos, sp.pos - sp.vel * LENGTH, c, 2.0 - t, true)
