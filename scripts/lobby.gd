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

var _servers: Array = []


func _ready() -> void:
	name_edit.text = "Player%d" % (randi() % 900 + 100)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(back_pressed.emit)
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


func _on_visibility_changed() -> void:
	if visible:
		Net.start_browsing()
	else:
		Net.stop_browsing()
