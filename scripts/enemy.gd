extends Area2D
## Enemy ship. Server-simulated; `type` picks the look and behavior.
##   WEAVER (ship 01): weaves side to side as it drifts down; comes in lines.
##   DIVER  (ship 02): faster; comes in Vs that zigzag down together, bouncing
##                     off the screen edges while holding formation.
## The host spawns enemies and decides damage and death; movement is deterministic
## from the spawn data, so every peer runs it locally with no per-frame sync.

enum { WEAVER, DIVER }

const TYPES: Array[Dictionary] = [
	{"ship": 0, "hp": 1, "points": 10, "speed": 90.0},
	{"ship": 1, "hp": 1, "points": 15, "speed": 130.0},
]
const HEIGHT := 36.0
const WEAVE_AMPLITUDE := 60.0
const WEAVE_FREQUENCY := 2.5  # radians per second
const ZIGZAG_SPEED := 110.0  # horizontal speed of a diver group
const EDGE_MARGIN := 20.0
const ARENA_WIDTH := 540.0
const EXIT_Y := 1020.0
const RAMP_TIME := 1.0  # seconds to go from RAMP_START to full speed
const RAMP_START := 0.5  # fraction of full speed when spawned
const WEAVER_SPACING := 70.0
const WEAVER_GROUP_MIN := 3
const WEAVER_GROUP_MAX := 5
const DIVER_GROUP := 3
const DIVER_V_OFFSET := Vector2(50, 40)  # each wing is this far out and back
const SPAWN_Y := -40.0

@export var type := WEAVER
@export var group_x := -1.0  # group center at spawn; < 0 means this ship's x
@export var zig_dir := 1.0  # initial horizontal direction of the group

var hp := 0
var _damage_carry := 0.0  # fractions of a hit (vulcan rounds) not yet adding up to one
var _spawn_pos := Vector2.ZERO
var _base_x := 0.0
var _time := 0.0

@onready var body: Sprite2D = $Body


func _ready() -> void:
	type = clampi(type, 0, TYPES.size() - 1)
	hp = TYPES[type].hp
	_spawn_pos = position
	_base_x = position.x
	var tex := Ships.get_lit_enemy_texture(TYPES[type].ship)
	body.texture = tex
	body.scale = Ships.scale_for(tex, HEIGHT)
	# Godot flips the normal map's Y along with flip_v (checked empirically on 4.6), so
	# the shared normal map lights correctly upside down; no flipped variant needed.
	body.flip_v = true
	body.light_mask = Ships.LIGHT_MASK
	area_entered.connect(_on_area_entered)


func points() -> int:
	return TYPES[type].points


## Spawn data plus where this ship is in its flight, for a player joining late.
func snapshot() -> Dictionary:
	return {"x": _spawn_pos.x, "y": _spawn_pos.y, "type": type, "group_x": group_x, "dir": zig_dir,
		"id": String(name).trim_prefix("Enemy").to_int(), "time": _time, "pos": position}


## Picks up a flight from a snapshot (see snapshot()).
func restore(time: float, pos: Vector2) -> void:
	_time = time
	position = pos


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	simulate(delta)
	if position.y > EXIT_Y:
		queue_free()  # same on every peer: the paths are deterministic


func simulate(delta: float) -> void:
	_time += delta
	position.y += speed_now() * delta
	match type:
		WEAVER:
			var x := _base_x + sin(_time * WEAVE_FREQUENCY) * WEAVE_AMPLITUDE
			position.x = clampf(x, 20.0, ARENA_WIDTH - 20.0)
		DIVER:
			var center := group_x if group_x >= 0.0 else _base_x
			position.x = zigzag_center(center, zig_dir, _time) + (_base_x - center)


## Current falling speed: eases in from RAMP_START over RAMP_TIME.
func speed_now() -> float:
	var t := clampf(_time / RAMP_TIME, 0.0, 1.0)
	return TYPES[type].speed * lerpf(RAMP_START, 1.0, t)


## Spawn positions for a group: weavers in a horizontal line, divers in a V
## (leader in front). Centered on center_x.
static func group_layout(group_type: int, count: int, center_x: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if group_type == DIVER:
		out.append(Vector2(center_x, SPAWN_Y))
		for i in range(1, count):
			var rank := ceili(i / 2.0)
			var side := -1.0 if i % 2 == 1 else 1.0
			out.append(Vector2(center_x + side * DIVER_V_OFFSET.x * rank, SPAWN_Y - DIVER_V_OFFSET.y * rank))
	else:
		var left := center_x - WEAVER_SPACING * (count - 1) / 2.0
		for i in count:
			out.append(Vector2(left + WEAVER_SPACING * i, SPAWN_Y))
	return out


## Distance from a group's center to the farthest point it can reach sideways.
static func group_half_width(group_type: int, count: int) -> float:
	if group_type == DIVER:
		return DIVER_V_OFFSET.x * floorf(count / 2.0)
	return WEAVER_SPACING * (count - 1) / 2.0 + WEAVE_AMPLITUDE


## Group center x after `time` seconds: moves at ZIGZAG_SPEED and bounces
## between the edges so the whole V stays on screen. Shared by the group, so
## every ship in it turns at the same moment.
static func zigzag_center(start_x: float, dir: float, time: float) -> float:
	var margin := group_half_width(DIVER, DIVER_GROUP) + EDGE_MARGIN
	var lo := margin
	var span := ARENA_WIDTH - 2.0 * margin
	if span <= 0.0:
		return ARENA_WIDTH / 2.0
	var m := fposmod(start_x - lo + signf(dir) * ZIGZAG_SPEED * time, 2.0 * span)
	return lo + (m if m <= span else 2.0 * span - m)


## Host only. `amount` may be a fraction of a hit; fractions add up.
func take_damage(amount: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or hp <= 0:
		return
	_damage_carry += amount
	var hits := floori(_damage_carry + 0.0001)
	_damage_carry = maxf(0.0, _damage_carry - hits)
	if hits <= 0:
		return
	hp -= hits
	if hp <= 0:
		_destroy(true)
	else:
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.play_hit.rpc()


## Rammed by a player: destroyed without scoring.
func ram() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or hp <= 0:
		return
	hp = 0
	_destroy(false)


func _destroy(award_points: bool) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.destroy_enemy(self, award_points)
	else:
		queue_free()


## Every peer removes a bullet that hits; only the shooter's copy reports the hit.
func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not area.is_in_group("bullet"):
		return
	area.queue_free()
	if area.is_mine():
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.report_hit.rpc_id(1, String(name), area.damage())
