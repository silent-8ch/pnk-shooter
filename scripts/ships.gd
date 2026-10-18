extends Node
## Ship registry autoload: available ships, named color palettes, and the local
## player's choices (ship + palette per ship), persisted to user://.

const SHIP_HEIGHT := 44.0  # on-screen height in px, regardless of texture size
const RENDER_SCALE := 0.2  # SVG -> texture scale, matches the import settings
const SETTINGS_PATH := "user://settings.cfg"
const LIGHT_MASK := 2  # light_mask bit for ship bodies; ship lights cull to this bit only

const LIST: Array[Dictionary] = [
	{"name": "Ship 01", "svg": "res://assets/ship01.svg", "normal": "res://assets/ship01_normal.png"},
	{"name": "Ship 02", "svg": "res://assets/ship02.svg", "normal": "res://assets/ship02_normal.png"},
	{"name": "Ship 03", "svg": "res://assets/ship03.svg", "normal": "res://assets/ship03_normal.png"},
	{"name": "Ship 04", "svg": "res://assets/ship04.svg", "normal": "res://assets/ship04_normal.png"},
	{"name": "Ship 05", "svg": "res://assets/ship05.svg", "normal": "res://assets/ship05_normal.png"},
]

## Slot order: 1 outline, 2 hull, 3 glass, 4 thrusters, 5 accents, 6 panels,
## 7 trim, 8 wings, 9 nose. An empty colors array means the ship's painted colors.
const PALETTES: Array[Dictionary] = [
	{"name": "Factory", "colors": [
		Color("e6e8eb"), Color("4a4f57"), Color("bfe3f2"), Color("8c939c"), Color("d0d4d9"),
		Color("b8bec6"), Color("ffffff"), Color("5d636b"), Color("9aa1aa")]},
	{"name": "Ember", "colors": [
		Color("fff1e0"), Color("c0392b"), Color("ffd27a"), Color("ff8c1a"), Color("ffb347"),
		Color("8b1e1e"), Color("ff5e3a"), Color("e2582a"), Color("ffe066")]},
	{"name": "Arctic", "colors": [
		Color("ffffff"), Color("a8d8f0"), Color("e8fbff"), Color("5fb4e6"), Color("d4f1ff"),
		Color("3a7cc2"), Color("9fc9e8"), Color("2f5f9e"), Color("7fe0ff")]},
	{"name": "Toxic", "colors": [
		Color("d8ff5a"), Color("1a1f14"), Color("7dff3a"), Color("b6ff00"), Color("39ff14"),
		Color("2e4d1a"), Color("9cff57"), Color("3d5c1f"), Color("e5ff00")]},
	{"name": "Midnight", "colors": [
		Color("c9c3ff"), Color("1b1446"), Color("8a7dff"), Color("4b2c91"), Color("6a5acd"),
		Color("2a1a5e"), Color("9370db"), Color("120c33"), Color("c77dff")]},
	{"name": "Gold Rush", "colors": [
		Color("fff6d5"), Color("b8860b"), Color("ffe9a0"), Color("ffd700"), Color("8b5a2b"),
		Color("6b4423"), Color("daa520"), Color("a0522d"), Color("fff1a8")]},
	{"name": "Neon", "colors": [
		Color("ffffff"), Color("1a0b2e"), Color("00f0ff"), Color("ff2bd6"), Color("00f0ff"),
		Color("2d0f4a"), Color("ff2bd6"), Color("3a145e"), Color("39ffea")]},
	{"name": "Stealth", "colors": [
		Color("9aa0a6"), Color("1c1d20"), Color("3b4a55"), Color("5a5f66"), Color("44484e"),
		Color("2a2c30"), Color("6b7077"), Color("141518"), Color("80868d")]},
	{"name": "Sunset", "colors": [
		Color("ffe8d6"), Color("6a2c70"), Color("ffc15e"), Color("ff7b39"), Color("f08a5d"),
		Color("3f1d4a"), Color("b83b5e"), Color("8e3c76"), Color("ffb26b")]},
	{"name": "Ocean", "colors": [
		Color("e0fbfc"), Color("0b2545"), Color("98f5e1"), Color("1fa2a6"), Color("3ddbd9"),
		Color("13315c"), Color("2ec4b6"), Color("134074"), Color("8de4ff")]},
	{"name": "Rose", "colors": [
		Color("ffffff"), Color("f4a6c1"), Color("fff0f5"), Color("ff6f91"), Color("ffd1dc"),
		Color("e07a9f"), Color("ffffff"), Color("d6648f"), Color("ffc2d4")]},
	{"name": "Camo", "colors": [
		Color("e6dfc8"), Color("4b5320"), Color("c2b280"), Color("8a7f5a"), Color("a39b6d"),
		Color("3b4219"), Color("d2c29d"), Color("5c6b2f"), Color("7c6f45")]},
]

## Enemy-only palettes, one per ship index. Same slot order; not selectable.
const ENEMY_PALETTES: Array[Dictionary] = [
	{"name": "Crimson", "colors": [
		Color("ffd6d6"), Color("8b0000"), Color("ff9c9c"), Color("ff3b30"), Color("ff6b6b"),
		Color("5c0a0a"), Color("d7263d"), Color("a4161a"), Color("ff4d6d")]},
	{"name": "Inferno", "colors": [
		Color("ffe0d0"), Color("3d0b0b"), Color("ff7a59"), Color("ff1e00"), Color("e63946"),
		Color("2b0505"), Color("ff5733"), Color("7a0f0f"), Color("ffb4a2")]},
	{"name": "Blood Orange", "colors": [
		Color("ffe8d0"), Color("7a2e0a"), Color("ffb26b"), Color("ff6a00"), Color("ff8c42"),
		Color("4a1a05"), Color("e85d04"), Color("9c3b0d"), Color("ffc078")]},
	{"name": "Rust", "colors": [
		Color("f5d6c6"), Color("5e2a1c"), Color("e8a07a"), Color("c1440e"), Color("d9764a"),
		Color("3b1a10"), Color("b5523b"), Color("7a3424"), Color("f0b090")]},
	{"name": "Magma", "colors": [
		Color("fff0c9"), Color("400a0a"), Color("ffcc33"), Color("ff3300"), Color("ff9900"),
		Color("260505"), Color("ff6600"), Color("661111"), Color("ffe066")]},
]

## Enemy colors climb this ramp as the stage goes up (stage 0 uses the
## per-ship ENEMY_PALETTES above); past the end it starts over and the ships
## pulse (see enemy_glows()). Built from the Crimson palette, hue-shifted.
const ENEMY_STAGE_HUES: Array[float] = [0.33, 0.78, 0.55, 0.13]  # toxic green, violet, ice blue, gold
const ENEMY_STAGE_NAMES: Array[String] = ["Toxic Green", "Violet", "Ice Blue", "Gold", "Obsidian"]

const THRUSTER_SLOT := 4
const ENEMY_PART_VARIANTS := 4  # precomputed crack patterns per enemy ship
const ENEMY_PART_MAX := 7  # max parts before cracking
const ENEMY_PART_MIN_AREA := 120  # px at RENDER_SCALE; smaller parts merge

signal selection_changed(index: int)

var selected := 0
var _palette_by_ship := {}  # ship index -> palette index
var _svg_cache := {}  # ship index -> SVG text
var _texture_cache := {}  # "ship:palette" -> Texture2D
var _parts_cache := {}  # "ship:variant" -> Array[Dictionary]
var _analysis_cache := {}  # ship -> ShipParts.analyze() result
var _thruster_cache := {}  # ship -> get_thrusters() result
var _lit_cache := {}  # "ship:palette" / "enemy:ship[:stage]" -> CanvasTexture
var _hit_cache := {}  # ship -> hit polygons (see hit_polygons)


func _ready() -> void:
	load_selection()


# --- Ships -----------------------------------------------------------------

func count() -> int:
	return LIST.size()


func is_valid(index: int) -> bool:
	return index >= 0 and index < LIST.size()


func clamp_index(index: int) -> int:
	return index if is_valid(index) else 0


func get_name_of(index: int) -> String:
	return LIST[clamp_index(index)].name


func get_svg(index: int) -> String:
	index = clamp_index(index)
	if not _svg_cache.has(index):
		_svg_cache[index] = FileAccess.get_file_as_string(LIST[index].svg)
	return _svg_cache[index]


## The ship rendered with a palette. palette < 0 uses the ship's saved palette.
func get_texture(index: int, palette: int = -1) -> Texture2D:
	index = clamp_index(index)
	palette = palette_for(index) if palette < 0 else clamp_palette(palette)
	return _render_cached("%d:%d" % [index, palette], index, get_palette_colors(index, palette))


## The ship rendered in its enemy palette for `stage` (see enemy_colors).
func get_enemy_texture(index: int, stage := 0) -> Texture2D:
	index = clamp_index(index)
	return _render_cached(_enemy_key(index, stage), index, enemy_colors(index, stage))


## Cache key of an enemy look: stage 0 and every stage that loops back to it share one.
func _enemy_key(index: int, stage: int) -> String:
	var step := enemy_color_step(stage)
	return "enemy:%d" % index if step == 0 else "enemy:%d:s%d" % [index, step]


## Where `stage` is on the color ramp: 0 = the per-ship reds, 1.. = ENEMY_STAGE_NAMES.
static func enemy_color_step(stage: int) -> int:
	return posmod(stage, ENEMY_STAGE_NAMES.size() + 1)


## Past the end of the ramp (it has looped), enemies pulse.
static func enemy_glows(stage: int) -> bool:
	return stage > ENEMY_STAGE_NAMES.size()


## The 9 slot colors of an enemy ship at `stage`.
static func enemy_colors(index: int, stage := 0) -> Array[Color]:
	var base: Array = ENEMY_PALETTES[index % ENEMY_PALETTES.size()].colors
	var step := enemy_color_step(stage)
	var out: Array[Color] = []
	for c: Color in base:
		if step == 0:
			out.append(c)
		elif step <= ENEMY_STAGE_HUES.size():
			out.append(Color.from_hsv(ENEMY_STAGE_HUES[step - 1], c.s, c.v, c.a))
		else:  # Obsidian: near black, the brightest parts glow red
			out.append(Color.from_hsv(0.0, 0.9, 1.0, c.a) if c.v > 0.95 and c.s > 0.5 else Color.from_hsv(0.0, c.s * 0.4, c.v * 0.22, c.a))
	return out


## Hit outline of a ship, traced from its art's alpha at RENDER_SCALE: polygons
## in texture pixels, centered like the sprite. Scale them by the sprite's scale.
func hit_polygons(index: int) -> Array[PackedVector2Array]:
	index = clamp_index(index)
	if not _hit_cache.has(index):
		var out: Array[PackedVector2Array] = []
		var img := Image.new()
		if img.load_svg_from_string(get_svg(index), RENDER_SCALE) == OK:
			var bits := BitMap.new()
			bits.create_from_image_alpha(img, 0.5)
			var half := Vector2(img.get_size()) / 2.0
			for poly in bits.opaque_to_polygons(Rect2i(Vector2i.ZERO, img.get_size()), 1.0):
				if poly.size() < 3 or absf(_area(poly)) < 4.0:
					continue
				var centered := PackedVector2Array()
				for v in poly:
					centered.append(v - half)
				out.append(centered)
		_hit_cache[index] = out
	return _hit_cache[index]


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a / 2.0


## Swaps `area`'s collision shapes for the outline of ship `index`, drawn by
## `sprite` (its scale and flip). Keeps the old shapes if the art has no outline.
func apply_hitbox(area: CollisionObject2D, index: int, sprite: Sprite2D) -> void:
	var polys := hit_polygons(index)
	if polys.is_empty():
		return
	for c in area.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			area.remove_child(c)
			c.free()
	var k := Vector2(sprite.scale.x, -sprite.scale.y if sprite.flip_v else sprite.scale.y)
	for poly in polys:
		var shape := CollisionPolygon2D.new()
		shape.name = "Hit"
		var pts := PackedVector2Array()
		for v in poly:
			pts.append(v * k + sprite.position)
		shape.polygon = pts
		area.add_child(shape)


## Pieces of the enemy-palette ship for wreck effects (see ShipParts.split),
## in the same pixel scale as get_enemy_texture(). `variant` picks one of
## ENEMY_PART_VARIANTS precomputed crack patterns.
func get_enemy_parts(index: int, variant: int, stage := 0) -> Array[Dictionary]:
	index = clamp_index(index)
	variant = posmod(variant, ENEMY_PART_VARIANTS)
	var look := _enemy_key(index, stage)
	var key := "%s:%d" % [look, variant]
	if not _parts_cache.has(key):
		if not _analysis_cache.has(look):
			_analysis_cache[look] = ShipParts.analyze(get_svg(index), enemy_colors(index, stage), RENDER_SCALE,
					ENEMY_PART_MAX, ENEMY_PART_MIN_AREA)
		var a: Dictionary = _analysis_cache[look]
		var parts: Array[Dictionary] = []
		if not a.is_empty():
			var shards := 1 + variant % 2  # crack one or two of the largest parts
			parts = ShipParts.pieces(a, ShipParts.crack(a, shards, variant + 1))
		_parts_cache[key] = parts
	return _parts_cache[key]


## Exhaust points of the ship's thrusters (slot 4), for engine flames:
## [{pos: Vector2 (px from texture center), width: float (px)}]. Only slot-4
## paint in the lower half counts: flames trail behind the ship, so thruster
## color painted up front is just color. A ship can have none.
func get_thrusters(index: int) -> Array[Dictionary]:
	index = clamp_index(index)
	if not _thruster_cache.has(index):
		var out: Array[Dictionary] = []
		for a in ShipParts.slot_anchors(get_svg(index), THRUSTER_SLOT, RENDER_SCALE):
			if a.pos.y > 0.0:
				out.append(a)
		_thruster_cache[index] = out
	return _thruster_cache[index]


## Builds every enemy part variant up front so the first kill doesn't hitch.
func prewarm_enemy_parts(stage := 0) -> void:
	for ship in count():
		get_lit_enemy_texture(ship, stage)
		for v in ENEMY_PART_VARIANTS:
			get_enemy_parts(ship, v, stage)


## get_texture() paired with the ship's baked normal map, for 2D lighting.
func get_lit_texture(index: int, palette: int = -1) -> CanvasTexture:
	index = clamp_index(index)
	palette = palette_for(index) if palette < 0 else clamp_palette(palette)
	return _lit_cached("%d:%d" % [index, palette], index, get_texture(index, palette))


## get_enemy_texture() paired with the ship's baked normal map.
func get_lit_enemy_texture(index: int, stage := 0) -> CanvasTexture:
	index = clamp_index(index)
	return _lit_cached(_enemy_key(index, stage), index, get_enemy_texture(index, stage))


func _lit_cached(key: String, index: int, diffuse: Texture2D) -> CanvasTexture:
	if not _lit_cache.has(key):
		var tex := CanvasTexture.new()
		tex.diffuse_texture = diffuse
		tex.normal_texture = get_normal_texture(index)
		_lit_cache[key] = tex
	return _lit_cache[key]


## The ship's baked normal map (tools/bake_normals.gd), same pixel size as its textures.
func get_normal_texture(index: int) -> Texture2D:
	return load(LIST[clamp_index(index)].normal)


func _render_cached(key: String, index: int, colors: Array[Color]) -> Texture2D:
	if not _texture_cache.has(key):
		var tex: Texture2D = ShipSkin.render(get_svg(index), colors, RENDER_SCALE)
		if tex == null:
			tex = _missing_texture()
		_texture_cache[key] = tex
	return _texture_cache[key]


## Magenta square shown when a ship SVG cannot be rendered.
func _missing_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	return ImageTexture.create_from_image(img)


## Uniform scale that renders a texture at `height` px.
func scale_for(tex: Texture2D, height: float = SHIP_HEIGHT) -> Vector2:
	return Vector2.ONE * (height / tex.get_size().y)


## Uniform scale that renders the ship at SHIP_HEIGHT.
func get_scale(index: int, palette: int = -1) -> Vector2:
	return scale_for(get_texture(index, palette))


func select(index: int) -> void:
	selected = clamp_index(index)
	save_selection()
	selection_changed.emit(selected)


# --- Palettes --------------------------------------------------------------

func palette_count() -> int:
	return PALETTES.size()


func is_valid_palette(index: int) -> bool:
	return index >= 0 and index < PALETTES.size()


func clamp_palette(index: int) -> int:
	return index if is_valid_palette(index) else 0


func get_palette_name(index: int) -> String:
	return PALETTES[clamp_palette(index)].name


## The 9 slot colors a palette applies to a ship (Factory = the ship's own paint).
func get_palette_colors(ship: int, palette: int) -> Array[Color]:
	var colors: Array = PALETTES[clamp_palette(palette)].colors
	if colors.is_empty():
		return ShipSkin.default_palette(get_svg(ship))
	var out: Array[Color] = []
	out.assign(colors)
	return out


func palette_for(ship: int) -> int:
	return _palette_by_ship.get(clamp_index(ship), 0)


func set_palette(ship: int, palette: int) -> void:
	_palette_by_ship[clamp_index(ship)] = clamp_palette(palette)
	save_selection()


# --- Persistence -----------------------------------------------------------

func save_selection(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep other sections if the file exists
	cfg.set_value("player", "ship", selected)
	for ship in _palette_by_ship:
		cfg.set_value("palettes", str(ship), _palette_by_ship[ship])
	cfg.save(path)


func load_selection(path: String = SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	selected = clamp_index(int(cfg.get_value("player", "ship", 0)))
	_palette_by_ship.clear()
	if cfg.has_section("palettes"):
		for key in cfg.get_section_keys("palettes"):
			var ship := int(key)
			if is_valid(ship):
				_palette_by_ship[ship] = clamp_palette(int(cfg.get_value("palettes", key, 0)))
