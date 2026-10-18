extends Area2D
## Player bullet. Local on every peer (Game.fire_bullet creates each copy) and
## moved there; `shooter` is the peer that fired it, whose copy reports hits.
## Carries a PointLight2D tinted to `color` that lights ship bodies only
## (Ships.LIGHT_MASK); any bullet using this scene gets the same light.
## The body is the painted bullet animation recolored: slot 1 (outline) stays
## white, slot 2 (core) takes `color`.
## `kind` picks the shot (KINDS): a LASER flies along `direction` (straight
## up); a MISSILE is a smaller, darker laser that turns toward the nearest enemy
## (each peer steers its own copy; only the shooter's copy reports hits, so small
## differences don't matter); a VULCAN round (autocannon) is tiny, fast and weak,
## and fizzles after a short range. Damage can be a fraction of a hit; ships and
## enemies add up the fractions.

enum { LASER, MISSILE, VULCAN }
const KINDS: Array[Dictionary] = [
	{"speed": 420.0, "scale": 1.0, "damage": 1.0, "range": INF, "darken": 0.0, "light": 1.0},
	{"speed": 340.0, "scale": 0.6, "damage": 1.0, "range": INF, "darken": 0.5, "light": 0.5},
	{"speed": 900.0, "scale": 0.3, "damage": 0.25, "range": 200.0, "darken": 0.0, "light": 0.25},
]
const SPEED := 420.0  # laser
const HEIGHT := 44.0  # on-screen height in px
const RENDER_SCALE := 1.5  # SVG -> texture, sharper than 1:1 on high-DPI phones
const FRAMES := preload("res://assets/effects/bullet.tres")
const MISSILE_TURN := 4.0  # rad/s

@export var color := Color.YELLOW
var shooter := 0  # peer id that fired it
var direction := Vector2.UP
var kind := LASER
var _travelled := 0.0


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


static func frames_for(c: Color) -> SpriteFrames:
	return PaletteFrames.recolor(FRAMES, [Color.WHITE, c], RENDER_SCALE)


func damage() -> float:
	return KINDS[kind].damage


func is_seeking() -> bool:
	return kind == MISSILE


func max_range() -> float:
	return KINDS[kind].range


func is_mine() -> bool:
	return multiplayer.multiplayer_peer != null and shooter == multiplayer.get_unique_id()


func _physics_process(delta: float) -> void:
	var speed: float = KINDS[kind].speed
	if is_seeking():
		_steer(delta)
	position += direction * speed * delta
	_travelled += speed * delta
	var arena := Rect2(Vector2.ZERO, Vector2(540, 960)).grow(HEIGHT)
	if _travelled >= max_range() or not arena.has_point(position):
		queue_free()


## Nearest enemy, or null.
func seek_target() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.is_queued_for_deletion():
			continue
		var d := position.distance_squared_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _steer(delta: float) -> void:
	var target := seek_target()
	if target == null:
		return
	var want := direction.angle_to(target.position - position)
	direction = direction.rotated(clampf(want, -MISSILE_TURN * delta, MISSILE_TURN * delta))
	rotation = Vector2.UP.angle_to(direction)
