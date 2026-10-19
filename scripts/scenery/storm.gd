extends "res://scripts/scenery/scenery.gd"
## Ion Storm: dark purple clouds churn behind the action, with distant flashes.
## Every few seconds lightning picks a spot: a pulsing ring warns for a moment,
## then a bolt comes down from the top and hurts any ship inside. Gusts of wind
## shove ships sideways, and a dark overlay cuts visibility (flickering bright
## on each strike). The boss calls down chain lightning on a player's spot
## (a strike on them and two near them) and fires an aimed spread.
## Strike times, spots and gusts come from run_seed and time, so every peer
## agrees; the boss's strikes are sent by the host (chain_strike).

const STRIKE_GAP := 3.25  # s between strikes on average
const STRIKE_JITTER := 0.75  # s a strike's time can move (gaps stay 2.5..4 s)
const STRIKE_RADIUS := 55.0  # px hurt around a strike's spot
const WARN_TIME := 1.0  # s the ring warns before the bolt
const BOLT_TIME := 0.25  # s the bolt stays on screen
const STRIKE_AREA := Rect2(40, 160, 460, 760)  # where strikes can land
const STRIKE_HITS := 1.0  # hits a strike does
const BOLT_STEPS := 9  # jagged segments in a bolt
const BOLT_WOBBLE := 26.0  # px a bolt's joints stray sideways
const GUST_TIME := 3.0  # s per gust
const WIND_MAX := 90.0  # px/s strongest sideways push
const DARK_ALPHA := 0.25  # overlay darkness
const FLASH_TIME := 0.35  # s the screen flickers after a strike
const CLOUDS := 14  # cloud blobs
const CLOUD_SPEED := Vector2(6, 22)  # px/s cloud drift range (down)
const FAR_FLASH_GAP := Vector2(1.5, 4.0)  # s between cosmetic distant flashes
const FAR_FLASH_TIME := 0.3  # s a distant flash lasts
const CHAIN_SPOTS := 3  # boss strikes per attack
const CHAIN_SPREAD := Vector2(45, 95)  # px from the target for the 2nd/3rd strike
const SPREAD := 0.22  # rad between the boss's bullets
const CLOUD_COLOR := Color(0.32, 0.16, 0.48, 0.10)
const WARN_COLOR := Color(0.85, 0.7, 1.0)
const BOLT_COLOR := Color(0.9, 0.85, 1.0)
const BOLT_GLOW := Color(0.7, 0.45, 1.0, 0.5)

var _next_strike := 1  # index of the next ambient strike to land
var _clouds := []  # cosmetic: {pos, r, speed, sway}
var _far_flash := 0.0  # s left on the current distant flash
var _far_flash_at := Vector2.ZERO
var _far_flash_wait := 2.0
var _flash := 0.0  # s left of the strike flicker
var _bolts := []  # {points: PackedVector2Array, left}
var _chain := []  # boss strikes warning: {pos, left}
var _boss_attacks := 0  # host: chain lightning calls so far
var _overlay: Node2D


func _ready() -> void:
	for i in CLOUDS:
		_clouds.append({"pos": Vector2(randf() * 540.0, randf() * 960.0), "r": randf_range(70, 160),
			"speed": randf_range(CLOUD_SPEED.x, CLOUD_SPEED.y), "sway": randf() * TAU})
	_overlay = Node2D.new()
	_overlay.name = "StormOverlay"
	_overlay.z_index = 50
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Inside a warning ring that lands within BOLT_TIME of `ahead` s from now
## (an ambient strike or the boss's chain lightning).
func danger_at(pos: Vector2, ahead: float) -> float:
	var at := time + ahead
	var reach := STRIKE_RADIUS + 18.0
	for s in strikes_between(at - BOLT_TIME, at + WARN_TIME):
		if s.pos.distance_to(pos) < reach:
			return 1.0
	for c in _chain:
		if c.left < ahead + BOLT_TIME + 0.4 and c.pos.distance_to(pos) < reach:
			return 1.0
	return 0.0


## When ambient strike `k` (from 1) lands.
func strike_time(k: int) -> float:
	return k * STRIKE_GAP + (roll(k, 1) - 0.5) * STRIKE_JITTER


## Where ambient strike `k` lands.
func strike_pos(k: int) -> Vector2:
	return STRIKE_AREA.position + STRIKE_AREA.size * Vector2(roll(k, 2), roll(k, 3))


## Ambient strikes landing in [t0, t1): [{pos, time}], in order.
func strikes_between(t0: float, t1: float) -> Array:
	var out := []
	var first := maxi(1, floori((t0 - STRIKE_JITTER) / STRIKE_GAP))
	var last := ceili((t1 + STRIKE_JITTER) / STRIKE_GAP)
	for k in range(first, last + 1):
		var t := strike_time(k)
		if t >= t0 and t < t1:
			out.append({"pos": strike_pos(k), "time": t})
	return out


func push_at(_pos: Vector2) -> Vector2:
	return Vector2(wind(time), 0.0)


## Sideways wind (px/s) at time `t`: eases from one gust's strength to the next.
func wind(t: float) -> float:
	var g := floori(t / GUST_TIME)
	var f := smoothstep(0.0, 1.0, t / GUST_TIME - g)
	return lerpf(_gust(g), _gust(g + 1), f)


func _gust(g: int) -> float:
	return (roll(g, 7) * 2.0 - 1.0) * WIND_MAX


func step(delta: float) -> void:
	while strike_time(_next_strike) <= time:
		_land(strike_pos(_next_strike), _next_strike, not _forking())
		_next_strike += 1
	for c in _chain:
		c.left -= delta
		if c.left <= 0.0:
			_land(c.pos, int(c.pos.x * 7.0 + c.pos.y), true)
	_chain = _chain.filter(func(c): return c.left > 0.0)
	for b in _bolts:
		b.left -= delta
	if not _bolts.is_empty() and _bolts[0].left <= 0.0:
		_bolts = _bolts.filter(func(b): return b.left > 0.0)
	_flash = maxf(0.0, _flash - delta)
	_step_cosmetic(delta)
	if _overlay:
		_overlay.queue_redraw()


## A bolt hits `at`: hurts local ships there (if `hurts`), shows the bolt and flicker.
func _land(at: Vector2, seed_i: int, hurts: bool) -> void:
	if hurts:
		hurt_local(at, STRIKE_RADIUS, STRIKE_HITS)
	_bolts.append({"points": _bolt_points(at, seed_i), "left": BOLT_TIME})
	_flash = FLASH_TIME


## No ambient strikes hurt while the party is voting at a fork.
func _forking() -> bool:
	return game != null and game.has_method("fork_open") and game.fork_open()


func _bolt_points(at: Vector2, seed_i: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var top := Vector2(at.x + (roll(seed_i, 4) - 0.5) * 120.0, -10.0)
	for i in BOLT_STEPS + 1:
		var f := float(i) / BOLT_STEPS
		var p := top.lerp(at, f)
		if i > 0 and i < BOLT_STEPS:
			p.x += (roll(seed_i, 10 + i) - 0.5) * 2.0 * BOLT_WOBBLE
		pts.append(p)
	return pts


func _step_cosmetic(delta: float) -> void:
	for c in _clouds:
		c.pos.y += c.speed * delta
		c.sway += delta * 0.4
		if c.pos.y - c.r > 960.0:
			c.pos = Vector2(randf() * 540.0, -c.r)
	_far_flash = maxf(0.0, _far_flash - delta)
	_far_flash_wait -= delta
	if _far_flash_wait <= 0.0:
		_far_flash_wait = randf_range(FAR_FLASH_GAP.x, FAR_FLASH_GAP.y)
		_far_flash = FAR_FLASH_TIME
		_far_flash_at = Vector2(randf() * 540.0, randf() * 600.0)


## Host: chain lightning on `target` plus an aimed spread.
func boss_attack(boss: Node2D, target: Node2D, n: int) -> bool:
	if game == null:
		return false
	var spots := chain_spots(target.position, _boss_attacks)
	_boss_attacks += 1
	chain_strike.rpc(spots)
	var aim := (target.position - boss.position).normalized()
	for i in n:
		game.fire_enemy_bullet.rpc(boss.position + aim * 50.0, aim.rotated((i - (n - 1) / 2.0) * SPREAD))
	return true


## The boss's strike spots for attack `c` on `at`: one on it, the rest near it.
func chain_spots(at: Vector2, c: int) -> PackedVector2Array:
	var spots := PackedVector2Array([at])
	for i in range(1, CHAIN_SPOTS):
		var d := lerpf(CHAIN_SPREAD.x, CHAIN_SPREAD.y, roll(c, 20 + i))
		var p := at + Vector2.from_angle(roll(c, 30 + i) * TAU) * d
		spots.append(p.clamp(STRIKE_AREA.position, STRIKE_AREA.end))
	return spots


## Host -> everyone: boss strikes warn at `spots`, then land after WARN_TIME.
@rpc("authority", "call_local", "reliable")
func chain_strike(spots: PackedVector2Array) -> void:
	for p in spots:
		_chain.append({"pos": p, "left": WARN_TIME})


## Boss strikes still warning (for tests and drawing).
func chain_pending() -> int:
	return _chain.size()


func _draw() -> void:
	for c in _clouds:
		var p: Vector2 = c.pos + Vector2(sin(c.sway) * 18.0, 0.0)
		for j in 3:
			draw_circle(p + Vector2(j * 14.0 - 14.0, j * 6.0), c.r * (1.0 - j * 0.22), CLOUD_COLOR)
	if _far_flash > 0.0:
		var a := _far_flash / FAR_FLASH_TIME
		draw_circle(_far_flash_at, 140.0, Color(0.6, 0.4, 0.9, 0.12 * a))
		draw_circle(_far_flash_at, 70.0, Color(0.8, 0.65, 1.0, 0.12 * a))


func _draw_overlay() -> void:
	var dark := DARK_ALPHA * (1.0 - _flash / FLASH_TIME * 0.8)
	_overlay.draw_rect(Rect2(0, 0, 540, 960), Color(0.02, 0.0, 0.05, dark))
	if _flash > 0.0:
		_overlay.draw_rect(Rect2(0, 0, 540, 960), Color(0.75, 0.6, 1.0, 0.12 * _flash / FLASH_TIME))
	for k in range(_next_strike, _next_strike + 2):
		var left := strike_time(k) - time
		if left <= WARN_TIME:
			_draw_warning(strike_pos(k), left)
	for c in _chain:
		_draw_warning(c.pos, c.left)
	for b in _bolts:
		var a: float = b.left / BOLT_TIME
		_overlay.draw_polyline(b.points, Color(BOLT_GLOW, BOLT_GLOW.a * a), 9.0)
		_overlay.draw_polyline(b.points, Color(BOLT_COLOR, a), 3.0)
		_overlay.draw_circle(b.points[b.points.size() - 1], STRIKE_RADIUS * 0.7, Color(BOLT_COLOR, 0.35 * a))


## A pulsing ring at `at`, tightening as the strike (`left` s away) nears.
func _draw_warning(at: Vector2, left: float) -> void:
	var f := clampf(1.0 - left / WARN_TIME, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(time * 18.0)
	_overlay.draw_arc(at, STRIKE_RADIUS, 0.0, TAU, 32, Color(WARN_COLOR, 0.35 + 0.45 * pulse), 2.5)
	_overlay.draw_arc(at, STRIKE_RADIUS * (1.0 - f), 0.0, TAU, 24, Color(WARN_COLOR, 0.5 * f), 1.5)
	_overlay.draw_circle(at, STRIKE_RADIUS, Color(WARN_COLOR, 0.06 + 0.08 * f))
