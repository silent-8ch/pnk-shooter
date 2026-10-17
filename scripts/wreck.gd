extends Node2D

## Cosmetic death effect for an enemy, played locally on every peer. The wreck
## veers off spinning and trailing smoke while growing or shrinking (as if
## moving toward/away from the camera), shedding a part or two, then explodes
## and its remaining parts (see ShipParts) fly apart. Every random choice comes
## from `fx_seed`, so each explosion looks different but identical on all peers.
##
## The node itself stays put; the hull moves inside it so loose parts and
## smoke keep their own world-space motion.

const SpriteEffect := preload("res://scripts/sprite_effect.gd")
const SPARKS: Array[Texture2D] = [
	preload("res://assets/filler/fx/spark_00.svg"),
	preload("res://assets/filler/fx/spark_01.svg"),
	preload("res://assets/filler/fx/spark_02.svg"),
]
const EMBER := preload("res://assets/filler/fx/ember.svg")
const TRAIL_PUFFS: Array[Texture2D] = [
	preload("res://assets/filler/fx/trail_puff_00.svg"),
	preload("res://assets/filler/fx/trail_puff_01.svg"),
	preload("res://assets/filler/fx/trail_puff_02.svg"),
]
const FLASH := preload("res://assets/filler/fx/flash.svg")
const RING := preload("res://assets/filler/fx/ring.svg")

const DURATION := 0.8  # veer time before exploding
const VEER_SPEED := 180.0
const FALL_SPEED := 60.0
const SPIN_MIN := 4.0
const SPIN_MAX := 9.0
const GROW_RANGE := Vector2(1.3, 1.7)  # end scale when coming toward the camera
const SHRINK_RANGE := Vector2(0.3, 0.6)  # end scale when falling away
const SMOKE_LIFETIME := 0.7
const SMOKE_SCALE := Vector2(0.18, 0.3)  # puff size range at normal depth (64px art)
const SPARK_LIFETIME := 0.45
const FLASH_TIME := 0.12
const RING_TIME := 0.4
const PIECE_LIFE := 0.7  # loose parts fade out over this long
const PIECE_SPEED := Vector2(100, 260)  # outward speed range at the explosion
const BREAKOFF_SPEED := Vector2(60, 140)  # kick for parts shed during the veer
const PIECE_SPIN := Vector2(3, 10)
const LINGER := 0.8  # time after the explosion before the node is freed
const BLAST_HEIGHT := 56.0  # hand-drawn explosion size at normal depth
const BLAST_TINT := Color(1.0, 0.72, 0.3)  # the explosion art is white ink
const BLAST_SMOKE_HEIGHT := 64.0

## Fiery spark color ramps; one is picked per explosion.
const SPARK_RAMPS: Array = [
	[Color("fffbe6"), Color("ffd23f"), Color("ff6b1a"), Color("8b1e1e00")],
	[Color("ffffff"), Color("ffe8a3"), Color("ff9f43"), Color("5c2a0a00")],
	[Color("ffe0e0"), Color("ff5e5e"), Color("c0392b"), Color("3d0b0b00")],
	[Color("fff4d6"), Color("ffb347"), Color("e2582a"), Color("2b0f0500")],
]

var velocity := Vector2.ZERO
var spin := 0.0
var end_scale := 1.0
var exploded := false

# Explosion look, rolled from the seed.
var spark_amount := 32
var spark_speed := 1.0
var spark_ramp := 0
var flash_radius := 26.0
var rings: Array[Dictionary] = []  # {radius, width, delay}
var breakoffs: Array[Dictionary] = []  # parts shed during the veer: {piece, time}
var pops: Array[Dictionary] = []  # secondary bursts: {offset, delay, size}
var smoke_shade := 0.5
var smoke_puff := 0  # index into TRAIL_PUFFS
var spark_tex := 0  # index into SPARKS

var hull: Node2D  # holds one sprite per part
var smoke: CPUParticles2D
var loose: Array[Dictionary] = []  # flying parts: {node, vel, spin, age}
var _sparks: Array[CPUParticles2D] = []
var _base_scale := Vector2.ONE
var _time := 0.0
var _boom_time := 0.0
var _boom_size := 1.0
var _boom_origin := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


## parts: ShipParts pieces of `texture` ({texture, offset}); empty = one piece.
func setup(texture: Texture2D, base_scale: Vector2, fx_seed: int, parts: Array = []) -> void:
	_rng.seed = fx_seed
	_roll_motion(_rng)
	_roll_explosion(_rng)

	_base_scale = base_scale
	smoke = _make_smoke()
	add_child(smoke)  # added first so it draws under the ship
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


func _roll_motion(rng: RandomNumberGenerator) -> void:
	velocity = Vector2.from_angle(rng.randf() * TAU) * VEER_SPEED + Vector2(0, FALL_SPEED)
	spin = rng.randf_range(SPIN_MIN, SPIN_MAX) * (1.0 if rng.randf() < 0.5 else -1.0)
	var r := GROW_RANGE if rng.randf() < 0.5 else SHRINK_RANGE
	end_scale = rng.randf_range(r.x, r.y)


func _roll_explosion(rng: RandomNumberGenerator) -> void:
	spark_amount = rng.randi_range(24, 48)
	spark_speed = rng.randf_range(0.7, 1.3)
	spark_ramp = rng.randi_range(0, SPARK_RAMPS.size() - 1)
	flash_radius = rng.randf_range(18.0, 36.0)
	smoke_shade = rng.randf_range(0.35, 0.7)
	smoke_puff = rng.randi_range(0, TRAIL_PUFFS.size() - 1)
	spark_tex = rng.randi_range(0, SPARKS.size() - 1)
	rings.clear()
	for i in rng.randi_range(1, 2):
		rings.append({
			"radius": rng.randf_range(45.0, 80.0),
			"angle": rng.randf() * TAU,
			"delay": i * rng.randf_range(0.05, 0.12),
		})
	pops.clear()
	for i in rng.randi_range(0, 3):
		pops.append({
			"offset": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(12.0, 30.0),
			"delay": rng.randf_range(0.05, 0.25),
			"size": rng.randf_range(0.35, 0.6),
			"fired": false,
		})


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
		smoke.position = hull.position
		smoke.scale_amount_min = SMOKE_SCALE.x * z
		smoke.scale_amount_max = SMOKE_SCALE.y * z
		for b in breakoffs:
			if not b.done and _time >= b.time:
				b.done = true
				var kick := _rng.randf_range(BREAKOFF_SPEED.x, BREAKOFF_SPEED.y)
				_detach(hull.get_child(b.piece), kick, velocity)
		if _time >= DURATION:
			explode()
		return
	_boom_time += delta
	for pop in pops:
		if not pop.fired and _boom_time >= pop.delay:
			pop.fired = true
			_burst(pop.offset, pop.size)
	queue_redraw()
	if _boom_time >= LINGER:
		queue_free()


## Apparent size (1 = normal depth) at veer progress t in [0, 1].
func depth_scale(t: float) -> float:
	return lerpf(1.0, end_scale, t * t)


func explode() -> void:
	if exploded:
		return
	exploded = true
	_boom_size = end_scale  # nearer explosions look bigger, farther ones smaller
	_boom_origin = hull.position
	smoke.emitting = false
	for piece in hull.get_children():
		if piece.visible:
			var speed := _rng.randf_range(PIECE_SPEED.x, PIECE_SPEED.y) * _boom_size
			_detach(piece, speed, velocity * 0.3)
	_burst(Vector2.ZERO, _boom_size)
	# Hand-drawn blast and smoke puff at the blast point, sized by depth.
	SpriteEffect.spawn(self, _boom_origin, SpriteEffect.SMOKE, BLAST_SMOKE_HEIGHT * _boom_size)
	SpriteEffect.spawn(self, _boom_origin, SpriteEffect.EXPLOSION, BLAST_HEIGHT * _boom_size,
			BLAST_TINT)
	queue_redraw()


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


func _burst(offset: Vector2, size: float) -> void:
	_sparks.append(_spark_emitter(offset, size))
	# A few embers stretched along their flight path.
	var e := _spark_emitter(offset, size)
	e.texture = EMBER
	e.amount = maxi(3, e.amount / 4)
	e.particle_flag_align_y = true
	e.initial_velocity_min *= 1.4
	e.initial_velocity_max *= 1.4
	e.scale_amount_min = 0.25 * size
	e.scale_amount_max = 0.45 * size


func _spark_emitter(offset: Vector2, size: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = SPARKS[spark_tex]
	p.local_coords = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(6, int(spark_amount * size))
	p.lifetime = SPARK_LIFETIME
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 120.0 * spark_speed * size
	p.initial_velocity_max = 320.0 * spark_speed * size
	p.damping_min = 150.0
	p.damping_max = 300.0
	p.scale_amount_min = 0.2 * size
	p.scale_amount_max = 0.45 * size
	p.color_ramp = _ramp(SPARK_RAMPS[spark_ramp])
	p.position = _boom_origin + offset
	add_child(p)
	p.emitting = true
	return p


func _draw() -> void:
	if not exploded:
		return
	var s := _boom_size
	# Flash
	if _boom_time < FLASH_TIME:
		var a := 1.0 - _boom_time / FLASH_TIME
		_draw_centered(FLASH, Vector2.ZERO, flash_radius * s, 0.0, Color(1, 1, 1, a))
	# Shockwave rings
	for ring in rings:
		var t: float = (_boom_time - ring.delay) / RING_TIME
		if t > 0.0 and t < 1.0:
			var r: float = ring.radius * s * ease(t, 0.4)
			_draw_centered(RING, Vector2.ZERO, r, ring.angle + t, Color(1, 0.85, 0.6, 1.0 - t))
	# Secondary pop flashes
	for pop in pops:
		var pt: float = (_boom_time - pop.delay) / FLASH_TIME
		if pt > 0.0 and pt < 1.0:
			_draw_centered(FLASH, pop.offset, flash_radius * pop.size, 0.0, Color(1, 0.9, 0.7, 1.0 - pt))


## Draws `tex` centered at `pos` (relative to the blast) with the given radius.
func _draw_centered(tex: Texture2D, pos: Vector2, radius: float, angle: float, color: Color) -> void:
	draw_set_transform(_boom_origin + pos, angle)
	draw_texture_rect(tex, Rect2(-radius, -radius, radius * 2.0, radius * 2.0), false, color)


func _make_smoke() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = TRAIL_PUFFS[smoke_puff]
	p.local_coords = false
	p.amount = 40
	p.lifetime = SMOKE_LIFETIME
	p.spread = 180.0
	p.gravity = Vector2(0, -15)
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = SMOKE_SCALE.x
	p.scale_amount_max = SMOKE_SCALE.y
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = grow
	# The puff art is already gray; lighten or darken it a little per wreck.
	var g := remap(smoke_shade, 0.35, 0.7, 0.75, 1.0)
	p.color_ramp = _ramp([Color(g, g, g, 0.8), Color(g * 0.7, g * 0.7, g * 0.7, 0.0)])
	p.emitting = true
	return p


static func _ramp(colors: Array) -> Gradient:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for i in colors.size():
		grad.add_point(float(i) / (colors.size() - 1), colors[i])
	return grad
