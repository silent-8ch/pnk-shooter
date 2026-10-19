extends Area2D
## Tetran, after the Life Force boss: a big armored core with four straight
## segmented arms so long they run off every edge of the screen. It glides
## down to HOVER and holds there, turning steadily one way; ships have to orbit
## it to stay in a gap between two arms. Only the core (its Enemy) can be hurt: the
## arms soak up shots and hurt any ship they touch (group "hazard", see
## Player). It never fires; the small groups that come in during any boss
## fight (Game.BOSS_ADD_TYPES) keep the pressure on.
## A child of its Enemy (type TETRAN). Everything follows the Enemy's flight
## time, so every peer sees the same core and arms with no syncing.
## Drawn in code until it has art: a pulsing core in an armored ring, arms of
## shrinking plated segments.

const ARMS := 4
const SEGMENTS := 36
const SEG_LEN := 32.0  # px between segment centres
const SEG_RADIUS := Vector2(18, 12)  # first and last segment
const ARM_WIDTH := 24.0  # the hit box: the narrowest segment's width all along
const CORE_RADIUS := 56.0
const HOVER := Vector2(270, 400)  # where it holds, a little above the middle
const SPIN := 0.45  # radians per second
const START_ANGLE := PI / 4.0  # an X, so the ships at the bottom start in a gap
const CORE_COLOR := Color("ff5a3c")
const ARMOR_COLOR := Color("7f8aa3")
const SEG_COLOR := Color("5d6a85")

var enemy: Node2D  # the core
var _shapes: Array[CollisionShape2D] = []


func _ready() -> void:
	enemy = get_parent()
	add_to_group("hazard")
	collision_layer = 2  # ships run into it like an enemy
	collision_mask = 4  # bullets
	for a in ARMS:
		var s := CollisionShape2D.new()
		s.shape = RectangleShape2D.new()
		s.shape.size = Vector2(arm_length(), ARM_WIDTH)
		add_child(s)
		_shapes.append(s)
	area_entered.connect(_on_area_entered)
	_place_shapes()


func _time() -> float:
	return enemy.get("_time") if enemy else 0.0


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_place_shapes()
	queue_redraw()


func _place_shapes() -> void:
	var turn := angle_at(_time())
	for a in ARMS:
		var dir := arm_angle(turn, a)
		_shapes[a].position = Vector2.from_angle(dir) * (CORE_RADIUS + arm_length() / 2.0)
		_shapes[a].rotation = dir


## From the core's edge to the last segment's centre.
static func arm_length() -> float:
	return SEGMENTS * SEG_LEN


static func segment_radius(i: int) -> float:
	return lerpf(SEG_RADIUS.x, SEG_RADIUS.y, float(i) / (SEGMENTS - 1))


static func arm_angle(turn: float, a: int) -> float:
	return turn + a * TAU / ARMS


## Where the core is `time` s after spawning at `spawn`: it glides down to
## HOVER and holds there.
static func core_position(spawn: Vector2, time: float, speed: float) -> Vector2:
	return Vector2(HOVER.x, minf(spawn.y + speed * time, HOVER.y))


## How it's turned at `time`: always the same way at SPIN.
static func angle_at(time: float) -> float:
	return START_ANGLE + SPIN * time


## Every segment centre, arm by arm, relative to the core (game space, not
## scaled): straight out from the core at its quarter of the turn.
static func arm_points(time: float) -> Array:
	var out: Array = []
	var turn := angle_at(time)
	for a in ARMS:
		var dir := Vector2.from_angle(arm_angle(turn, a))
		var arm: Array[Vector2] = []
		for i in SEGMENTS:
			arm.append(dir * (CORE_RADIUS + SEG_RADIUS.x * 0.5 + i * SEG_LEN))
		out.append(arm)
	return out


## Whether a circle at `at` (game space), radius `r`, touches an arm.
func touches(at: Vector2, r: float) -> bool:
	var turn := angle_at(_time())
	var s: float = enemy.scale.x
	for a in ARMS:
		var dir := Vector2.from_angle(arm_angle(turn, a))
		var root: Vector2 = enemy.position + dir * CORE_RADIUS * s
		var tip: Vector2 = enemy.position + dir * (CORE_RADIUS + arm_length()) * s
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, root, tip)) < ARM_WIDTH * 0.5 * s + r:
			return true
	return false


## The arms soak up shots: every peer removes a bullet that hits them, no damage.
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("bullet") and not area.is_hostile():
		area.queue_free()


func _draw() -> void:
	var time := _time()
	for arm in arm_points(time):
		for i in range(SEGMENTS - 1, -1, -1):  # outermost first, so the root sits on top
			var r := segment_radius(i)
			var p: Vector2 = arm[i]
			draw_circle(p, r + 1.5, Color(0, 0, 0, 0.6))
			draw_circle(p, r, SEG_COLOR.lerp(ARMOR_COLOR, float(i % 2)))
			draw_circle(p + Vector2(-r, -r) * 0.3, r * 0.35, Color(1, 1, 1, 0.18))
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	draw_circle(Vector2.ZERO, CORE_RADIUS + 5.0, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, CORE_RADIUS, ARMOR_COLOR)
	draw_circle(Vector2.ZERO, CORE_RADIUS * 0.72, Color(0.08, 0.08, 0.12))
	draw_circle(Vector2.ZERO, CORE_RADIUS * (0.5 + 0.08 * pulse), CORE_COLOR.lightened(0.3 * pulse))
	var turn := angle_at(time)
	for a in ARMS:  # armor plates between the arms
		draw_arc(Vector2.ZERO, CORE_RADIUS - 4.0, arm_angle(turn, a) + 0.35, arm_angle(turn, a + 1) - 0.35, 12,
			ARMOR_COLOR.lightened(0.25), 6.0, true)
