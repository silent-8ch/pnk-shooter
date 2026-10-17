extends Area2D
## Enemy ship. Server-simulated; `type` picks the look and behavior.
##   WEAVER (ship 01): weaves side to side as it drifts down; comes in lines.
##   DIVER  (ship 02): faster; comes in Vs that zigzag down together, bouncing
##                     off the screen edges while holding formation.
## Movement happens in flat `world` coordinates; `position` is its Depth
## projection, so enemies emerge small from the vanishing point and fan out toward
## the players, growing as they come.

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
const RISE := 12.0  # screen px of travel over which a new ship fades in

@export var type := WEAVER
@export var group_x := -1.0  # group center at spawn; < 0 means this ship's x
@export var zig_dir := 1.0  # initial horizontal direction of the group

var world := Vector2.INF  # flat arena position; INF = take it from `position`
var hp := 0
var _last_y := INF
var _travel := 0.0  # screen px moved so far, for the fade-in
var _base_x := 0.0
var _time := 0.0

@onready var body: Sprite2D = $Body


func _ready() -> void:
	type = clampi(type, 0, TYPES.size() - 1)
	hp = TYPES[type].hp
	if world == Vector2.INF:
		world = position
	_base_x = world.x
	var tex := Ships.get_lit_enemy_texture(TYPES[type].ship)
	body.texture = tex
	_apply_depth()
	# Godot flips the normal map's Y along with flip_v (checked empirically on 4.6), so
	# the shared normal map lights correctly upside down; no flipped variant needed.
	body.flip_v = true
	body.light_mask = Ships.LIGHT_MASK
	area_entered.connect(_on_area_entered)


func points() -> int:
	return TYPES[type].points


## Every peer sizes and fades the ship from its replicated screen position.
func _process(_delta: float) -> void:
	if _last_y != INF:
		_travel += absf(position.y - _last_y)
	_last_y = position.y
	_apply_depth()


func _apply_depth() -> void:
	var s := Depth.scale_at(position.y)
	body.scale = Ships.scale_for(body.texture, HEIGHT) * s
	$Shape.scale = Vector2.ONE * s
	body.modulate.a = clampf(_travel / RISE, 0.0, 1.0) if position.y < Depth.REF_Y else 1.0


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	simulate(delta)
	if world.y > EXIT_Y:
		queue_free()


func simulate(delta: float) -> void:
	_time += delta
	world.y += speed_now() * delta
	match type:
		WEAVER:
			var x := _base_x + sin(_time * WEAVE_FREQUENCY) * WEAVE_AMPLITUDE
			world.x = clampf(x, 20.0, ARENA_WIDTH - 20.0)
		DIVER:
			var center := group_x if group_x >= 0.0 else _base_x
			world.x = zigzag_center(center, zig_dir, _time) + (_base_x - center)
	position = Depth.project(world)


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


func take_damage(amount: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or hp <= 0:
		return
	hp -= amount
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


func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if area.is_in_group("bullet"):
		area.queue_free()
		take_damage(1)
