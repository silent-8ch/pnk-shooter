extends GutTest
## Save and exit: a solo host can save the run from the pause menu and leave;
## CONTINUE on the title picks it up at the start of the saved stage with the
## ship as it was. The save is plain versioned JSON that newer builds can
## read, and it's cleared when the run ends.

const MainScene := preload("res://scenes/main.tscn")
const PATH := "user://test_save_game.json"

var game: Node2D
var _saved_peer: MultiplayerPeer
var _saved_path := ""


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	_saved_path = SaveGame.path
	SaveGame.path = PATH
	SaveGame.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	game.stop()
	SaveGame.clear()
	SaveGame.path = _saved_path
	multiplayer.multiplayer_peer = _saved_peer


func _start() -> Node:
	game.start()
	return game.local_player()


func _built_up_ship() -> Node:
	var me := _start()
	game.kind = "storm"
	game.stage = 3
	game.score = 4321
	game.spares = 2
	game.exp_mult = 2
	me.levels[&"reactor"] = 8
	me.levels[&"shields"] = 2
	me.levels[&"missile"] = 2
	me.levels[&"weapons"] = 4
	me.add_power(&"shields")
	me.add_power(&"shields")
	me.arm(&"missile")
	me.shield = 1
	me.exp_balance = 17
	me.exp_total = 90
	me.tail = [1, 2]
	me.hp = me.max_hp() - 10.0
	return me


func test_only_a_solo_live_run_can_be_saved() -> void:
	assert_false(game.can_save(), "no run")
	var me := _start()
	assert_true(game.can_save())
	me.hp = 0.0
	assert_false(game.can_save(), "not while down")
	me.hp = me.max_hp()
	game.over = true
	assert_false(game.can_save(), "not after game over")


func test_the_demo_cant_be_saved() -> void:
	game.start_demo()
	assert_false(game.can_save())


func test_saving_writes_the_run_and_the_ship() -> void:
	var me := _built_up_ship()
	assert_true(game.save_run())
	assert_true(SaveGame.exists())
	var st := SaveGame.read()
	assert_eq(st.kind, "storm")
	assert_eq(int(st.stage), 3)
	assert_eq(int(st.score), 4321)
	assert_eq(int(st.levels.missile), 2)
	assert_has(st.armed, "missile")
	assert_eq(int(st.version), SaveGame.VERSION)
	assert_eq(int(st.exp_balance), 17)
	assert_eq(me.exp_balance, 17, "saving leaves the ship alone")


func test_continue_picks_up_at_the_start_of_the_stage_with_the_ship() -> void:
	var before := _built_up_ship()
	var hp: float = before.hp
	game.save_run()
	game.stop()
	game.resume = SaveGame.read()
	var me := _start()
	assert_eq(game.kind, "storm")
	assert_eq(game.stage, 3)
	assert_eq(game.score, 4321)
	assert_eq(game.spares, 2)
	assert_eq(game.exp_mult, 2)
	assert_eq(game.kills, 0, "the stage from its start")
	assert_eq(game.level_time, 0.0)
	assert_eq(me.levels.get(&"missile", 0), 2)
	assert_eq(me.power_of(&"shields"), 2)
	assert_true(me.is_armed(&"missile"))
	assert_true(me.is_armed(&"lasers"))
	assert_eq(me.shield, 1)
	assert_eq(me.exp_balance, 17)
	assert_eq(me.exp_total, 90)
	assert_eq(me.tail, [1, 2])
	assert_almost_eq(me.hp, hp, 0.01)
	assert_true(game.resume.is_empty(), "used once")


func test_a_save_from_a_newer_or_older_build_still_loads() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 99, "kind": "nowhere", "stage": 2,
		"levels": {"reactor": 6, "warp_drive": 3}, "armed": ["lasers", "plasma"], "brand_new_field": true}))
	f.close()
	game.resume = SaveGame.read()
	var me := _start()
	assert_eq(game.kind, LevelKinds.FIRST, "an unknown kind falls back")
	assert_eq(game.stage, 2)
	assert_eq(me.levels.get(&"reactor", 0), 6)
	assert_false(me.levels.has(&"warp_drive"), "unknown upgrades dropped")
	assert_eq(game.spares, game.START_SPARES, "missing: a fresh run's")


func test_a_broken_save_is_ignored() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	assert_false(SaveGame.exists())
	assert_eq(SaveGame.read(), {})


func test_the_save_is_cleared_when_the_run_ends() -> void:
	_start()
	game.save_run()
	game.game_over(10, 0, ["Me"])
	assert_false(SaveGame.exists())


# --- Menus ---------------------------------------------------------------------------

func test_continue_shows_only_with_a_save() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	assert_false(main.main_menu.continue_button.visible)
	SaveGame.write({"kind": "orbit", "stage": 1})
	main.main_menu.refresh()
	assert_true(main.main_menu.continue_button.visible)
	Net.stop_browsing()


func test_save_and_exit_shows_only_when_it_can_save() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	main.game.start()
	main.set_paused(true)
	assert_true(main.pause_menu.save_exit_button.visible)
	main.set_paused(false)
	main.game.local_player().hp = 0.0
	main.set_paused(true)
	assert_false(main.pause_menu.save_exit_button.visible)
	main.game.stop()
	Net.stop_browsing()


func test_save_and_exit_saves_and_goes_to_the_title() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	main.game.start()
	main.save_and_exit()
	assert_true(SaveGame.exists())
	assert_false(main.game.active)
	assert_true(main.main_menu.visible)
	assert_true(main.main_menu.continue_button.visible)
	Net.stop_browsing()
