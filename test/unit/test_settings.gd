extends GutTest
## Settings autoload: sound effects on/off (the SFX bus), left- or right-handed
## controls, both persisted and switchable from the main and pause menus.

const MainScene := preload("res://scenes/main.tscn")
const PATH := "user://test_settings_settings.cfg"

var _saved_sfx := true
var _saved_left := true
var _saved_file := PackedByteArray()  # the real settings file, put back byte for byte
var _had_file := false


func before_all() -> void:
	_had_file = FileAccess.file_exists(Settings.SETTINGS_PATH)
	if _had_file:
		_saved_file = FileAccess.get_file_as_bytes(Settings.SETTINGS_PATH)


func after_all() -> void:
	if _had_file:
		var f := FileAccess.open(Settings.SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_saved_file)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.SETTINGS_PATH))


func before_each() -> void:
	_saved_sfx = Settings.sfx
	_saved_left = Settings.left_handed
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func after_each() -> void:
	Settings.set_sfx(_saved_sfx, PATH)
	Settings.set_left_handed(_saved_left, PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _sfx_bus() -> int:
	return AudioServer.get_bus_index(Settings.SFX_BUS)


# --- Sound effects ---------------------------------------------------------------

func test_sound_effects_go_through_the_sfx_bus() -> void:
	var p := AudioStreamPlayer.new()
	add_child_autofree(p)
	assert_eq(p.bus, Settings.SFX_BUS)


func test_scene_sounds_go_through_it_too() -> void:
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	assert_eq(game.get_node("ShootSound").bus, Settings.SFX_BUS)
	assert_eq(game.get_node("SirenSound").bus, Settings.SFX_BUS)


func test_music_stays_on_master() -> void:
	assert_eq(Music.player.bus, &"Master")
	assert_eq(Music.boss_player.bus, &"Master")


func test_sfx_off_mutes_the_bus_only() -> void:
	Settings.set_sfx(false, PATH)
	assert_true(AudioServer.is_bus_mute(_sfx_bus()))
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "music still plays")
	Settings.set_sfx(true, PATH)
	assert_false(AudioServer.is_bus_mute(_sfx_bus()))


# --- Persistence -----------------------------------------------------------------

func test_settings_persist_and_keep_other_sections() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", false)
	cfg.save(PATH)
	Settings.set_sfx(false, PATH)
	Settings.set_left_handed(false, PATH)
	Settings.sfx = true
	Settings.left_handed = true
	Settings.load_settings(PATH)
	assert_false(Settings.sfx)
	assert_false(Settings.left_handed)
	cfg.load(PATH)
	assert_eq(cfg.get_value("audio", "music"), false, "music's choice kept")


func test_defaults_without_settings() -> void:
	Settings.sfx = false
	Settings.left_handed = false
	Settings.load_settings(PATH)
	assert_true(Settings.sfx)
	assert_true(Settings.left_handed, "left-handed by default")


# --- Menus -----------------------------------------------------------------------

func test_menu_toggles_drive_settings_and_stay_in_sync() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	Settings.set_sfx(true, PATH)
	Settings.set_left_handed(true, PATH)
	var menu_sfx: CheckButton = main.main_menu.get_node("%SfxToggle")
	var pause_sfx: CheckButton = main.pause_menu.get_node("%SfxToggle")
	var menu_hand: Button = main.main_menu.get_node("%HandSide")
	var pause_hand: Button = main.pause_menu.get_node("%HandSide")
	assert_true(menu_sfx.button_pressed)
	assert_eq(menu_hand.text, "Controls on: LEFT")
	menu_sfx.button_pressed = false
	assert_false(Settings.sfx)
	assert_false(pause_sfx.button_pressed)
	pause_hand.pressed.emit()
	assert_false(Settings.left_handed, "a tap switches sides")
	assert_eq(menu_hand.text, "Controls on: RIGHT", "both menus show it")
	assert_eq(pause_hand.text, "Controls on: RIGHT")
	menu_hand.pressed.emit()
	assert_true(Settings.left_handed, "and back")
	assert_eq(pause_hand.text, "Controls on: LEFT")
	Settings.set_sfx(true, PATH)
	Settings.set_left_handed(true, PATH)
	Net.stop_browsing()


# --- Handedness ------------------------------------------------------------------

func _game() -> Node2D:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	return game


## The SHIP button sits opposite the action buttons, so handedness moves it the
## other way: left-handed controls put the bar on the left and SHIP on the right.
func test_right_handed_moves_the_ship_button_and_popups_left() -> void:
	var saved_peer := multiplayer.multiplayer_peer
	var game := _game()
	var panel: ShipPanel = game.get_node("PointerControls/ShipPanel")
	var screen := panel.get_viewport_rect().size
	Settings.set_left_handed(true, PATH)
	assert_gt(panel.tab_rect().get_center().x, screen.x / 2.0, "bar left, SHIP right")
	assert_lte(panel.tab_rect().end.x, screen.x)
	Settings.set_left_handed(false, PATH)
	assert_lt(panel.tab_rect().get_center().x, screen.x / 2.0, "bar right, SHIP left")
	assert_gte(panel.tab_rect().position.x, 0.0)
	panel.page = ShipPanel.SYSTEMS_PAGE
	assert_lt(panel.popup_rect().get_center().x, screen.x / 2.0)
	assert_gte(panel.popup_rect().position.x, 0.0)
	multiplayer.multiplayer_peer = saved_peer


func test_right_handed_lines_the_bar_up_from_the_right() -> void:
	var saved_peer := multiplayer.multiplayer_peer
	var game := _game()
	var bar: ActionBar = game.get_node("PointerControls/ActionBar")
	bar.set_shown(&"missile", true)
	var screen := bar.get_viewport_rect().size
	Settings.set_left_handed(true, PATH)
	assert_lt(bar.button_rect(0).position.x, bar.button_rect(1).position.x, "LASERS leftmost")
	Settings.set_left_handed(false, PATH)
	var lasers := bar.button_rect(0)
	var missile := bar.button_rect(1)
	assert_gt(lasers.position.x, missile.end.x, "LASERS rightmost")
	assert_almost_eq(lasers.end.x, screen.x - ActionBar.MARGIN, 0.01)
	assert_eq(bar.action_for_key(KEY_1), &"lasers", "key 1 is still LASERS")
	multiplayer.multiplayer_peer = saved_peer


# --- Settings menus ------------------------------------------------------------------

func test_settings_live_in_a_small_settings_menu_and_play_stands_out() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	for menu in [main.main_menu, main.pause_menu]:
		var box: Control = menu.get_node("%SettingsBox")
		assert_false(box.visible, "tucked away")
		assert_true(box.is_ancestor_of(menu.get_node("%MusicToggle")))
		assert_true(box.is_ancestor_of(menu.get_node("%SfxToggle")))
		assert_true(box.is_ancestor_of(menu.get_node("%HandSide")))
		var settings: Button = menu.get_node("%SettingsButton")
		menu.show_settings(false)
		settings.pressed.emit()
		assert_true(box.visible)
		assert_false(menu.get_node("%MainButtons").visible, "in place of the main buttons")
		menu.get_node("%BackButton").pressed.emit()
		assert_false(box.visible)
		assert_true(menu.get_node("%MainButtons").visible)
	var play: Button = main.main_menu.get_node("%PlayButton")
	var settings_button: Button = main.main_menu.get_node("%SettingsButton")
	assert_gt(play.custom_minimum_size.y, settings_button.custom_minimum_size.y * 2.0, "Play is the big one")
	assert_gt(play.get_theme_font_size("font_size"), settings_button.get_theme_font_size("font_size") * 2)
	var resume: Button = main.pause_menu.get_node("%ResumeButton")
	assert_gt(resume.custom_minimum_size.y, main.pause_menu.get_node("%SettingsButton").custom_minimum_size.y * 2.0)
	Net.stop_browsing()


func test_settings_close_when_the_menu_is_shown_again() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	main.main_menu.show_settings(true)
	main.main_menu.visible = false
	main.main_menu.visible = true
	assert_false(main.main_menu.get_node("%SettingsBox").visible)
	Net.stop_browsing()


# --- Name ----------------------------------------------------------------------------

func test_the_lobby_remembers_your_name() -> void:
	Settings.set_player_name("", PATH)
	Settings.set_player_name("Paul", PATH)
	Settings.player_name = ""
	Settings.load_settings(PATH)
	assert_eq(Settings.player_name, "Paul")
	var lobby: Node = preload("res://scenes/lobby.tscn").instantiate()
	add_child_autofree(lobby)
	assert_eq(lobby.name_edit.text, "Paul", "filled in next time")
	Settings.player_name = ""
