extends "res://scripts/scenery/scenery.gd"
## Crystal Crevices: a narrow fissure cut through a seam of crystal. Behind the
## action, slabs of faceted crystal jut in from both walls and scroll past in
## parallax, with motes of dust glinting between them. Everything is drawn with
## straight edges and corners — flat facets, no circles or arcs.
##
## Hazard: resonance beams. Every BEAM_GAP s or so a node on each wall lights
## up, a thin line strung between them warns for BEAM_WARN s, then the beam
## lances across the fissure for BEAM_TIME s and cuts any ship near the line.
## The beams run wall to wall at a slant, so there is no safe row — ships dodge
## off the line rather than above or below it. Times and ends come from
## run_seed and time, so every peer agrees (roll).
##
## Hazard: shatter bursts. The crystal-crusted debris in this level goes off
## when it breaks: shooting one at close range costs a hit (BURST_RADIUS). The
## host sees the break and tells everyone (shatter), so each peer hurts the
## ships it flies.
##
## Hazard: crystal rain. Shards fall out of the seam the whole level through
## (rain_time), light and constant. They are ordinary obstacles, so they block
## shots and can be shot apart to clear a lane.
##
## Boss: the Crystal Storm, the cloud the rain comes from (Enemy.CRYSTAL,
## crystal_boss.gd). One target, no parts to break off — what it does instead is
## open up: a downpour of shards across its target's column, a spread of shots,
## and a resonance beam every BOSS_BEAM_EVERY attacks. The worse it's hurt the
## more it drops, and the rain runs faster the whole time it's overhead.

const ObstacleScript := preload("res://scripts/obstacle.gd")

const ARENA := Vector2(540, 960)

# --- Crystal rain ---
## Shards drift down out of the seam the whole level through — light and
## constant, where the Asteroid Belt's rocks come in heavy bursts. They are
## ordinary obstacles, so they block shots and can be shot apart (2 hits) to
## clear a lane. The boss is the cloud they fall from, and it rains harder
## (RAIN_BOSS_SCALE) while it's up.
const RAIN_PIECE := "crystal_shard"
const RAIN_FIRST := 4.0  # s before the first shard
const RAIN_INTERVAL := 2.6  # s between shards
const RAIN_BOSS_SCALE := 0.45  # of the usual gap while the cloud is overhead
const SALT_RAIN_LANE := 21

# --- Resonance beams ---
const BEAM_GAP := 4.0  # s between beams on average
const BEAM_JITTER := 0.9  # s a beam's time can move (gaps stay 3.1..4.9 s)
const BEAM_WARN := 1.1  # s the line warns before it fires
const BEAM_TIME := 0.3  # s the beam stays on screen, cutting
const BEAM_REACH := 24.0  # px either side of the line that gets cut
const BEAM_HITS := 1.0
const BEAM_BAND := Vector2(170.0, 830.0)  # the y range a beam's ends sit in
const BEAM_TILT := 300.0  # px the two ends' y can differ by, at most
const SALT_BEAM_TIME := 1
const SALT_BEAM_Y := 2
const SALT_BEAM_TILT := 3

# --- Shatter bursts ---
const BURST_PIECE := "debris"  # the crystal-crusted one; see the level file
const BURST_RADIUS := 56.0
const BURST_HITS := 1.0
const BURST_TIME := 0.3  # s the burst shows

# --- Boss ---
const BOSS_SPREAD := 0.19  # rad between its bullets
const BOSS_BEAM_EVERY := 3  # every this many attacks it lances a beam too
const BOSS_WEAR_SHOTS := 3  # extra bullets a volley by the time it's nearly done for
const BOSS_BEAM_TILT := 150.0  # px the beam through the target slants by
const DOWNPOUR_SHARDS := Vector2i(3, 6)  # shards a downpour drops, fresh cloud to worn out
const DOWNPOUR_SPREAD := 150.0  # px across the target's column it covers
const DOWNPOUR_STAGGER := 50.0  # px each later shard starts higher
const DOWNPOUR_EDGE := 30.0  # px kept from the side walls

# --- Look ---
const SLABS := 11  # crystal slabs per wall
const SLAB_DEPTH := Vector2(26.0, 92.0)  # px they reach in from the wall
const SLAB_HEIGHT := Vector2(50.0, 130.0)
const SLAB_SPEED := Vector2(8.0, 26.0)  # px/s parallax range (slower = farther)
const MOTES := 44
const WRAP := 150.0  # px a slab scrolls past the edge before it wraps
const FAR_COLOR := Color(0.16, 0.30, 0.40, 0.45)  # deepest slab
const NEAR_COLOR := Color(0.40, 0.72, 0.86, 0.55)
const SEAM_COLOR := Color(0.75, 0.95, 1.0, 0.30)
const MOTE_COLOR := Color(0.80, 0.95, 1.0, 0.35)
const WARN_COLOR := Color(0.65, 0.92, 1.0)
const BEAM_COLOR := Color(0.92, 0.99, 1.0)
const BEAM_GLOW := Color(0.40, 0.80, 1.0, 0.5)
const BURST_COLOR := Color(0.85, 0.97, 1.0)

var _next_beam := 1  # index of the next ambient beam to fire
var _slabs := []  # cosmetic: {side, y, depth, height, speed}
var _motes := PackedVector2Array()
var _mote_speed := PackedFloat32Array()
var _live := []  # beams on screen now: {a, b, left}
var _pending := []  # beams still warning: {a, b, left}
var _bursts := []  # {at, left}
var _boss_attacks := 0  # host: volleys fired
var _rained := 0  # host: shards sent down so far
var _overlay: Node2D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed  # cosmetic, but the same look on every peer anyway
	for i in SLABS:
		for side in 2:
			var depth := rng.randf()
			_slabs.append({
				"side": side,
				"y": rng.randf() * ARENA.y,
				"depth": lerpf(SLAB_DEPTH.x, SLAB_DEPTH.y, depth),
				"height": rng.randf_range(SLAB_HEIGHT.x, SLAB_HEIGHT.y),
				"speed": lerpf(SLAB_SPEED.x, SLAB_SPEED.y, depth),
			})
	for i in MOTES:
		_motes.append(Vector2(rng.randf() * ARENA.x, rng.randf() * ARENA.y))
		_mote_speed.append(rng.randf_range(SLAB_SPEED.x, SLAB_SPEED.y) * 0.7)
	_overlay = Node2D.new()  # beams read in front of the ships, like the storm's bolts
	_overlay.name = "CrystalOverlay"
	_overlay.z_index = 50
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


# --- Resonance beams --------------------------------------------------------------

## When ambient beam `k` (from 1) fires.
func beam_time(k: int) -> float:
	return k * BEAM_GAP + (roll(k, SALT_BEAM_TIME) - 0.5) * BEAM_JITTER


## Where ambient beam `k` runs: [left wall end, right wall end].
func beam_line(k: int) -> Array:
	var ya := lerpf(BEAM_BAND.x, BEAM_BAND.y, roll(k, SALT_BEAM_Y))
	var tilt := (roll(k, SALT_BEAM_TILT) - 0.5) * 2.0 * BEAM_TILT
	var yb := clampf(ya + tilt, BEAM_BAND.x, BEAM_BAND.y)
	return [Vector2(0.0, ya), Vector2(ARENA.x, yb)]


## Ambient beams firing in [t0, t1): [{a, b, time}], in order.
func beams_between(t0: float, t1: float) -> Array:
	var out := []
	var first := maxi(1, floori((t0 - BEAM_JITTER) / BEAM_GAP))
	var last := ceili((t1 + BEAM_JITTER) / BEAM_GAP)
	for k in range(first, last + 1):
		var t := beam_time(k)
		if t >= t0 and t < t1:
			var line := beam_line(k)
			out.append({"a": line[0], "b": line[1], "time": t})
	return out


## Inside a beam that fires within BEAM_TIME of `ahead` s from now (ambient or
## the boss's), 0 (clear) to 1: what the AI pilot steers off (AiPilot).
func danger_at(pos: Vector2, ahead: float) -> float:
	var at := time + ahead
	var reach := BEAM_REACH + 18.0
	for b in beams_between(at - BEAM_TIME, at + BEAM_WARN):
		if _near_line(pos, b.a, b.b, reach):
			return 1.0
	for b in _pending:
		if b.left < ahead + BEAM_TIME + 0.4 and _near_line(pos, b.a, b.b, reach):
			return 1.0
	return 0.0


static func _near_line(pos: Vector2, a: Vector2, b: Vector2, reach: float) -> bool:
	return pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b)) < reach


func step(delta: float) -> void:
	while beam_time(_next_beam) <= time:
		var line := beam_line(_next_beam)
		_fire_beam(line[0], line[1], not _forking())
		_next_beam += 1
	for b in _pending:
		b.left -= delta
		if b.left <= 0.0:
			_fire_beam(b.a, b.b, true)
	_pending = _pending.filter(func(b): return b.left > 0.0)
	for b in _live:
		b.left -= delta
	_live = _live.filter(func(b): return b.left > 0.0)
	for b in _bursts:
		b.left -= delta
	_bursts = _bursts.filter(func(b): return b.left > 0.0)
	if _overlay:
		_overlay.queue_redraw()
	if game != null and game.multiplayer.is_server() and not _forking():
		while time >= rain_time(_rained):
			_place(RAIN_PIECE, rain_at(_rained))
			_rained += 1


# --- Crystal rain -----------------------------------------------------------------

## When shard `k` (0, 1, ...) falls. They come closer together while the cloud
## is overhead, so the boss fight rains hardest.
func rain_time(k: int) -> float:
	return RAIN_FIRST + rain_gap() * k


func rain_gap() -> float:
	var boss: bool = game != null and game.has_method("boss_alive") and game.boss_alive()
	return RAIN_INTERVAL * (RAIN_BOSS_SCALE if boss else 1.0)


## Where shard `k` comes down (the same lane on every peer).
func rain_at(k: int) -> Vector2:
	var lane := int(roll(k, SALT_RAIN_LANE) * ObstacleScript.LANES)
	return Vector2(ObstacleScript.center_x(RAIN_PIECE, 1, lane, ARENA.x), ObstacleScript.spawn_y(RAIN_PIECE))


## Host: one shard at exactly `at`, announced to everyone.
func _place(piece: String, at: Vector2) -> void:
	game.spawn_obstacle_at(piece, at)


## A beam lances from `a` to `b`: cuts the local ships on the line (if `hurts`)
## and shows for BEAM_TIME.
func _fire_beam(a: Vector2, b: Vector2, hurts: bool) -> void:
	if hurts:
		_hurt_line(a, b, BEAM_REACH, BEAM_HITS)
	_live.append({"a": a, "b": b, "left": BEAM_TIME})


## No ambient beam hurts while the party is voting at a fork.
func _forking() -> bool:
	return game != null and game.has_method("fork_open") and game.fork_open()


## Hits every ship this peer flies within `reach` of the line a..b.
func _hurt_line(a: Vector2, b: Vector2, reach: float, hits: float) -> void:
	if game == null:
		return
	for p in game.players.get_children():
		if not p.is_local() or not p.is_alive():
			continue
		var c := Geometry2D.get_closest_point_to_segment(p.position, a, b)
		if p.position.distance_to(c) < reach + game.SHIP_RADIUS:
			p.take_damage(hits, c.y > p.position.y)


## Beams still warning (for tests and drawing).
func pending_beams() -> int:
	return _pending.size()


## Beams on screen now (for tests and drawing).
func live_beams() -> int:
	return _live.size()


# --- Shatter bursts ---------------------------------------------------------------

## Host: crystal-crusted debris broke. Everyone sees the burst and each peer
## hurts the ships it flies that were standing too close.
func on_obstacle_destroyed(piece: String, at: Vector2) -> void:
	if piece != BURST_PIECE or game == null or not game.multiplayer.is_server():
		return
	shatter.rpc(at)


## Host -> everyone: a shard burst at `at`.
@rpc("authority", "call_local", "reliable")
func shatter(at: Vector2) -> void:
	hurt_local(at, BURST_RADIUS, BURST_HITS)
	_bursts.append({"at": at, "left": BURST_TIME})


# --- Boss -------------------------------------------------------------------------

## Host: a tight aimed spread, wider for each arm the party has broken off, plus
## a resonance beam through the target every few volleys (every one once both
## arms are gone).
## Host: the cloud opens up. A downpour of shards falls across the target's
## column, wider the more the cloud has been worn down, plus a spread of shots;
## every few attacks it also lances a resonance beam.
func boss_attack(boss: Node2D, target: Node2D, n: int) -> bool:
	if game == null:
		return false
	var cloud: Node = boss.get_node_or_null("CrystalStorm")
	var wear: float = cloud.wear() if cloud else 0.0
	_boss_attacks += 1
	for at in downpour(boss, target.position, wear):
		_place(RAIN_PIECE, at)
	var shots := n + int(round(BOSS_WEAR_SHOTS * wear))
	var aim := (target.position - boss.position).normalized()
	for i in shots:
		game.fire_enemy_bullet.rpc(boss.position + aim * 50.0, aim.rotated((i - (shots - 1) / 2.0) * BOSS_SPREAD))
	if _boss_attacks % BOSS_BEAM_EVERY == 0:
		var line := boss_beam(target.position, _boss_attacks)
		lance.rpc(line[0], line[1])
	return true


## Where a downpour's shards start: a row across the target's column, out of the
## cloud's underside, stepped so they don't all land at once.
func downpour(boss: Node2D, at: Vector2, wear: float) -> Array:
	var out := []
	var n := DOWNPOUR_SHARDS.x + int(round((DOWNPOUR_SHARDS.y - DOWNPOUR_SHARDS.x) * wear))
	var top: float = boss.position.y + (boss.get_node_or_null("CrystalStorm").underside() if boss.get_node_or_null("CrystalStorm") else 0.0)
	var edge := DOWNPOUR_SPREAD * 0.5
	var cx := clampf(at.x, edge + DOWNPOUR_EDGE, ARENA.x - edge - DOWNPOUR_EDGE)
	for j in n:
		var x := cx + (j - (n - 1) / 2.0) * (DOWNPOUR_SPREAD / maxi(n - 1, 1))
		out.append(Vector2(x, top + DOWNPOUR_STAGGER * j))
	return out


## The beam the boss strings through `at` on volley `c`: wall to wall, slanted.
func boss_beam(at: Vector2, c: int) -> Array:
	var tilt := (roll(c, SALT_BEAM_TILT) - 0.5) * 2.0 * BOSS_BEAM_TILT
	var ya := clampf(at.y - tilt * at.x / ARENA.x, BEAM_BAND.x, BEAM_BAND.y)
	var yb := clampf(ya + tilt, BEAM_BAND.x, BEAM_BAND.y)
	return [Vector2(0.0, ya), Vector2(ARENA.x, yb)]


## Host -> everyone: a beam warns from `a` to `b`, then fires after BEAM_WARN.
@rpc("authority", "call_local", "reliable")
func lance(a: Vector2, b: Vector2) -> void:
	_pending.append({"a": a, "b": b, "left": BEAM_WARN})


# --- Look -------------------------------------------------------------------------

func _draw() -> void:
	var h := ARENA.y + WRAP * 2.0
	for i in _motes.size():
		var p := _motes[i]
		var y := fposmod(p.y + _mote_speed[i] * time, h) - WRAP
		draw_rect(Rect2(p.x, y, 2.0, 2.0), MOTE_COLOR)
	for s in _slabs:
		var depth := inverse_lerp(SLAB_SPEED.x, SLAB_SPEED.y, s.speed)
		var y: float = fposmod(s.y + s.speed * time, h) - WRAP
		_draw_slab(s.side, y, s.depth, s.height, FAR_COLOR.lerp(NEAR_COLOR, depth))


## One crystal slab jutting in from a wall: a flat sided wedge, with a lit seam
## along the edge facing the fissure.
func _draw_slab(side: int, y: float, depth: float, height: float, c: Color) -> void:
	var x := 0.0 if side == 0 else ARENA.x
	var inward := depth if side == 0 else -depth
	var pts := PackedVector2Array([
		Vector2(x, y),
		Vector2(x + inward * 0.75, y + height * 0.22),
		Vector2(x + inward, y + height * 0.55),
		Vector2(x + inward * 0.45, y + height * 0.85),
		Vector2(x, y + height),
	])
	draw_colored_polygon(pts, c)
	draw_line(pts[1], pts[2], SEAM_COLOR, 1.5)
	draw_line(pts[2], pts[3], SEAM_COLOR, 1.5)


func _draw_overlay() -> void:
	for b in _pending:  # the line warning, tightening as it nears
		var f := clampf(1.0 - b.left / BEAM_WARN, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(time * 18.0)
		_overlay.draw_line(b.a, b.b, Color(WARN_COLOR, 0.18 + 0.30 * f * pulse), 1.0 + 2.0 * f)
		_draw_node(b.a, f)
		_draw_node(b.b, f)
	for b in _live:
		var a: float = b.left / BEAM_TIME
		_overlay.draw_line(b.a, b.b, Color(BEAM_GLOW, BEAM_GLOW.a * a), BEAM_REACH * 1.6 * a)
		_overlay.draw_line(b.a, b.b, Color(BEAM_COLOR, a), 3.0)
	for s in _bursts:
		var f: float = s.left / BURST_TIME
		_draw_burst(s.at, f)


## A wall node lighting up before a beam: a small diamond, brighter as it charges.
func _draw_node(at: Vector2, f: float) -> void:
	var r := 6.0 + 5.0 * f
	_overlay.draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0),
	]), Color(WARN_COLOR, 0.35 + 0.5 * f))


## Shards thrown out of a break: straight spikes, fading as they fly.
func _draw_burst(at: Vector2, f: float) -> void:
	var out := BURST_RADIUS * (1.0 - f) + 10.0
	for k in 8:
		var dir := Vector2.from_angle(TAU * k / 8.0 + 0.2)
		_overlay.draw_line(at + dir * out * 0.45, at + dir * out, Color(BURST_COLOR, f), 2.5)
