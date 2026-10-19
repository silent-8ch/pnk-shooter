extends GutTest
## Music autoload: looping background track, on/off toggle persisted in settings, menu toggles,
## the boss track crossfading in while a boss is up, and the fanfare (with
## reverb) in the break after the mini boss or a boss.

const MainScene := preload("res://scenes/main.tscn")
const PATH := "user://test_music_settings.cfg"

var _saved := true
var _saved_file := PackedByteArray()  # the real settings file, put back byte for byte
var _had_file := false


func before_all() -> void:
	_had_file = FileAccess.file_exists(Music.SETTINGS_PATH)
	if _had_file:
		_saved_file = FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)


func after_all() -> void:
	if _had_file:
		var f := FileAccess.open(Music.SETTINGS_PATH, FileAccess.WRITE)
		f.store_buffer(_saved_file)
		f.close()


func before_each() -> void:
	_saved = Music.enabled
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func after_each() -> void:
	Music.set_boss(false)
	Music.set_fanfare(false)
	Music.mix = 0.0
	Music.fanfare_mix = 0.0
	Music.boss_player.stop()
	Music.fanfare_player.stop()
	Music.set_level(Music.TRACK)
	Music.player.stream_paused = false
	Music._set_volumes()
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


func _fade(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		Music._process(0.05)
		t += 0.05


func test_boss_track_loops() -> void:
	assert_true(Music.boss_player.stream is AudioStreamMP3)
	assert_true(Music.boss_player.stream.loop)
	assert_ne(Music.boss_player.stream, Music.player.stream)


func test_boss_crossfades_in_and_holds_the_main_track_place() -> void:
	Music.set_enabled(true, PATH)
	Music.set_boss(true)
	assert_true(Music.boss_player.playing, "starts at once")
	_fade(Music.FADE / 2.0)
	assert_almost_eq(Music.mix, 0.5, 0.05, "halfway through the crossfade")
	assert_true(Music.player.playing, "both play while fading")
	assert_almost_eq(Music.player.volume_db, Music.boss_player.volume_db, 0.6, "about even")
	_fade(Music.FADE)
	assert_eq(Music.mix, 1.0)
	assert_true(Music.player.stream_paused, "main track paused, not stopped")


func test_boss_gone_crossfades_back() -> void:
	Music.set_enabled(true, PATH)
	Music.set_boss(true)
	_fade(Music.FADE + 0.1)
	Music.set_boss(false)
	assert_false(Music.player.stream_paused, "picks up where it left off")
	_fade(Music.FADE + 0.1)
	assert_eq(Music.mix, 0.0)
	assert_false(Music.boss_player.playing)
	assert_true(Music.player.playing)


func test_music_off_keeps_the_boss_track_quiet() -> void:
	Music.set_enabled(false, PATH)
	Music.set_boss(true)
	assert_false(Music.boss_player.playing)
	Music.set_enabled(true, PATH)
	assert_true(Music.boss_player.playing, "comes in when music is turned back on mid-fight")


func test_game_drives_the_boss_track() -> void:
	var saved_peer := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game._process(0.016)
	assert_false(Music.boss, "no boss yet")
	game.spawn_enemy({"x": 270.0, "y": -100.0, "type": preload("res://scripts/enemy.gd").BOSS, "id": 1, "stage": 0})
	game._process(0.016)
	assert_true(Music.boss)
	game.stop()
	assert_false(Music.boss, "leaving the game ends it")
	multiplayer.multiplayer_peer = saved_peer


# --- Fanfare -----------------------------------------------------------------------

func test_fanfare_loops_through_a_reverb_bus() -> void:
	assert_true(Music.fanfare_player.stream is AudioStreamWAV)
	assert_eq(Music.fanfare_player.stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(Music.fanfare_player.bus, Music.FANFARE_BUS)
	var bus := AudioServer.get_bus_index(Music.FANFARE_BUS)
	assert_gte(bus, 0)
	assert_eq(AudioServer.get_bus_send(bus), &"Master", "not muted with the sound effects")
	assert_true(AudioServer.get_bus_effect(bus, 0) is AudioEffectChorus)
	assert_true(AudioServer.get_bus_effect(bus, 1) is AudioEffectReverb)


func test_fanfare_crossfades_in_and_back() -> void:
	Music.set_enabled(true, PATH)
	Music.set_fanfare(true)
	assert_true(Music.fanfare_player.playing, "starts at once")
	_fade(Music.FADE + 0.1)
	assert_eq(Music.fanfare_mix, 1.0)
	assert_true(Music.player.stream_paused, "main track holds its place")
	Music.set_fanfare(false)
	assert_false(Music.player.stream_paused)
	_fade(Music.FADE + 0.1)
	assert_eq(Music.fanfare_mix, 0.0)
	assert_false(Music.fanfare_player.playing)
	assert_true(Music.player.playing)


func test_boss_track_fades_out_as_the_fanfare_comes_in() -> void:
	Music.set_enabled(true, PATH)
	Music.set_boss(true)
	_fade(Music.FADE + 0.1)
	Music.set_boss(false)
	Music.set_fanfare(true)
	_fade(Music.FADE + 0.1)
	assert_false(Music.boss_player.playing)
	assert_lte(Music.player.volume_db, Music.SILENT_DB, "the main track stays quiet")
	assert_almost_eq(Music.fanfare_player.volume_db, 0.0, 0.01)


func test_music_off_keeps_the_fanfare_quiet() -> void:
	Music.set_enabled(false, PATH)
	Music.set_fanfare(true)
	assert_false(Music.fanfare_player.playing)
	Music.set_enabled(true, PATH)
	assert_true(Music.fanfare_player.playing)


func test_game_plays_the_fanfare_in_the_breaks() -> void:
	var saved_peer := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.level = null
	game.spawn_elite()
	game.destroy_enemy(game.get_node("Enemies").get_children().back(), true)
	game._process(0.016)
	assert_true(Music.fanfare, "the refit after the mini boss")
	game.set_refit_ready(true)
	game._process(0.016)
	assert_false(Music.fanfare, "back to the fight")
	game.spawn_boss()
	game.destroy_enemy(game.get_node("Enemies").get_children().back(), true)
	game._process(0.016)
	assert_true(Music.fanfare, "the refit after the boss")
	game.set_refit_ready(true)
	game._process(0.016)
	assert_true(game.fork_open())
	assert_true(Music.fanfare, "and the fork")
	game.choose_fork(0)
	game._process(0.016)
	assert_false(Music.fanfare, "the next stage")
	game.stop()
	multiplayer.multiplayer_peer = saved_peer


# --- Level and mini boss tracks ----------------------------------------------------

func test_every_level_kind_has_its_own_looping_track() -> void:
	var seen := {}
	for k in LevelKinds.KINDS:
		var path := LevelKinds.music_of(k)
		assert_true(ResourceLoader.exists(path), path)
		var track: AudioStream = load(path)
		assert_true(track is AudioStreamMP3 and track.loop, path)
		assert_false(seen.has(path), "%s shares %s" % [k, path])
		seen[path] = true
	assert_eq(LevelKinds.music_of(LevelKinds.FIRST), Music.TRACK.resource_path)
	assert_eq(LevelKinds.music_of("asteroid_belt"), "res://assets/music/asteroid b inst mix ab oz.mp3")


func test_a_new_level_track_starts_from_the_top() -> void:
	Music.set_enabled(true, PATH)
	var storm: AudioStream = load(LevelKinds.music_of("storm"))
	Music.set_level(storm)
	assert_eq(Music.player.stream, storm)
	assert_true(Music.player.playing)


func test_a_new_level_track_waits_out_the_fanfare() -> void:
	Music.set_enabled(true, PATH)
	Music.set_fanfare(true)
	_fade(Music.FADE + 0.1)
	var storm: AudioStream = load(LevelKinds.music_of("storm"))
	Music.set_level(storm)
	assert_false(Music.player.playing, "quiet under the fanfare")
	Music.set_fanfare(false)
	assert_true(Music.player.playing)
	assert_eq(Music.player.stream, storm)


func test_mini_boss_has_its_own_track() -> void:
	Music.set_enabled(true, PATH)
	Music.set_boss(true, Music.MINI_BOSS_TRACK)
	assert_eq(Music.boss_player.stream, Music.MINI_BOSS_TRACK)
	assert_true(Music.boss_player.playing)
	assert_true(Music.MINI_BOSS_TRACK.loop)
	Music.set_boss(true, Music.BOSS_TRACK)
	assert_eq(Music.boss_player.stream, Music.BOSS_TRACK, "the boss's takes over")
	assert_true(Music.boss_player.playing)


func test_game_plays_the_kind_and_mini_boss_tracks() -> void:
	var saved_peer := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.level = null
	game.kind = "asteroid_belt"
	game._process(0.016)
	assert_eq(Music.player.stream.resource_path, LevelKinds.music_of("asteroid_belt"))
	game.spawn_elite()
	game._process(0.016)
	assert_true(Music.boss)
	assert_eq(Music.boss_player.stream, Music.MINI_BOSS_TRACK)
	game.stop()
	assert_false(Music.boss)
	assert_eq(Music.player.stream, Music.TRACK, "back to the menu's")
	multiplayer.multiplayer_peer = saved_peer



func test_fanfare_cuts_in_fast_so_the_opening_hits() -> void:
	Music.set_enabled(true, PATH)
	Music.set_fanfare(true)
	_fade(Music.FANFARE_IN + 0.06)
	assert_eq(Music.fanfare_mix, 1.0)
	assert_lt(Music.FANFARE_IN, Music.FADE)


func test_chorus_on_the_opening_then_off() -> void:
	assert_eq(Music.chorus_wet(0.0), Music.CHORUS_WET)
	assert_eq(Music.chorus_wet(Music.CHORUS_TIME - 0.1), Music.CHORUS_WET)
	assert_eq(Music.chorus_wet(Music.CHORUS_TIME + Music.CHORUS_OUT + 0.1), 0.0)
	Music.set_enabled(true, PATH)
	Music.set_fanfare(true)
	assert_eq(Music.fanfare_time, 0.0, "from the top each break")


func test_mastered_fanfare_starts_without_silence() -> void:
	var w: AudioStreamWAV = Music.FANFARE_TRACK
	assert_true(w.resource_path.ends_with("k620-fanfare.wav"))
