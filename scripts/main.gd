extends Node
## Root node: screen flow (menu -> ship select -> lobby -> game), pause menu,
## and input actions.

@onready var game: Node2D = $Game
@onready var main_menu: CanvasLayer = $MainMenu
@onready var ship_select: CanvasLayer = $ShipSelect
@onready var lobby: CanvasLayer = $Lobby
@onready var pause_menu: CanvasLayer = $PauseMenu


func _ready() -> void:
	_setup_input_map()
	Net.game_started.connect(_on_game_started)
	Net.disconnected.connect(_on_disconnected)
	main_menu.play_pressed.connect(show_screen.bind(ship_select))
	main_menu.quit_pressed.connect(quit)
	ship_select.ship_chosen.connect(func(_i: int) -> void: show_screen(lobby))
	ship_select.back_pressed.connect(show_screen.bind(main_menu))
	lobby.back_pressed.connect(show_screen.bind(ship_select))
	pause_menu.resume_pressed.connect(set_paused.bind(false))
	pause_menu.leave_pressed.connect(leave_game)
	pause_menu.quit_pressed.connect(quit)
	show_screen(main_menu)
	_handle_cmdline()


## Shows one pre-game screen and hides the others. Pass null for none (in game).
func show_screen(screen: CanvasLayer) -> void:
	for s in [main_menu, ship_select, lobby]:
		s.visible = s == screen


func is_paused() -> bool:
	return pause_menu.visible


func set_paused(paused: bool) -> void:
	if paused and not game.active:
		return
	pause_menu.visible = paused
	game.input_enabled = not paused


func toggle_pause() -> void:
	set_paused(not is_paused())


func leave_game() -> void:
	set_paused(false)
	Net.leave()
	game.stop()
	show_screen(main_menu)


func quit() -> void:
	Net.leave()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and game.active:
		toggle_pause()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:  # Android back button
		if game.active:
			toggle_pause()
		elif lobby.visible:
			show_screen(ship_select)
		elif ship_select.visible:
			show_screen(main_menu)


func _on_game_started() -> void:
	show_screen(null)
	set_paused(false)
	game.start()


func _on_disconnected() -> void:
	set_paused(false)
	game.stop()
	show_screen(lobby)
	lobby.set_status("Disconnected from host")


## Allows `godot -- --host` or `godot -- --join=192.168.1.5` for quick testing.
func _handle_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			Net.host("Host")
		elif arg.begins_with("--join="):
			Net.join(arg.trim_prefix("--join="), "Client")


func _setup_input_map() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("fire", [KEY_SPACE, KEY_Z])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
