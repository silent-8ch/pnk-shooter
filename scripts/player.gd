extends Area2D
## A player ship. Simulated on the server; the owning peer sends input.

const SPEED := 340.0
const FIRE_COOLDOWN := 0.16
const RESPAWN_TIME := 2.0
const MAX_HP := 3

@export var peer_id := 1
@export var player_name := "Player"
@export var color := Color.WHITE
@export var ship := 0  # index into Ships.LIST
@export var palette := 0  # index into Ships.PALETTES
var spawn_position := Vector2.ZERO

var hp := MAX_HP  # replicated
var input_dir := Vector2.ZERO
var firing := false
var _cooldown := 0.0
var _respawn_timer := 0.0

@onready var body: Sprite2D = $Body
@onready var label: Label = $Label


func _ready() -> void:
	label.text = player_name
	body.texture = Ships.get_lit_texture(ship, palette)
	body.scale = Ships.get_scale(ship, palette)
	body.light_mask = Ships.LIGHT_MASK
	area_entered.connect(_on_area_entered)


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func is_alive() -> bool:
	return hp > 0


func _process(_delta: float) -> void:
	body.modulate.a = 1.0 if is_alive() else 0.25
	if multiplayer.multiplayer_peer == null:
		return
	if is_local():
		_gather_input()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_simulate(delta)


func _gather_input() -> void:
	var dir := Vector2.ZERO
	var fire := false
	var pointer := get_tree().get_first_node_in_group("pointer_controls")
	if pointer and pointer.is_active():
		dir = pointer.direction_from(position, _movement_bounds())
		fire = pointer.firing
	var game := get_tree().get_first_node_in_group("game")
	if game and not game.input_enabled:
		dir = Vector2.ZERO
		fire = false
	if multiplayer.is_server():
		input_dir = dir
		firing = fire
	else:
		send_input.rpc_id(1, dir, fire)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func send_input(dir: Vector2, fire: bool) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	input_dir = dir.limit_length(1.0)
	firing = fire


func _simulate(delta: float) -> void:
	if not is_alive():
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			hp = MAX_HP
			position = spawn_position
		return

	position += input_dir * SPEED * delta
	var bounds := _movement_bounds()
	position = position.clamp(bounds.position, bounds.end)

	_cooldown -= delta
	if firing and _cooldown <= 0.0:
		_cooldown = FIRE_COOLDOWN
		get_tree().get_first_node_in_group("game").spawn_bullet(position + Vector2(0, -26), color)


func _movement_bounds() -> Rect2:
	var arena: Rect2 = get_parent().get_parent().ARENA
	return arena.grow(-20)


func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or not is_alive():
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		_respawn_timer = RESPAWN_TIME


func _on_area_entered(area: Area2D) -> void:
	if not multiplayer.is_server():
		return
	if area.is_in_group("enemy"):
		take_damage(1)
		area.ram()
