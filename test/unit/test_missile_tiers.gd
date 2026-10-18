extends GutTest
## Missile tiers: MISSILE goes to 3 levels in tier I and 6 in tier II. Each level
## adds a missile per gun to the salvo (fanned out sideways) and reloads faster.
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


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _missiles() -> Array:
	return game.get_node("Bullets").get_children().filter(func(b): return b.is_seeking())


func _trails() -> Array:
	return game.get_node("Effects").get_children().filter(func(n): return n is SmokeTrail)


func _salvo(level: int) -> Array:
	player.levels[&"missile"] = level
	player._missile_cooldown = 0.0
	for m in _missiles():
		m.free()
	player._missile_requested = true
	player._simulate(0.016)
	return _missiles()


func test_many_levels_across_both_tiers() -> void:
	assert_eq(PowerMeter.max_level(&"missile", 1), 3)
	assert_eq(PowerMeter.max_level(&"missile", 2), 6)


func test_each_level_adds_a_missile_to_the_salvo() -> void:
	for lv in range(1, 7):
		assert_eq(_salvo(lv).size(), lv, "level %d" % lv)


func test_options_fire_a_full_salvo_each() -> void:
	player.options = 2
	player._process(0.0)
	assert_eq(_salvo(3).size(), 9)


func test_salvo_fans_out_evenly_and_symmetrically() -> void:
	player.levels[&"missile"] = 1
	assert_eq(player.missile_directions(), [Vector2.UP] as Array[Vector2])
	player.levels[&"missile"] = 5
	var dirs: Array[Vector2] = player.missile_directions()
	assert_almost_eq(Vector2.UP.angle_to(dirs[0]), -PlayerScript.MISSILE_FAN, 0.0001)
	assert_almost_eq(Vector2.UP.angle_to(dirs[4]), PlayerScript.MISSILE_FAN, 0.0001)
	assert_almost_eq(dirs[2], Vector2.UP, Vector2(0.0001, 0.0001))
	for i in 5:
		assert_almost_eq(dirs[i].x, -dirs[4 - i].x, 0.0001)


func test_higher_levels_reload_faster() -> void:
	var last := INF
	for lv in range(1, 7):
		player.levels[&"missile"] = lv
		assert_lt(player.missile_cooldown(), last, "level %d" % lv)
		last = player.missile_cooldown()
	player.levels[&"missile"] = 1
	assert_eq(player.missile_cooldown(), PlayerScript.MISSILE_COOLDOWN)


func test_button_cooldown_follows_the_level() -> void:
	game.get_node("PointerControls").visible = true
	var bar: ActionBar = game.get_node("PointerControls/ActionBar")
	player.levels[&"missile"] = 4
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
