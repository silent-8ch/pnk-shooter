extends Node
## Root node: screen flow (menu -> ship select -> lobby -> game) and pause menu.

@onready var game: Node2D = $Game
@onready var main_menu: CanvasLayer = $MainMenu
@onready var ship_select: CanvasLayer = $ShipSelect
@onready var lobby: CanvasLayer = $Lobby
@onready var pause_menu: CanvasLayer = $PauseMenu


func _ready() -> void:
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
	game.run_ended.connect(_on_run_ended)
	show_screen(main_menu)
	_handle_cmdline()


## Shows one pre-game screen and hides the others. Pass null for none (in game).
func show_screen(screen: CanvasLayer) -> void:
	for s in [main_menu, ship_select, lobby]:
		s.visible = s == screen


func is_paused() -> bool:
	return pause_menu.visible


func set_paused(paused: bool) -> void:
	if paused and (not game.active or game.over):
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


## The results of a finished run were up long enough: the host starts the next
## run for everyone still connected (fresh ships, spares and score).
func _on_run_ended() -> void:
	set_paused(false)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		game.restart_run.rpc()


## The host left. In a game, keep playing solo; otherwise back to the lobby.
func _on_disconnected(old_id: int) -> void:
	if game.active:
		game.continue_solo(old_id)
		return
	Net.leave()
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
