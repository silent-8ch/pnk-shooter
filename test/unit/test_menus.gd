extends GutTest
## Screen flow: main menu -> ship select -> lobby, back buttons, pause menu.

const MainScene := preload("res://scenes/main.tscn")

var main: Node
var _saved_ship := 0


func before_each() -> void:
	_saved_ship = Ships.selected
	main = MainScene.instantiate()
	add_child_autofree(main)
	# Don't actually quit the test runner.
	main.main_menu.quit_pressed.disconnect(main.quit)
	main.pause_menu.quit_pressed.disconnect(main.quit)


func after_each() -> void:
	Ships.selected = _saved_ship
	Ships.save_selection()
	Net.stop_browsing()


func _visible_screens() -> Array:
	return [main.main_menu, main.ship_select, main.lobby].filter(func(s): return s.visible)


func test_starts_on_main_menu_only() -> void:
	assert_eq(_visible_screens(), [main.main_menu])
	assert_false(main.pause_menu.visible)


func test_play_goes_to_ship_select() -> void:
	main.main_menu.get_node("%PlayButton").pressed.emit()
	assert_eq(_visible_screens(), [main.ship_select])


func test_confirm_ship_goes_to_lobby() -> void:
	main.show_screen(main.ship_select)
	main.ship_select.get_node("%ConfirmButton").pressed.emit()
	assert_eq(_visible_screens(), [main.lobby])


func test_back_buttons_walk_back_to_menu() -> void:
	main.show_screen(main.lobby)
	main.lobby.get_node("%BackButton").pressed.emit()
	assert_eq(_visible_screens(), [main.ship_select])
	main.ship_select.get_node("%BackButton").pressed.emit()
	assert_eq(_visible_screens(), [main.main_menu])


func test_menu_quit_button_emits() -> void:
	watch_signals(main.main_menu)
	main.main_menu.get_node("%QuitButton").pressed.emit()
	assert_signal_emitted(main.main_menu, "quit_pressed")


func test_lobby_browsing_follows_visibility() -> void:
	main.show_screen(main.lobby)
	assert_not_null(Net._browser)
	main.show_screen(main.main_menu)
	assert_null(Net._browser)


func test_cannot_pause_outside_game() -> void:
	main.set_paused(true)
	assert_false(main.is_paused())


func test_pause_blocks_input_and_resume_restores() -> void:
	main.game.active = true
	main.set_paused(true)
	assert_true(main.is_paused())
	assert_false(main.game.input_enabled)
	main.pause_menu.get_node("%ResumeButton").pressed.emit()
	assert_false(main.is_paused())
	assert_true(main.game.input_enabled)


func test_escape_toggles_pause_in_game() -> void:
	main.game.active = true
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	main._unhandled_input(ev)
	assert_true(main.is_paused())
	main._unhandled_input(ev)
	assert_false(main.is_paused())


func test_leave_game_returns_to_menu() -> void:
	main.game.active = true
	main.show_screen(null)
	main.set_paused(true)
	main.pause_menu.get_node("%LeaveButton").pressed.emit()
	assert_false(main.game.active)
	assert_false(main.is_paused())
	assert_true(main.game.input_enabled)
	assert_eq(_visible_screens(), [main.main_menu])
	assert_null(multiplayer.multiplayer_peer if multiplayer.multiplayer_peer is ENetMultiplayerPeer else null)


func test_android_back_walks_screens_and_pauses() -> void:
	main.show_screen(main.lobby)
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(_visible_screens(), [main.ship_select])
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(_visible_screens(), [main.main_menu])
	main.game.active = true
	main.show_screen(null)
	main._notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_true(main.is_paused())


func test_host_leaving_mid_game_keeps_playing() -> void:
	var saved := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	main.game.start()
	main.show_screen(null)
	main._on_disconnected(1)
	assert_true(main.game.active, "game keeps running")
	assert_eq(_visible_screens(), [], "no menu pops up")
	main.game.stop()
	multiplayer.multiplayer_peer = saved


func test_host_leaving_outside_a_game_returns_to_lobby() -> void:
	main.show_screen(main.lobby)
	main._on_disconnected(5)
	assert_eq(_visible_screens(), [main.lobby])
