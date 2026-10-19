extends GutTest
## AiPilot: an AI flying a player's own ship (the idle demo, "AI plays for
## me"). It steers the safest way toward its goal, shoots what's above it, uses
## its upgrades, spends exp and taps READY at refits, and picks a gate at forks.
## The demo: a random ship with random upgrades in a random kind of level,
## starting over when it's shot down; idle on the title screen starts it and
## any press ends it.

const PlayerScene := preload("res://scenes/player.tscn")
const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const TetranScript := preload("res://scripts/tetran.gd")
const StormScript := preload("res://scripts/scenery/storm.gd")
const MainScene := preload("res://scenes/main.tscn")
const SCORES := "user://test_ai_pilot_scores.json"

var game: Node2D
var _saved_peer: MultiplayerPeer
var _saved_path := ""
var _saved_pilot := false


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	_saved_pilot = Net.ai_pilot
	_saved_path = HighScores.path
	HighScores.path = SCORES
	HighScores.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	game.stop()
	HighScores.clear()
	HighScores.path = _saved_path
	Net.ai_pilot = _saved_pilot
	multiplayer.multiplayer_peer = _saved_peer


func _ship(pos := Vector2(270, 700)) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	p.pilot = AiPilot.new()
	game.get_node("Players").add_child(p)
	return p


func _live() -> void:
	game.active = true
	game.level = null


func _enemy(pos: Vector2, type := EnemyScript.TANK) -> Area2D:
	game.spawn_enemy({"x": pos.x, "y": pos.y, "type": type, "id": 900 + game.get_node("Enemies").get_child_count(), "stage": 0})
	var e: Area2D = game.get_node("Enemies").get_children().back()
	e.position = pos
	e.set_physics_process(false)  # hold still
	return e


func _think(p: Area2D, frames := 1) -> void:
	for i in frames:
		p.pilot.think(p, 1.0 / 60.0)


# --- Loadout -------------------------------------------------------------------------

func test_random_loadout_buys_powers_and_arms() -> void:
	var p := _ship()
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var before := 0
	for id in p.levels:
		before += p.levels[id]
	AiPilot.random_loadout(p, r, 10)
	var after := 0
	for id in p.levels:
		after += p.levels[id]
	assert_eq(after, before + 10)
	assert_true(p.power_spare() == 0 or _every_system_full(p), "the reactor's shared out")
	for g in [&"lasers", &"missile", &"beam", &"auto"]:
		if p.levels.get(g, 0) > 0 and p.power_of(&"weapons") - p.weapons_used() >= Systems.gun_power(g):
			assert_true(p.is_armed(g), "armed what it could: %s" % g)
	assert_false(p.is_armed(&"healbeam"), "never the heal beam")


func _every_system_full(p: Node) -> bool:
	for s in Systems.systems():
		if p.power_of(s.id) < p.levels.get(s.id, 0):
			return false
	return true


func test_re_arms_after_a_respawn() -> void:
	var p := _ship()
	p.levels[&"missile"] = 1
	p.levels[&"reactor"] = 8
	p.levels[&"weapons"] = 4
	p.respawn()
	assert_true(p.is_armed(&"lasers"))


# --- Steering ------------------------------------------------------------------------

func test_dodges_a_shot_coming_straight_at_it() -> void:
	_live()
	var p := _ship(Vector2(270, 700))
	game.fire_enemy_bullet(Vector2(270, 600), Vector2.DOWN)
	var shot: Area2D = game.get_node("Bullets").get_children().back()
	var closest := INF
	for i in 90:
		_think(p)
		p.position += p.input_dir * p.move_speed() / 60.0
		shot.position += shot.velocity() / 60.0
		closest = minf(closest, p.position.distance_to(shot.position))
	assert_gt(closest, AiPilot.SHIP_RADIUS + 6.0, "never in its way")


func test_stays_put_when_its_spot_is_safe() -> void:
	_live()
	var p := _ship(Vector2(270, 700))
	var goal := Vector2(270, 700)
	assert_lt(p.pilot.best_move(p, game, goal).length(), 0.2)


func test_heads_under_the_enemy_it_hunts() -> void:
	_live()
	var p := _ship(Vector2(150, 700))
	var e := _enemy(Vector2(400, 300))
	assert_eq(p.pilot.hunt(p, game), e)
	var goal: Vector2 = p.pilot.goal_for(p, game)
	assert_almost_eq(goal.x, 400.0, 1.0)
	_think(p, 30)  # it eases into a move
	assert_gt(p.input_dir.x, 0.3, "slides over")


func test_keeps_clear_of_tetrans_arms() -> void:
	_live()
	game.kind = "deep_space"
	game.spawn_boss()
	var e: Area2D = game.get_node("Enemies").get_children().back()
	e.position = TetranScript.HOVER
	var p := _ship()
	var tetran: Node = e.get_node("Tetran")
	var turn := TetranScript.angle_at(tetran._time())
	var on_arm: Vector2 = e.position + Vector2.from_angle(TetranScript.arm_angle(turn, 1)) * 300.0
	var between: Vector2 = e.position + Vector2.from_angle(TetranScript.arm_angle(turn, 1) + PI / 4.0) * 300.0
	var threats: Dictionary = p.pilot._threats(p, game)
	assert_gte(p.pilot._danger(on_arm, 0.0, threats, game), AiPilot.HIT)
	assert_eq(p.pilot._danger(between, 0.0, threats, game), 0.0, "the gap is safe")


func test_rides_its_gap_toward_the_spot_under_tetrans_core() -> void:
	_live()
	game.kind = "deep_space"
	game.spawn_boss()
	var e: Area2D = game.get_node("Enemies").get_children().back()
	e.position = TetranScript.HOVER
	var tetran: Node = e.get_node("Tetran")
	var p := _ship()
	var bounds: Rect2 = p._movement_bounds()
	for k in 40:
		tetran.enemy.set("_time", k * 0.7)
		var turn := TetranScript.angle_at(k * 0.7)
		p.position = e.position + Vector2.from_angle(turn + 0.6) * 250.0  # in the gap after arm 0
		var spot: Vector2 = p.pilot.tetran_spot(p, e, bounds)
		var a := wrapf((spot - e.position).angle() - turn, 0.0, TAU)
		assert_between(a, AiPilot.TETRAN_GAP_MARGIN - 0.001, PI / 2.0 - AiPilot.TETRAN_GAP_MARGIN + 0.001, "same gap at %d" % k)
		assert_true(bounds.grow(1.0).has_point(spot))


func test_steers_clear_of_lightning_warnings() -> void:
	_live()
	game.kind = "storm"
	game._process(0.0)
	var storm: Node = game.scenery
	var s: Array = storm.strikes_between(storm.time, storm.time + 30.0)
	assert_false(s.is_empty())
	var hit: Dictionary = s[0]
	assert_eq(storm.danger_at(hit.pos, hit.time - storm.time), 1.0)
	assert_eq(storm.danger_at(hit.pos + Vector2(200, 0), hit.time - storm.time), 0.0)


func test_survives_a_stream_of_aimed_shots() -> void:
	_live()
	var p := _ship(Vector2(270, 700))
	for i in 8:
		game.fire_enemy_bullet(Vector2(270 + (i % 3 - 1) * 40, 380), (p.position - Vector2(270, 380)).normalized())
		await wait_seconds(0.3)
	await wait_seconds(1.0)
	assert_eq(p.hp, p.max_hp(), "untouched")


# --- Guns ----------------------------------------------------------------------------

func test_fires_at_what_is_above_it() -> void:
	_live()
	var p := _ship(Vector2(270, 700))
	_enemy(Vector2(270, 300))
	p.pilot._use_guns(p, game)
	assert_true(p._fire_requested)


func test_holds_fire_with_a_friend_in_line() -> void:
	_live()
	var p := _ship(Vector2(270, 700))
	_enemy(Vector2(270, 300))
	var f: Area2D = PlayerScene.instantiate()
	f.name = "5"
	f.peer_id = 5
	f.position = Vector2(270, 500)
	game.get_node("Players").add_child(f)
	p.pilot._use_guns(p, game)
	assert_false(p._fire_requested)


func test_fires_missiles_and_the_beam_at_a_boss() -> void:
	_live()
	var p := _ship(Vector2(270, 700))
	p.levels[&"reactor"] = 10
	p.levels[&"weapons"] = 8
	p.levels[&"missile"] = 1
	p.levels[&"beam"] = 1
	p.pilot.manage(p)
	assert_true(p.is_armed(&"missile"))
	assert_true(p.is_armed(&"beam"))
	var e := _enemy(Vector2(270, 300), EnemyScript.BOSS)
	e.position = Vector2(270, 300)
	p.pilot._use_guns(p, game)
	assert_true(p._missile_requested)
	assert_true(p._beam_requested)


func test_sends_drones_for_someone_to_rescue() -> void:
	_live()
	var p := _ship()
	p.levels[&"reactor"] = 6
	p.levels[&"drones"] = 1
	p.levels[&"rescue"] = 1
	p.pilot.manage(p)
	game.spawn_pod(Vector2(200, 300), 0, "Pod1")
	p.pilot._use_guns(p, game)
	assert_true(p._launch_requested)


func test_drops_a_repair_kit_when_hurt() -> void:
	_live()
	var p := _ship()
	p.levels[&"reactor"] = 6
	p.levels[&"medbay"] = 1
	p.pilot.manage(p)
	p.hp = p.max_hp() - PlayerScript.HIT_HP * 2
	p.pilot._use_guns(p, game)
	assert_true(p._repair_requested)


# --- Breaks --------------------------------------------------------------------------

func test_spends_its_exp_and_taps_ready_at_a_refit() -> void:
	_live()
	var p := _ship()
	p.exp_balance = 40
	game.begin_refit(false)
	_think(p)
	assert_lt(p.exp_balance, 40, "bought something")
	assert_true(game.refit, "browses a moment first")
	_think(p, int(AiPilot.READY_DELAY * 60.0) + 2)
	assert_false(game.refit, "READY")


func test_flies_into_a_gate_at_a_fork() -> void:
	_live()
	var p := _ship(Vector2(270, 800))
	game.show_fork([{"kind": "orbit", "reward": "spare"}, {"kind": "storm", "reward": "repair"}])
	var goal: Vector2 = p.pilot.goal_for(p, game)
	var gates: Array = game._gates()
	assert_true(gates.any(func(g): return g.position == goal))


# --- AI plays for me -----------------------------------------------------------------

func test_host_ship_gets_a_pilot_when_asked() -> void:
	Net.ai_pilot = true
	game.start()
	var p: Node = game.get_node("Players/1")
	assert_not_null(p.pilot)
	assert_false(p.ai, "still the host's own ship: it collects exp")
	assert_false(game.pointer_controls.visible, "no controls to work")


func test_no_pilot_by_default() -> void:
	Net.ai_pilot = false
	game.start()
	assert_null(game.get_node("Players/1").pilot)


# --- Demo ----------------------------------------------------------------------------

func test_demo_flies_a_random_ship_through_a_random_kind() -> void:
	var kinds := {}
	var ships := {}
	for i in 12:
		game.start_demo()
		assert_true(game.demo)
		assert_true(LevelKinds.is_kind(game.kind))
		kinds[game.kind] = true
		var p: Node = game.get_node("Players/1")
		assert_not_null(p.pilot)
		ships[p.ship] = true
		game.stop()
	assert_gt(kinds.size(), 1, "kinds vary")
	assert_gt(ships.size(), 1, "ships vary")


func test_demo_ship_starts_with_upgrades() -> void:
	game.start_demo()
	var p: Node = game.get_node("Players/1")
	var n := 0
	for id in p.levels:
		n += p.levels[id]
	var fresh := 0
	for it in Systems.ITEMS:
		fresh += it.get("start", 0)
	assert_gte(n - fresh, game.DEMO_UPGRADES.x)
	assert_false(game.pointer_controls.visible)


func test_demo_starts_over_when_shot_down_and_keeps_no_score() -> void:
	game.start_demo()
	var p: Node = game.get_node("Players/1")
	p.take_damage(100)
	assert_false(p.is_alive())
	for i in int(game.DEMO_RESTART / 0.1) + 2:
		game._physics_process(0.1)
	await wait_frames(2)
	assert_true(game.demo)
	var again: Node = game.get_node_or_null("Players/1")
	assert_not_null(again)
	assert_ne(again, p, "a new ship")
	assert_true(again.is_alive())
	assert_eq(HighScores.load_all().size(), 0)


func test_idle_title_starts_the_demo_and_a_press_ends_it() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	var g: Node = main.game
	main._process(main.DEMO_IDLE - 1.0)
	assert_false(g.demo)
	var move := InputEventMouseMotion.new()
	main._input(move)
	main._process(2.0)
	assert_false(g.demo, "moving the mouse counts as not idle")
	main._process(main.DEMO_IDLE)
	assert_true(g.demo)
	assert_false(main.main_menu.visible)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	main._input(key)
	assert_false(g.demo)
	assert_false(g.active)
	assert_true(main.main_menu.visible)
	Net.stop_browsing()


func test_goes_for_exp_across_the_screen() -> void:
	_live()
	var p := _ship(Vector2(80, 700))
	game.spawn_pickup(Vector2(460, 420), "Pickup1")
	assert_eq(p.pilot.goal_for(p, game), Vector2(460, 420), "worth the trip")
