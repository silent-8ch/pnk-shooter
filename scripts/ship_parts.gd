class_name ShipParts
## Breaks a painted ship SVG into separate piece textures for wreck effects.
##
## The ship is rendered once with its palette and once with a "label" palette
## (a distinct flat color per slot) to find which slot each pixel belongs to.
## Connected regions of the same slot become parts; outline pixels (slot 1)
## join the nearest part; small parts merge into the neighbor they share the
## most border with until at most max_pieces remain (analyze()). crack() then
## splits the largest parts along jagged lines into shards, and pieces() crops
## each part into its own texture with its offset from the ship's center.

const OUTLINE_SLOT := 1
const ALPHA_MIN := 26  # of 255


## Renders and labels a ship. Returns {} on failure, else
## {image: Image, w, h, comp: PackedInt32Array (part id per pixel, -1 = empty)}.
static func analyze(svg: String, colors: Array[Color], scale: float, max_pieces: int, min_area: int) -> Dictionary:
	var img := Image.new()
	if img.load_svg_from_string(ShipSkin.apply_palette(svg, colors), scale) != OK:
		return {}
	var n_slots := maxi(ShipSkin.slot_count(svg), 1)
	var label_img := Image.new()
	if label_img.load_svg_from_string(ShipSkin.apply_palette(svg, label_colors(n_slots)), scale) != OK:
		return {}
	img.convert(Image.FORMAT_RGBA8)
	label_img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var slots := _label_slots(img.get_data(), label_img.get_data(), w * h, n_slots)
	var comp := _components(slots, w, h)
	_absorb_unassigned(comp, slots, w, h)
	_merge_small(comp, w, h, max_pieces, min_area)
	return {"image": img, "w": w, "h": h, "comp": comp}


## Analyzes, cracks `shards` of the largest parts, and builds the pieces.
static func split(svg: String, colors: Array[Color], scale: float, max_pieces: int,
		min_area: int, shards: int, rng_seed: int) -> Array[Dictionary]:
	var a := analyze(svg, colors, scale, max_pieces, min_area)
	if a.is_empty():
		return []
	return pieces(a, crack(a, shards, rng_seed))


## Distinct flat colors used to identify slots in the label render.
static func label_colors(n: int) -> Array[Color]:
	var out: Array[Color] = []
	for i in n:
		out.append(Color.from_hsv(float(i) / n, 1.0, 1.0 if i % 2 == 0 else 0.55))
	return out


# Per pixel: -1 transparent, else the 1-based slot whose label color is nearest.
static func _label_slots(rgba: PackedByteArray, labels: PackedByteArray, n: int, n_slots: int) -> PackedInt32Array:
	var pal := PackedInt32Array()
	for c in label_colors(n_slots):
		pal.append(c.r8)
		pal.append(c.g8)
		pal.append(c.b8)
	var out := PackedInt32Array()
	out.resize(n)
	for i in n:
		var o := i * 4
		if rgba[o + 3] < ALPHA_MIN:
			out[i] = -1
			continue
		var r := labels[o]
		var g := labels[o + 1]
		var b := labels[o + 2]
		var best := 0
		var best_d := 1 << 30
		for k in n_slots:
			var dr := r - pal[k * 3]
			var dg := g - pal[k * 3 + 1]
			var db := b - pal[k * 3 + 2]
			var d := dr * dr + dg * dg + db * db
			if d < best_d:
				best_d = d
				best = k
		out[i] = best + 1
	return out


# Connected regions (4-neighbour) of the same non-outline slot. -1 = none yet.
static func _components(slots: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var n := w * h
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var stack := PackedInt32Array()
	var next := 0
	for start in n:
		var s := slots[start]
		if s <= OUTLINE_SLOT or comp[start] != -1:
			continue
		comp[start] = next
		stack.append(start)
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var x := i % w
			if x > 0 and comp[i - 1] == -1 and slots[i - 1] == s:
				comp[i - 1] = next
				stack.append(i - 1)
			if x < w - 1 and comp[i + 1] == -1 and slots[i + 1] == s:
				comp[i + 1] = next
				stack.append(i + 1)
			if i >= w and comp[i - w] == -1 and slots[i - w] == s:
				comp[i - w] = next
				stack.append(i - w)
			if i < n - w and comp[i + w] == -1 and slots[i + w] == s:
				comp[i + w] = next
				stack.append(i + w)
		next += 1
	return comp


# Outline and other unassigned opaque pixels join the nearest part (BFS).
static func _absorb_unassigned(comp: PackedInt32Array, slots: PackedInt32Array, w: int, h: int) -> void:
	var n := w * h
	var queue := PackedInt32Array()
	for i in n:
		if comp[i] != -1:
			queue.append(i)
	if queue.is_empty():
		for i in n:  # nothing but outline: the whole ship is one part
			if slots[i] != -1:
				comp[i] = 0
		return
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var c := comp[i]
		var x := i % w
		# 8-neighbour so diagonal-only pixels are reached too.
		for dy in [-w, 0, w]:
			for dx in [-1, 0, 1]:
				if (dx == -1 and x == 0) or (dx == 1 and x == w - 1):
					continue
				var j: int = i + dy + dx
				if j >= 0 and j < n and comp[j] == -1 and slots[j] != -1:
					comp[j] = c
					queue.append(j)


# Merges the smallest part into the neighbour it shares the most border with,
# until every part is >= min_area and there are at most max_pieces. Works on
# a part adjacency graph built in one pass, then relabels pixels once.
static func _merge_small(comp: PackedInt32Array, w: int, h: int, max_pieces: int, min_area: int) -> void:
	var n := w * h
	var area := {}  # id -> px
	var sum := {}  # id -> Vector2 (for centroids)
	var border := {}  # id -> {other id -> shared edges}
	for i in n:
		var a := comp[i]
		if a == -1:
			continue
		area[a] = area.get(a, 0) + 1
		sum[a] = sum.get(a, Vector2.ZERO) + Vector2(i % w, i / w)
		if not border.has(a):
			border[a] = {}
		if i % w < w - 1:
			_count_edge(border, a, comp[i + 1])
		if i < n - w:
			_count_edge(border, a, comp[i + w])
	var parent := {}
	for id in area:
		parent[id] = id
	while area.size() > 1:
		var smallest := -1
		for id in area:
			if smallest == -1 or area[id] < area[smallest]:
				smallest = id
		if area.size() <= max_pieces and area[smallest] >= min_area:
			break
		var target := -1
		var edges: Dictionary = border[smallest]
		for id in edges:
			if target == -1 or edges[id] > edges[target]:
				target = id
		if target == -1:  # isolated: join the part with the nearest centroid
			var c: Vector2 = sum[smallest] / area[smallest]
			for id in area:
				if id != smallest and (target == -1 or c.distance_squared_to(sum[id] / area[id]) < c.distance_squared_to(sum[target] / area[target])):
					target = id
		# Fold smallest into target.
		area[target] += area[smallest]
		sum[target] += sum[smallest]
		for other in edges:
			if other == target:
				continue
			var e: int = edges[other]
			border[target][other] = border[target].get(other, 0) + e
			border[other][target] = border[other].get(target, 0) + e
			border[other].erase(smallest)
		border[target].erase(smallest)
		border.erase(smallest)
		area.erase(smallest)
		sum.erase(smallest)
		parent[smallest] = target
	for i in n:
		if comp[i] != -1:
			comp[i] = _find(parent, comp[i])


static func _count_edge(border: Dictionary, a: int, b: int) -> void:
	if b == -1 or b == a:
		return
	border[a][b] = border[a].get(b, 0) + 1
	if not border.has(b):
		border[b] = {}
	border[b][a] = border[b].get(a, 0) + 1


static func _find(parent: Dictionary, id: int) -> int:
	while parent[id] != id:
		id = parent[id]
	return id


## Copy of the analysis' part map with the `count` largest parts split in two
## along a jagged line through their center.
static func crack(a: Dictionary, count: int, rng_seed: int) -> PackedInt32Array:
	var w: int = a.w
	var n: int = a.w * a.h
	var comp: PackedInt32Array = a.comp.duplicate()
	if count <= 0:
		return comp
	var area := {}
	var sum := {}
	var max_id := -1
	for i in n:
		var id := comp[i]
		if id != -1:
			area[id] = area.get(id, 0) + 1
			sum[id] = sum.get(id, Vector2.ZERO) + Vector2(i % w, i / w)
			max_id = maxi(max_id, id)
	var ids := area.keys()
	ids.sort_custom(func(x, y): return area[x] > area[y])
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for k in mini(count, ids.size()):
		var id: int = ids[k]
		var center: Vector2 = sum[id] / area[id]
		var normal := Vector2.from_angle(rng.randf() * TAU)
		var along := normal.orthogonal()
		var freq := rng.randf_range(0.25, 0.5)
		var amp := rng.randf_range(2.0, 4.0)
		var phase := rng.randf() * TAU
		max_id += 1
		for i in n:
			if comp[i] != id:
				continue
			var p := Vector2(i % w, i / w) - center
			# Triangle-wave jitter along the cut makes a jagged crack.
			var jag := amp * (absf(fposmod(p.dot(along) * freq + phase, 2.0) - 1.0) * 2.0 - 1.0)
			if p.dot(normal) + jag > 0.0:
				comp[i] = max_id
	return comp


## Crops each part into a texture.
## Returns [{texture: Texture2D, offset: Vector2 (px from image center), area: int}].
static func pieces(a: Dictionary, comp: PackedInt32Array) -> Array[Dictionary]:
	var w: int = a.w
	var h: int = a.h
	var src: PackedByteArray = (a.image as Image).get_data()
	var rects := {}  # id -> [min_x, min_y, max_x, max_y]
	var area := {}
	for i in w * h:
		var id := comp[i]
		if id == -1:
			continue
		var x := i % w
		var y := i / w
		if rects.has(id):
			var r: Array = rects[id]
			r[0] = mini(r[0], x)
			r[1] = mini(r[1], y)
			r[2] = maxi(r[2], x)
			r[3] = maxi(r[3], y)
		else:
			rects[id] = [x, y, x, y]
		area[id] = area.get(id, 0) + 1
	var center := Vector2(w, h) / 2.0
	var out: Array[Dictionary] = []
	for id in rects:
		var r: Array = rects[id]
		var pw: int = r[2] - r[0] + 1
		var ph: int = r[3] - r[1] + 1
		var data := PackedByteArray()
		data.resize(pw * ph * 4)  # zero = transparent
		for y in ph:
			for x in pw:
				var si: int = (r[1] + y) * w + r[0] + x
				if comp[si] == id:
					var so := si * 4
					var d := (y * pw + x) * 4
					data[d] = src[so]
					data[d + 1] = src[so + 1]
					data[d + 2] = src[so + 2]
					data[d + 3] = src[so + 3]
		var img := Image.create_from_data(pw, ph, false, Image.FORMAT_RGBA8, data)
		out.append({
			"texture": ImageTexture.create_from_image(img),
			"offset": Vector2(r[0], r[1]) + Vector2(pw, ph) / 2.0 - center,
			"area": area[id],
		})
	return out


## Where each separate region of `slot` sits: [{pos: Vector2 (bottom center,
## px from image center), width: float (px)}], left to right. Used to place
## engine flames under the thrusters.
static func slot_anchors(svg: String, slot: int, scale: float) -> Array[Dictionary]:
	var n_slots := maxi(ShipSkin.slot_count(svg), 1)
	var colors := label_colors(n_slots)
	var img := Image.new()
	if img.load_svg_from_string(ShipSkin.apply_palette(svg, colors), scale) != OK:
		return []
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var slots := _label_slots(data, data, w * h, n_slots)
	var only := PackedInt32Array()
	only.resize(w * h)
	for i in w * h:
		only[i] = slots[i] if slots[i] == slot else -1
	var comp := _components(only, w, h)
	var bounds := {}  # id -> [min_x, max_x, max_y]
	for i in w * h:
		var id := comp[i]
		if id == -1:
			continue
		var x := i % w
		var y := i / w
		if bounds.has(id):
			var b: Array = bounds[id]
			b[0] = mini(b[0], x)
			b[1] = maxi(b[1], x)
			b[2] = maxi(b[2], y)
		else:
			bounds[id] = [x, x, y]
	var center := Vector2(w, h) / 2.0
	var out: Array[Dictionary] = []
	for id in bounds:
		var b: Array = bounds[id]
		var width: float = b[1] - b[0] + 1
		if width < 3.0:
			continue  # anti-aliasing specks
		out.append({"pos": Vector2((b[0] + b[1] + 1) / 2.0, b[2] + 1) - center, "width": width})
	# A region stacked above a lower one (e.g. a nozzle ring over a nozzle) is
	# not a separate exhaust: keep only the lowest region in each column.
	var kept: Array[Dictionary] = []
	for a in out:
		var covered := false
		for o in out:
			if o != a and o.pos.y > a.pos.y and absf(o.pos.x - a.pos.x) < o.width / 2.0:
				covered = true
		if not covered:
			kept.append(a)
	kept.sort_custom(func(x, y): return x.pos.x < y.pos.x)
	return kept
