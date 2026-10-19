extends Node2D

## Cosmetic death effect for an enemy, played locally on every peer. The wreck
## veers off spinning while growing or shrinking (as if moving toward/away from
## the camera), shedding a part or two, then explodes (the painted explosion,
## recolored from one of FIRE_RAMPS) and its remaining parts (see ShipParts) fly
## apart. Every random choice comes from `fx_seed`, so each explosion looks
## different but identical on all peers.
##
## The node itself stays put; the hull moves inside it so loose parts keep
## their own world-space motion.
##
## Broken enemies are non-combatants: the wreck passes through everything and
## its explosion hurts nothing.

const SpriteEffect := preload("res://scripts/sprite_effect.gd")
const IMPLOSION_SOUND := preload("res://assets/sfx/implosion.tres")  # random pitch/volume per play
const EXPLOSION_SOUND := preload("res://assets/sfx/explosion.tres")

const DURATION := 0.8  # veer time before exploding
const VEER_SPEED := 180.0
const FALL_SPEED := 60.0
const SPIN_MIN := 4.0
const SPIN_MAX := 9.0
const GROW_RANGE := Vector2(1.3, 1.7)  # end scale when coming toward the camera
const SHRINK_RANGE := Vector2(0.3, 0.6)  # end scale when falling away
const PIECE_LIFE := 0.7  # loose parts fade out over this long
const PIECE_SPEED := Vector2(100, 260)  # outward speed range at the explosion
const BREAKOFF_SPEED := Vector2(60, 140)  # kick for parts shed during the veer
const PIECE_SPIN := Vector2(3, 10)
const LINGER := 0.8  # time after the explosion before the node is freed
const BLAST_HEIGHT := 56.0  # painted explosion size at normal depth
const RADIUS := 14.0  # hull reach for collisions, at normal depth
const BLAST_RADIUS := 48.0  # destroys/damages within this, at normal depth

## Fire color ramps for the painted explosion; one is picked per explosion.
const FIRE_RAMPS: Array = [
	[Color("fffbe6"), Color("ffd23f"), Color("ff6b1a"), Color("8b1e1e00")],
	[Color("ffffff"), Color("ffe8a3"), Color("ff9f43"), Color("5c2a0a00")],
	[Color("ffe0e0"), Color("ff5e5e"), Color("c0392b"), Color("3d0b0b00")],
	[Color("fff4d6"), Color("ffb347"), Color("e2582a"), Color("2b0f0500")],
]

var velocity := Vector2.ZERO
var spin := 0.0
var end_scale := 1.0
var exploded := false
var pod_name := ""  # its own escape pod, which it doesn't hit

var fire_ramp := 0  # index into FIRE_RAMPS, rolled from the seed
var breakoffs: Array[Dictionary] = []  # parts shed during the veer: {piece, time}

var hull: Node2D  # holds one sprite per part
var loose: Array[Dictionary] = []  # flying parts: {node, vel, spin, age}
var _base_scale := Vector2.ONE
var _time := 0.0
var _boom_time := 0.0
var _boom_size := 1.0
var _boom_origin := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var implosion_sound := AudioStreamPlayer.new()  # plays as the enemy dies
var explosion_sound := AudioStreamPlayer.new()


## parts: ShipParts pieces of `texture` ({texture, offset}); empty = one piece.
func setup(texture: Texture2D, base_scale: Vector2, fx_seed: int, parts: Array = []) -> void:
	_rng.seed = fx_seed
	_roll_motion(_rng)
	fire_ramp = _rng.randi_range(0, FIRE_RAMPS.size() - 1)

	_base_scale = base_scale
	hull = Node2D.new()
	add_child(hull)
	if parts.is_empty():
		parts = [{"texture": texture, "offset": Vector2.ZERO}]
	for part in parts:
		var sprite := Sprite2D.new()
		sprite.texture = part.texture
		sprite.position = part.offset
		sprite.light_mask = Ships.LIGHT_MASK  # dimmed and lit like ships (no normal map)
		hull.add_child(sprite)
	_apply_hull_scale(1.0)
	_roll_breakoffs(_rng, parts)

	implosion_sound.stream = IMPLOSION_SOUND
	implosion_sound.autoplay = true
	add_child(implosion_sound)
	explosion_sound.stream = EXPLOSION_SOUND
	add_child(explosion_sound)


func _roll_motion(rng: RandomNumberGenerator) -> void:
	velocity = Vector2.from_angle(rng.randf() * TAU) * VEER_SPEED + Vector2(0, FALL_SPEED)
	spin = rng.randf_range(SPIN_MIN, SPIN_MAX) * (1.0 if rng.randf() < 0.5 else -1.0)
	var r := GROW_RANGE if rng.randf() < 0.5 else SHRINK_RANGE
	end_scale = rng.randf_range(r.x, r.y)


## Sheds 1-2 of the smaller parts mid-veer (never the largest, and only when
## at least two parts would stay attached).
func _roll_breakoffs(rng: RandomNumberGenerator, parts: Array) -> void:
	breakoffs.clear()
	var order := range(parts.size())
	order.sort_custom(func(a, b): return parts[a].get("area", 0) < parts[b].get("area", 0))
	var count := mini(rng.randi_range(1, 2), parts.size() - 2)
	for i in count:
		breakoffs.append({
			"piece": order[i],
			"time": rng.randf_range(0.25, 0.65) * DURATION,
			"done": false,
		})


func _apply_hull_scale(z: float) -> void:
	hull.scale = _base_scale * z * Vector2(1, -1)  # flipped: enemies face down


func _process(delta: float) -> void:
	_time += delta
	_update_loose(delta)
	if not exploded:
		hull.position += velocity * delta
		hull.rotation += spin * delta
		var t := clampf(_time / DURATION, 0.0, 1.0)
		var z := depth_scale(t)
		_apply_hull_scale(z)
		for b in breakoffs:
			if not b.done and _time >= b.time:
				b.done = true
				var kick := _rng.randf_range(BREAKOFF_SPEED.x, BREAKOFF_SPEED.y)
				_detach(hull.get_child(b.piece), kick, velocity)
		if _time >= DURATION:
			explode()
		return
	_boom_time += delta
	if _boom_time >= LINGER:
		queue_free()


## Apparent size (1 = normal depth) at veer progress t in [0, 1].
func depth_scale(t: float) -> float:
	return lerpf(1.0, end_scale, t * t)


## Hull center in the parent's space (where it hits and blasts).
func hull_position() -> Vector2:
	return position + (hull.position if hull else Vector2.ZERO)


func reach() -> float:
	return RADIUS * depth_scale(clampf(_time / DURATION, 0.0, 1.0))


func blast_radius() -> float:
	return BLAST_RADIUS * _boom_size


func _game() -> Node:
	return get_tree().get_first_node_in_group("game") if is_inside_tree() else null


func explode() -> void:
	if exploded:
		return
	exploded = true
	_boom_size = end_scale  # nearer explosions look bigger, farther ones smaller
	_boom_origin = hull.position
	for piece in hull.get_children():
		if piece.visible:
			var speed := _rng.randf_range(PIECE_SPEED.x, PIECE_SPEED.y) * _boom_size
			_detach(piece, speed, velocity * 0.3)
	# Painted blast at the blast point, sized by depth.
	SpriteEffect.spawn(self, _boom_origin, SpriteEffect.explosion_frames(FIRE_RAMPS[fire_ramp]),
		BLAST_HEIGHT * _boom_size)
	# Nearer blasts sound deeper and louder, farther ones higher and quieter.
	explosion_sound.pitch_scale = clampf(1.0 / sqrt(_boom_size), 0.75, 1.4)
	explosion_sound.volume_db = clampf(linear_to_db(_boom_size), -8.0, 3.0)
	if explosion_sound.is_inside_tree():
		explosion_sound.play()


## Turns a hull part into a loose piece flying away from the hull center.
func _detach(piece: Sprite2D, speed: float, inherit: Vector2) -> void:
	if not piece.visible:
		return
	var xf := piece.global_transform
	piece.visible = false
	var sprite := Sprite2D.new()
	sprite.texture = piece.texture
	sprite.light_mask = piece.light_mask
	add_child(sprite)
	sprite.global_transform = xf
	var out := sprite.position - hull.position
	var dir := out.normalized() if out.length() > 1.0 else Vector2.from_angle(_rng.randf() * TAU)
	var s := _rng.randf_range(PIECE_SPIN.x, PIECE_SPIN.y) * (1.0 if _rng.randf() < 0.5 else -1.0)
	loose.append({"node": sprite, "vel": dir * speed + inherit, "spin": s, "age": 0.0})


func _update_loose(delta: float) -> void:
	for p in loose:
		if p.age >= PIECE_LIFE or not is_instance_valid(p.node):
			continue
		var node: Sprite2D = p.node
		p.age += delta
		node.position += p.vel * delta
		node.rotation += p.spin * delta
		node.modulate.a = clampf(1.0 - p.age / PIECE_LIFE, 0.0, 1.0)
		if p.age >= PIECE_LIFE:
			node.queue_free()
