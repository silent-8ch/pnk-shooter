extends CanvasLayer
## Host / join UI with a live list of games found on the local network.

signal back_pressed

@onready var name_edit: LineEdit = %NameEdit
@onready var host_button: Button = %HostButton
@onready var server_list: ItemList = %ServerList
@onready var ip_edit: LineEdit = %IPEdit
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var back_button: Button = %BackButton
@onready var buddy_toggle: CheckButton = %BuddyToggle
@onready var pilot_toggle: CheckButton = %PilotToggle
@onready var high_scores_label: Label = %HighScoresLabel

const HIGH_SCORES_SHOWN := 5

var _servers: Array = []


func _ready() -> void:
	name_edit.text = "Player%d" % (randi() % 900 + 100)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(back_pressed.emit)
	buddy_toggle.set_pressed_no_signal(Net.ai_buddy)
	buddy_toggle.toggled.connect(func(on: bool) -> void: Net.ai_buddy = on)
	pilot_toggle.set_pressed_no_signal(Net.ai_pilot)
	pilot_toggle.toggled.connect(func(on: bool) -> void: Net.ai_pilot = on)
	server_list.item_selected.connect(_on_server_selected)
	server_list.item_activated.connect(_on_server_activated)
	Net.servers_updated.connect(_on_servers_updated)
	Net.join_failed.connect(set_status)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func set_status(text: String) -> void:
	status_label.text = text


func _player_name() -> String:
	Net.all_weapons = name_edit.text == Net.ALL_WEAPONS_NAME
	var n := name_edit.text.strip_edges().left(12)
	return n if n != "" else "Player"


func _on_host_pressed() -> void:
	set_status("Hosting...")
	Net.host(_player_name())


func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		set_status("Pick a game from the list or enter the host's IP")
		return
	_join(ip)


func _on_server_selected(index: int) -> void:
	ip_edit.text = _servers[index].ip


func _on_server_activated(index: int) -> void:
	_join(_servers[index].ip)


func _join(ip: String) -> void:
	set_status("Connecting to %s..." % ip)
	Net.join(ip, _player_name())


func _on_servers_updated(servers: Array) -> void:
	_servers = servers
	server_list.clear()
	for s in servers:
		server_list.add_item("%s  (%s)" % [s.name, s.ip])


## The best runs on this device (HighScores), one per line.
func show_high_scores() -> void:
	var lines := PackedStringArray(["High scores"])
	var runs := HighScores.top(HIGH_SCORES_SHOWN)
	for i in runs.size():
		var r: Dictionary = runs[i]
		lines.append("%d. Stage %d   %d   %s" % [i + 1, r.stage, r.score, ", ".join(PackedStringArray(r.get("players", [])))])
	if runs.is_empty():
		lines.append("No runs yet")
	high_scores_label.text = "\n".join(lines)


func _on_visibility_changed() -> void:
	if visible:
		show_high_scores()
		Net.start_browsing()
	else:
		Net.stop_browsing()
