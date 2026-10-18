extends Area2D
## Player bullet. Local on every peer (Game.fire_bullet creates each copy) and
## moved there; `shooter` is the peer that fired it, whose copy reports hits.
## Carries a PointLight2D tinted to `color` that lights ship bodies only
## (Ships.LIGHT_MASK); any bullet using this scene gets the same light.
## The body is the painted bullet animation recolored: slot 1 (outline) stays
## white, slot 2 (core) takes `color`.
## `kind` picks the shot (KINDS): a LASER flies along `direction` (straight
## up); a MISSILE is a smaller, darker laser that turns toward the nearest enemy
## or other player's ship (see seek_target)
## (each peer steers its own copy; only the shooter's copy reports hits, so small
## differences don't matter). Missiles launch along `direction` (Player fans
## them out) and only start turning after MISSILE_LAUNCH s, and each leaves a
## SmokeTrail in Game.effects that lingers after it's gone; a VULCAN round (autocannon) is tiny, fast and weak,
## and fizzles after a short range. An ENEMY_SHOT is the boss's: slower, so it
## can be dodged; its `shooter` is ENEMY_SHOOTER, so it hurts every player and
## passes through enemies. Damage can be a fraction of a hit; ships and
## enemies add up the fractions.

enum { LASER, MISSILE, VULCAN, ENEMY_SHOT }
const ENEMY_SHOOTER := -1  # `shooter` of an enemy's bullet
const KINDS: Array[Dictionary] = [
	{"speed": 420.0, "scale": 1.0, "damage": 1.0, "range": INF, "darken": 0.0, "light": 1.0},
	{"speed": 340.0, "scale": 0.6, "damage": 1.0, "range": INF, "darken": 0.5, "light": 0.5},
	{"speed": 900.0, "scale": 0.3, "damage": 0.25, "range": 200.0, "darken": 0.0, "light": 0.25},
	{"speed": 230.0, "scale": 0.7, "damage": 1.0, "range": INF, "darken": 0.0, "light": 0.8},
]
const SPEED := 420.0  # laser
const HEIGHT := 44.0  # on-screen height in px
const RENDER_SCALE := 1.5  # SVG -> texture, sharper than 1:1 on high-DPI phones
const FRAMES := preload("res://assets/effects/bullet.tres")
const MISSILE_TURN := 4.0  # rad/s
const MISSILE_LAUNCH := 0.15  # s a missile flies straight out before it seeks
const SmokeTrail := preload("res://scripts/smoke_trail.gd")

@export var color := Color.YELLOW
var shooter := 0  # peer id that fired it
var direction := Vector2.UP
var kind := LASER
var _travelled := 0.0
var _age := 0.0
var trail: Line2D  # a missile's smoke, in Game.effects (or beside the bullet without a game)


func _ready() -> void:
	kind = clampi(kind, 0, KINDS.size() - 1)
	var k := KINDS[kind]
	var c := color.darkened(k.darken)
	var frames := frames_for(c)
	$Body.sprite_frames = frames
	$Body.scale = Vector2.ONE * (HEIGHT / frames.get_frame_texture(&"default", 0).get_height()) * k.scale
	$Light.energy *= k.light
	$Body.play()
	$Light.color = c
	$Light.range_item_cull_mask = Ships.LIGHT_MASK
	rotation = Vector2.UP.angle_to(direction)
	if kind == MISSILE:
		trail = SmokeTrail.new()
		var game := get_tree().get_first_node_in_group("game")
		var parent: Node = game.effects if game else get_parent()
		parent.add_child(trail)
		trail.emit(parent.to_local(global_position))
		tree_exiting.connect(_end_trail)


func _end_trail() -> void:
	if is_instance_valid(trail):
		trail.finish()


static func frames_for(c: Color) -> SpriteFrames:
	return PaletteFrames.recolor(FRAMES, [Color.WHITE, c], RENDER_SCALE)


func damage() -> float:
	return KINDS[kind].damage


## Fired by an enemy (the boss): hurts players, not enemies.
func is_hostile() -> bool:
	return shooter == ENEMY_SHOOTER


func is_seeking() -> bool:
	return kind == MISSILE


func max_range() -> float:
	return KINDS[kind].range


## True on the peer that reports this bullet's hits: whoever fired it, or the
## host for its AI buddy's shots.
func is_mine() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if shooter == multiplayer.get_unique_id():
		return true
	var game := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	return game != null and game.controls(shooter)


func _physics_process(delta: float) -> void:
	var speed: float = KINDS[kind].speed
	_age += delta
	if is_seeking() and _age >= MISSILE_LAUNCH:
		_steer(delta)
	position += direction * speed * delta
	if trail:
		trail.emit(trail.get_parent().to_local(global_position))
	_travelled += speed * delta
	var arena := Rect2(Vector2.ZERO, Vector2(540, 960)).grow(HEIGHT)
	if _travelled >= max_range() or not arena.has_point(position):
		queue_free()


## Nearest enemy or other player's ship (friendly fire), or null. Never the
## shooter's own ship, and never a ship with a friendly beacon (BEACON).
func seek_target() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for group in [&"enemy", &"player"]:
		for n in get_tree().get_nodes_in_group(group):
			if n.is_queued_for_deletion():
				continue
			if group == &"player" and (n.peer_id == shooter or not n.is_alive() or n.beacon):
				continue
			var d := position.distance_squared_to(n.position)
			if d < best_d:
				best_d = d
				best = n
	return best


func _steer(delta: float) -> void:
	var target := seek_target()
	if target == null:
		return
	var want := direction.angle_to(target.position - position)
	direction = direction.rotated(clampf(want, -MISSILE_TURN * delta, MISSILE_TURN * delta))
	rotation = Vector2.UP.angle_to(direction)
