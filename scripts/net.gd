extends Node
## Networking autoload: hosting, joining, and LAN discovery (UDP broadcast).

const GAME_PORT := 8910
const DISCOVERY_PORT := 8911
const DISCOVER_MSG := "PNK_DISCOVER"
const ANNOUNCE_PREFIX := "PNK_HOST|"
const BROWSE_INTERVAL := 1.0
const SERVER_TIMEOUT := 4.0
const MAX_PLAYERS := 8

signal game_started
signal join_failed(reason: String)
signal disconnected
signal servers_updated(servers: Array)

var player_name := "Player"

var _browser: PacketPeerUDP
var _announcer: PacketPeerUDP
var _servers := {}  # ip -> {"name": String, "ip": String, "last_seen": float}
var _browse_timer := 0.0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if _browser:
		_poll_browser(delta)
	if _announcer:
		_poll_announcer()


# --- Hosting / joining -----------------------------------------------------

func host(pname: String) -> void:
	player_name = pname
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS)
	if err != OK:
		join_failed.emit("Could not host on port %d (error %d)" % [GAME_PORT, err])
		return
	stop_browsing()
	multiplayer.multiplayer_peer = peer
	_start_announcer()
	game_started.emit()


func join(ip: String, pname: String) -> void:
	player_name = pname
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, GAME_PORT)
	if err != OK:
		join_failed.emit("Could not connect to %s (error %d)" % [ip, err])
		return
	multiplayer.multiplayer_peer = peer


func leave() -> void:
	_stop_announcer()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func _on_connected_to_server() -> void:
	stop_browsing()
	game_started.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit("Could not connect to host")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	disconnected.emit()


# --- LAN discovery: host side ----------------------------------------------

func _start_announcer() -> void:
	_announcer = PacketPeerUDP.new()
	var err := _announcer.bind(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		push_warning("LAN discovery unavailable: could not bind UDP port %d" % DISCOVERY_PORT)
		_announcer = null


func _stop_announcer() -> void:
	if _announcer:
		_announcer.close()
		_announcer = null


func _poll_announcer() -> void:
	while _announcer.get_available_packet_count() > 0:
		var msg := _announcer.get_packet().get_string_from_utf8()
		if msg != DISCOVER_MSG:
			continue
		_announcer.set_dest_address(_announcer.get_packet_ip(), _announcer.get_packet_port())
		_announcer.put_packet((ANNOUNCE_PREFIX + player_name).to_utf8_buffer())


# --- LAN discovery: client side --------------------------------------------

func start_browsing() -> void:
	if _browser:
		return
	_browser = PacketPeerUDP.new()
	_browser.set_broadcast_enabled(true)
	var err := _browser.bind(0, "0.0.0.0")
	if err != OK:
		push_warning("LAN discovery unavailable: could not open UDP socket")
		_browser = null
		return
	_servers.clear()
	_browse_timer = BROWSE_INTERVAL  # send immediately


func stop_browsing() -> void:
	if _browser:
		_browser.close()
		_browser = null


func _poll_browser(delta: float) -> void:
	_browse_timer += delta
	if _browse_timer >= BROWSE_INTERVAL:
		_browse_timer = 0.0
		_browser.set_dest_address("255.255.255.255", DISCOVERY_PORT)
		_browser.put_packet(DISCOVER_MSG.to_utf8_buffer())

	var changed := false
	while _browser.get_available_packet_count() > 0:
		var msg := _browser.get_packet().get_string_from_utf8()
		if not msg.begins_with(ANNOUNCE_PREFIX):
			continue
		var ip := _browser.get_packet_ip()
		var hname := msg.substr(ANNOUNCE_PREFIX.length())
		if not _servers.has(ip) or _servers[ip].name != hname:
			changed = true
		_servers[ip] = {"name": hname, "ip": ip, "last_seen": Time.get_ticks_msec() / 1000.0}

	var now := Time.get_ticks_msec() / 1000.0
	for ip in _servers.keys():
		if now - _servers[ip].last_seen > SERVER_TIMEOUT:
			_servers.erase(ip)
			changed = true

	if changed:
		servers_updated.emit(get_servers())


func get_servers() -> Array:
	var out := _servers.values()
	out.sort_custom(func(a, b): return a.name < b.name)
	return out


# --- Helpers ---------------------------------------------------------------

func get_local_ip() -> String:
	var fallback := ""
	for addr in IP.get_local_addresses():
		if addr.contains(":"):
			continue  # skip IPv6
		if addr.begins_with("127."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		if addr.begins_with("172."):
			var second := int(addr.split(".")[1])
			if second >= 16 and second <= 31:
				return addr
		if fallback == "":
			fallback = addr
	return fallback
