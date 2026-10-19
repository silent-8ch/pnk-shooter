extends GutTest
## A stage's pauses: halfway to the boss an ELITE mini boss comes in; shooting
## it down starts a refit, and so does the boss (which then leads to the fork).
## A refit clears enemies, their shots and obstacles, stops the level, and
## lasts until everyone taps READY. Nothing hurts the ships from a boss kill
## until the next stage starts.

const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const PlayerScript := preload("res://scripts/player.gd")

var game: Node2D
var player: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.level = null
	game.get_node("PointerControls").visible = true
	player = PlayerScene.instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 800)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _enemies() -> Array:
	return game.get_node("Enemies").get_children().filter(func(e): return not e.is_queued_for_deletion())


func _kill_weaver() -> void:
	game.spawn_group(EnemyScript.WEAVER, 270.0, 1)
	game.destroy_enemy(_enemies().back(), true)


func _elite() -> Area2D:
	game.spawn_elite()
	return _enemies().back()


func _refit_after_elite() -> void:
	game.destroy_enemy(_elite(), true)


# --- The mini boss -----------------------------------------------------------------

func test_elite_comes_in_halfway_to_the_boss() -> void:
	assert_eq(game.mini_boss_kills(), game.boss_kills_needed() / 2)
	for i in game.mini_boss_kills() - 1:
		_kill_weaver()
	game._physics_process(0.016)
	assert_false(game.elite_alive())
	_kill_weaver()
	game._physics_process(0.016)
	assert_true(game.elite_alive())
	assert_false(game.boss_alive(), "not the boss")


func test_only_one_elite_a_stage() -> void:
	for i in game.mini_boss_kills():
		_kill_weaver()
	game._physics_process(0.016)
	game.destroy_enemy(_enemies().filter(func(e): return e.is_elite())[0], true)
	game.set_refit_ready(true)
	game._physics_process(0.016)
	assert_false(game.elite_alive(), "no second one")


func test_elite_is_a_big_tank_with_a_bar_that_never_fires() -> void:
	var e := _elite()
	assert_true(e.is_elite())
	assert_true(e.has_bar())
	assert_false(e.is_boss())
	assert_eq(EnemyScript.TYPES[EnemyScript.ELITE].ship, EnemyScript.TYPES[EnemyScript.TANK].ship, "a tank")
	assert_gt(EnemyScript.TYPES[EnemyScript.ELITE].hp, EnemyScript.TYPES[EnemyScript.TANK].hp * 3)
	assert_gt(EnemyScript.TYPES[EnemyScript.ELITE].height, EnemyScript.TYPES[EnemyScript.TANK].height)
	for i in 600:
		e._physics_process(1.0 / 60.0)
	assert_lte(e.position.y, EnemyScript.BOSS_Y + EnemyScript.BOSS_BOB + 1.0, "holds at the top")
	var hostile := game.get_node("Bullets").get_children().filter(func(b): return b.is_hostile())
	assert_eq(hostile.size(), 0, "no bullets")


func test_elite_shrugs_off_rams() -> void:
	var e := _elite()
	var hp: int = e.hp
	e.ram()
	assert_true(game.elite_alive())
	assert_lt(e.hp, hp)


func test_escorts_dont_count_toward_the_boss_while_the_elite_is_up() -> void:
	_elite()
	_kill_weaver()
	assert_eq(game.kills, 0)


# --- Refit -------------------------------------------------------------------------

func test_shooting_the_elite_down_starts_a_refit() -> void:
	_refit_after_elite()
	assert_true(game.refit)
	assert_false(game.refit_after_boss)
	assert_true(game.between_levels())


func test_shooting_the_boss_down_starts_a_refit_then_the_fork() -> void:
	game.spawn_boss()
	game.destroy_enemy(_enemies().back(), true)
	assert_true(game.refit)
	assert_true(game.refit_after_boss)
	assert_false(game.fork_open(), "not yet")
	assert_eq(game.stage, 1)


func test_refit_clears_enemies_shots_and_obstacles_but_not_loot() -> void:
	game.spawn_group(EnemyScript.WEAVER, 270.0, 3)
	game.fire_enemy_bullet(Vector2(100, 100), Vector2.DOWN)
	game.fire_bullet(Vector2(200, 500), Color.RED)  # a player's
	game.spawn_obstacle({"name": "Obstacle1", "piece": "asteroid_l", "x": 270.0, "y": 300.0, "count": 1, "dir": 1.0})
	game.spawn_pickup(Vector2(300, 300), "Pickup1")
	game.spawn_pod(Vector2(320, 300), 0, "Pod1")
	_refit_after_elite()
	assert_eq(game.get_node("Enemies").get_child_count(), 0, "enemies gone")
	assert_false(game.boss_alive() or game.elite_alive())
	var shots := game.get_node("Bullets").get_children()
	assert_eq(shots.filter(func(b): return b.is_hostile()).size(), 0, "their shots gone")
	assert_eq(shots.size(), 1, "ours stay")
	assert_eq(game.get_node("Obstacles").get_child_count(), 0)
	assert_true(game.get_node("Pickups").has_node("Pickup1"), "pickups stay")
	assert_true(game.get_node("Pods").has_node("Pod1"), "pods stay")


func test_cleared_enemies_score_nothing() -> void:
	game.spawn_group(EnemyScript.WEAVER, 270.0, 3)
	var score: int = game.score
	game.begin_refit(false)
	assert_eq(game.score, score)
	assert_eq(game.get_node("Pods").get_child_count(), 0)


func test_cleared_enemies_warp_out() -> void:
	game.spawn_group(EnemyScript.WEAVER, 270.0, 1)
	var e: Node2D = _enemies()[0]
	game.begin_refit(false)
	assert_true(is_instance_valid(e))
	assert_false(e.is_in_group("enemy"))
	await wait_seconds(game.WARP_TIME + 0.1)
	assert_false(is_instance_valid(e), "gone after the flash")


func test_nothing_spawns_and_the_level_holds_during_a_refit() -> void:
	game.begin_refit(false)
	var t: float = game.level_time
	for i in 200:
		game._physics_process(0.1)
	assert_eq(game.level_time, t)
	assert_eq(_enemies().size(), 0)


func test_ships_cant_be_hurt_during_a_refit_or_the_fork() -> void:
	game.begin_refit(true)
	player.take_damage(3)
	assert_eq(player.hp, PlayerScript.MAX_HP)
	game.set_refit_ready(true)
	assert_true(game.fork_open())
	player.take_damage(3)
	assert_eq(player.hp, PlayerScript.MAX_HP, "nor at the fork")
	game.choose_fork(0)
	var hp: float = player.hp  # the gate's reward may have added armor
	player.take_damage(1)
	assert_lt(player.hp, hp, "the next stage is live")


func test_everyone_ready_ends_the_refit_and_the_fight_goes_on() -> void:
	_refit_after_elite()
	game.set_refit_ready(true)
	assert_false(game.refit)
	assert_false(game.fork_open(), "on to the boss, no fork")


func test_unready_keeps_it_going() -> void:
	game.begin_refit(false)
	game.set_refit_ready(false)
	assert_true(game.refit)


func test_refit_opens_the_ship_popup() -> void:
	var panel: ShipPanel = game.get_node("PointerControls/ShipPanel")
	game.begin_refit(false)
	assert_eq(panel.page, ShipPanel.SYSTEMS_PAGE)


func test_stop_ends_a_refit() -> void:
	game.begin_refit(false)
	game.stop()
	assert_false(game.refit)


# --- READY panel -------------------------------------------------------------------

func test_ready_panel_shows_only_during_a_refit() -> void:
	var panel: RefitPanel = game.get_node("PointerControls/RefitPanel")
	assert_false(panel.is_active())
	game.begin_refit(false)
	assert_true(panel.is_active())
	assert_eq(panel.list.size(), 1, "who's in")
	assert_false(panel.list[0].ready)


func test_ready_button_readies_and_the_refit_ends() -> void:
	var panel: RefitPanel = game.get_node("PointerControls/RefitPanel")
	game.begin_refit(false)
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = panel.ready_rect().get_center()
	panel._input(ev)
	assert_false(game.refit, "the only player was ready")
	assert_false(panel.is_ready, "reset for next time")


func test_ready_panel_blocks_steering() -> void:
	var panel: RefitPanel = game.get_node("PointerControls/RefitPanel")
	game.begin_refit(false)
	var pointer: Node = game.get_node("PointerControls/Control")
	assert_true(pointer._on_action_bar(panel.ready_rect().get_center()))
