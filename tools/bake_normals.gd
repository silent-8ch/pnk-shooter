extends SceneTree
## Offline normal-map baker for the ship SVGs. Run from the project root:
##   Godot --headless -s tools/bake_normals.gd
## Writes each ship's Ships.LIST[i].normal PNG at the same pixel size as the runtime
## texture (ShipSkin.render at Ships.RENDER_SCALE), so CanvasTexture diffuse and normal line up.
##
## Height field: every pixel gets the height of the painted slot visible there (see
## SLOT_HEIGHTS), plus an edge bevel that rises with distance from the ship's silhouette.
## The field is lightly blurred and turned into a tangent-space normal map
## (OpenGL style, green = up), RGB = n * 0.5 + 0.5, alpha = the ship's alpha.

const ShipsScript := preload("res://scripts/ships.gd")
const ShipSkinScript := preload("res://scripts/ship_skin.gd")

## Base height per slot (index = slot - 1), 0 = flat background, 1 = highest.
const SLOT_HEIGHTS: Array[float] = [
	0.10,  # 1 outline: lowest, reads as a groove between parts
	0.45,  # 2 hull
	0.90,  # 3 glass: canopy bulges out
	0.30,  # 4 thrusters: recessed
	0.60,  # 5 accents
	0.40,  # 6 panels: slightly inset from the hull
	0.55,  # 7 trim
	0.35,  # 8 wings: thinner than the hull
	0.80,  # 9 nose
]
const BEVEL_PX := 4.0  # distance from the silhouette over which the bevel rises
const BEVEL_HEIGHT := 0.6  # extra height once fully inside the bevel
const EMPTY_ALPHA := 0.1  # pixels below this alpha count as empty space
const STRENGTH := 3.0  # height-gradient multiplier; higher = steeper normals


func _init() -> void:
	for ship in ShipsScript.LIST:
		var svg := FileAccess.get_file_as_string(ship.svg)
		var img := bake(svg, ShipsScript.RENDER_SCALE)
		var path: String = ProjectSettings.globalize_path(ship.normal)
		var err := img.save_png(path)
		print("%s -> %s %s (%s)" % [ship.svg, ship.normal, img.get_size(), error_string(err)])
	quit()


## The full bake: normal map for a painted SVG rendered at `scale`.
static func bake(svg: String, scale: float) -> Image:
	var slots := slot_map(svg, scale)
	var alpha: PackedFloat32Array = slots.alpha
	var size: Vector2i = slots.size
	var height := height_field(slots.slot, alpha, size)
	return normal_map(blur(height, size), alpha, size)


## Per-pixel visible slot (1-based, 0 = empty) and alpha. Renders the SVG once per slot with
## that slot white and the rest black; the slot with the most coverage at a pixel wins.
## Works like a label palette but antialiased edges cannot be misclassified.
static func slot_map(svg: String, scale: float) -> Dictionary:
	var n := ShipSkinScript.slot_count(svg)
	var size := Vector2i.ZERO
	var best := PackedFloat32Array()
	var slot := PackedInt32Array()
	var alpha := PackedFloat32Array()
	for k in range(1, n + 1):
		var palette: Array[Color] = []
		for i in n:
			palette.append(Color.WHITE if i == k - 1 else Color.BLACK)
		var img := Image.new()
		img.load_svg_from_string(ShipSkinScript.apply_palette(svg, palette), scale)
		img.convert(Image.FORMAT_RGBA8)
		if k == 1:
			size = img.get_size()
			best.resize(size.x * size.y)
			best.fill(0.0)
			slot.resize(size.x * size.y)
			slot.fill(0)
			alpha.resize(size.x * size.y)
		for y in size.y:
			for x in size.x:
				var c := img.get_pixel(x, y)
				var i := y * size.x + x
				alpha[i] = c.a
				if c.a >= EMPTY_ALPHA and c.r > best[i]:
					best[i] = c.r
					slot[i] = k
	# Opaque pixels no slot claims (e.g. unpainted shapes) count as hull.
	for i in slot.size():
		if alpha[i] >= EMPTY_ALPHA and slot[i] == 0:
			slot[i] = 2
	return {"slot": slot, "alpha": alpha, "size": size}


## Slot height plus a bevel that grows with distance from empty pixels (and the image border).
static func height_field(slot: PackedInt32Array, alpha: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var dist := distance_to_empty(alpha, size)
	var h := PackedFloat32Array()
	h.resize(slot.size())
	for i in slot.size():
		if slot[i] == 0:
			h[i] = 0.0
			continue
		var t := smoothstep(0.0, BEVEL_PX, dist[i])
		h[i] = SLOT_HEIGHTS[slot[i] - 1] + BEVEL_HEIGHT * t
	return h


## Chamfer distance (1, sqrt 2) from each pixel to the nearest empty pixel; empty = 0.
static func distance_to_empty(alpha: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(alpha.size())
	for i in alpha.size():
		d[i] = 0.0 if alpha[i] < EMPTY_ALPHA else INF
	var diag := sqrt(2.0)
	# Forward pass (top-left neighbors), then backward (bottom-right). Out of bounds = empty.
	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			if d[i] == 0.0:
				continue
			var v := d[i]
			v = minf(v, (d[i - 1] if x > 0 else 0.0) + 1.0)
			v = minf(v, (d[i - size.x] if y > 0 else 0.0) + 1.0)
			v = minf(v, (d[i - size.x - 1] if x > 0 and y > 0 else 0.0) + diag)
			v = minf(v, (d[i - size.x + 1] if x < size.x - 1 and y > 0 else 0.0) + diag)
			d[i] = v
	for y in range(size.y - 1, -1, -1):
		for x in range(size.x - 1, -1, -1):
			var i := y * size.x + x
			if d[i] == 0.0:
				continue
			var v := d[i]
			v = minf(v, (d[i + 1] if x < size.x - 1 else 0.0) + 1.0)
			v = minf(v, (d[i + size.x] if y < size.y - 1 else 0.0) + 1.0)
			v = minf(v, (d[i + size.x + 1] if x < size.x - 1 and y < size.y - 1 else 0.0) + diag)
			v = minf(v, (d[i + size.x - 1] if x > 0 and y < size.y - 1 else 0.0) + diag)
			d[i] = v
	return d


## 3x3 box blur, clamped at the border.
static func blur(h: PackedFloat32Array, size: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(h.size())
	for y in size.y:
		for x in size.x:
			var sum := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					sum += _at(h, size, x + dx, y + dy)
			out[y * size.x + x] = sum / 9.0
	return out


## Central-difference normals. Image y runs down but the map is green-up, so dh/dy flips sign.
static func normal_map(h: PackedFloat32Array, alpha: PackedFloat32Array, size: Vector2i) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			var dx := (_at(h, size, x + 1, y) - _at(h, size, x - 1, y)) * 0.5
			var dy := (_at(h, size, x, y + 1) - _at(h, size, x, y - 1)) * 0.5
			var n := Vector3(-dx * STRENGTH, dy * STRENGTH, 1.0).normalized()
			if alpha[i] < EMPTY_ALPHA:
				n = Vector3(0, 0, 1)
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, alpha[i]))
	return img


static func _at(h: PackedFloat32Array, size: Vector2i, x: int, y: int) -> float:
	return h[clampi(y, 0, size.y - 1) * size.x + clampi(x, 0, size.x - 1)]
