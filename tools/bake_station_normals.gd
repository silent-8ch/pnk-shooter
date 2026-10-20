extends SceneTree
## Offline normal-map baker for the station wreckage art. Run from the project root:
##   Godot --headless -s tools/bake_station_normals.gd
## Writes assets/obstacles/<id>_normal.png for each of PIECES, at the same pixel size as
## the imported texture (the SVG at scale 1), so Obstacle.lit_art's CanvasTexture lines up.
##
## Height field, in px, per piece (see PIECES):
##   round:  a rolled edge rising over `round` x the piece's thickest half-width (its
##           deepest distance from the edge); 1 = a full tube (the ring's band), less = a
##           thick slab with rounded sides (the solar panel).
##   dome:   adds the asteroids' sphere over the whole piece, rolled off at every edge
##           (the reactor: a domed module whose rings and stubs each stay rounded).
##   inset:  slots pressed INSET_DEPTH x the thickness in, with soft walls (the panel's
##           cells, the ring's windows).
## Then the ships' baker (bake_normals.gd) turns it into a tangent-space normal map
## (OpenGL style, green up), alpha = the piece's alpha.

const Baker := preload("res://tools/bake_normals.gd")
const Asteroids := preload("res://tools/bake_asteroid_normals.gd")

const PIECES := {
	"solar_panel": {"round": 0.5, "inset": [2]},
	"reactor": {"dome": true, "round": 0.4, "inset": []},
	"ring_arc": {"round": 1.0, "inset": [3, 4, 5, 6]},
}
const ART_DIR := "res://assets/obstacles/"
const INSET_DEPTH := 0.25  # of the thickness
const INSET_WALL := 1.5  # px over which an inset's wall slopes
const SMOOTH := 1  # box blur radius in px on the final height, against pixel stairs


func _init() -> void:
	for id in PIECES:
		var src: String = ART_DIR + id + ".svg"
		var out := normal_path(id)
		var img := bake(id, FileAccess.get_file_as_string(src))
		var err := img.save_png(ProjectSettings.globalize_path(out))
		print("%s -> %s %s (%s)" % [src, out, img.get_size(), error_string(err)])
	quit()


static func normal_path(id: String) -> String:
	return ART_DIR + id + "_normal.png"


## The full bake: normal map for piece `id`'s SVG rendered at scale 1.
static func bake(id: String, svg: String) -> Image:
	var slots: Dictionary = Baker.slot_map(svg, 1.0)
	var size: Vector2i = slots.size
	var h := height(PIECES[id], slots.slot, slots.alpha, size)
	return Baker.normal_map(h, slots.alpha, size)


static func height(profile: Dictionary, slot: PackedInt32Array, alpha: PackedFloat32Array,
		size: Vector2i) -> PackedFloat32Array:
	var edge := Baker.distance_to_empty(alpha, size)
	var thick := 1.0
	for d in edge:
		thick = maxf(thick, d)
	var r := maxf(1.0, thick * profile.round)
	var h := rounded(edge, alpha, r)
	if profile.get("dome", false):
		# The sphere, its every part rolled off at its own edges (rings, pipe stubs).
		var dome := Asteroids.sphere(alpha, size)
		for i in h.size():
			h[i] = dome[i] * h[i] / r + h[i]
	_inset(h, profile.inset, slot, alpha, size, thick)
	h = Baker.box_blur(h, size, SMOOTH)
	for i in h.size():
		if alpha[i] < Baker.EMPTY_ALPHA:
			h[i] = 0.0
	return h


## A quarter-circle roll from the edge up to height `r`, reached `r` px in; flat beyond.
static func rounded(edge: PackedFloat32Array, alpha: PackedFloat32Array, r: float) -> PackedFloat32Array:
	r = maxf(1.0, r)
	var h := PackedFloat32Array()
	h.resize(edge.size())
	for i in edge.size():
		if alpha[i] < Baker.EMPTY_ALPHA:
			continue
		var t := clampf(edge[i] / r, 0.0, 1.0)
		h[i] = sqrt(1.0 - (1.0 - t) * (1.0 - t)) * r
	return h


## Presses every pixel of `slots` in, sloping down over INSET_WALL px from its edge.
static func _inset(h: PackedFloat32Array, slots: Array, slot: PackedInt32Array,
		alpha: PackedFloat32Array, size: Vector2i, thick: float) -> void:
	if slots.is_empty():
		return
	var mask := PackedFloat32Array()
	mask.resize(slot.size())
	for i in slot.size():
		mask[i] = 1.0 if slot[i] in slots and alpha[i] >= Baker.EMPTY_ALPHA else 0.0
	var d := Baker.distance_to_empty(mask, size)
	var depth := thick * INSET_DEPTH
	for i in h.size():
		if mask[i] > 0.0:
			h[i] -= depth * clampf(d[i] / INSET_WALL, 0.0, 1.0)
