class_name Thrusters
extends Node2D
## Jets on a ship (players and enemies alike) that fire to change its course.
## Each ship has its own `layout` of thrusters, set in the ship painter
## (Ships.thruster_layout): where each nozzle sits, which way its flame points
## and how big it is. A flame pushes the ship the other way, so as the ship
## changes course (worked out from how it moves) every thruster that pushes
## that way fires, in proportion. Each flares and puffs a little exhaust.
## Local on every peer, from the ship's own movement, so nothing is sent.

const FULL := 900.0  # px/s² of change in speed for a jet at full blast
const SMOOTH := 12.0  # how quickly the jets follow changes (per second)
const IDLE := 0.12  # how much a jet shows while the ship just keeps moving its way
const MIN_SHOW := 0.06  # below this a jet is off
const PUFF_LIFE := 0.3  # s
const PUFF_RATE := 40.0  # puffs per second at full blast, per jet
const PUFF_SPEED := 90.0  # px/s out of the nozzle
const MAX_PUFFS := 60

var radius := 20.0  # px from the ship's middle to its edge (sizes the flames)
## [{pos, dir, size, main}]: nozzles in px from the ship's middle (facing up),
## and the way each flame points. Defaults to Ships.default_layout.
var layout: Array = []
var flame := Color("ffb347")  # the flame's outer color
var core := Color("fff4d6")
var thrust := Vector2.ZERO  # -1..1 each way: which way the jets push now (x right, y down)
var _last_pos := Vector2.INF
var _vel := Vector2.ZERO
var _puffs: Array = []  # {pos, vel, age} in game space
var _puff_debt: Array[float] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true  # drawn in game space: the jets point the way the world sees them
	show_behind_parent = true  # just under its ship (a negative z would sink it under the backdrop)
	_rng.randomize()
	if layout.is_empty():
		layout = Ships.default_layout(Vector2(radius, radius) * 2.0)


## A layout for a ship facing down (enemies): mirrored top to bottom, and
## `scale` times the size.
static func flipped(l: Array, scale := 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in l:
		out.append({"pos": Vector2(t.pos.x, -t.pos.y) * scale, "dir": Vector2(t.dir.x, -t.dir.y), "size": t.size, "main": t.main})
	return out


## A layout `scale` times the size.
static func scaled(l: Array, scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in l:
		out.append({"pos": t.pos * scale, "dir": t.dir, "size": t.size, "main": t.main})
	return out


## How hard thruster `t` fires (0..1) for a push `want` (x right, y down): a
## flame pushes the ship opposite to where it points.
static func power(t: Dictionary, want: Vector2) -> float:
	return maxf(0.0, (-(t.dir as Vector2)).dot(want))


## The push `accel` (px/s²) and a cruise `vel` (px/s) call for: mostly the
## change in speed, plus a little for keeping going.
static func push_for(accel: Vector2, vel: Vector2) -> Vector2:
	var t := accel / FULL
	if vel.length() > 5.0:
		t += vel.normalized() * IDLE
	return t.limit_length(1.0)


func _process(delta: float) -> void:
	var ship := get_parent() as Node2D
	if ship == null or delta <= 0.0:
		return
	global_position = ship.global_position
	global_rotation = ship.global_rotation  # a turning ship's jets turn with it
	var at := ship.global_position
	if _last_pos == Vector2.INF:
		_last_pos = at
	var vel := (at - _last_pos) / delta
	_last_pos = at
	if vel.length() > 2000.0:  # a respawn or warp: not a burn
		vel = _vel
	var accel := (vel - _vel) / delta
	_vel = vel
	var showing: bool = ship.visible and (not ship.has_method("is_alive") or ship.is_alive())
	var want := push_for(accel, vel).rotated(-global_rotation) if showing else Vector2.ZERO  # in the ship's own frame
	thrust = thrust.lerp(want, minf(1.0, SMOOTH * delta))
	_emit(delta)
	_age_puffs(delta)
	queue_redraw()


func _emit(delta: float) -> void:
	_puff_debt.resize(layout.size())
	for i in layout.size():
		var t: Dictionary = layout[i]
		var p := power(t, thrust)
		if p < MIN_SHOW:
			continue
		_puff_debt[i] += p * PUFF_RATE * delta * clampf(t.size, 0.5, 2.0)
		while _puff_debt[i] >= 1.0 and _puffs.size() < MAX_PUFFS:
			_puff_debt[i] -= 1.0
			var dir: Vector2 = (t.dir as Vector2).rotated(_rng.randf_range(-0.35, 0.35))
			_puffs.append({"pos": to_global(t.pos + dir * radius * 0.2 * p), "vel": dir.rotated(global_rotation) * PUFF_SPEED * (0.5 + p) + _vel * 0.3, "age": 0.0})
		_puff_debt[i] = minf(_puff_debt[i], 1.0)


func _age_puffs(delta: float) -> void:
	for i in range(_puffs.size() - 1, -1, -1):
		var p: Dictionary = _puffs[i]
		p.age += delta
		p.pos += p.vel * delta
		if p.age >= PUFF_LIFE:
			_puffs.remove_at(i)


func _draw() -> void:
	for p in _puffs:
		var t: float = p.age / PUFF_LIFE
		draw_circle(to_local(p.pos), 2.0 + 4.0 * t, Color(flame, 0.45 * (1.0 - t)))
	var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05)
	for t in layout:
		var p := power(t, thrust)
		if p < MIN_SHOW:
			continue
		var base: Vector2 = t.pos
		var dir: Vector2 = t.dir
		var side := dir.orthogonal()
		var length: float = radius * (0.25 + 0.55 * p) * t.size * flicker
		var width: float = radius * (0.1 + 0.06 * p) * t.size
		var a := clampf(p * 2.0, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([base + side * width, base + dir * length, base - side * width]), Color(flame, 0.75 * a))
		draw_colored_polygon(PackedVector2Array([base + side * width * 0.5, base + dir * length * 0.6, base - side * width * 0.5]), Color(core, 0.9 * a))
