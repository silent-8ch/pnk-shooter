extends GutTest
## Music autoload: looping background track, on/off toggle persisted in settings, menu toggles.

const MainScene := preload("res://scenes/main.tscn")
const PATH := "user://test_music_settings.cfg"

var _saved := true


func before_each() -> void:
	_saved = Music.enabled
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func after_each() -> void:
	Music.set_enabled(_saved, PATH)
	Music.enabled = _saved
	Music._apply()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_track_loops() -> void:
	assert_true(Music.player.stream is AudioStreamMP3)
	assert_true(Music.player.stream.loop)


func test_plays_when_enabled_and_stops_when_disabled() -> void:
	Music.set_enabled(true, PATH)
	assert_true(Music.player.playing)
	Music.set_enabled(false, PATH)
	assert_false(Music.player.playing)
	Music.set_enabled(true, PATH)
	assert_true(Music.player.playing)


func test_setting_persists_and_keeps_other_sections() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "ship", 1)
	cfg.save(PATH)
	Music.set_enabled(true, PATH)
	Music.set_enabled(false, PATH)
	Music.enabled = true
	Music.load_settings(PATH)
	assert_false(Music.enabled)
	cfg.load(PATH)
	assert_eq(cfg.get_value("player", "ship"), 1)


func test_defaults_to_on_without_settings() -> void:
	Music.enabled = false
	Music.load_settings(PATH)
	assert_true(Music.enabled)


func test_menu_toggles_drive_music_and_stay_in_sync() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	var menu_toggle: CheckButton = main.main_menu.get_node("%MusicToggle")
	var pause_toggle: CheckButton = main.pause_menu.get_node("%MusicToggle")
	assert_eq(menu_toggle.button_pressed, Music.enabled)
	Music.set_enabled(true, PATH)
	menu_toggle.button_pressed = false
	assert_false(Music.enabled)
	assert_false(pause_toggle.button_pressed)
	pause_toggle.button_pressed = true
	assert_true(Music.enabled)
	assert_true(menu_toggle.button_pressed)
	Net.stop_browsing()
