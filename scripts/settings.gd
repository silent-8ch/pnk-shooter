extends Node
## Settings autoload: sound effects on/off and which hand the controls are
## laid out for, kept in the same settings file as Music's choice.
## Sound effects: every AudioStreamPlayer that joins the tree on the Master bus
## (anything but the music) is moved to the SFX bus, which this mutes.
## Handedness: left-handed (the default) puts the SHIP pill and its popups
## bottom left and the action buttons from the left edge, LASERS first;
## right-handed mirrors both (ShipPanel, ActionBar).

const SETTINGS_PATH := "user://settings.cfg"
const SFX_BUS := &"SFX"

signal sfx_changed(on: bool)
signal handed_changed(left: bool)

var sfx := true
var left_handed := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(SFX_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, SFX_BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
	get_tree().node_added.connect(_on_node_added)
	load_settings()
	_apply()


func set_sfx(on: bool, path: String = SETTINGS_PATH) -> void:
	if on == sfx:
		return
	sfx = on
	_apply()
	save_settings(path)
	sfx_changed.emit(on)


## The menus' switch: which side the controls are on (tap to swap).
static func side_text(left: bool) -> String:
	return "Controls on: %s" % ("LEFT" if left else "RIGHT")


func set_left_handed(left: bool, path: String = SETTINGS_PATH) -> void:
	if left == left_handed:
		return
	left_handed = left
	save_settings(path)
	handed_changed.emit(left)


func _apply() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SFX_BUS), not sfx)


## Sound effects go through the SFX bus; the music stays on Master.
func _on_node_added(node: Node) -> void:
	if (node is AudioStreamPlayer or node is AudioStreamPlayer2D) and node.bus == &"Master" \
			and not Music.is_ancestor_of(node):
		node.bus = SFX_BUS


func save_settings(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep other sections if the file exists
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("controls", "left_handed", left_handed)
	cfg.save(path)


func load_settings(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # missing file -> defaults
	sfx = bool(cfg.get_value("audio", "sfx", true))
	left_handed = bool(cfg.get_value("controls", "left_handed", true))
