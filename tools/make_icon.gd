extends SceneTree
## Builds the game icons from a ship SVG in one of the Ships palettes. Run from the project root:
##   Godot --headless -s tools/make_icon.gd
## Writes:
##   icon.png                  512 px app/project icon: ship on a rounded dark tile
##   icon_foreground.png       432 px Android adaptive foreground: ship only, inside the safe zone
##   icon_background.png       432 px Android adaptive background: dark tile with a soft glow

const ShipsScript := preload("res://scripts/ships.gd")
const ShipSkinScript := preload("res://scripts/ship_skin.gd")

const SHIP := 1  # index into Ships.LIST (ship02)
const PALETTE := "Arctic"
const BACKGROUND := Color(0.05, 0.06, 0.12)  # matches the game's background
const GLOW := Color("5fb4e6")  # light blue halo behind the ship
const GLOW_ALPHA := 0.35
const CORNER := 0.125  # rounded tile corner radius, fraction of the size

const ICON_SIZE := 512
const ICON_SHIP := 0.74  # ship size as a fraction of the icon
const ADAPTIVE_SIZE := 432
const ADAPTIVE_SHIP := 0.58  # inside Android's 66% safe zone


func _init() -> void:
	var ship := ship_image(SHIP, PALETTE)
	_save(icon(ship), "res://icon.png")
	_save(foreground(ship), "res://icon_foreground.png")
	_save(background(ADAPTIVE_SIZE, false), "res://icon_background.png")
	quit()


static func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("%s %s (%s)" % [path, img.get_size(), error_string(err)])


static func palette_colors(name: String) -> Array[Color]:
	var out: Array[Color] = []
	for p in ShipsScript.PALETTES:
		if p.name == name:
			out.assign(p.colors)
	assert(not out.is_empty(), "no palette named " + name)
	return out


## The ship rendered large (crisp when scaled down into the icons).
static func ship_image(ship: int, palette: String) -> Image:
	var svg := FileAccess.get_file_as_string(ShipsScript.LIST[ship].svg)
	var tex := ShipSkinScript.render(svg, palette_colors(palette), 1.0)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Copy of `ship` scaled to fit a `box` px square, keeping its aspect ratio.
static func fit(ship: Image, box: int) -> Image:
	var img := ship.duplicate()
	var s := float(box) / maxi(img.get_width(), img.get_height())
	img.resize(maxi(1, roundi(img.get_width() * s)), maxi(1, roundi(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	return img


static func _paste_centered(dst: Image, src: Image) -> void:
	var at := (dst.get_size() - src.get_size()) / 2
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), at)


## Dark tile with a radial glow; rounded corners (antialiased) when `rounded`.
static func background(size: int, rounded: bool) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	var r := size * CORNER
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var glow := clampf(1.0 - p.distance_to(c) / (size * 0.5), 0.0, 1.0)
			var col := BACKGROUND.lerp(GLOW, glow * glow * GLOW_ALPHA)
			col.a = _corner_coverage(p, size, r) if rounded else 1.0
			img.set_pixel(x, y, col)
	return img


# 1 inside the rounded square, 0 outside, smooth over one pixel at the corners.
static func _corner_coverage(p: Vector2, size: int, r: float) -> float:
	var q := Vector2(clampf(p.x, r, size - r), clampf(p.y, r, size - r))
	return clampf(r - p.distance_to(q) + 0.5, 0.0, 1.0)


static func icon(ship: Image) -> Image:
	var img := background(ICON_SIZE, true)
	_paste_centered(img, fit(ship, roundi(ICON_SIZE * ICON_SHIP)))
	return img


static func foreground(ship: Image) -> Image:
	var img := Image.create(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	_paste_centered(img, fit(ship, roundi(ADAPTIVE_SIZE * ADAPTIVE_SHIP)))
	return img
