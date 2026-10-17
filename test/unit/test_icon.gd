extends GutTest
## Game icon: ship02 in the Arctic palette, used for the project and Android launcher.

const IconMaker := preload("res://tools/make_icon.gd")


func _png(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_project_uses_icon_png() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/icon"), "res://icon.png")


func test_android_launcher_icons_set() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	assert_eq(cfg.get_value("preset.0.options", "launcher_icons/main_192x192"), "res://icon.png")
	assert_eq(cfg.get_value("preset.0.options", "launcher_icons/adaptive_foreground_432x432"), "res://icon_foreground.png")
	assert_eq(cfg.get_value("preset.0.options", "launcher_icons/adaptive_background_432x432"), "res://icon_background.png")


func test_icon_sizes() -> void:
	assert_eq(_png("res://icon.png").get_size(), Vector2i(512, 512))
	assert_eq(_png("res://icon_foreground.png").get_size(), Vector2i(432, 432))
	assert_eq(_png("res://icon_background.png").get_size(), Vector2i(432, 432))


func test_icon_is_ship02_in_arctic() -> void:
	assert_eq(IconMaker.SHIP, 1)
	assert_eq(Ships.LIST[IconMaker.SHIP].svg, "res://assets/ship02.svg")
	assert_eq(IconMaker.palette_colors(IconMaker.PALETTE), Ships.get_palette_colors(1, 2))
	var ship := IconMaker.ship_image(IconMaker.SHIP, IconMaker.PALETTE)
	assert_eq(IconMaker.icon(ship).get_data(), _png("res://icon.png").get_data(), "icon.png is up to date")


func test_icon_has_rounded_transparent_corners() -> void:
	var img := _png("res://icon.png")
	assert_eq(img.get_pixel(0, 0).a, 0.0)
	assert_eq(img.get_pixel(256, 2).a, 1.0)


func test_foreground_ship_inside_safe_zone() -> void:
	var img := _png("res://icon_foreground.png")
	var used := img.get_used_rect()
	var safe := Rect2i(Vector2i(72, 72), Vector2i(288, 288))  # center 2/3 of 432
	assert_true(safe.encloses(used), "ship %s within %s" % [used, safe])
	assert_gt(used.size.x, 200, "ship is not tiny")
