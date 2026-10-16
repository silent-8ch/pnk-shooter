extends Area2D
## Enemy ship. Server-simulated; `type` picks the look and behavior.
##   WEAVER (ship 01): weaves side to side as it drifts down; comes in lines.
##   DIVER  (ship 02): faster, steers toward the nearest living player; comes in Vs.

enum { WEAVER, DIVER }

const TYPES: Array[Dictionary] = [
	{"ship": 0, "hp": 1, "points": 10, "speed": 90.0},
	{"ship": 1, "hp": 1, "points": 15, "speed": 130.0},
]
const HEIGHT := 36.0
const WEAVE_AMPLITUDE := 60.0
const WEAVE_FREQUENCY := 2.5  # radians per second
const DIVE_STEER_SPEED := 70.0  # max horizontal speed while diving
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

var hp := 0
var _base_x := 0.0
var _time := 0.0

@onready var body: Sprite2D = $Body


func _ready() -> void:
	type = clampi(type, 0, TYPES.size() - 1)
	hp = TYPES[type].hp
	_base_x = position.x
	var tex := Ships.get_enemy_texture(TYPES[type].ship)
	body.texture = tex
	body.scale = Ships.scale_for(tex, HEIGHT)
	body.flip_v = true
	area_entered.connect(_on_area_entered)


func points() -> int:
	return TYPES[type].points


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	simulate(delta)
	if position.y > EXIT_Y:
		queue_free()


func simulate(delta: float) -> void:
	_time += delta
	position.y += speed_now() * delta
	match type:
		WEAVER:
			var x := _base_x + sin(_time * WEAVE_FREQUENCY) * WEAVE_AMPLITUDE
			position.x = clampf(x, 20.0, ARENA_WIDTH - 20.0)
		DIVER:
			var target := _nearest_player()
			if target:
				var dx := target.position.x - position.x
				position.x += clampf(dx, -DIVE_STEER_SPEED * delta, DIVE_STEER_SPEED * delta)


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


func _nearest_player() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("player"):
		if not p.is_alive() or p.position.y < position.y:
			continue  # only dive at living players still below
		var d := position.distance_squared_to(p.position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func take_damage(amount: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	hp -= amount
	if hp <= 0:
		get_tree().get_first_node_in_group("game").add_score(points())
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if area.is_in_group("bullet"):
		area.queue_free()
		take_damage(1)
