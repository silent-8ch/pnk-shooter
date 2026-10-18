extends Area2D
## Repair kit a player drops with the REPAIR button: a small copy of their ship
## with a pulsing cross. It stays where it was dropped; the first damaged ship
## to fly over it (its dropper included) heals HEAL hits' worth. Ships at full health
## pass over it. Local on every peer like Pickup; the host gives it to the
## first claim (Game.request_repair). Uncollected, it blinks out after LIFETIME.

const SCALE := 0.5  # relative to the dropper's ship (Player.OPTION_SCALE)
const RADIUS := 18.0
const HEAL := 1.0  # hits (Player.HIT_HP each)
const ARM_TIME := 0.75  # s before it can be taken, so the dropper flies clear first
const LIFETIME := 15.0
const BLINK_TIME := 3.0
const CROSS_COLOR := Color("8dff7a")
const CROSS_SIZE := 6.0
const PULSE_RATE := 3.0

var ship := 0
var palette := 0
var taken := false  # gone on every peer once the host says so
var body := Sprite2D.new()
var _age := 0.0
var _claimed := false  # local: already asked the host for it


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # players
	monitorable = false
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)
	add_to_group("repair_kit")
	body.texture = Ships.get_lit_texture(ship, palette)
	body.scale = Ships.get_scale(ship, palette) * SCALE
	body.light_mask = Ships.LIGHT_MASK
	body.show_behind_parent = true  # cross on top
	add_child(body)


func _process(delta: float) -> void:
	_age += delta
	var left := LIFETIME - _age
	if left <= 0.0:
		queue_free()
		return
	visible = left >= BLINK_TIME or fmod(left, 0.2) > 0.1
	queue_redraw()
	if monitoring:
		claim_from(get_overlapping_areas())


func armed() -> bool:
	return _age >= ARM_TIME


## The local ship, if it's touching and damaged, asks the host for the kit.
func claim_from(areas: Array) -> void:
	if taken or _claimed or not armed() or multiplayer.multiplayer_peer == null:
		return
	for a in areas:
		if a.is_in_group("player") and a.is_local() and not a.ai and a.is_alive() and a.needs_repair():
			var game := get_tree().get_first_node_in_group("game")
			if game:
				_claimed = true
				game.request_repair.rpc_id(1, String(name))
			return


func _draw() -> void:
	var c := Color(CROSS_COLOR, 0.6 + 0.4 * sin(_age * PULSE_RATE * TAU))
	draw_rect(Rect2(-CROSS_SIZE, -CROSS_SIZE / 3.0, CROSS_SIZE * 2.0, CROSS_SIZE * 2.0 / 3.0), c)
	draw_rect(Rect2(-CROSS_SIZE / 3.0, -CROSS_SIZE, CROSS_SIZE * 2.0 / 3.0, CROSS_SIZE * 2.0), c)
