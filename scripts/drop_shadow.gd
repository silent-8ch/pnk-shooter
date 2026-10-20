class_name DropShadow
extends Sprite2D
## The global light: one sun, up and to the left of the arena (LIGHT_DIR points
## from it toward the action). It lights the ships (make_sun: a light far off
## along -LIGHT_DIR, so its rays are near parallel and their normal maps shade
## them bright on the side facing it, dark on the other), and everything that
## casts a shadow gets a DropShadow:
## a flat dark copy of its sprite, drawn behind it and pushed away from the light
## by OFFSET x `height` screen px, whichever way the sprite turns, flips or scales.
## Unlit itself (light_mask 0), and it follows its sprite's texture, frame and
## flips every frame. Cosmetic and local on every peer.

const LIGHT_DIR := Vector2(1, 1) / sqrt(2.0)  # from the light: down and to the right on screen
const OFFSET := 12.0  # px a shadow falls at height 1 (a ship)
const COLOR := Color(0, 0, 0, 0.6)
const SHIP_HEIGHT := 1.0
const OBSTACLE_HEIGHT := 0.6  # rocks and wreckage drift lower than the ships
const SUN_DISTANCE := 4000.0  # px from the arena's middle, up and left along -LIGHT_DIR
const SUN_ELEVATION := deg_to_rad(40.0)  # how high the sun stands over the arena
const SUN_ENERGY := 1.0
const SUN_COLOR := Color(1.0, 0.96, 0.88)  # warm sunlight
const SUN_REACH := 1200.0  # px past the arena's middle its light still covers (spawn margins)

var height := SHIP_HEIGHT


## A shadow for `sprite` at `h` (see SHIP_HEIGHT, OBSTACLE_HEIGHT), added as its child.
static func attach(sprite: Sprite2D, h: float = SHIP_HEIGHT) -> DropShadow:
	var s := DropShadow.new()
	s.name = "Shadow"
	s.height = h
	sprite.add_child(s)
	return s


## The sun: an additive light on the ships only (Ships.LIGHT_MASK), far off up and left of
## `center` along -LIGHT_DIR and SUN_ELEVATION up, with a flat texture big enough to reach
## past the whole arena. Not a DirectionalLight2D (see Game: the Compatibility renderer
## ignores its cull mask).
static func make_sun(center: Vector2) -> PointLight2D:
	var sun := PointLight2D.new()
	sun.name = "Sun"
	sun.position = center - LIGHT_DIR * SUN_DISTANCE
	sun.height = SUN_DISTANCE * tan(SUN_ELEVATION)
	sun.blend_mode = Light2D.BLEND_MODE_ADD
	sun.energy = SUN_ENERGY
	sun.color = SUN_COLOR
	sun.range_item_cull_mask = Ships.LIGHT_MASK
	sun.shadow_enabled = false
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color.WHITE)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 16
	tex.height = 16
	sun.texture = tex
	sun.texture_scale = (SUN_DISTANCE + SUN_REACH) * 2.0 / tex.width
	return sun


func _ready() -> void:
	show_behind_parent = true
	light_mask = 0
	modulate = COLOR
	_follow()


func _process(_delta: float) -> void:
	_follow()


## Where the shadow falls, in screen px from what casts it.
func world_offset() -> Vector2:
	return LIGHT_DIR * OFFSET * height


func _follow() -> void:
	var src := get_parent() as Sprite2D
	if src == null:
		return
	texture = src.texture
	region_enabled = src.region_enabled
	region_rect = src.region_rect
	hframes = src.hframes
	vframes = src.vframes
	frame = src.frame
	centered = src.centered
	offset = src.offset
	flip_h = src.flip_h
	flip_v = src.flip_v
	# The parent's transform turns and scales a child, so undo it: the offset stays
	# the same on screen however the sprite is rotated, flipped or sized.
	position = src.global_transform.affine_inverse().basis_xform(world_offset())
