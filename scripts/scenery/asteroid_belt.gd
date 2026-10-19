extends "res://scripts/scenery/scenery.gd"
## Asteroid Belt: dense drifting rocks. Behind the action, distant dim rocks
## and dust drift down in slow parallax (cosmetic). Hazards (host only, as
## obstacle events everyone sees): a medium asteroid shot apart breaks into two
## small ones, and every SHOWER_INTERVAL a rock shower of small asteroids falls
## in (lanes from `roll`). The boss hurls rocks: a wide arc of shots, and every
## few attacks a handful of small asteroids thrown out in front of it.

const ObstacleScript := preload("res://scripts/obstacle.gd")

const ARENA_SIZE := Vector2(540, 960)
const FAR_ROCKS := 14  # distant lumpy rocks in the background
const DUST := 40  # distant specks
const FAR_SPEED := Vector2(6.0, 22.0)  # px/s parallax range (slower = farther)
const FAR_SIZE := Vector2(5.0, 18.0)  # px radius range of the distant rocks
const ROCK_SIDES := 7  # corners of a distant rock's outline
const FAR_COLOR := Color(0.32, 0.25, 0.2, 0.35)  # dimmest; nearer ones are lighter
const NEAR_COLOR := Color(0.5, 0.4, 0.3, 0.5)
const DUST_COLOR := Color(0.75, 0.62, 0.48, 0.25)
const WRAP := 40.0  # px a background rock goes off screen before it wraps

const SPLIT_FROM := "asteroid_m"  # this piece shot apart breaks into...
const SPLIT_INTO := "asteroid_s"
const SPLIT_PIECES := 2
const SPLIT_OFFSET := 22.0  # px from where it broke

const SHOWER_PIECE := "asteroid_s"
const SHOWER_FIRST := 12.0  # s before the first rock shower
const SHOWER_INTERVAL := 20.0  # s between showers
const SHOWER_ROCKS := Vector2i(4, 6)  # small rocks per shower
const SHOWER_STAGGER := 45.0  # px each later rock of a shower starts higher
const SALT_SHOWER_COUNT := 11
const SALT_SHOWER_LANE := 12
const SALT_SPLIT := 13
const SALT_THROW := 14

const BOSS_ARC := 0.22  # rad between the shots of the boss's arc
const BOSS_EXTRA_SHOTS := 2  # the arc is this many shots wider than `n`
const BOSS_ROCK_EVERY := 3  # every this many attacks it throws rocks too
const BOSS_ROCKS := Vector2i(2, 3)
const BOSS_ROCK_SPREAD := 70.0  # px between thrown rocks
const BOSS_ROCK_AHEAD := 90.0  # px below the boss they appear
const BOSS_ROCK_EDGE := 30.0  # px kept from the side edges

var _far_pos := PackedVector2Array()  # start positions
var _far_speed := PackedFloat32Array()
var _far_size := PackedFloat32Array()
var _far_spin := PackedFloat32Array()
var _rock_shape := PackedVector2Array()  # unit outline shared by distant rocks
var _dust_pos := PackedVector2Array()
var _dust_speed := PackedFloat32Array()
var _showers := 0  # showers sent in so far (host)
var _splits := 0  # medium rocks split so far (host)
var _boss_attacks := 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed  # cosmetic, but the same look on every peer anyway
	for i in FAR_ROCKS:
		var depth := rng.randf()
		_far_pos.append(Vector2(rng.randf() * ARENA_SIZE.x, rng.randf() * ARENA_SIZE.y))
		_far_speed.append(lerpf(FAR_SPEED.x, FAR_SPEED.y, depth))
		_far_size.append(lerpf(FAR_SIZE.x, FAR_SIZE.y, depth))
		_far_spin.append(rng.randf_range(-0.4, 0.4))
	for i in ROCK_SIDES:
		var a := TAU * i / ROCK_SIDES
		_rock_shape.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.7, 1.0))
	for i in DUST:
		_dust_pos.append(Vector2(rng.randf() * ARENA_SIZE.x, rng.randf() * ARENA_SIZE.y))
		_dust_speed.append(rng.randf_range(FAR_SPEED.x, FAR_SPEED.y) * 0.6)


func step(_delta: float) -> void:
	if game == null or not game.multiplayer.is_server() or not _playing():
		return
	while time >= shower_time(_showers):
		for at in shower(_showers):
			_place(SHOWER_PIECE, at)
		_showers += 1


## When rock shower `k` (0, 1, ...) falls in, in s of scenery time.
func shower_time(k: int) -> float:
	return SHOWER_FIRST + SHOWER_INTERVAL * k


## Where rock shower `k`'s small rocks start (the same on every peer).
func shower(k: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := SHOWER_ROCKS.x + int(roll(k, SALT_SHOWER_COUNT) * (SHOWER_ROCKS.y - SHOWER_ROCKS.x + 1))
	var y := ObstacleScript.spawn_y(SHOWER_PIECE)
	for j in n:
		var lane := int(roll(k * 16 + j, SALT_SHOWER_LANE) * ObstacleScript.LANES)
		var x := ObstacleScript.center_x(SHOWER_PIECE, 1, lane, ARENA_SIZE.x)
		out.append(Vector2(x, y - SHOWER_STAGGER * j))
	return out


## Host: a medium asteroid shot apart breaks into two small ones beside it.
func on_obstacle_destroyed(piece: String, at: Vector2) -> void:
	if piece != SPLIT_FROM or game == null or not game.multiplayer.is_server():
		return
	var a := roll(_splits, SALT_SPLIT) * PI
	_splits += 1
	for i in SPLIT_PIECES:
		_place(SPLIT_INTO, at + Vector2.from_angle(a + PI * i) * SPLIT_OFFSET)


## Host: a wide arc of shots at `target`; every few attacks it also throws
## small asteroids out in front of itself, around the target's side.
func boss_attack(boss: Node2D, target: Node2D, n: int) -> bool:
	if game == null:
		return false
	var aim := (target.position - boss.position).normalized()
	var shots := n + BOSS_EXTRA_SHOTS
	for i in shots:
		game.fire_enemy_bullet.rpc(boss.position + aim * 50.0, aim.rotated((i - (shots - 1) / 2.0) * BOSS_ARC))
	_boss_attacks += 1
	if _boss_attacks % BOSS_ROCK_EVERY == 0:
		for at in thrown_rocks(boss.position, target.position, _boss_attacks):
			_place(SPLIT_INTO, at)
	return true


## Where the boss's `attack`th throw puts its rocks.
func thrown_rocks(boss_pos: Vector2, target_pos: Vector2, attack: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := BOSS_ROCKS.x + int(roll(attack, SALT_THROW) * (BOSS_ROCKS.y - BOSS_ROCKS.x + 1))
	var cx := clampf(target_pos.x, BOSS_ROCK_EDGE + BOSS_ROCK_SPREAD, ARENA_SIZE.x - BOSS_ROCK_EDGE - BOSS_ROCK_SPREAD)
	for j in n:
		out.append(Vector2(cx + (j - (n - 1) / 2.0) * BOSS_ROCK_SPREAD, boss_pos.y + BOSS_ROCK_AHEAD))
	return out


func _playing() -> bool:
	return not (game.has_method("fork_open") and game.fork_open())


## Host: one obstacle of `piece` at exactly `at`, announced to everyone.
func _place(piece: String, at: Vector2) -> void:
	game.spawn_obstacle_at(piece, at)


func _draw() -> void:
	var h := ARENA_SIZE.y + WRAP * 2.0
	for i in _dust_pos.size():
		var p := _dust_pos[i]
		draw_rect(Rect2(p.x, fposmod(p.y + _dust_speed[i] * time, h) - WRAP, 1.5, 1.5), DUST_COLOR)
	for i in _far_pos.size():
		var depth := inverse_lerp(FAR_SPEED.x, FAR_SPEED.y, _far_speed[i])
		var at := Vector2(_far_pos[i].x, fposmod(_far_pos[i].y + _far_speed[i] * time, h) - WRAP)
		draw_set_transform(at, _far_spin[i] * time, Vector2.ONE * _far_size[i])
		draw_colored_polygon(_rock_shape, FAR_COLOR.lerp(NEAR_COLOR, depth))
	draw_set_transform(Vector2.ZERO)
