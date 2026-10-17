extends Node
## Music autoload: loops the background track; the on/off choice persists in settings.

const TRACK := preload("res://assets/music/neu haus inst mix ab oz.mp3")
const SETTINGS_PATH := "user://settings.cfg"

signal enabled_changed(on: bool)

var enabled := true
var player := AudioStreamPlayer.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = TRACK
	add_child(player)
	load_settings()
	_apply()


func set_enabled(on: bool, path: String = SETTINGS_PATH) -> void:
	if on == enabled:
		return
	enabled = on
	_apply()
	save_settings(path)
	enabled_changed.emit(on)


func _apply() -> void:
	if enabled and not player.playing and player.is_inside_tree():
		player.play()
	elif not enabled:
		player.stop()


func save_settings(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep other sections if the file exists
	cfg.set_value("audio", "music", enabled)
	cfg.save(path)


func load_settings(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # missing file -> default on
	enabled = bool(cfg.get_value("audio", "music", true))
