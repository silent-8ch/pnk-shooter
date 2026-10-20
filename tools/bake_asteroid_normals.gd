extends SceneTree
## Offline normal-map baker for the asteroid art. Run from the project root:
##   Godot --headless -s tools/bake_asteroid_normals.gd
## Writes assets/obstacles/<id>_normal.png for each of PIECES, at the same pixel size as
## the imported texture (the SVG at scale 1), so Obstacle.lit_art's CanvasTexture lines up.
##
## Height field, in px:
##   rock:    a sphere over the whole asteroid, so it reads very round: centered on the
##            silhouette's middle, its radius reaching the farthest edge, rounded off to
##            nothing over RIM of the radius at the lumpy edge.
##   craters: every slot 3 spot is a bowl pressed into the sphere, CRATER_DEPTH of its own
##            size deep at the middle, with a low raised lip (CRATER_LIP) just outside it.
## Then the ships' baker (bake_normals.gd) turns it into a tangent-space normal map
## (OpenGL style, green up), alpha = the asteroid's alpha.

const Baker := preload("res://tools/bake_normals.gd")

const PIECES: Array[String] = ["asteroid_s", "asteroid_m", "asteroid_l"]
const ART_DIR := "res://assets/obstacles/"
const CRATER_SLOT := 3
const RIM := 0.12  # of the sphere's radius: the edge falloff
const CRATER_DEPTH := 0.6  # bowl depth per px of the crater's own radius
const CRATER_LIP := 0.25  # lip height per px of the crater's radius ...
const CRATER_LIP_WIDTH := 0.5  # ... spread this far outside it, per px of its radius
const SMOOTH := 1  # box blur radius in px on the final height, against pixel stairs


func _init() -> void:
	for id in PIECES:
		var src := ART_DIR + id + ".svg"
		var out := normal_path(id)
		var img := bake(FileAccess.get_file_as_string(src))
		var err := img.save_png(ProjectSettings.globalize_path(out))
		print("%s -> %s %s (%s)" % [src, out, img.get_size(), error_string(err)])
	quit()


static func normal_path(id: String) -> String:
	return ART_DIR + id + "_normal.png"


## The full bake: normal map for an asteroid SVG rendered at scale 1.
static func bake(svg: String) -> Image:
	var slots: Dictionary = Baker.slot_map(svg, 1.0)
	var size: Vector2i = slots.size
	var h := height(slots.slot, slots.alpha, size)
	return Baker.normal_map(h, slots.alpha, size)


static func height(slot: PackedInt32Array, alpha: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var h := sphere(alpha, size)
	_add_craters(h, slot, alpha, size)
	h = Baker.box_blur(h, size, SMOOTH)
	for i in h.size():
		if alpha[i] < Baker.EMPTY_ALPHA:
			h[i] = 0.0
	return h


## A dome over the silhouette: a sphere centered on its middle, its radius reaching the
## farthest edge pixel, faded to 0 over RIM x the radius of the distance to the edge.
static func sphere(alpha: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var c := Vector2.ZERO
	var n := 0
	for y in size.y:
		for x in size.x:
			if alpha[y * size.x + x] >= Baker.EMPTY_ALPHA:
				c += Vector2(x, y)
				n += 1
	var h := PackedFloat32Array()
	h.resize(alpha.size())
	if n == 0:
		return h
	c /= n
	var radius := 0.0
	for y in size.y:
		for x in size.x:
			if alpha[y * size.x + x] >= Baker.EMPTY_ALPHA:
				radius = maxf(radius, c.distance_to(Vector2(x, y)))
	radius += 1.0
	var edge := Baker.distance_to_empty(alpha, size)
	var rim := maxf(1.0, radius * RIM)
	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			if alpha[i] < Baker.EMPTY_ALPHA:
				continue
			var r := c.distance_to(Vector2(x, y)) / radius
			h[i] = sqrt(maxf(0.0, 1.0 - r * r)) * radius * smoothstep(0.0, rim, edge[i])
	return h


## Presses a bowl (and raises a lip around it) for every connected patch of CRATER_SLOT.
static func _add_craters(h: PackedFloat32Array, slot: PackedInt32Array, alpha: PackedFloat32Array, size: Vector2i) -> void:
	var inside := PackedFloat32Array()  # 1 in a crater, 0 elsewhere: distance to its edge from inside
	var outside := PackedFloat32Array()  # the reverse: distance to the nearest crater from outside
	inside.resize(slot.size())
	outside.resize(slot.size())
	for i in slot.size():
		var crater := slot[i] == CRATER_SLOT and alpha[i] >= Baker.EMPTY_ALPHA
		inside[i] = 1.0 if crater else 0.0
		outside[i] = 0.0 if crater else 1.0
	var d_in := Baker.distance_to_empty(inside, size)
	var d_out := Baker.distance_to_empty(outside, size)
	var label := _components(inside, size)
	var radius := {}  # component -> its deepest distance from the edge (its own radius)
	for i in label.size():
		if label[i] >= 0:
			radius[label[i]] = maxf(radius.get(label[i], 0.0), d_in[i])
	var nearest := _nearest_crater_radius(label, radius, d_out, size)
	for i in h.size():
		if alpha[i] < Baker.EMPTY_ALPHA:
			continue
		if label[i] >= 0:
			var cr: float = maxf(1.0, radius[label[i]])
			var t := clampf(d_in[i] / cr, 0.0, 1.0)
			h[i] -= sqrt(1.0 - (1.0 - t) * (1.0 - t)) * cr * CRATER_DEPTH
		elif nearest[i] > 0.0:
			var w := nearest[i] * CRATER_LIP_WIDTH
			var u := clampf(d_out[i] / maxf(1.0, w), 0.0, 1.0)
			h[i] += (1.0 - u) * (1.0 - u) * nearest[i] * CRATER_LIP


## Connected patches (4-neighbour) of `mask` > 0: a label per pixel, -1 outside.
static func _components(mask: PackedFloat32Array, size: Vector2i) -> PackedInt32Array:
	var label := PackedInt32Array()
	label.resize(mask.size())
	label.fill(-1)
	var next := 0
	for start in mask.size():
		if mask[start] <= 0.0 or label[start] >= 0:
			continue
		var stack: Array[int] = [start]
		label[start] = next
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var x := i % size.x
			var y := i / size.x
			for nb in [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]:
				if nb[0] < 0 or nb[1] < 0 or nb[0] >= size.x or nb[1] >= size.y:
					continue
				var j: int = nb[1] * size.x + nb[0]
				if mask[j] > 0.0 and label[j] < 0:
					label[j] = next
					stack.append(j)
		next += 1
	return label


## For pixels outside the craters: the radius of the crater nearest them (0 if none is
## within reach of a lip), found by spreading each crater's radius outward.
static func _nearest_crater_radius(label: PackedInt32Array, radius: Dictionary,
		d_out: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(label.size())
	for i in label.size():
		r[i] = radius[label[i]] if label[i] >= 0 else 0.0
	# Two chamfer-style passes carry the radius along the distance field.
	for pass_dir in [1, -1]:
		var ys := range(size.y) if pass_dir == 1 else range(size.y - 1, -1, -1)
		var xs := range(size.x) if pass_dir == 1 else range(size.x - 1, -1, -1)
		for y in ys:
			for x in xs:
				var i: int = y * size.x + x
				if label[i] >= 0:
					continue
				for nb in [[x - pass_dir, y], [x, y - pass_dir]]:
					if nb[0] < 0 or nb[1] < 0 or nb[0] >= size.x or nb[1] >= size.y:
						continue
					var j: int = nb[1] * size.x + nb[0]
					if r[j] > 0.0 and d_out[j] <= d_out[i] and d_out[i] <= r[j] * CRATER_LIP_WIDTH + 1.0:
						r[i] = maxf(r[i], r[j])
	return r
