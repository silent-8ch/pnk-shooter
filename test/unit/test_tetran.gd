extends GutTest
## Tetran, Deep Space's boss (after Life Force): a big armored core holding
## mid-screen with four straight arms that run off the screen, turning steadily
## one way, so ships orbit it. Only the core can be hurt; the arms soak
## up shots and hurt ships that touch them. It never fires; easy enemies come
## in during the fight.

const EnemyScript := preload("res://scripts/enemy.gd")
const TetranScript := preload("res://scripts/tetran.gd")
const BulletScene := preload("res://scenes/bullet.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const PlayerScript := preload("res://scripts/player.gd")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _tetran() -> Area2D:
	game.kind = LevelKinds.FIRST
	game.spawn_boss()
	return game.get_node("Enemies").get_children().back()


func _player(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _fly(e: Area2D, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		e._physics_process(1.0 / 60.0)
		e.get_node("Tetran")._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0


func _hostile() -> Array:
	return game.get_node("Bullets").get_children().filter(func(b): return b.is_hostile())


func test_deep_space_boss_is_tetran() -> void:
	assert_eq(LevelKinds.FIRST, "deep_space")
	var e := _tetran()
	assert_true(e.is_tetran())
	assert_true(e.is_boss(), "a boss in every way: bar, music, stage, refit")
	assert_true(e.has_node("Tetran"))
	assert_false(e.body.visible, "draws itself")


func test_other_kinds_keep_their_boss() -> void:
	game.kind = "asteroid_belt"
	game.spawn_boss()
	var e: Area2D = game.get_node("Enemies").get_children().back()
	assert_eq(e.type, EnemyScript.BOSS)


func test_four_straight_arms_of_shrinking_segments() -> void:
	var arms: Array = TetranScript.arm_points(3.0)
	assert_eq(arms.size(), 4)
	for arm in arms:
		assert_eq(arm.size(), TetranScript.SEGMENTS)
		var dir: Vector2 = arm[0].normalized()
		for p in arm:
			assert_almost_eq(p.normalized().dot(dir), 1.0, 0.0001, "straight")
	assert_gt(TetranScript.segment_radius(0), TetranScript.segment_radius(TetranScript.SEGMENTS - 1))
	var e := _tetran()
	assert_eq(e.get_node("Tetran").get_child_count(), 4, "a hit box per arm")


func test_arms_run_off_every_edge_of_the_screen() -> void:
	var reach: float = TetranScript.CORE_RADIUS + TetranScript.arm_length()
	for corner in [Vector2(0, 0), Vector2(540, 0), Vector2(0, 960), Vector2(540, 960)]:
		assert_gt(reach, TetranScript.HOVER.distance_to(corner) + 100.0, str(corner))


func test_core_is_big() -> void:
	assert_gte(TetranScript.CORE_RADIUS, 50.0)
	var e := _tetran()
	assert_eq((e.get_node("Shape").shape as CircleShape2D).radius, TetranScript.CORE_RADIUS)


func test_always_turns_the_same_way_steadily() -> void:
	var step := 1.0 / 60.0
	var t := 0.0
	while t < 60.0:
		assert_almost_eq(TetranScript.angle_at(t + step) - TetranScript.angle_at(t), TetranScript.SPIN * step, 0.00001)
		t += 1.0
	assert_gt(TetranScript.angle_at(60.0) - TetranScript.angle_at(0.0), TAU, "goes all the way round")


func test_starts_as_an_x_so_the_bottom_is_a_gap() -> void:
	var down := (Vector2(270, 800) - TetranScript.HOVER).angle()
	for a in TetranScript.ARMS:
		var arm := TetranScript.arm_angle(TetranScript.angle_at(0.0), a)
		assert_gt(absf(angle_difference(arm, down)), 0.5, "arm %d clear of the spawn" % a)


func test_core_glides_in_and_holds() -> void:
	var spawn := Vector2(270, EnemyScript.SPAWN_Y - 60.0)
	assert_lt(TetranScript.core_position(spawn, 0.5, 90.0).y, TetranScript.HOVER.y)
	assert_eq(TetranScript.core_position(spawn, 30.0, 90.0), TetranScript.HOVER)
	assert_eq(TetranScript.core_position(spawn, 60.0, 90.0), TetranScript.HOVER)


func test_every_peer_sees_the_same_arms() -> void:
	assert_eq(TetranScript.arm_points(4.2), TetranScript.arm_points(4.2))


func test_core_takes_damage() -> void:
	var e := _tetran()
	var hp: int = e.hp
	game.report_hit(String(e.name), 1.0)
	assert_eq(e.hp, hp - 1)


func test_arms_soak_up_shots() -> void:
	var e := _tetran()
	var hp: int = e.hp
	var arms: Area2D = e.get_node("Tetran")
	var b: Area2D = BulletScene.instantiate()
	b.shooter = 1
	game.get_node("Bullets").add_child(b)
	arms._on_area_entered(b)
	assert_true(b.is_queued_for_deletion(), "stopped")
	assert_eq(e.hp, hp, "no damage")


func test_arms_let_its_own_shots_out() -> void:
	var e := _tetran()
	game.fire_enemy_bullet(e.position, Vector2.DOWN)
	var b: Area2D = _hostile()[0]
	e.get_node("Tetran")._on_area_entered(b)
	assert_false(b.is_queued_for_deletion())


func test_arms_hurt_ships_that_touch_them() -> void:
	var e := _tetran()
	var p := _player(Vector2(270, 800))
	p._on_area_entered(e.get_node("Tetran"))
	assert_lt(p.hp, PlayerScript.MAX_HP)


func test_never_fires() -> void:
	var e := _tetran()
	_player(Vector2(270, 800))
	_fly(e, 30.0)
	assert_eq(_hostile().size(), 0)


func test_easy_enemies_come_in_during_the_fight() -> void:
	game.active = true
	game.level = null
	_tetran()
	for i in int(game.BOSS_ADD_INTERVAL / 0.1) + 2:
		game._physics_process(0.1)
	var adds := game.get_node("Enemies").get_children().filter(func(x): return not x.is_boss())
	assert_gt(adds.size(), 0)
	for a in adds:
		assert_has(game.BOSS_ADD_TYPES, a.type)


func test_shooting_it_down_ends_the_stage() -> void:
	var e := _tetran()
	game.destroy_enemy(e, true)
	assert_eq(game.stage, 1)
	assert_true(game.refit)
