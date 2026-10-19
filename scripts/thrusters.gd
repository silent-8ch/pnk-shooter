class_name Thrusters
extends Node2D
## Jets on a ship (players and enemies alike) that fire to change its course:
## it watches how the ship's velocity changes and fires the jet that would
## push it that way. Pushing up lights the main engine under it, pushing down
## the nose jets, pushing left the jet on its right side and right the one on
## its left; each flares in proportion and puffs a little exhaust. Local on
## every peer, from the ship's own movement, so nothing is sent.

const FULL := 900.0  # px/s² of change in speed for a jet at full blast
const SMOOTH := 12.0  # how quickly the jets follow changes (per second)
const IDLE := 0.12  # how much a jet shows while the ship just keeps moving its way
const MIN_SHOW := 0.06  # below this a jet is off
const PUFF_LIFE := 0.3  # s
const PUFF_RATE := 40.0  # puffs per second at full blast, per jet
const PUFF_SPEED := 90.0  # px/s out of the nozzle
const MAX_PUFFS := 40

var radius := 20.0  # px from the ship's middle to its edge
var flame := Color("ffb347")  # the flame's outer color
var core := Color("fff4d6")
var thrust := Vector2.ZERO  # -1..1 each way: which way the jets push now (x right, y down)
var _last_pos := Vector2.INF
var _vel := Vector2.ZERO
var _puffs: Array = []  # {pos, vel, age} in the ship's parent's space
var _puff_debt := Vector4.ZERO  # up, down, left, right
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true  # drawn in game space: the jets point the way the world sees them, whatever the ship's facing
	z_index = -1
	_rng.randomize()


## What each jet shows (0..1): {up, down, left, right}, from a push `t`
## (x right, y down; up = the main engine).
static func jets(t: Vector2) -> Dictionary:
	return {"up": maxf(0.0, -t.y), "down": maxf(0.0, t.y), "left": maxf(0.0, -t.x), "right": maxf(0.0, t.x)}


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
	var at := ship.global_position
	if _last_pos == Vector2.INF:
		_last_pos = at
	var vel := (at - _last_pos) / delta
	_last_pos = at
	if vel.length() > 2000.0:  # a respawn or warp: not a burn
		vel = _vel
	var accel := (vel - _vel) / delta
	_vel = vel
	var visible_ship: bool = ship.visible and (not ship.has_method("is_alive") or ship.is_alive())
	var want := push_for(accel, vel) if visible_ship else Vector2.ZERO
	thrust = thrust.lerp(want, minf(1.0, SMOOTH * delta))
	_emit(delta)
	_age_puffs(delta)
	queue_redraw()


## Nozzle spot and the way its flame points, for a jet (in this node's space).
func nozzle(jet: String) -> Array:
	match jet:
		"up":
			return [Vector2(0, radius * 0.9), Vector2.DOWN]
		"down":
			return [Vector2(0, -radius * 0.9), Vector2.UP]
		"left":
			return [Vector2(radius * 0.8, 0), Vector2.RIGHT]
		_:
			return [Vector2(-radius * 0.8, 0), Vector2.LEFT]


func _emit(delta: float) -> void:
	var j := jets(thrust)
	var keys := ["up", "down", "left", "right"]
	for k in 4:
		var power: float = j[keys[k]]
		if power < MIN_SHOW:
			continue
		_puff_debt[k] += power * PUFF_RATE * delta
		while _puff_debt[k] >= 1.0 and _puffs.size() < MAX_PUFFS:
			_puff_debt[k] -= 1.0
			var n: Array = nozzle(keys[k])
			var dir: Vector2 = (n[1] as Vector2).rotated(_rng.randf_range(-0.35, 0.35))
			_puffs.append({"pos": global_position + n[0] + dir * radius * 0.3 * power, "vel": dir * PUFF_SPEED * (0.5 + power) + _vel * 0.3, "age": 0.0})
		_puff_debt[k] = minf(_puff_debt[k], 1.0)


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
		draw_circle(p.pos - global_position, 2.0 + 4.0 * t, Color(flame, 0.45 * (1.0 - t)))
	var j := jets(thrust)
	for key in j:
		var power: float = j[key]
		if power < MIN_SHOW:
			continue
		var n: Array = nozzle(key)
		var base: Vector2 = n[0]
		var dir: Vector2 = n[1]
		var side := dir.orthogonal()
		var length := radius * (0.35 + 0.9 * power) * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05))
		var width := radius * (0.18 + 0.12 * power) * (1.0 if key == "up" else 0.7)
		var flame_pts := PackedVector2Array([base + side * width, base + dir * length, base - side * width])
		draw_colored_polygon(flame_pts, Color(flame, 0.75 * clampf(power * 2.0, 0.0, 1.0)))
		var core_pts := PackedVector2Array([base + side * width * 0.5, base + dir * length * 0.6, base - side * width * 0.5])
		draw_colored_polygon(core_pts, Color(core, 0.9 * clampf(power * 2.0, 0.0, 1.0)))
