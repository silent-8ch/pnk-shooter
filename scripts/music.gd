extends Node
## Music autoload: loops the background track, the level kind's own
## (set_level, LevelKinds.music_of); the on/off choice persists in settings.
## While a boss or the mini boss is up (set_boss), its track takes over: the two crossfade
## over FADE s, the background track pausing once it's silent so it picks up
## where it left off, and the boss track starting from the top each fight.
## In the break after the mini boss or a boss (set_fanfare: the refit, and
## after a boss the fork) the fanfare
## takes over from the top, cutting in fast (FANFARE_IN s) so its opening
## hits, through the Fanfare bus's big reverb so it sounds grand, with a
## chorus thickening the first CHORUS_TIME s. The track is mastered louder
## with its lead-in silence trimmed (tools/master_fanfare.py).

const TRACK := preload("res://assets/music/neu haus inst mix ab oz.mp3")
const BOSS_TRACK := preload("res://assets/music/meter inst mix ab oz 2nd.mp3")
const MINI_BOSS_TRACK := preload("res://assets/music/desperate joy ab oz.mp3")
const FANFARE_TRACK := preload("res://assets/music/k620-fanfare.wav")
const FANFARE_IN := 0.25  # s for the fanfare to cut in
const CHORUS_TIME := 6.0  # s of chorus on the fanfare's opening
const CHORUS_OUT := 1.5  # s for the chorus to fade off after
const CHORUS_WET := 0.6
const FANFARE_BUS := &"Fanfare"
const FADE := 1.5  # s to crossfade between the tracks
const SILENT_DB := -60.0
const SETTINGS_PATH := "user://settings.cfg"

signal enabled_changed(on: bool)

var enabled := true
var player := AudioStreamPlayer.new()
var boss_player := AudioStreamPlayer.new()
var boss := false  # a boss is up: the boss track is (fading) in
var mix := 0.0  # 0 = background track only, 1 = boss track only
var fanfare_player := AudioStreamPlayer.new()
var fanfare := false  # the break after a boss: the fanfare is (fading) in
var fanfare_mix := 0.0  # 1 = fanfare only, over whatever mix says
var fanfare_time := 0.0  # s since the fanfare last started
var chorus: AudioEffectChorus


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = TRACK
	add_child(player)
	boss_player.stream = BOSS_TRACK
	add_child(boss_player)
	_add_fanfare_bus()
	fanfare_player.stream = FANFARE_TRACK
	fanfare_player.bus = FANFARE_BUS
	add_child(fanfare_player)
	load_settings()
	_apply()


## A large hall: long tail, a little pre-delay, the low end kept dry.
func _add_fanfare_bus() -> void:
	if AudioServer.get_bus_index(FANFARE_BUS) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, FANFARE_BUS)
	AudioServer.set_bus_send(i, &"Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.85
	reverb.damping = 0.35
	reverb.spread = 1.0
	reverb.predelay_msec = 60.0
	reverb.predelay_feedback = 0.3
	reverb.hipass = 0.15
	reverb.dry = 0.85
	reverb.wet = 0.45
	chorus = AudioEffectChorus.new()
	chorus.wet = CHORUS_WET
	chorus.dry = 1.0
	AudioServer.add_bus_effect(i, chorus, 0)  # chorus first, then the hall
	AudioServer.add_bus_effect(i, reverb)


func set_enabled(on: bool, path: String = SETTINGS_PATH) -> void:
	if on == enabled:
		return
	enabled = on
	_apply()
	save_settings(path)
	enabled_changed.emit(on)


func _apply() -> void:
	if enabled and player.is_inside_tree():
		if not player.playing and mix < 1.0 and fanfare_mix < 1.0:
			player.play()
		if boss and not boss_player.playing:
			boss_player.play()
		if fanfare and not fanfare_player.playing:
			fanfare_player.play()
		_set_volumes()
	elif not enabled:
		player.stop()
		boss_player.stop()
		fanfare_player.stop()


## The background track: a new one starts from the top; while it can't be
## heard (a boss's or the fanfare's) it waits to come in when they fade out.
func set_level(track: AudioStream) -> void:
	if track == null or track == player.stream:
		return
	player.stop()
	player.stream_paused = false
	player.stream = track
	if enabled and player.is_inside_tree() and mix < 1.0 and fanfare_mix < 1.0:
		player.play()


## A boss came in (true) or went (false): crossfade to its track (`track`,
## the mini boss's or a boss's) or back. A different track while one is up
## starts over.
func set_boss(on: bool, track: AudioStream = BOSS_TRACK) -> void:
	if on and boss and track != boss_player.stream:
		boss_player.stream = track
		if enabled:
			boss_player.play()
		return
	if on == boss:
		return
	boss = on
	if on:
		boss_player.stream = track
	if not enabled:
		mix = 1.0 if on else 0.0
		return
	if on:
		boss_player.play()  # from the top, each fight
	else:
		player.stream_paused = false
		if not player.playing:
			player.play()
	_set_volumes()


## The break after a boss started (true) or ended (false): crossfade to the
## fanfare or back to the background track.
func set_fanfare(on: bool) -> void:
	if on == fanfare:
		return
	fanfare = on
	if not enabled:
		fanfare_mix = 1.0 if on else 0.0
		return
	if on:
		fanfare_player.play()  # from the top, each break
		fanfare_time = 0.0
	else:
		player.stream_paused = false
		if not player.playing:
			player.play()
	_set_volumes()


## The chorus on the opening: full for CHORUS_TIME s, then fading off.
func chorus_wet(time: float) -> float:
	return CHORUS_WET * (1.0 - clampf((time - CHORUS_TIME) / CHORUS_OUT, 0.0, 1.0))


func _process(delta: float) -> void:
	fanfare_time += delta
	if chorus:
		chorus.wet = chorus_wet(fanfare_time)
	var target := 1.0 if boss else 0.0
	var fanfare_target := 1.0 if fanfare else 0.0
	if mix == target and fanfare_mix == fanfare_target:
		return
	mix = move_toward(mix, target, delta / FADE)
	fanfare_mix = move_toward(fanfare_mix, fanfare_target, delta / (FANFARE_IN if fanfare else FADE))
	_set_volumes()
	if not enabled:
		return
	if mix >= 1.0 or fanfare_mix >= 1.0:
		player.stream_paused = true  # silent: hold its place for later
	if mix <= 0.0:
		boss_player.stop()
	if fanfare_mix <= 0.0:
		fanfare_player.stop()


func _set_volumes() -> void:
	var rest := 1.0 - fanfare_mix
	_set_volume(player, (1.0 - mix) * rest)
	_set_volume(boss_player, mix * rest)
	_set_volume(fanfare_player, fanfare_mix)


func _set_volume(p: AudioStreamPlayer, level: float) -> void:
	p.volume_db = linear_to_db(level) if level > 0.0 else SILENT_DB


func save_settings(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep other sections if the file exists
	cfg.set_value("audio", "music", enabled)
	cfg.save(path)


func load_settings(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # missing file -> default on
	enabled = bool(cfg.get_value("audio", "music", true))
