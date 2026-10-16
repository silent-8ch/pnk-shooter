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
	{"name": "Factory", "colors": []},
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
	var key := "%d:%d" % [index, palette]
	if not _texture_cache.has(key):
		var tex: Texture2D = ShipSkin.render(get_svg(index), get_palette_colors(index, palette), RENDER_SCALE)
		if tex == null:
			tex = load(LIST[index].svg)  # imported texture as a last resort
		_texture_cache[key] = tex
	return _texture_cache[key]


## Uniform scale that renders the ship at SHIP_HEIGHT.
func get_scale(index: int, palette: int = -1) -> Vector2:
	var tex := get_texture(index, palette)
	return Vector2.ONE * (SHIP_HEIGHT / tex.get_size().y)


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
