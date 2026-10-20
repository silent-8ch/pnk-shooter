class_name TitleDance
extends Node2D
## Behind the title: ships 01 and 02 dancing, a slow loop of LOOP s. They
## circle each other wide, swoop together, meet nose to nose for a kiss (a
## little burst of hearts), hold each other close spinning slowly, then drift
## apart to start again. Their thrusters fire as they change course, like
## they do in the game (Thrusters). pose_at(t) is the whole routine, so it's easy to
## check and the same every time; each ship faces where it's heading, or its
## partner when they're close. Lit like the game: dimmed by a shade, lit by the Sun
## off the screen's top-left corner, and they shadow each other.

const LOOP := 12.0  # s
const WIDE := 140.0  # px apart (radius) while circling
const CLOSE := 26.0  # px apart (radius) in the embrace
const KISS := 18.0  # px: nose to nose
const SHIP_HEIGHT := 70.0
const HEART := Color("ff5fa2")
const HEART_COUNT := 7
const HEART_LIFE := 1.6  # s
## Phases, in loop seconds: circle, swoop in, kiss, embrace, drift apart.
const CIRCLE_END := 3.5
const SWOOP_END := 5.0
const KISS_END := 6.5
const EMBRACE_END := 10.0

var center := Vector2(270, 560)
var _a := Sprite2D.new()
var _b := Sprite2D.new()
var _time := 0.0


func _ready() -> void:
	var screen := get_viewport_rect()
	add_child(Sun.make_shade(screen))
	add_child(Sun.make(screen))
	for pair in [[_a, 0], [_b, 1]]:
		var s: Sprite2D = pair[0]
		var ship: int = pair[1]
		s.texture = Ships.get_lit_texture(ship, Ships.palette_for(ship))
		s.scale = Ships.scale_for(s.texture, SHIP_HEIGHT)
		s.light_mask = Ships.LIGHT_MASK
		add_child(s)
		Sun.occlude(s)
		var jets := Thrusters.new()  # they fire as the dancers swoop and turn
		jets.name = "Thrusters"
		jets.radius = SHIP_HEIGHT / 2.0
		jets.layout = Thrusters.scaled(Ships.thruster_layout(ship), SHIP_HEIGHT / Ships.SHIP_HEIGHT)
		s.add_child(jets)
	_apply(pose_at(0.0))


func _process(delta: float) -> void:
	_time += delta
	var vp := get_viewport_rect().size
	center = Vector2(vp.x * 0.5, vp.y * 0.58)
	_apply(pose_at(_time))
	queue_redraw()


## How far apart (radius from their middle) and how far round they are at loop time `t`.
static func spacing_at(t: float) -> float:
	var u := fposmod(t, LOOP)
	if u < CIRCLE_END:
		return WIDE
	if u < SWOOP_END:
		return lerpf(WIDE, KISS, smoothstep(CIRCLE_END, SWOOP_END, u))
	if u < KISS_END:
		return KISS
	if u < EMBRACE_END:
		return lerpf(KISS, CLOSE, smoothstep(KISS_END, KISS_END + 0.6, u))
	return lerpf(CLOSE, WIDE, smoothstep(EMBRACE_END, LOOP, u))


## The angle round their middle at loop time `t`: brisk while dancing, still
## for the kiss, a slow sway in the embrace. Continuous across the loop.
static func turn_at(t: float) -> float:
	var u := fposmod(t, LOOP)
	var spins := floorf(t / LOOP)
	var full := _turn(LOOP)
	return spins * full + _turn(u)


static func _turn(u: float) -> float:
	var a := 0.0
	a += 1.4 * minf(u, CIRCLE_END)  # circling
	if u > CIRCLE_END:
		a += 0.7 * (minf(u, SWOOP_END) - CIRCLE_END)  # slowing as they swoop in
	if u > KISS_END:
		a += 0.35 * (minf(u, EMBRACE_END) - KISS_END)  # swaying together
	if u > EMBRACE_END:
		a += 1.0 * (u - EMBRACE_END)  # twirling apart
	return a


## Both ships at loop time `t` (relative to the middle): {a, b} positions,
## {a_rot, b_rot} facings (0 = up), and `kiss`/`embrace` amounts 0..1.
static func pose_at(t: float) -> Dictionary:
	var r := spacing_at(t)
	var ang := turn_at(t)
	var a_pos := Vector2.from_angle(ang) * r
	var b_pos := -a_pos
	var u := fposmod(t, LOOP)
	var close := 1.0 - clampf((r - KISS) / (WIDE - KISS), 0.0, 1.0)
	# Far apart they face along the dance (tangent); close, they face each other.
	var tangent := Vector2.from_angle(ang + PI / 2.0)
	var a_face := tangent.lerp((b_pos - a_pos).normalized(), close).normalized()
	var b_face := (-tangent).lerp((a_pos - b_pos).normalized(), close).normalized()
	var kiss := 1.0 if u >= SWOOP_END and u < KISS_END else 0.0
	var embrace := 1.0 if u >= KISS_END and u < EMBRACE_END else 0.0
	return {"a": a_pos, "b": b_pos, "a_rot": Vector2.UP.angle_to(a_face), "b_rot": Vector2.UP.angle_to(b_face),
		"kiss": kiss, "embrace": embrace, "time": u}


func _apply(pose: Dictionary) -> void:
	_a.position = center + pose.a
	_b.position = center + pose.b
	_a.rotation = pose.a_rot
	_b.rotation = pose.b_rot
	var lean: float = 0.12 * pose.embrace  # leaning into each other
	_a.rotation += lean
	_b.rotation += lean


## The hearts from the kiss: rising, swaying and fading over HEART_LIFE.
func _draw() -> void:
	var since: float = fposmod(_time, LOOP) - SWOOP_END
	if since < 0.0 or since > HEART_LIFE:
		return
	var t := since / HEART_LIFE
	for i in HEART_COUNT:
		var x := (i - (HEART_COUNT - 1) / 2.0) * 12.0 + sin(since * 4.0 + i) * 6.0
		var at := center + Vector2(x, -10.0 - 90.0 * t * (0.6 + 0.4 * fmod(i * 0.37, 1.0)))
		_heart(at, 5.0 + 3.0 * (1.0 - t), Color(HEART, 1.0 - t))


func _heart(at: Vector2, size: float, c: Color) -> void:
	draw_circle(at + Vector2(-size * 0.5, 0), size * 0.55, c)
	draw_circle(at + Vector2(size * 0.5, 0), size * 0.55, c)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-size, size * 0.15), at + Vector2(size, size * 0.15),
		at + Vector2(0, size * 1.3)]), c)
