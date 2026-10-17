extends GutTest
## Ships autoload: registry, index validation, persistence.

const TMP_CFG := "user://test_settings.cfg"

var _saved_selected := 0
var _saved_palettes := {}


func before_each() -> void:
	_saved_selected = Ships.selected
	_saved_palettes = Ships._palette_by_ship.duplicate()


func after_each() -> void:
	Ships.selected = _saved_selected
	Ships._palette_by_ship = _saved_palettes
	Ships.save_selection()
	DirAccess.remove_absolute(TMP_CFG)


func test_registry_has_both_ships() -> void:
	assert_eq(Ships.count(), 2)
	assert_eq(Ships.LIST[0].svg, "res://assets/ship01.svg")
	assert_eq(Ships.LIST[1].svg, "res://assets/ship02.svg")
	assert_not_null(Ships.get_texture(0))
	assert_not_null(Ships.get_texture(1))
	assert_ne(Ships.get_name_of(0), Ships.get_name_of(1))


func test_index_validation() -> void:
	assert_true(Ships.is_valid(0))
	assert_true(Ships.is_valid(1))
	assert_false(Ships.is_valid(-1))
	assert_false(Ships.is_valid(2))
	assert_eq(Ships.clamp_index(-1), 0)
	assert_eq(Ships.clamp_index(7), 0)
	assert_eq(Ships.clamp_index(1), 1)


func test_scale_normalises_height() -> void:
	for i in Ships.count():
		var size: Vector2 = Ships.get_texture(i).get_size() * Ships.get_scale(i)
		assert_almost_eq(size.y, Ships.SHIP_HEIGHT, 0.5)


func test_select_clamps_and_emits() -> void:
	watch_signals(Ships)
	Ships.select(1)
	assert_eq(Ships.selected, 1)
	assert_signal_emitted_with_parameters(Ships, "selection_changed", [1])
	Ships.select(42)
	assert_eq(Ships.selected, 0)


func test_save_and_load_roundtrip() -> void:
	Ships.selected = 1
	Ships.save_selection(TMP_CFG)
	Ships.selected = 0
	Ships.load_selection(TMP_CFG)
	assert_eq(Ships.selected, 1)


func test_load_missing_file_keeps_current() -> void:
	Ships.selected = 1
	Ships.load_selection("user://does_not_exist.cfg")
	assert_eq(Ships.selected, 1)


func test_load_invalid_index_falls_back() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "ship", 99)
	cfg.save(TMP_CFG)
	Ships.selected = 1
	Ships.load_selection(TMP_CFG)
	assert_eq(Ships.selected, 0)


# --- Palettes ---

func test_twelve_named_palettes_factory_first() -> void:
	assert_eq(Ships.palette_count(), 12)
	assert_eq(Ships.get_palette_name(0), "Factory")
	var names := {}
	for p in Ships.palette_count():
		names[Ships.get_palette_name(p)] = true
	assert_eq(names.size(), 12, "names are unique")


func test_every_palette_fills_all_slots_of_every_ship() -> void:
	for ship in Ships.count():
		var slots := ShipSkin.slot_count(Ships.get_svg(ship))
		for p in Ships.palette_count():
			assert_eq(Ships.get_palette_colors(ship, p).size(), slots, "ship %d palette %d" % [ship, p])


func test_factory_is_neutral() -> void:
	for c in Ships.get_palette_colors(0, 0):
		assert_lt(c.s, 0.25, "low saturation: %s" % c.to_html(false))

func test_palette_index_clamps() -> void:
	assert_false(Ships.is_valid_palette(-1))
	assert_false(Ships.is_valid_palette(Ships.palette_count()))
	assert_eq(Ships.clamp_palette(99), 0)
	assert_eq(Ships.get_palette_name(-5), "Factory")


func test_textures_differ_per_palette_and_are_cached() -> void:
	var a := Ships.get_texture(0, 1)
	assert_same(Ships.get_texture(0, 1), a)
	assert_not_same(Ships.get_texture(0, 2), a)


func test_palette_texture_uses_palette_colors() -> void:
	# Arctic hull is light blue; sample the rendered image for a hull-like pixel.
	var img := Ships.get_texture(1, 2).get_image()
	var found := false
	var hull := Color("a8d8f0")
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and absf(c.r - hull.r) < 0.03 and absf(c.g - hull.g) < 0.03 and absf(c.b - hull.b) < 0.03:
				found = true
				break
		if found:
			break
	assert_true(found, "rendered ship contains the Arctic hull color")


func test_palette_per_ship_defaults_to_factory() -> void:
	Ships._palette_by_ship.clear()
	assert_eq(Ships.palette_for(0), 0)
	Ships._palette_by_ship[1] = 3
	assert_eq(Ships.palette_for(1), 3)
	assert_eq(Ships.palette_for(0), 0)


func test_palettes_save_and_load_per_ship() -> void:
	Ships._palette_by_ship = {0: 4, 1: 5}
	Ships.save_selection(TMP_CFG)
	Ships._palette_by_ship.clear()
	Ships.load_selection(TMP_CFG)
	assert_eq(Ships.palette_for(0), 4)
	assert_eq(Ships.palette_for(1), 5)


func test_load_ignores_bad_palette_entries() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("palettes", "0", 99)
	cfg.set_value("palettes", "7", 2)
	cfg.save(TMP_CFG)
	Ships.load_selection(TMP_CFG)
	assert_eq(Ships.palette_for(0), 0)
	assert_false(Ships._palette_by_ship.has(7))


# --- Export / enemy palettes ----------------------------------------------

func test_ship_svgs_exported_as_raw_files() -> void:
	# Imported SVGs are left out of exports; palettes need the raw SVG text.
	for ship in Ships.LIST:
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(ship.svg + ".import"), OK)
		assert_eq(cfg.get_value("remap", "importer"), "keep", ship.svg)


func test_enemy_palettes_cover_every_ship() -> void:
	assert_eq(Ships.ENEMY_PALETTES.size(), Ships.count())
	for ship in Ships.count():
		var slots := ShipSkin.slot_count(Ships.get_svg(ship))
		assert_eq(Ships.ENEMY_PALETTES[ship].colors.size(), slots)


func test_enemy_palettes_not_selectable() -> void:
	for enemy in Ships.ENEMY_PALETTES:
		for p in Ships.PALETTES:
			assert_ne(enemy.name, p.name)


func test_enemy_texture_cached_and_differs_from_player() -> void:
	var tex := Ships.get_enemy_texture(0)
	assert_not_null(tex)
	assert_same(Ships.get_enemy_texture(0), tex)
	assert_not_same(tex, Ships.get_texture(0, 0))
	assert_not_same(tex, Ships.get_enemy_texture(1))


func test_scale_for_height() -> void:
	var tex := Ships.get_texture(0, 0)
	assert_almost_eq(tex.get_size().y * Ships.scale_for(tex, 36.0).y, 36.0, 0.001)


# --- Thruster anchors -------------------------------------------------------

func test_every_ship_has_thrusters_in_its_lower_half() -> void:
	for ship in Ships.count():
		var t := Ships.get_thrusters(ship)
		assert_gt(t.size(), 0, "ship %d" % ship)
		var h: float = Ships.get_texture(ship, 0).get_size().y
		for a in t:
			assert_gt(a.pos.y, 0.0, "below center")
			assert_lte(a.pos.y, h / 2.0 + 1.0, "inside the texture")
			assert_gte(a.width, 3.0)


func test_thrusters_sorted_and_not_stacked() -> void:
	for ship in Ships.count():
		var t := Ships.get_thrusters(ship)
		for i in range(1, t.size()):
			assert_gt(t[i].pos.x, t[i - 1].pos.x)
		for a in t:
			for b in t:
				if a != b:
					assert_false(b.pos.y > a.pos.y and absf(b.pos.x - a.pos.x) < b.width / 2.0)


func test_thrusters_cached() -> void:
	assert_same(Ships.get_thrusters(0), Ships.get_thrusters(0))
