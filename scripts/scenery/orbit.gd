extends "res://scripts/scenery/scenery.gd"
## Planet Orbit: a big planet hangs half off one side of the screen (side from
## run_seed), slowly turning: bands and continents scroll across its disc, the
## night side is shaded and the atmosphere glows along its curved horizon.
## Hazards: its gravity pulls ships gently toward that side (push_at), and
## every RING_INTERVAL s the host sends in a curved arc of debris and small
## asteroids with a gap to fly through. Boss: "orbital strike", shots from the
## planet's side aimed across the screen at the target, plus an aimed spread.

const ARENA := Vector2(540, 960)
const PLANET_RADIUS := 420.0  # px
const PLANET_SHOWN := 190.0  # px of the disc on screen at its widest
const PLANET_Y := 470.0  # center height
const SPIN := 0.05  # rad/s the surface turns
const TILT := 0.35  # rad the terminator is tilted
const NIGHT_DEPTH := 0.45  # terminator ellipse minor axis vs the radius
const ARC_STEPS := 24  # polygon points per half circle
const CONTINENTS := 9
const BANDS := 6
const OCEAN := Color(0.10, 0.32, 0.42)
const LAND := Color(0.28, 0.55, 0.36)
const BAND := Color(0.55, 0.85, 0.9, 0.10)
const NIGHT := Color(0.0, 0.01, 0.04, 0.55)
const GLOW := Color(0.48, 1.0, 0.71)  # rim glow, the kind's color

const GRAVITY_MAX := 55.0  # px/s pull at the planet's horizon
const GRAVITY_FALLOFF := 220.0  # px from the horizon where the pull halves

const RING_FIRST := 8.0  # s before the first debris ring
const RING_INTERVAL := 15.0  # s between debris rings
const RING_SLOTS := 9  # pieces across a ring, before the gap
const RING_GAP := 2  # slots left open to fly through
const RING_MARGIN := 30.0  # px from the screen edges
const RING_LAG := 260.0  # px the far end trails the planet end: the arc's curve
const RING_PIECES := ["debris", "asteroid_s"]

const STRIKE_MIN := 2  # orbital strike shots from the planet's side
const STRIKE_MAX := 4
const STRIKE_SPACING := 90.0  # px between strike shots' start heights
const STRIKE_INSET := 6.0  # px in from the screen edge they start
const SPREAD := 3  # aimed shots from the boss
const SPREAD_ANGLE := 0.22  # rad between them

var side := -1.0  # -1 planet on the left, 1 on the right
var center := Vector2.ZERO  # planet center (often off screen)
var rings_sent := 0  # host: debris rings spawned so far
var _night := PackedVector2Array()  # night side polygon around the planet center
var _land: Array = []  # [lon, lat, size] per continent


func _ready() -> void:
	side = -1.0 if roll(0, 1) < 0.5 else 1.0
	var cx := PLANET_SHOWN - PLANET_RADIUS
	center = Vector2(cx if side < 0.0 else ARENA.x - cx, PLANET_Y)
	_build_night()
	for i in CONTINENTS:
		_land.append([roll(i, 2) * TAU, (roll(i, 3) - 0.5) * 2.4, 40.0 + 70.0 * roll(i, 4)])


## The night side: half the disc's rim, back along the terminator ellipse.
func _build_night() -> void:
	_night.clear()
	var tilt := TILT * -side
	for i in ARC_STEPS + 1:
		var a := PI * i / ARC_STEPS
		_night.append(Vector2(cos(a), sin(a)).rotated(tilt) * PLANET_RADIUS)
	for i in range(ARC_STEPS - 1, 0, -1):
		var a := PI * i / ARC_STEPS
		_night.append(Vector2(cos(a) * PLANET_RADIUS, sin(a) * PLANET_RADIUS * NIGHT_DEPTH).rotated(tilt))


func step(_delta: float) -> void:
	if game == null or not game.multiplayer.is_server() or not game.active:
		return
	if game.fork_open():
		return
	while time >= ring_time(rings_sent):
		_send_ring(rings_sent)
		rings_sent += 1


## When debris ring `k` comes in (s of scenery time).
func ring_time(k: int) -> float:
	return RING_FIRST + RING_INTERVAL * k


## Debris ring `k`: [{piece, pos}], the same on every peer for the same seed.
func ring_layout(k: int) -> Array:
	var out := []
	var gap := int(roll(k, 10) * (RING_SLOTS - RING_GAP + 1))
	var width := ARENA.x - 2.0 * RING_MARGIN
	for i in RING_SLOTS:
		if i >= gap and i < gap + RING_GAP:
			continue
		var x := RING_MARGIN + width * i / (RING_SLOTS - 1)
		var f := (x if side < 0.0 else ARENA.x - x) / ARENA.x  # 0 at the planet
		var piece: String = RING_PIECES[int(roll(k * RING_SLOTS + i, 11) * RING_PIECES.size())]
		out.append({"piece": piece, "pos": Vector2(x, -30.0 - RING_LAG * f * f)})
	return out


func _send_ring(k: int) -> void:
	for p in ring_layout(k):
		game.spawn_obstacle_at(p.piece, p.pos, side)


func push_at(pos: Vector2) -> Vector2:
	var to := center - pos
	var d := maxf(to.length() - PLANET_RADIUS, 0.0)
	return to.normalized() * GRAVITY_MAX / (1.0 + d / GRAVITY_FALLOFF)


## Orbital strike: shots from the planet's edge of the screen, spread over the
## target's height and aimed at it, plus an aimed spread from the boss.
func boss_attack(boss: Node2D, target: Node2D, n: int) -> bool:
	var edge := STRIKE_INSET if side < 0.0 else ARENA.x - STRIKE_INSET
	var strikes := clampi(n - 2, STRIKE_MIN, STRIKE_MAX)
	for i in strikes:
		var y := clampf(target.position.y + (i - (strikes - 1) / 2.0) * STRIKE_SPACING, 40.0, ARENA.y - 40.0)
		var from := Vector2(edge, y)
		game.fire_enemy_bullet.rpc(from, target.position - from)
	var aim := (target.position - boss.position).normalized()
	for i in SPREAD:
		game.fire_enemy_bullet.rpc(boss.position + aim * 50.0, aim.rotated((i - (SPREAD - 1) / 2.0) * SPREAD_ANGLE))
	return true


func _draw() -> void:
	for i in 4:  # atmosphere haze beyond the horizon
		draw_circle(center, PLANET_RADIUS + 34.0 - i * 8.0, Color(GLOW, 0.03 + 0.02 * i))
	draw_circle(center, PLANET_RADIUS, OCEAN)
	for i in BANDS:
		var lat := (i + 0.5) / BANDS * 2.6 - 1.3
		var y := center.y + sin(lat) * PLANET_RADIUS
		var half := cos(lat) * PLANET_RADIUS
		draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), BAND, 10.0 + 6.0 * (i % 3))
	var rot := time * SPIN * -side  # surface turns toward the open screen
	for c in _land:
		var lon: float = c[0] + rot
		var depth := cos(lon) * cos(c[1])  # toward the viewer
		if depth <= 0.05:
			continue
		var at := center + Vector2(sin(lon) * cos(c[1]), sin(c[1])) * PLANET_RADIUS
		draw_circle(at, c[2] * sqrt(depth), Color(LAND, 0.4 + 0.5 * depth))
		draw_circle(at + Vector2(c[2] * 0.3, -c[2] * 0.2) * depth, c[2] * 0.6 * sqrt(depth), Color(LAND.lightened(0.15), 0.5 * depth))
	draw_set_transform(center)
	draw_colored_polygon(_night, NIGHT)
	draw_set_transform(Vector2.ZERO)
	for i in 3:  # rim glow along the curved horizon
		draw_arc(center, PLANET_RADIUS - 2.0 - i * 4.0, 0.0, TAU, 96, Color(GLOW, 0.5 - 0.15 * i), 3.0 - i)
