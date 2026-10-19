extends GutTest
## Players joining late catch up: between runs they wait on the ready screen;
## mid-run they get the open fork (with the time left), the boss's hp and the
## scenery's clock (hazard timing).

const PlayerScene := preload("res://scenes/player.tscn")
const MainScene := preload("res://scenes/main.tscn")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func test_joining_between_runs_waits_for_the_next_run() -> void:
	game.active = false
	game.register_player("Late", 0, 0)
	assert_eq(game.get_node("Players").get_child_count(), 0, "no world to join")
	assert_true(game.peer_names.values().has("Late"), "listed on the ready screen")


func test_joining_during_the_results_waits_too() -> void:
	game.active = true
	game.over = true
	game.register_player("Late", 0, 0)
	assert_eq(game.get_node("Players").get_child_count(), 0)


func test_waiting_joiner_sees_the_ready_screen() -> void:
	game.queue_free()
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	var g: Node2D = main.get_node("Game")
	g.start()
	g.wait_for_run("")
	assert_false(g.active)
	var screen: CanvasLayer = main.get_node("ReadyScreen")
	assert_true(screen.visible)
	assert_string_contains(screen.results_label.text, "next run")


func test_a_fork_shown_late_keeps_the_hosts_countdown() -> void:
	game.active = true
	game.show_fork([{"kind": "orbit", "reward": "spare"}, {"kind": "storm", "reward": "repair"}], 3.5)
	assert_true(game.fork_open())
	assert_almost_eq(game._fork_left, 3.5, 0.001)


func test_scenery_clock_applies_to_the_matching_scenery() -> void:
	game.active = true
	game.kind = "storm"
	game._process(0.0)
	game.set_scenery_time("storm", 42.0)
	assert_almost_eq(game.scenery.time, 42.0, 0.1)


func test_scenery_clock_waits_for_its_kind_to_come_in() -> void:
	game.active = true
	game._process(0.0)  # still deep space here
	game.set_scenery_time("orbit", 17.0)
	assert_lt(game.scenery.time, 1.0, "not for this scenery")
	game.kind = "orbit"  # ScoreSync catches up
	game._process(0.0)
	assert_almost_eq(game.scenery.time, 17.0, 0.1)
