extends GutTest
## ShipSkin: reading painter metadata, swapping fills by slot, rasterizing.

# 20x10 image: left half slot 1, right half slot 2, a 1px dot without a slot.
const PAINTED := """<?xml version="1.0" standalone="no"?>
<svg version="1.0" xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10" data-slots="2" data-slot-names="Hull,Trim &amp; Glass">
<g fill="#ffffff" stroke="none">
<rect x="0" y="0" width="10" height="10" data-slot="1" fill="#ffffff"/>
<path d="M10 0 l10 0 l0 10
l-10 0 z" data-slot="2" fill="#ff0000"/>
<rect x="19" y="9" width="1" height="1"/>
</g>
</svg>
"""

# Unpainted ship: plain potrace-style outline, no slot metadata.
const UNPAINTED := """<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">
<g fill="#ffffff" stroke="none">
<path d="M0 0 l10 0 l0 10 l-10 0 z"/>
</g>
</svg>
"""

const RED := Color("ff0000")
const BLUE := Color("0000ff")
const GREEN := Color("00ff00")


func test_slot_count_reads_root_attribute() -> void:
	assert_eq(ShipSkin.slot_count(PAINTED), 2)


func test_slot_count_grows_to_highest_shape_slot() -> void:
	var svg := "<svg data-slots=\"1\"><path data-slot=\"4\"/></svg>"
	assert_eq(ShipSkin.slot_count(svg), 4)


func test_unpainted_ship_has_no_slots() -> void:
	var svg := UNPAINTED
	assert_eq(ShipSkin.slot_count(svg), 0)
	assert_eq(ShipSkin.slot_names(svg).size(), 0)
	assert_eq(ShipSkin.default_palette(svg).size(), 0)


func test_slot_names_unescaped_and_padded() -> void:
	assert_eq(ShipSkin.slot_names(PAINTED), PackedStringArray(["Hull", "Trim & Glass"]))
	var svg := "<svg data-slots=\"3\" data-slot-names=\"Hull\"><path data-slot=\"1\"/></svg>"
	assert_eq(ShipSkin.slot_names(svg), PackedStringArray(["Hull", "Slot 2", "Slot 3"]))


func test_default_palette_is_first_fill_per_slot() -> void:
	var pal := ShipSkin.default_palette(PAINTED)
	assert_eq(pal.size(), 2)
	assert_eq(pal[0], Color.WHITE)
	assert_eq(pal[1], RED)


func test_apply_palette_swaps_fills_by_slot() -> void:
	var out := ShipSkin.apply_palette(PAINTED, [GREEN, BLUE])
	assert_string_contains(out, "data-slot=\"1\" fill=\"#00ff00\"")
	assert_string_contains(out, "data-slot=\"2\" fill=\"#0000ff\"")
	assert_false(out.contains("#ff0000"), "old slot 2 fill replaced")
	assert_string_contains(out, "<rect x=\"19\" y=\"9\" width=\"1\" height=\"1\"/>", "unslotted shape untouched")
	assert_string_contains(out, "<g fill=\"#ffffff\"", "group fill untouched")


func test_apply_palette_keeps_default_fill_for_slots_beyond_palette() -> void:
	var out := ShipSkin.apply_palette(PAINTED, [GREEN])
	assert_string_contains(out, "data-slot=\"1\" fill=\"#00ff00\"")
	assert_string_contains(out, "data-slot=\"2\" fill=\"#ff0000\"")


func test_apply_palette_adds_fill_when_shape_has_none() -> void:
	var svg := "<svg><path data-slot=\"1\" d=\"M0 0\"/><rect data-slot=\"1\"></rect></svg>"
	var out := ShipSkin.apply_palette(svg, [BLUE])
	assert_eq(out, "<svg><path data-slot=\"1\" d=\"M0 0\" fill=\"#0000ff\"/><rect data-slot=\"1\" fill=\"#0000ff\"></rect></svg>")


func test_apply_palette_leaves_unpainted_svg_unchanged() -> void:
	var svg := UNPAINTED
	assert_eq(ShipSkin.apply_palette(svg, [RED, BLUE]), svg)


func test_render_uses_palette_colors() -> void:
	var tex := ShipSkin.render(PAINTED, [GREEN, BLUE])
	assert_not_null(tex)
	assert_eq(tex.get_size(), Vector2(20, 10))
	var img := tex.get_image()
	assert_eq(img.get_pixel(3, 5), GREEN, "slot 1 pixel")
	assert_eq(img.get_pixel(15, 5), BLUE, "slot 2 pixel")


func test_render_scales() -> void:
	var tex := ShipSkin.render(PAINTED, [GREEN, BLUE], 3.0)
	assert_eq(tex.get_size(), Vector2(60, 30))


func test_render_file_rasterizes_real_ship() -> void:
	var tex := ShipSkin.render_file("res://assets/ship01.svg", [RED], 0.1)
	assert_not_null(tex)
	assert_gt(tex.get_width(), 0)
	assert_gt(tex.get_height(), 0)


func test_render_file_missing_returns_null_and_errors() -> void:
	assert_null(ShipSkin.render_file("res://assets/missing.svg", [RED]))
	assert_push_error("could not read")


# 20x20: a slot-2 fill under a slot-1 outline ring. The fill covers 2..18, the ring 2..18 with a 4px wall.
const LAYERED := """<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" data-slots="2">
<g data-layer="fills" stroke="none">
<path data-slot="2" fill="#ff0000" d="M2 2L18 2L18 18L2 18Z"/>
</g>
<path data-slot="1" fill="#ffffff" d="M2 2L18 2L18 18L2 18Z M6 6L6 14L14 14L14 6Z"/>
</svg>
"""


func test_fill_layer_counts_and_defaults() -> void:
	assert_eq(ShipSkin.slot_count(LAYERED), 2)
	assert_eq(ShipSkin.default_palette(LAYERED), [Color.WHITE, RED] as Array[Color])


func test_fill_layer_recolored_and_drawn_under_outline() -> void:
	var tex := ShipSkin.render(LAYERED, [BLUE, GREEN])
	var img := tex.get_image()
	assert_eq(img.get_pixel(10, 10), GREEN, "fill shows through the outline's hole")
	assert_eq(img.get_pixel(3, 10), BLUE, "outline drawn over the fill")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "outside stays transparent")


func test_shipped_ships_are_painted() -> void:
	for ship in Ships.LIST:
		var path: String = ship.svg
		var svg := FileAccess.get_file_as_string(path)
		assert_eq(ShipSkin.slot_count(svg), 9, path)
		assert_eq(ShipSkin.default_palette(svg).size(), 9, path)
