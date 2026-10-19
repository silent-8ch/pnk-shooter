extends GutTest
## Missile levels: MISSILE goes to 6 levels (counted only while it's armed). Each
## level adds a missile per gun to the salvo (fanned out sideways) and reloads faster.
## Every missile trails Gundam-style smoke that lingers after it's gone.

const PlayerScript := preload("res://scripts/player.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const SmokeTrail := preload("res://scripts/smoke_trail.gd")

var game: Node2D
var player: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	player = preload("res://scenes/player.tscn").instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 700)
	game.get_node("Players").add_child(player)
	player.levels[&"reactor"] = Systems.max_level(&"reactor")
	player.levels[&"weapons"] = Systems.max_level(&"weapons")


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _missiles() -> Array:
	return game.get_node("Bullets").get_children().filter(func(b): return b.is_seeking())


func _trails() -> Array:
	return game.get_node("Effects").get_children().filter(func(n): return n is SmokeTrail)


## MISSILE at `level`, armed.
func _missile_at(level: int) -> void:
	player.levels[&"missile"] = level
	if not player.is_armed(&"missile"):
		assert_true(player.arm(&"missile"))


func _salvo(level: int) -> Array:
	_missile_at(level)
	player._missile_cooldown = 0.0
	for m in _missiles():
		m.free()
	player._missile_requested = true
	player._simulate(0.016)
	return _missiles()


func test_many_levels() -> void:
	assert_eq(Systems.max_level(&"missile"), 6)


func test_levels_count_only_while_armed() -> void:
	player.levels[&"missile"] = 3
	assert_eq(player.level(&"missile"), 0)
	assert_eq(player.missile_directions().size(), 0)
	assert_true(player.arm(&"missile"))
	assert_eq(player.level(&"missile"), 3)
	player.disarm(&"missile")
	assert_eq(player.level(&"missile"), 0)


func test_each_level_adds_a_missile_to_the_salvo() -> void:
	for lv in range(1, 7):
		assert_eq(_salvo(lv).size(), lv, "level %d" % lv)


func test_options_fire_a_full_salvo_each() -> void:
	player.levels[&"option"] = 2
	player.levels[&"drones"] = 2
	assert_true(player.add_power(&"drones"))
	assert_true(player.add_power(&"drones"))
	player._process(0.0)
	assert_eq(_salvo(3).size(), 9)


func test_salvo_fans_out_evenly_and_symmetrically() -> void:
	_missile_at(1)
	assert_eq(player.missile_directions(), [Vector2.UP] as Array[Vector2])
	_missile_at(5)
	var dirs: Array[Vector2] = player.missile_directions()
	assert_almost_eq(dirs[2], Vector2.UP, Vector2(0.0001, 0.0001))
	for i in 5:
		assert_almost_eq(dirs[i].x, -dirs[4 - i].x, 0.0001)
	var gap := Vector2.UP.angle_to(dirs[1]) - Vector2.UP.angle_to(dirs[0])
	for i in 4:
		assert_almost_eq(Vector2.UP.angle_to(dirs[i + 1]) - Vector2.UP.angle_to(dirs[i]), gap, 0.0001, "even")


func test_a_small_salvo_starts_narrow_and_branches_out_with_levels() -> void:
	var widest := 0.0
	for lv in range(2, Systems.max_level(&"missile") + 1):
		_missile_at(lv)
		var dirs: Array[Vector2] = player.missile_directions()
		var spread := absf(Vector2.UP.angle_to(dirs[0]))
		assert_gt(spread, widest, "level %d fans wider" % lv)
		widest = spread
		if lv == 2:
			assert_lt(spread, PlayerScript.MISSILE_FAN / 3.0, "two start close together")
	assert_almost_eq(widest, PlayerScript.MISSILE_FAN, 0.0001, "the full fan at the top level")


func test_higher_levels_reload_faster() -> void:
	var last := INF
	for lv in range(1, 7):
		_missile_at(lv)
		assert_lt(player.missile_cooldown(), last, "level %d" % lv)
		last = player.missile_cooldown()
	_missile_at(1)
	assert_eq(player.missile_cooldown(), PlayerScript.MISSILE_COOLDOWN)


func test_button_cooldown_follows_the_level() -> void:
	game.get_node("PointerControls").visible = true
	var bar: ActionBar = game.get_node("PointerControls/ActionBar")
	_missile_at(4)
	player._gather_input()
	assert_true(bar.press(&"missile"))
	assert_almost_eq(bar.cooldown_left(&"missile"), player.missile_cooldown(), 0.0001)


func test_missiles_fly_straight_out_before_seeking() -> void:
	var e: Area2D = preload("res://scenes/enemy.tscn").instantiate()
	e.position = Vector2(400, 500)
	game.get_node("Enemies").add_child(e)
	var left := Vector2.UP.rotated(-PlayerScript.MISSILE_FAN)
	game.fire_bullet(Vector2(270, 700), Color.RED, left, BulletScript.MISSILE)
	var m: Area2D = _missiles()[0]
	m._physics_process(BulletScript.MISSILE_LAUNCH * 0.9)
	assert_almost_eq(m.direction, left, Vector2(0.0001, 0.0001), "launch phase")
	for i in 10:
		m._physics_process(1.0 / 60.0)
	assert_gt(m.direction.x, left.x + 0.05, "then curls right toward the enemy")


# --- Smoke ---------------------------------------------------------------------

func test_each_missile_trails_smoke_but_lasers_dont() -> void:
	game.fire_bullet(Vector2(100, 700), Color.RED)
	assert_eq(_trails().size(), 0)
	_salvo(3)
	assert_eq(_trails().size(), 3)


func test_trail_follows_the_missile() -> void:
	game.fire_bullet(Vector2(270, 700), Color.RED, Vector2.UP, BulletScript.MISSILE)
	var m: Area2D = _missiles()[0]
	var trail: Line2D = _trails()[0]
	for i in 20:
		m._physics_process(1.0 / 60.0)
		trail._process(1.0 / 60.0)
	assert_gt(trail.get_point_count(), 3)
	assert_almost_eq(trail.get_point_position(trail.get_point_count() - 1), m.position, Vector2(0.01, 0.01), "head on the missile")
	assert_gt(trail.get_point_position(0).y, m.position.y, "tail behind it")


func test_old_smoke_fades_and_the_trail_outlives_its_missile() -> void:
	game.fire_bullet(Vector2(270, 700), Color.RED, Vector2.UP, BulletScript.MISSILE)
	var m: Area2D = _missiles()[0]
	var trail: Line2D = _trails()[0]
	for i in 20:
		m._physics_process(1.0 / 60.0)
		trail._process(1.0 / 60.0)
	m.free()
	assert_true(is_instance_valid(trail), "smoke lingers")
	trail._process(SmokeTrail.LIFE + 0.01)
	assert_eq(trail.get_point_count(), 0)
	assert_true(trail.is_queued_for_deletion(), "then it's gone")


func test_trail_looks_like_smoke() -> void:
	var t := SmokeTrail.new()
	assert_lt(t.gradient.get_color(0).a, t.gradient.get_color(1).a, "fades toward the old end")
	assert_gt(t.width_curve.sample(0.0), t.width_curve.sample(1.0), "swells as it ages")
	t.free()


func test_stopping_the_game_with_missiles_in_flight_is_clean() -> void:
	_salvo(3)
	game.stop()
	await wait_physics_frames(2)
	assert_eq(_trails().size(), 0)


# --- Wild flight -----------------------------------------------------------------

func _fly(from: Vector2, frames: int) -> Array:
	game.fire_bullet(from, player.color, Vector2.UP, BulletScript.MISSILE)
	var m: Area2D = _missiles().back()
	var path := []
	for i in frames:
		m._physics_process(1.0 / 60.0)
		path.append(m.position)
	return path


func test_missiles_corkscrew_and_jitter_off_their_course() -> void:
	var path := _fly(Vector2(270, 800), 40)
	var lo := INF
	var hi := -INF
	var crossings := 0
	for i in path.size():
		var off: float = path[i].x - 270.0
		lo = minf(lo, off)
		hi = maxf(hi, off)
		if i > 0 and signf(off) != signf(path[i - 1].x - 270.0):
			crossings += 1
	assert_gt(hi - lo, BulletScript.SPIRAL_AMP, "swings side to side")
	assert_lt(maxf(absf(lo), absf(hi)), BulletScript.SPIRAL_AMP + BulletScript.JITTER + 0.5, "around its course")
	assert_gte(crossings, 2, "spirals back and forth")
	assert_lt(path.back().y, 800.0 - 100.0, "still makes headway")


func test_every_peer_flies_the_same_wild_path() -> void:
	var a := _fly(Vector2(200, 800), 30)
	var b := _fly(Vector2(200, 800), 30)
	assert_eq(a, b)
	var c := _fly(Vector2(320, 800), 30)
	assert_ne(a.map(func(p): return p.x - 200.0), c.map(func(p): return p.x - 320.0), "each missile wobbles its own way")


func test_the_swing_settles_when_it_closes_in() -> void:
	var e: Area2D = load("res://scenes/enemy.tscn").instantiate()
	e.position = Vector2(270, 760)
	game.get_node("Enemies").add_child(e)
	game.fire_bullet(Vector2(270, 800), player.color, Vector2.UP, BulletScript.MISSILE)
	var m: Area2D = _missiles().back()
	for i in 12:
		m._physics_process(1.0 / 60.0)
	assert_lt(m._closing, 1.0)
