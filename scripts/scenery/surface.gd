extends "res://scripts/scenery/scenery.gd"
## Planet Surface: flying low over rocky orange ground through a canyon. The
## ground (craters, ridges, rocks, dust) scrolls with the obstacles. Rock walls
## on both edges widen and narrow along the course (smooth noise from roll), but
## always leave at least a MIN_CHANNEL wide channel. The walls are solid: they
## shove a ship back into the channel, and scraping one costs SCRAPE_HITS (at
## most every SCRAPE_COOLDOWN s). The boss bombards the ground: warning circles
## near its target blow up BOMB_DELAY s later, plus an aimed shot.

const ObstacleScript := preload("res://scripts/obstacle.gd")

const W := 540.0  # arena width
const H := 960.0  # arena height
const WALL_MIN := 26.0  # px, narrowest a wall gets
const WALL_MAX := 112.0  # px, widest; two of these still leave MIN_CHANNEL
const MIN_CHANNEL := 300.0  # px, the channel never gets narrower
const WALL_SEG := 260.0  # px of course between wall noise points
const WALL_STEP := 32.0  # px between drawn wall points
const WALL_PUSH := 520.0  # px/s shove out of a wall
const WALL_SPRING := 14.0  # px/s more per px of overlap
const SCRAPE_HITS := 0.25  # hits per scrape
const SCRAPE_COOLDOWN := 0.6  # s between scrapes for one ship
const BOMB_DELAY := 1.0  # s from warning circle to explosion
const BOMB_RADIUS := 40.0  # px
const BOMB_HITS := 1.0
const BOMB_SPREAD := 90.0  # px, how far around the target the circles land
const BOMB_MAX := 5  # circles per attack at most
const BLAST_SHOW := 0.3  # s the explosion flash lingers
const GROUND_PERIOD := 1200.0  # px, the ground pattern repeats this often
const CRATERS := 9
const ROCKS := 26
const RIDGES := 6
const DUST := 40

const GROUND_DARK := Color(0.09, 0.05, 0.03)
const GROUND_BAND := Color(0.16, 0.09, 0.05, 0.6)
const CRATER_RIM := Color(0.30, 0.17, 0.08)
const CRATER_PIT := Color(0.07, 0.04, 0.02)
const ROCK := Color(0.36, 0.21, 0.11)
const ROCK_LIT := Color(0.52, 0.32, 0.17)
const RIDGE := Color(0.24, 0.13, 0.06)
const DUST_COLOR := Color(0.85, 0.55, 0.30, 0.25)
const WALL := Color(0.30, 0.16, 0.08)
const WALL_EDGE := Color(0.55, 0.31, 0.14)
const WALL_SHADE := Color(0.18, 0.09, 0.04)
const WARN := Color(1.0, 0.35, 0.15)
const EXPLOSION_SIZE := 2.6  # the explosion's height, in blast radii
const SpriteEffect := preload("res://scripts/sprite_effect.gd")
const WreckScript := preload("res://scripts/wreck.gd")

var strikes: Array[Dictionary] = []  # {pos, left}: bombardment circles; left < 0 once exploded
var _attacks := 0  # boss attacks so far (the host's count picks the spots)
var _scrape_cd := {}  # ship name -> s until it can scrape again
var _noise := {}  # roll cache: segment key -> value
var _ground: Array[Dictionary] = []  # cosmetic features {kind, pos, size}
var _overlay: Node2D  # on top of the ships: warning circles and blasts


func _ready() -> void:
	_build_ground()
	_overlay = Node2D.new()
	_overlay.z_index = 50
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func step(delta: float) -> void:
	_scrape_walls(delta)
	_tick_strikes(delta)
	if _overlay:
		_overlay.queue_redraw()


# --- Walls ---------------------------------------------------------------------

## How far the wall on `side` (0 left, 1 right) reaches into the screen at screen `y`, now.
func wall_width(side: int, y: float) -> float:
	var d := time * ObstacleScript.scroll_speed() - y  # course distance of that row
	var s := d / WALL_SEG
	var k := floori(s)
	var f := smoothstep(0.0, 1.0, s - k)
	return lerpf(WALL_MIN, WALL_MAX, lerpf(_wall_noise(k, side), _wall_noise(k + 1, side), f))


func _wall_noise(k: int, side: int) -> float:
	var key := k * 2 + side
	if not _noise.has(key):
		if _noise.size() > 64:
			_noise.clear()
		_noise[key] = roll(k, 101 + side)
	return _noise[key]


## How deep a ship at `pos` sinks into a wall: < 0 left wall, > 0 right wall, 0 clear.
func _wall_overlap(pos: Vector2) -> float:
	var r: float = game.SHIP_RADIUS if game else 14.0
	var left := wall_width(0, pos.y) - (pos.x - r)
	if left > 0.0:
		return -left
	var right := (pos.x + r) - (W - wall_width(1, pos.y))
	return maxf(right, 0.0)


## Inside a bombardment circle that's still to blow, or scraping a wall.
func danger_at(pos: Vector2, _ahead: float) -> float:
	for s in strikes:
		if s.left > -0.05 and s.pos.distance_to(pos) < BOMB_RADIUS + 20.0:
			return 1.0
	var r: float = game.SHIP_RADIUS if game else 14.0
	var gap := minf(pos.x - r - wall_width(0, pos.y), W - wall_width(1, pos.y) - pos.x - r)
	return 0.5 if gap < 10.0 else 0.0


func push_at(pos: Vector2) -> Vector2:
	var o := _wall_overlap(pos)
	if o == 0.0:
		return Vector2.ZERO
	return Vector2(-signf(o) * (WALL_PUSH + absf(o) * WALL_SPRING), 0.0)


## Every peer: ships it flies that touch a wall get scraped now and then.
func _scrape_walls(delta: float) -> void:
	for id in _scrape_cd.keys():
		_scrape_cd[id] -= delta
	if game == null:
		return
	for p in game.players.get_children():
		if not (p.is_local() and p.is_alive()) or _wall_overlap(p.position) == 0.0:
			continue
		if _scrape_cd.get(p.name, 0.0) > 0.0:
			continue
		_scrape_cd[p.name] = SCRAPE_COOLDOWN
		var side := -1.0 if p.position.x < W / 2.0 else 1.0
		Sparks.at_hit(p, p.position + Vector2(side * game.SHIP_RADIUS, 0), Vector2.ZERO, Color("ffcf7a"), 10)
		p.take_damage(SCRAPE_HITS)


# --- Boss bombardment ------------------------------------------------------------

func boss_attack(boss: Node2D, target: Node2D, n: int) -> bool:
	if game == null:
		return false
	var count := clampi(n - 1, 2, BOMB_MAX)
	bombard.rpc(bomb_spots(_attacks, target.position, count))
	_attacks += 1
	var aim := (target.position - boss.position).normalized()
	game.fire_enemy_bullet.rpc(boss.position + aim * 50.0, aim)
	return true


## Where attack `i`'s `count` circles land around `at`: the first right on it.
func bomb_spots(i: int, at: Vector2, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in count:
		var off := Vector2.ZERO
		if j > 0:
			off = Vector2.from_angle(roll(i * 8 + j, 7) * TAU) * BOMB_SPREAD * (0.5 + 0.5 * roll(i * 8 + j, 8))
		out.append((at + off).clamp(Vector2.ZERO, Vector2(W, H)))
	return out


## Host -> everyone: warning circles at `spots`; they blow up BOMB_DELAY s later.
@rpc("authority", "call_local", "reliable")
func bombard(spots: PackedVector2Array) -> void:
	for s in spots:
		strikes.append({"pos": s, "left": BOMB_DELAY})


## A bombardment shell lands: the painted explosion, sized to its blast.
func _explode(at: Vector2) -> void:
	var parent: Node = game.effects if game and game.get("effects") else self
	SpriteEffect.spawn(parent, at, SpriteEffect.explosion_frames(WreckScript.FIRE_RAMPS[0]), BOMB_RADIUS * EXPLOSION_SIZE)


func _tick_strikes(delta: float) -> void:
	for i in range(strikes.size() - 1, -1, -1):
		var s: Dictionary = strikes[i]
		var was: float = s.left
		s.left -= delta
		if was > 0.0 and s.left <= 0.0:
			hurt_local(s.pos, BOMB_RADIUS, BOMB_HITS)
			_explode(s.pos)
		if s.left < -BLAST_SHOW:
			strikes.remove_at(i)


# --- Drawing -----------------------------------------------------------------------

## Cosmetic ground features, laid out once from the seed.
func _build_ground() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([run_seed, "ground"])
	for i in CRATERS:
		_ground.append({"kind": 0, "pos": Vector2(r.randf_range(60, W - 60), r.randf() * GROUND_PERIOD), "size": r.randf_range(18, 46)})
	for i in RIDGES:
		_ground.append({"kind": 1, "pos": Vector2(r.randf_range(0, W - 160), r.randf() * GROUND_PERIOD), "size": r.randf_range(120, 260)})
	for i in ROCKS:
		_ground.append({"kind": 2, "pos": Vector2(r.randf_range(10, W - 10), r.randf() * GROUND_PERIOD), "size": r.randf_range(3, 9)})
	for i in DUST:
		_ground.append({"kind": 3, "pos": Vector2(r.randf_range(0, W), r.randf() * GROUND_PERIOD), "size": r.randf_range(1, 2.5)})


func _draw() -> void:
	var scroll := time * ObstacleScript.scroll_speed()
	_draw_bands(scroll)
	for g in _ground:
		var y := fposmod(g.pos.y + scroll, GROUND_PERIOD) - (GROUND_PERIOD - H) / 2.0
		if y < -60.0 or y > H + 60.0:
			continue
		_draw_feature(g, Vector2(g.pos.x, y))
	_draw_wall(0)
	_draw_wall(1)


func _draw_bands(scroll: float) -> void:
	for i in 5:
		var y := fposmod(i * 240.0 + scroll * 0.9, GROUND_PERIOD) - 120.0
		draw_rect(Rect2(0, y, W, 70), GROUND_BAND)


func _draw_feature(g: Dictionary, at: Vector2) -> void:
	var s: float = g.size
	match g.kind:
		0:  # crater
			draw_circle(at, s, CRATER_RIM)
			draw_circle(at + Vector2(s * 0.12, s * 0.12), s * 0.78, CRATER_PIT)
			draw_arc(at, s, PI * 1.0, PI * 1.6, 8, ROCK_LIT, 2.0)
		1:  # ridge
			draw_line(at, at + Vector2(s, s * 0.18), RIDGE, 6.0)
			draw_line(at + Vector2(0, -3), at + Vector2(s, s * 0.18 - 3), GROUND_DARK, 2.0)
		2:  # rock
			draw_circle(at, s, ROCK)
			draw_circle(at - Vector2(s, s) * 0.3, s * 0.45, ROCK_LIT)
		3:  # dust
			draw_circle(at, s, DUST_COLOR)


func _draw_wall(side: int) -> void:
	var n := int(H / WALL_STEP) + 2
	var pts := PackedVector2Array()
	pts.resize(n + 2)
	var edge_x := 0.0 if side == 0 else W
	for i in n:
		var y := minf(i * WALL_STEP, H)
		var w := wall_width(side, y)
		pts[i] = Vector2(w if side == 0 else W - w, y)
	pts[n] = Vector2(edge_x, H)
	pts[n + 1] = Vector2(edge_x, 0)
	draw_colored_polygon(pts, WALL)
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var inward := Vector2(-10 if side == 0 else 10, 0)
		draw_line(a + inward, b + inward, WALL_SHADE, 8.0)
		draw_line(a, b, WALL_EDGE, 3.0)


func _draw_overlay() -> void:
	for s in strikes:
		var p: Vector2 = s.pos
		if s.left > 0.0:
			var t: float = 1.0 - s.left / BOMB_DELAY
			var c := WARN
			c.a = 0.25 + 0.15 * sin(time * 20.0)
			_overlay.draw_circle(p, BOMB_RADIUS * t, c)
			_overlay.draw_arc(p, BOMB_RADIUS, 0, TAU, 24, WARN, 2.0)
		# Once it blows, the painted explosion shows instead (_explode).
