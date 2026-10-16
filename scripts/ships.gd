extends Node
## Ship registry autoload: available ships, named color palettes, and the local
## player's choices (ship + palette per ship), persisted to user://.

const SHIP_HEIGHT := 44.0  # on-screen height in px, regardless of texture size
const RENDER_SCALE := 0.2  # SVG -> texture scale, matches the import settings
const SETTINGS_PATH := "user://settings.cfg"

const LIST: Array[Dictionary] = [
	{"name": "Ship 01", "svg": "res://assets/ship01.svg"},
	{"name": "Ship 02", "svg": "res://assets/ship02.svg"},
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
]

signal selection_changed(index: int)

var selected := 0
var _palette_by_ship := {}  # ship index -> palette index
var _svg_cache := {}  # ship index -> SVG text
var _texture_cache := {}  # "ship:palette" -> Texture2D


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


## The ship rendered in its enemy-only palette.
func get_enemy_texture(index: int) -> Texture2D:
	index = clamp_index(index)
	var colors: Array[Color] = []
	colors.assign(ENEMY_PALETTES[index % ENEMY_PALETTES.size()].colors)
	return _render_cached("enemy:%d" % index, index, colors)


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
