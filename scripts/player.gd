extends Area2D
## A player ship. Simulated on the server; the owning peer sends input.
## Sized by Depth from its screen y: smaller when flying up toward the vanishing point.

const SPEED := 340.0
const FIRE_COOLDOWN := 0.5  # min time between shots; each shot needs its own press
const RESPAWN_TIME := 2.0
const MAX_HP := 3
const TOP_Y := 360.0  # highest the ship may fly (stays well below the vanishing point)

@export var peer_id := 1
@export var player_name := "Player"
@export var color := Color.WHITE
@export var ship := 0  # index into Ships.LIST
@export var palette := 0  # index into Ships.PALETTES
var spawn_position := Vector2.ZERO

var hp := MAX_HP  # replicated
var input_dir := Vector2.ZERO
var _fire_requested := false  # server: a press arrived and is waiting for the cooldown check
var _seen_presses := -1  # local: pointer press count already handled (-1 = not synced yet)
var _cooldown := 0.0
var _respawn_timer := 0.0

@onready var body: Sprite2D = $Body
@onready var label: Label = $Label


func _ready() -> void:
	label.text = player_name
	body.texture = Ships.get_lit_texture(ship, palette)
	_apply_depth()
	body.light_mask = Ships.LIGHT_MASK
	area_entered.connect(_on_area_entered)


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func is_alive() -> bool:
	return hp > 0


func _apply_depth() -> void:
	var s := Depth.scale_at(position.y)
	body.scale = Ships.get_scale(ship, palette) * s
	$Shape.scale = Vector2.ONE * s


func _process(_delta: float) -> void:
	_apply_depth()
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
		fire = _seen_presses >= 0 and pointer.presses != _seen_presses
		_seen_presses = pointer.presses
	var game := get_tree().get_first_node_in_group("game")
	if game and not game.input_enabled:
		dir = Vector2.ZERO
		fire = false
	if multiplayer.is_server():
		input_dir = dir
		if fire:
			_fire_requested = true
	else:
		send_input.rpc_id(1, dir)
		if fire:
			request_fire.rpc_id(1)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func send_input(dir: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	input_dir = dir.limit_length(1.0)


## One press = one shot request. Reliable so a tap is never lost.
@rpc("any_peer", "call_remote", "reliable")
func request_fire() -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_fire_requested = true


func _simulate(delta: float) -> void:
	if not is_alive():
		_fire_requested = false
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			hp = MAX_HP
			position = spawn_position
		return

	position += input_dir * SPEED * delta
	var bounds := _movement_bounds()
	position = position.clamp(bounds.position, bounds.end)

	_cooldown -= delta
	if _fire_requested:
		_fire_requested = false  # a press during the cooldown is dropped, not queued
		if _cooldown > 0.0:
			return
		_cooldown = FIRE_COOLDOWN
		get_tree().get_first_node_in_group("game").spawn_bullet(position + Vector2(0, -26), color)


func _movement_bounds() -> Rect2:
	var arena: Rect2 = get_parent().get_parent().ARENA
	var r := arena.grow(-20)
	r.position.y = maxf(r.position.y, TOP_Y)
	r.end.y = arena.end.y - 20
	return r


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
