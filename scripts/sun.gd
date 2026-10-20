class_name Sun
## The global light: a spotlight in the ships' plane, just off the arena's top-left
## corner (LIGHT_DIR points from it toward the action). It lights ships and obstacles
## (Ships.LIGHT_MASK) through their normal maps, and everything that blocks light gets
## occluders (occlude), so ships and obstacles throw shadows onto each other. The
## background isn't lit by it, so nothing shades the background.
##
## Occluders cull their faces toward the light: only an outline's far side casts, so a
## piece's shadow starts where it ends and never darkens the piece itself.

const LIGHT_DIR := Vector2(1, 1) / sqrt(2.0)  # from the light: down and to the right on screen
const CORNER_OFFSET := 60.0  # px outside the arena's top-left corner, along -LIGHT_DIR
const SUN_HEIGHT := 120.0  # px over the plane: low, so light rakes across the pieces
const SUN_ENERGY := 1.0
const SUN_COLOR := Color(1.0, 0.96, 0.88)  # warm light
const SUN_REACH := 1600.0  # px its flat light covers from where it stands (the arena and margins)
const SHADE_ENERGY := 0.92  # the shade takes ships and obstacles down to ~8% out of the light: spooky
const SHADE_HEIGHT := 4096.0  # very high, so it subtracts evenly
const SHADOW_COLOR := Color(0, 0, 0, 0)  # shadowed: none of this light, the shade's dimming stays
const ALPHA_CUTOFF := 0.5  # texture alpha that blocks light
const SIMPLIFY := 1.5  # px tolerance when tracing an outline

static var _outlines := {}  # Texture2D -> Array[PackedVector2Array], texture px from the middle


## The light at `arena`'s top-left corner.
static func make(arena: Rect2) -> PointLight2D:
	var sun := PointLight2D.new()
	sun.name = "Sun"
	sun.position = arena.position - LIGHT_DIR * CORNER_OFFSET
	sun.height = SUN_HEIGHT
	sun.blend_mode = Light2D.BLEND_MODE_ADD
	sun.energy = SUN_ENERGY
	sun.color = SUN_COLOR
	sun.range_item_cull_mask = Ships.LIGHT_MASK
	sun.shadow_enabled = true
	sun.shadow_color = SHADOW_COLOR
	sun.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	sun.shadow_item_cull_mask = Ships.LIGHT_MASK
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color.WHITE)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 16
	tex.height = 16
	sun.texture = tex
	sun.texture_scale = SUN_REACH * 2.0 / tex.width
	return sun


## The shade: a SUB light dimming everything on Ships.LIGHT_MASK across `area` evenly, so
## only the sun (and bullet lights) bring color back. The game has its own (ShipShade).
static func make_shade(area: Rect2) -> PointLight2D:
	var shade := PointLight2D.new()
	shade.name = "ShipShade"
	shade.position = area.get_center()
	shade.height = SHADE_HEIGHT
	shade.blend_mode = Light2D.BLEND_MODE_SUB
	shade.energy = SHADE_ENERGY
	shade.range_item_cull_mask = Ships.LIGHT_MASK
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color.WHITE)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 16
	tex.height = 16
	shade.texture = tex
	shade.texture_scale = area.size.length() * 2.0 / tex.width
	return shade


## Makes `sprite` block the sun: one LightOccluder2D per opaque patch of its texture,
## as children, so they turn and scale with it. Set its texture and flips first.
static func occlude(sprite: Sprite2D) -> Array[LightOccluder2D]:
	var made: Array[LightOccluder2D] = []
	var flip := Vector2(-1.0 if sprite.flip_h else 1.0, -1.0 if sprite.flip_v else 1.0)
	for outline in outlines(sprite.texture):
		var points := PackedVector2Array()
		for p in outline:
			points.append(p * flip)
		if not Geometry2D.is_polygon_clockwise(points):
			points.reverse()
		var poly := OccluderPolygon2D.new()
		poly.polygon = points
		poly.cull_mode = OccluderPolygon2D.CULL_CLOCKWISE
		var o := LightOccluder2D.new()
		o.name = "Occluder"
		o.occluder = poly
		o.occluder_light_mask = Ships.LIGHT_MASK
		o.position = sprite.offset
		sprite.add_child(o)
		made.append(o)
	return made


## The opaque outlines of `tex` (cached), in px from its middle, wound clockwise on screen.
static func outlines(tex: Texture2D) -> Array:
	if tex == null:
		return []
	if _outlines.has(tex):
		return _outlines[tex]
	var src := tex
	if tex is CanvasTexture:
		src = (tex as CanvasTexture).diffuse_texture
	var img := src.get_image() if src else null
	var out: Array = []
	if img:
		if img.is_compressed():
			img.decompress()
		var mask := BitMap.new()
		mask.create_from_image_alpha(img, ALPHA_CUTOFF)
		var half := Vector2(img.get_size()) / 2.0
		for poly in mask.opaque_to_polygons(Rect2i(Vector2i.ZERO, img.get_size()), SIMPLIFY):
			var pts := PackedVector2Array()
			for p in poly:
				pts.append(p - half)
			if pts.size() < 3:
				continue
			if not Geometry2D.is_polygon_clockwise(pts):
				pts.reverse()
			out.append(pts)
	_outlines[tex] = out
	return out
