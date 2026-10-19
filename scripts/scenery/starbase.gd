extends "res://scripts/scenery/scenery.gd"
## Ruined Starbase: flying through the wreck of a space station. Behind the
## action, dark hull plating scrolls by: panel seams, rivets, flickering lit
## windows and the odd shower of sparks (cosmetic, randf is fine there).
## Hazard: blast doors. Every DOOR_INTERVAL s a horizontal band flashes warning
## stripes for DOOR_WARN s, then slams shut except for one gap; a ship caught in
## the sealed part takes a hit. The door stays shut DOOR_SHUT s. Band and gap
## come from roll() so every peer sees the same doors.
## Boss: sweeping turret fire, a fan of bullets whose aim swings a little
## further across the screen with each volley instead of aiming at anyone.

const WIDTH := 540.0
const HEIGHT := 960.0
const SCROLL := 40.0  # px/s the hull plating drifts down
const PANEL := Vector2(90, 64)  # one hull plate
const SEAM_COLOR := Color(0.02, 0.02, 0.03)
const PLATE_COLORS := [Color(0.10, 0.10, 0.12), Color(0.12, 0.12, 0.14), Color(0.085, 0.09, 0.105)]
const RIVET_COLOR := Color(0.22, 0.23, 0.27)
const RIVET_INSET := 6.0  # px from a plate's corner
const RIVETS := [Vector2(RIVET_INSET, RIVET_INSET), Vector2(PANEL.x - RIVET_INSET, RIVET_INSET),
	Vector2(RIVET_INSET, PANEL.y - RIVET_INSET), Vector2(PANEL.x - RIVET_INSET, PANEL.y - RIVET_INSET)]
const WINDOW_SIZE := Vector2(14, 8)
const WINDOW_LIT := Color(1.0, 0.82, 0.45, 0.85)
const WINDOW_DARK := Color(0.04, 0.05, 0.07)
const WINDOW_CHANCE := 0.35  # plates with a window row
const SPARK_COUNT := 10  # spark slots, reused
const SPARK_LIFE := 0.5  # s
const SPARK_RATE := 1.2  # bursts per second
const SPARK_COLOR := Color(1.0, 0.85, 0.4)

const DOOR_FIRST := 10.0  # s before the first door
const DOOR_INTERVAL := 18.0  # s between doors
const DOOR_WARN := 1.5  # s of warning stripes before it shuts
const DOOR_SHUT := 1.0  # s the shut door stays visible
const DOOR_BAND := 70.0  # px tall
const DOOR_Y := Vector2(220, 760)  # band center range
const DOOR_GAP := 130.0  # px wide opening
const DOOR_EDGE := 20.0  # the gap keeps this far from the screen edge
const DOOR_HITS := 1.0
const STRIPE := 36.0  # px per warning stripe
const STRIPE_SLANT := 18.0
const WARN_COLOR := Color(1.0, 0.8, 0.1, 0.55)
const WARN_DARK := Color(0.08, 0.07, 0.02, 0.45)
const GAP_COLOR := Color(0.4, 1.0, 0.6, 0.8)
const DOOR_COLOR := Color(0.32, 0.34, 0.38)
const DOOR_EDGE_COLOR := Color(0.85, 0.65, 0.15)

const SWEEP_STEP := 0.45  # rad the sweep phase moves per volley
const SWEEP_ARC := 1.0  # rad the fan's aim swings to either side of straight down
const FAN_SPREAD := 0.22  # rad between bullets in a fan
const MUZZLE := 50.0  # px from the boss's center

var _overlay: Node2D  # on top of the ships: door warnings and doors
var _shut_index := -1  # last door that has slammed
var _sweep := 0.0  # boss sweep phase
var _sparks: Array[Vector3] = []  # x, y, age (age >= SPARK_LIFE = unused)
var _spark_timer := 0.0


func _ready() -> void:
	_overlay = Node2D.new()
	_overlay.z_index = 50
	_overlay.draw.connect(_draw_doors)
	add_child(_overlay)
	for i in SPARK_COUNT:
		_sparks.append(Vector3(0, 0, SPARK_LIFE))


func step(delta: float) -> void:
	var i := door_index(time)
	if i >= 0 and i > _shut_index and time >= door_start(i) + DOOR_WARN:
		_shut_index = i
		_shut(i)
	_step_sparks(delta)
	_overlay.queue_redraw()


# --- Blast doors ------------------------------------------------------------------

## The latest door started by time `t`, or -1 before the first.
func door_index(t: float) -> int:
	if t < DOOR_FIRST:
		return -1
	return floori((t - DOOR_FIRST) / DOOR_INTERVAL)


## When door `i`'s warning starts (it shuts DOOR_WARN s later).
func door_start(i: int) -> float:
	return DOOR_FIRST + i * DOOR_INTERVAL


## Door `i`'s band: top and bottom y.
func door_band(i: int) -> Vector2:
	var y := lerpf(DOOR_Y.x, DOOR_Y.y, roll(i, 1))
	return Vector2(y - DOOR_BAND / 2.0, y + DOOR_BAND / 2.0)


## Door `i`'s opening: left and right x.
func door_gap(i: int) -> Vector2:
	var x := lerpf(DOOR_EDGE + DOOR_GAP / 2.0, WIDTH - DOOR_EDGE - DOOR_GAP / 2.0, roll(i, 2))
	return Vector2(x - DOOR_GAP / 2.0, x + DOOR_GAP / 2.0)


## True if `pos` is in the sealed part of door `i`.
func sealed_at(i: int, pos: Vector2) -> bool:
	var band := door_band(i)
	var gap := door_gap(i)
	return pos.y >= band.x and pos.y <= band.y and (pos.x < gap.x or pos.x > gap.y)


## Door `i` slams: each ship this peer flies inside the sealed part takes a hit.
func _shut(i: int) -> void:
	if game == null or (game.has_method("fork_open") and game.fork_open()):
		return
	for p in game.players.get_children():
		if p.is_local() and p.is_alive() and sealed_at(i, p.position):
			p.take_damage(DOOR_HITS, false)  # just this ship, not its neighbours in the gap


func _draw_doors() -> void:
	var i := door_index(time)
	if i < 0:
		return
	var t := time - door_start(i)
	if t >= DOOR_WARN + DOOR_SHUT:
		return
	var band := door_band(i)
	var gap := door_gap(i)
	if t < DOOR_WARN:
		var on := fmod(t, 0.3) < 0.2  # flashing
		_draw_stripes(0.0, gap.x, band, on)
		_draw_stripes(gap.y, WIDTH, band, on)
		_overlay.draw_rect(Rect2(gap.x, band.x, gap.y - gap.x, band.y - band.x), GAP_COLOR, false, 2.0)
		return
	for r in [Rect2(0, band.x, gap.x, band.y - band.x), Rect2(gap.y, band.x, WIDTH - gap.y, band.y - band.x)]:
		_overlay.draw_rect(r, DOOR_COLOR)
		_overlay.draw_rect(r, DOOR_EDGE_COLOR, false, 3.0)
	_overlay.draw_line(Vector2(gap.x, band.x), Vector2(gap.x, band.y), DOOR_EDGE_COLOR, 4.0)
	_overlay.draw_line(Vector2(gap.y, band.x), Vector2(gap.y, band.y), DOOR_EDGE_COLOR, 4.0)


func _draw_stripes(x0: float, x1: float, band: Vector2, on: bool) -> void:
	if x1 - x0 < 1.0:
		return
	_overlay.draw_rect(Rect2(x0, band.x, x1 - x0, band.y - band.x), WARN_DARK)
	if not on:
		return
	var x := x0
	while x < x1:
		var w := minf(STRIPE / 2.0, x1 - x)
		var s := minf(STRIPE_SLANT, x1 - x - w)
		_overlay.draw_colored_polygon(PackedVector2Array([Vector2(x, band.y), Vector2(x + w, band.y),
			Vector2(x + w + s, band.x), Vector2(x + s, band.x)]), WARN_COLOR)
		x += STRIPE


# --- Boss -----------------------------------------------------------------------

## Sweeping turret fire: a fan of `n` bullets aimed along a swinging angle.
func boss_attack(boss: Node2D, _target: Node2D, n: int) -> bool:
	if game == null:
		return false
	var aim := Vector2.DOWN.rotated(sin(_sweep) * SWEEP_ARC)
	_sweep += SWEEP_STEP
	for k in n:
		var dir := aim.rotated((k - (n - 1) / 2.0) * FAN_SPREAD)
		game.fire_enemy_bullet.rpc(boss.position + dir * MUZZLE, dir)
	return true


# --- Look (cosmetic) ----------------------------------------------------------------

func _step_sparks(delta: float) -> void:
	for k in _sparks.size():
		var s := _sparks[k]
		if s.z < SPARK_LIFE:
			_sparks[k] = Vector3(s.x, s.y + SCROLL * delta, s.z + delta)
	_spark_timer += delta
	if _spark_timer < 1.0 / SPARK_RATE:
		return
	_spark_timer = 0.0
	var at := Vector2(randf() * WIDTH, randf() * HEIGHT)
	var made := 0
	for k in _sparks.size():
		if _sparks[k].z >= SPARK_LIFE and made < 3:
			_sparks[k] = Vector3(at.x + randf_range(-6, 6), at.y + randf_range(-6, 6), randf() * 0.15)
			made += 1


func _draw() -> void:
	var off := fmod(time * SCROLL, PANEL.y)
	var row0 := floori(time * SCROLL / PANEL.y)  # rows scrolled past, so plates keep their look
	var cols := ceili(WIDTH / PANEL.x)
	var rows := ceili(HEIGHT / PANEL.y) + 1
	for r in rows:
		var y := off + (r - 1) * PANEL.y
		var id := row0 - r + 1  # the same plate keeps the same id as it scrolls
		for c in cols:
			_draw_plate(Vector2(c * PANEL.x, y), id, c)
	for s in _sparks:
		if s.z < SPARK_LIFE:
			var a := 1.0 - s.z / SPARK_LIFE
			draw_circle(Vector2(s.x, s.y), 1.5 + 2.0 * a, Color(SPARK_COLOR, a))


func _draw_plate(at: Vector2, row: int, col: int) -> void:
	var h := ((row * 73856093) ^ (col * 19349663)) & 0x7fffffff
	draw_rect(Rect2(at, PANEL), PLATE_COLORS[h % PLATE_COLORS.size()])
	draw_rect(Rect2(at, PANEL), SEAM_COLOR, false, 2.0)
	for corner in RIVETS:
		draw_circle(at + corner, 1.6, RIVET_COLOR)
	if float((h >> 8) % 100) / 100.0 >= WINDOW_CHANCE:
		return
	for w in 4:
		var lit := ((h >> (12 + w)) & 1) == 1 and sin(time * (3.0 + w) + float(h % 7)) > -0.85
		var pos := at + Vector2(12 + w * 18, PANEL.y / 2.0 - WINDOW_SIZE.y / 2.0)
		draw_rect(Rect2(pos, WINDOW_SIZE), WINDOW_LIT if lit else WINDOW_DARK)
