class_name Droid
extends Node2D
## A fun-time droid (FunTime): a small copy of its ship (rescue drone sized,
## in the ship's own colors) that circles it at ORBIT_RADIUS, with two lights
## flashing in turn through the pickup's star colors, and a pip for each exp it
## has earned so far. Local on every peer, following its own copy of the ship,
## named by the host (Game.spawn_droid).
## The ship's owner (the host, for the AI buddy) checks what touches it, like
## an enemy, a hazard, an obstacle or an enemy shot (the shot
## is used up). Its own side's shots pass through. Each touch is reported to
## the host (Game.report_droid_hit), which keeps its HP; it flashes white when
## hit and can't be hit again for HIT_COOLDOWN. Nothing hurts it between
## levels, like the ships.

const ORBIT_RADIUS := 44.0  # px from its ship
const ORBIT_SPEED := 2.4  # rad/s, anticlockwise
const RADIUS := 8.0  # px: what touches it (Player.DRONE_RADIUS)
const HP := 3  # hits to destroy
const HIT_COOLDOWN := 0.6  # s after a hit before it can be hit again (so a touch is one hit)
const FLASH_TIME := 0.08
const LIGHT_GAP := 5.0  # px either side of its middle
const PIP_GAP := 5.0  # px between the earned-exp pips under it
const PlayerScript := preload("res://scripts/player.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

var peer := 0  # the ship it orbits
var hp := HP  # host
var body := Sprite2D.new()
var _age := 0.0
var _phase := 0.0  # where on its orbit it starts (from its name)
var _cooldown := 0.0
var _flash := 0.0
var _skinned := false  # wearing its ship's look yet


func _ready() -> void:
	add_to_group("droid")
	_phase = fposmod(float(hash([String(name), "droid"])), TAU)
	body.light_mask = Ships.LIGHT_MASK
	body.show_behind_parent = true  # lights and pips on top
	add_child(body)
	z_index = 1


## How long it's been out (local).
func age() -> float:
	return _age


## Where it sits around its ship after `t` s out, from the ship.
func orbit_offset(t: float) -> Vector2:
	return Vector2.from_angle(_phase - ORBIT_SPEED * t) * ORBIT_RADIUS


## Exp earned so far, as shown by the pips (the host decides the real count).
func earned() -> int:
	return FunTime.reward_for(_age)


func _game() -> Node:
	return get_tree().get_first_node_in_group("game") if is_inside_tree() else null


func _ship(game: Node) -> Node2D:
	return game.players.get_node_or_null(str(peer)) if game else null


func _process(delta: float) -> void:
	_age += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if _flash > 0.0:
		_flash -= delta
		body.modulate = Color(3, 3, 3) if _flash > 0.0 else Color.WHITE
	var game := _game()
	var ship := _ship(game)
	visible = ship != null and ship.is_alive()
	if ship == null:
		return
	if not _skinned:
		_skinned = true
		body.texture = Ships.get_lit_texture(ship.ship, ship.palette)
		body.scale = Ships.get_scale(ship.ship, ship.palette) * PlayerScript.OPTION_SCALE * PlayerScript.DRONE_SCALE
	var before := position
	position = ship.position + orbit_offset(_age)
	if position != before:
		body.rotation = Vector2.UP.angle_to(position - before)  # the art faces up
	if visible and _cooldown <= 0.0 and multiplayer.multiplayer_peer != null and game.controls(peer) \
			and not game.between_levels() and touched(game, position):
		_cooldown = HIT_COOLDOWN
		game.report_droid_hit.rpc_id(1, String(name))
	queue_redraw()


## Whether it touches an enemy, a hazard, an obstacle or an enemy shot at `at`
## (the shot is used up); its own side's shots pass through.
func touched(game: Node, at: Vector2) -> bool:
	for e in game.enemies.get_children():
		if e.is_queued_for_deletion():
			continue
		var r: float = EnemyScript.TYPES[e.type].get("height", EnemyScript.HEIGHT) * 0.4 * e.scale.x
		if e.is_tetran():
			r = preload("res://scripts/tetran.gd").CORE_RADIUS * e.scale.x
		if at.distance_to(e.position) < r + RADIUS:
			return true
	for h in get_tree().get_nodes_in_group("hazard"):
		if h.has_method("touches") and h.touches(at, RADIUS):
			return true
	for o in game.obstacles.get_children():
		if not o.is_queued_for_deletion() and o.push_out(at, RADIUS).distance_to(at) > 0.01:
			return true
	for b in game.bullets.get_children():
		if b.is_queued_for_deletion() or not b.is_hostile():
			continue
		if at.distance_to(b.position) < RADIUS + 4.0:
			b.queue_free()
			return true
	return false


## Took a hit without being destroyed (every peer, from Game.flash_droid).
func flash() -> void:
	_flash = FLASH_TIME
	body.modulate = Color(3, 3, 3)


## Two lights flashing in turn through the star colors, and a pip per exp earned.
func _draw() -> void:
	var lit := PlayerScript.drone_light(_age)
	var colors := PickupScript.STAR_COLORS
	var step := int(_age * PickupScript.CYCLE_RATE / 3.0)
	for k in 2:
		var at := Vector2(LIGHT_GAP * (-1.0 if k == 0 else 1.0), -2)
		var c: Color = colors[(step + k * 3) % colors.size()]
		if k == lit:
			draw_circle(at, 5.0, Color(c, 0.35))
			draw_circle(at, 2.2, c.lightened(0.4))
		else:
			draw_circle(at, 1.6, Color(c, 0.45))
	var n := earned()
	for i in n:
		var at := Vector2((i - (n - 1) / 2.0) * PIP_GAP, RADIUS + 4.0)
		draw_circle(at, 1.8, UiStyle.AMBER)
