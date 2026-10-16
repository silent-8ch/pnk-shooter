extends Node2D
## Server-authoritative game world. The host simulates everything; clients
## send input and receive state through MultiplayerSpawner/Synchronizer.

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")

const ARENA := Rect2(0, 0, 540, 960)
const ENEMY_INTERVAL := 1.2
const PLAYER_COLORS: Array[Color] = [
	Color("5ad1ff"), Color("ff7ad9"), Color("8dff7a"), Color("ffd45a"),
	Color("c08dff"), Color("ff9c5a"), Color("7afff2"), Color("ffffff"),
]

@onready var players: Node2D = $Players
@onready var enemies: Node2D = $Enemies
@onready var bullets: Node2D = $Bullets
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var bullet_spawner: MultiplayerSpawner = $BulletSpawner
@onready var score_label: Label = $HUD/ScoreLabel
@onready var hp_label: Label = $HUD/HPLabel
@onready var info_label: Label = $HUD/InfoLabel
@onready var hud: CanvasLayer = $HUD
@onready var touch_controls: CanvasLayer = $TouchControls

var score := 0  # replicated by ScoreSync
var active := false
var input_enabled := true  # false while the pause menu is open
var _enemy_timer := 0.0
var _player_count := 0


func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	enemy_spawner.spawn_function = _spawn_enemy
	bullet_spawner.spawn_function = _spawn_bullet
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	hud.visible = false
	touch_controls.visible = false


func start() -> void:
	active = true
	hud.visible = true
	touch_controls.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if multiplayer.is_server():
		score = 0
		info_label.text = "Hosting at %s" % Net.get_local_ip()
		_add_player(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))
	else:
		info_label.text = "Connected"
		register_player.rpc_id(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))


func stop() -> void:
	active = false
	input_enabled = true
	hud.visible = false
	touch_controls.visible = false
	for group in [players, enemies, bullets]:
		for child in group.get_children():
			child.queue_free()
	score = 0
	_player_count = 0


func _process(_delta: float) -> void:
	if not active or multiplayer.multiplayer_peer == null:
		return
	score_label.text = "Score %d" % score
	var me := players.get_node_or_null(str(multiplayer.get_unique_id()))
	hp_label.text = "HP %d" % me.hp if me else "HP -"


func _physics_process(delta: float) -> void:
	if not active or not multiplayer.is_server():
		return
	_enemy_timer += delta
	if _enemy_timer >= ENEMY_INTERVAL:
		_enemy_timer = 0.0
		enemy_spawner.spawn({"x": randf_range(40.0, ARENA.size.x - 40.0)})


# --- Players ---------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String, ship: int, palette: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has_node(str(id)):
		return
	_add_player(id, pname, ship, palette)


func _add_player(id: int, pname: String, ship: int, palette: int) -> void:
	var idx := _player_count
	_player_count += 1
	player_spawner.spawn({
		"id": id,
		"name": pname.left(12),
		"ship": Ships.clamp_index(ship),
		"palette": Ships.clamp_palette(palette),
		"color": PLAYER_COLORS[idx % PLAYER_COLORS.size()],
		"pos": Vector2(ARENA.size.x * (0.2 + 0.6 * fposmod(idx * 0.37, 1.0)), ARENA.size.y - 120),
	})


func _spawn_player(data: Dictionary) -> Node:
	var p := PlayerScene.instantiate()
	p.name = str(data.id)
	p.peer_id = data.id
	p.player_name = data.name
	p.color = data.color
	p.ship = data.get("ship", 0)
	p.palette = data.get("palette", 0)
	p.position = data.pos
	p.spawn_position = data.pos
	print("[peer %d] spawned player %s (%d)" % [multiplayer.get_unique_id(), data.name, data.id])
	return p


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var p := players.get_node_or_null(str(id))
	if p:
		p.queue_free()


# --- Enemies / bullets (server only callers) --------------------------------

func _spawn_enemy(data: Dictionary) -> Node:
	var e := EnemyScene.instantiate()
	e.position = Vector2(data.x, -40)
	return e


func spawn_bullet(pos: Vector2, color: Color) -> void:
	bullet_spawner.spawn({"pos": pos, "color": color})


func _spawn_bullet(data: Dictionary) -> Node:
	var b := BulletScene.instantiate()
	b.position = data.pos
	b.color = data.color
	return b


func add_score(points: int) -> void:
	if multiplayer.is_server():
		score += points
