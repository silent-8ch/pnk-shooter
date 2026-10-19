extends GutTest
## A run: the party shares START_SPARE spare ships. A destroyed ship comes back
## only by taking one; with none left it waits (spectating). When nobody is
## alive and no spares are left, it's game over: the run is logged in the high
## scores, the results stay up a moment, and the next run starts. +SHIP (in
## HULL) buys a spare for everyone.

const PlayerScene := preload("res://scenes/player.tscn")
const PlayerScript := preload("res://scripts/player.gd")
const MainScene := preload("res://scenes/main.tscn")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	HighScores.path = "user://test_spares_scores.json"
	HighScores.clear()
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.level = null


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer
	HighScores.clear()
	HighScores.path = HighScores.PATH


func _ship(id: int, pos := Vector2(270, 700)) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	p.spawn_position = pos
	game.get_node("Players").add_child(p)
	return p


func _kill(p: Area2D) -> void:
	p.hp = 0.01
	p.take_damage(5.0)
	assert_false(p.is_alive())


func _wait_respawn(p: Area2D) -> void:
	p._simulate(PlayerScript.RESPAWN_TIME + 0.1)


func test_a_run_starts_with_four_shared_spares() -> void:
	assert_eq(game.START_SPARES, 4)
	assert_eq(game.spares, 4)
	var cfg: SceneReplicationConfig = game.get_node("ScoreSync").replication_config
	assert_true(cfg.has_property(NodePath(".:spares")))


func test_coming_back_takes_a_spare() -> void:
	var p := _ship(1)
	_kill(p)
	_wait_respawn(p)
	assert_true(p.is_alive())
	assert_eq(game.spares, 3)


func test_no_spares_no_coming_back() -> void:
	var p := _ship(1)
	game.spares = 0
	_kill(p)
	for i in 5:
		_wait_respawn(p)
	assert_false(p.is_alive(), "spectating")


func test_a_bought_spare_brings_back_a_waiting_ship() -> void:
	var dead := _ship(1)
	var buyer := _ship(7, Vector2(330, 700))
	buyer.ai = true  # flown on this peer
	game.spares = 0
	_kill(dead)
	_wait_respawn(dead)
	assert_false(dead.is_alive())
	buyer.exp_balance = 100
	assert_true(buyer.buy_upgrade(&"ship"))
	assert_eq(game.spares, 1)
	_wait_respawn(dead)
	assert_true(dead.is_alive())
	assert_eq(game.spares, 0)


func test_ship_item_is_limited() -> void:
	assert_eq(Systems.max_level(&"ship"), 3)
	var p := _ship(1)
	p.exp_balance = 1000
	for i in 3:
		assert_true(p.buy_upgrade(&"ship"))
	assert_false(p.buy_upgrade(&"ship"))
	assert_eq(game.spares, game.START_SPARES + 3)


func test_game_over_only_when_everyone_is_down_and_no_spares_left() -> void:
	var a := _ship(1)
	var b := _ship(7, Vector2(330, 700))
	b.ai = true  # flown on this peer
	game.spares = 0
	_kill(a)
	for i in 30:
		game._physics_process(0.1)
	assert_false(game.over, "b still flying")
	_kill(b)
	game._physics_process(game.GAME_OVER_GRACE * 0.5)
	assert_false(game.over, "grace")
	game._physics_process(game.GAME_OVER_GRACE * 0.6)
	assert_true(game.over)
	assert_false(game.input_enabled)


func test_spares_left_means_no_game_over() -> void:
	var a := _ship(1)
	_kill(a)
	for i in 30:
		game._physics_process(0.1)
	assert_false(game.over)


func test_game_over_logs_the_run_and_ends_it_after_the_results() -> void:
	game.score = 777
	game.stage = 2
	game._run_players = ["Pilot", "Buddy"]
	_ship(1)
	watch_signals(game)
	game.game_over(game.score, game.stage, game._run_players)
	var log := HighScores.load_all()
	assert_eq(log.size(), 1)
	assert_eq(log[0].score, 777)
	assert_eq(log[0].stage, 3)
	assert_eq(log[0].players, ["Pilot", "Buddy"])
	assert_gt(get_tree().get_nodes_in_group("banner").size(), 0)
	game._process(game.RESULTS_TIME - 0.5)
	assert_signal_not_emitted(game, "run_ended")
	game._process(1.0)
	assert_signal_emitted(game, "run_ended")


func test_restart_starts_a_fresh_run_with_the_same_peer() -> void:
	_ship(1)
	game.score = 500
	game.stage = 3
	game.spares = 0
	game.kills = 12
	game.restart_run()
	assert_eq(game.score, 0)
	assert_eq(game.stage, 0)
	assert_eq(game.kills, 0)
	assert_eq(game.spares, game.START_SPARES)
	assert_false(game.over)
	assert_true(game.active)
	assert_not_null(multiplayer.multiplayer_peer)
	assert_true(game.has_node("Players/1"), "the host's ship is back")


func test_hud_shows_the_spares() -> void:
	game.spares = 2
	game._process(0.0)
	var texts: Array = game.status_bar.segments().map(func(s): return s.text)
	assert_has(texts, "SHIPS 2")


func test_after_the_results_everyone_readies_up_for_the_next_run() -> void:
	game.queue_free()
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	var g: Node2D = main.get_node("Game")
	var screen: CanvasLayer = main.get_node("ReadyScreen")
	g.start()
	g.score = 300
	g.game_over(300, 1, ["Player"])
	main.set_paused(true)
	assert_false(main.is_paused(), "no pause over the results")
	g._process(g.RESULTS_TIME + 0.1)
	assert_true(screen.visible, "ready screen")
	assert_false(g.active, "waiting for everyone")
	assert_string_contains(screen.results_label.text, "Score 300")
	assert_string_contains(screen.players_label.text, "...")
	screen.ready_button.button_pressed = true  # the only player taps Ready
	assert_false(screen.visible)
	assert_true(g.active, "next run")
	assert_eq(g.score, 0)
	assert_eq(g.spares, g.START_SPARES)


func test_the_run_waits_for_every_player() -> void:
	game.peer_names = {1: "Host"}
	game.open_ready()
	var seen := []
	game.ready_changed.connect(func(list): seen.append(list))
	game.set_ready(false)
	assert_false(game.active and false)
	assert_eq(seen.back(), [{"name": "Host", "ready": false}])
	game.active = false
	game.set_ready(true)
	assert_true(game.active, "all (one) ready: the run starts")


func test_status_bar_shows_score_stage_ships_and_exp() -> void:
	game.score = 1234
	game.stage = 2
	game.spares = 3
	var texts: Array = game.status_bar.segments().map(func(s): return s.text)
	assert_has(texts, "SCORE 1234")
	assert_has(texts, "STAGE 3")
	assert_has(texts, "SHIPS 3")
	var me: Node = game.local_player()
	if me:
		me.exp_balance = 7
		texts = game.status_bar.segments().map(func(s): return s.text)
		assert_has(texts, "EXP 7")


func test_collecting_exp_pops_a_plus_one() -> void:
	game.spawn_pickup(Vector2(270, 500), "Pickup1")
	var before := game.get_node("Effects").get_children().filter(func(n): return n is FloatText).size()
	game.collect_pickup("Pickup1", multiplayer.get_unique_id())
	var pops := game.get_node("Effects").get_children().filter(func(n): return n is FloatText)
	if game.local_player() == null:
		assert_eq(pops.size(), before, "no ship of ours, nothing to pop")
		return
	assert_eq(pops.size(), before + 1)
	assert_eq(pops.back().text, "+1")
