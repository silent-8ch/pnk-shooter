extends GutTest
## Enemy types: look, stats, weaver/diver movement, and no-peer safety.

const EnemyScene := preload("res://scenes/enemy.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")


class FakePlayer extends Node2D:
	var alive := true

	func is_alive() -> bool:
		return alive


var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _enemy(type: int, pos := Vector2(270, 100)) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.type = type
	e.position = pos
	add_child_autofree(e)
	return e


func _player(pos: Vector2, alive := true) -> FakePlayer:
	var p := FakePlayer.new()
	p.position = pos
	p.alive = alive
	p.add_to_group("player")
	add_child_autofree(p)
	return p


# --- Look and stats ---------------------------------------------------------

func test_weaver_uses_ship01_enemy_texture() -> void:
	var e := _enemy(EnemyScript.WEAVER)
	assert_same(e.get_node("Body").texture, Ships.get_enemy_texture(0))


func test_diver_uses_ship02_enemy_texture() -> void:
	var e := _enemy(EnemyScript.DIVER)
	assert_same(e.get_node("Body").texture, Ships.get_enemy_texture(1))


func test_enemies_face_down_and_are_smaller_than_players() -> void:
	var body: Sprite2D = _enemy(EnemyScript.WEAVER).get_node("Body")
	assert_true(body.flip_v)
	var height := body.texture.get_size().y * body.scale.y
	assert_almost_eq(height, EnemyScript.HEIGHT, 0.01)
	assert_lt(EnemyScript.HEIGHT, Ships.SHIP_HEIGHT)


func test_stats_per_type() -> void:
	var w := _enemy(EnemyScript.WEAVER)
	var d := _enemy(EnemyScript.DIVER)
	assert_eq(w.hp, 1)
	assert_eq(d.hp, 1)
	assert_eq(w.points(), 10)
	assert_eq(d.points(), 15)
	assert_gt(EnemyScript.TYPES[EnemyScript.DIVER].speed, EnemyScript.TYPES[EnemyScript.WEAVER].speed)


func test_invalid_type_clamped() -> void:
	var e := _enemy(99)
	assert_eq(e.type, EnemyScript.TYPES.size() - 1)


# --- Movement ---------------------------------------------------------------

func test_weaver_drifts_down_and_weaves() -> void:
	var e := _enemy(EnemyScript.WEAVER, Vector2(270, 100))
	var xs := []
	for i in 30:
		e.simulate(0.1)
		xs.append(e.position.x)
	assert_gt(e.position.y, 100.0)
	assert_gt(xs.max(), 270.0 + 30.0, "weaves right")
	assert_lt(xs.min(), 270.0 - 30.0, "weaves left")
	assert_lte(xs.max(), 270.0 + EnemyScript.WEAVE_AMPLITUDE + 0.01)


func test_weaver_stays_in_arena() -> void:
	var e := _enemy(EnemyScript.WEAVER, Vector2(25, 100))
	for i in 30:
		e.simulate(0.1)
		assert_gte(e.position.x, 20.0)


func test_diver_steers_toward_nearest_player() -> void:
	_player(Vector2(500, 800))
	_player(Vector2(150, 400))
	var e := _enemy(EnemyScript.DIVER, Vector2(270, 100))
	e.simulate(0.1)
	assert_lt(e.position.x, 270.0, "steers left toward the closer player")
	assert_almost_eq(e.position.x, 270.0 - EnemyScript.DIVE_STEER_SPEED * 0.1, 0.01)


func test_diver_ignores_dead_and_passed_players() -> void:
	_player(Vector2(100, 400), false)  # dead
	_player(Vector2(500, 50))  # already above the diver
	var e := _enemy(EnemyScript.DIVER, Vector2(270, 100))
	e.simulate(0.1)
	assert_eq(e.position.x, 270.0)
	assert_gt(e.position.y, 100.0)


func test_diver_no_overshoot() -> void:
	_player(Vector2(272, 800))
	var e := _enemy(EnemyScript.DIVER, Vector2(270, 100))
	e.simulate(0.1)
	assert_almost_eq(e.position.x, 272.0, 0.001)


# --- No peer ----------------------------------------------------------------

func test_no_peer_physics_does_nothing() -> void:
	multiplayer.multiplayer_peer = null
	var e := _enemy(EnemyScript.WEAVER, Vector2(100, 100))
	e._physics_process(1.0)
	assert_eq(e.position, Vector2(100, 100))


func test_no_peer_take_damage_ignored() -> void:
	multiplayer.multiplayer_peer = null
	var e := _enemy(EnemyScript.WEAVER)
	e.take_damage(1)
	assert_eq(e.hp, 1)


# --- Speed ramp -------------------------------------------------------------

func test_slower_speeds() -> void:
	assert_eq(EnemyScript.TYPES[EnemyScript.WEAVER].speed, 90.0)
	assert_eq(EnemyScript.TYPES[EnemyScript.DIVER].speed, 130.0)
	assert_eq(EnemyScript.DIVE_STEER_SPEED, 70.0)


func test_eases_in_from_half_speed() -> void:
	var e := _enemy(EnemyScript.WEAVER)
	var full: float = EnemyScript.TYPES[EnemyScript.WEAVER].speed
	assert_almost_eq(e.speed_now(), full * 0.5, 0.001)
	e.simulate(EnemyScript.RAMP_TIME / 2.0)
	assert_almost_eq(e.speed_now(), full * 0.75, 0.001)
	e.simulate(EnemyScript.RAMP_TIME)
	assert_almost_eq(e.speed_now(), full, 0.001)


# --- Groups -----------------------------------------------------------------

func test_weaver_group_is_centered_line() -> void:
	var pts := EnemyScript.group_layout(EnemyScript.WEAVER, 5, 270.0)
	assert_eq(pts.size(), 5)
	for i in pts.size():
		assert_eq(pts[i].y, EnemyScript.SPAWN_Y)
		if i > 0:
			assert_almost_eq(pts[i].x - pts[i - 1].x, EnemyScript.WEAVER_SPACING, 0.001)
	assert_almost_eq((pts[0].x + pts[4].x) / 2.0, 270.0, 0.001)


func test_diver_group_is_v_with_leader_in_front() -> void:
	var pts := EnemyScript.group_layout(EnemyScript.DIVER, 3, 270.0)
	assert_eq(pts.size(), 3)
	assert_eq(pts[0], Vector2(270, EnemyScript.SPAWN_Y))
	var off: Vector2 = EnemyScript.DIVER_V_OFFSET
	assert_eq(pts[1], Vector2(270 - off.x, EnemyScript.SPAWN_Y - off.y))
	assert_eq(pts[2], Vector2(270 + off.x, EnemyScript.SPAWN_Y - off.y))


func test_groups_fit_in_arena() -> void:
	for count in range(EnemyScript.WEAVER_GROUP_MIN, EnemyScript.WEAVER_GROUP_MAX + 1):
		var half := EnemyScript.group_half_width(EnemyScript.WEAVER, count)
		assert_lt(2.0 * (half + 20.0), EnemyScript.ARENA_WIDTH, "weaver x%d" % count)
	var dh := EnemyScript.group_half_width(EnemyScript.DIVER, EnemyScript.DIVER_GROUP)
	assert_eq(dh, EnemyScript.DIVER_V_OFFSET.x)


func test_weavers_in_group_weave_in_sync() -> void:
	var a := _enemy(EnemyScript.WEAVER, Vector2(200, -40))
	var b := _enemy(EnemyScript.WEAVER, Vector2(270, -40))
	for i in 10:
		a.simulate(0.1)
		b.simulate(0.1)
	assert_almost_eq(b.position.x - a.position.x, 70.0, 0.001)
