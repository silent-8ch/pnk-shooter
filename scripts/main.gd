extends Node
## Root node: screen flow (menu -> ship select -> lobby -> game) and pause menu.
## Left idle on the title screen for DEMO_IDLE s, it plays the demo
## (Game.start_demo, offline); any tap, click or key ends it, back to the title.

const DEMO_IDLE := 15.0  # s

var _idle := 0.0

@onready var game: Node2D = $Game
@onready var main_menu: CanvasLayer = $MainMenu
@onready var ship_select: CanvasLayer = $ShipSelect
@onready var lobby: CanvasLayer = $Lobby
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var ready_screen: CanvasLayer = $ReadyScreen


func _ready() -> void:
	Net.game_started.connect(_on_game_started)
	Net.disconnected.connect(_on_disconnected)
	main_menu.play_pressed.connect(show_screen.bind(ship_select))
	main_menu.continue_pressed.connect(continue_run)
	pause_menu.save_exit_pressed.connect(save_and_exit)
	main_menu.quit_pressed.connect(quit)
	ship_select.ship_chosen.connect(func(_i: int) -> void: show_screen(lobby))
	ship_select.back_pressed.connect(show_screen.bind(main_menu))
	lobby.back_pressed.connect(show_screen.bind(ship_select))
	pause_menu.resume_pressed.connect(set_paused.bind(false))
	pause_menu.leave_pressed.connect(leave_game)
	pause_menu.quit_pressed.connect(quit)
	game.run_ended.connect(_on_run_ended)
	game.run_started.connect(func() -> void: ready_screen.visible = false)
	game.ready_changed.connect(ready_screen.show_players)
	game.waiting_for_run.connect(func() -> void:
		set_paused(false)
		ready_screen.open(game.last_results))
	ready_screen.ready_toggled.connect(func(on: bool) -> void:
		if multiplayer.multiplayer_peer != null:
			game.set_ready.rpc_id(1, on))
	ready_screen.leave_pressed.connect(leave_game)
	show_screen(main_menu)
	_handle_cmdline()


## Shows one pre-game screen and hides the others. Pass null for none (in game).
func show_screen(screen: CanvasLayer) -> void:
	for s in [main_menu, ship_select, lobby]:
		s.visible = s == screen
	if screen == main_menu:
		main_menu.refresh()  # CONTINUE, if there's a saved run


func is_paused() -> bool:
	return pause_menu.visible


func set_paused(paused: bool) -> void:
	if paused and (not game.active or game.over):
		return
	pause_menu.save_exit_button.visible = game.can_save()
	pause_menu.visible = paused
	game.input_enabled = not paused


func toggle_pause() -> void:
	set_paused(not is_paused())


func leave_game() -> void:
	set_paused(false)
	ready_screen.visible = false
	Net.leave()
	game.stop()
	show_screen(main_menu)


## Saves the solo run (Game.save_run) and leaves to the title.
func save_and_exit() -> void:
	if game.save_run():
		leave_game()


## The saved run, solo: hosts as it did and picks up at the start of its stage.
func continue_run() -> void:
	var st := SaveGame.read()
	if st.is_empty():
		main_menu.refresh()
		return
	Net.player_name = str(st.get("name", Net.player_name)).left(12)
	game.resume = st
	Net.host(Net.player_name)


func quit() -> void:
	Net.leave()
	get_tree().quit()


func _process(delta: float) -> void:
	if main_menu.visible and not game.active:
		_idle += delta
		if _idle >= DEMO_IDLE:
			start_demo()
	else:
		_idle = 0.0


func _input(event: InputEvent) -> void:
	if game.demo:
		if _is_press(event):
			get_viewport().set_input_as_handled()
			end_demo()
	elif main_menu.visible:
		_idle = 0.0


static func _is_press(event: InputEvent) -> bool:
	return (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch
		or event is InputEventJoypadButton) and event.is_pressed()


func start_demo() -> void:
	_idle = 0.0
	show_screen(null)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game.start_demo()


func end_demo() -> void:
	game.stop()
	multiplayer.multiplayer_peer = null
	show_screen(main_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and game.active:
		toggle_pause()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:  # Android back button
		if game.active:
			toggle_pause()
		elif ready_screen.visible:
			leave_game()
		elif lobby.visible:
			show_screen(ship_select)
		elif ship_select.visible:
			show_screen(main_menu)


func _on_game_started() -> void:
	show_screen(null)
	set_paused(false)
	game.start()


## The results of a finished run were up long enough: everyone goes to the
## ready screen; the next run starts when they're all ready (Game.set_ready).
func _on_run_ended() -> void:
	set_paused(false)
	game.stop()
	ready_screen.open(game.last_results)
	game.open_ready()


## The host left. In a game, keep playing solo; otherwise back to the lobby.
func _on_disconnected(old_id: int) -> void:
	if game.active:
		game.continue_solo(old_id)
		return
	Net.leave()
	set_paused(false)
	ready_screen.visible = false
	game.stop()
	show_screen(lobby)
	lobby.set_status("Disconnected from host")


## Allows `godot -- --host` or `godot -- --join=192.168.1.5` for quick testing,
## and `--kind=<id>` to start the run in one kind of level (LevelKinds) instead
## of flying to it through the forks. Read before --host, whatever the order.
func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--kind="):
			Net.start_kind = arg.trim_prefix("--kind=")
	for arg in args:
		if arg == "--host":
			Net.host("Host")
		elif arg.begins_with("--join="):
			Net.join(arg.trim_prefix("--join="), "Client")
