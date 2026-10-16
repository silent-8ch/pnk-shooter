extends GutTest
## Ship selection screen: one button per ship, highlight, confirm.

const ShipSelectScene := preload("res://scenes/ship_select.tscn")

var screen: CanvasLayer
var _saved_selected := 0
var _saved_palettes := {}


func before_each() -> void:
	_saved_selected = Ships.selected
	_saved_palettes = Ships._palette_by_ship.duplicate()
	Ships.selected = 0
	Ships._palette_by_ship.clear()
	screen = ShipSelectScene.instantiate()
	add_child_autofree(screen)


func after_each() -> void:
	Ships.selected = _saved_selected
	Ships._palette_by_ship = _saved_palettes
	Ships.save_selection()


func _buttons() -> Array:
	return screen.get_node("%ShipRow").get_children().filter(func(c): return c is Button)


func test_one_button_per_ship() -> void:
	assert_eq(_buttons().size(), Ships.count())


func test_initial_highlight_matches_current_selection() -> void:
	assert_eq(screen.get_highlighted(), 0)
	assert_true(_buttons()[0].button_pressed)
	assert_false(_buttons()[1].button_pressed)
	assert_string_starts_with(screen.get_node("%ShipNameLabel").text, Ships.get_name_of(0))


func test_pressing_button_highlights_without_selecting() -> void:
	_buttons()[1].pressed.emit()
	assert_eq(screen.get_highlighted(), 1)
	assert_true(_buttons()[1].button_pressed)
	assert_false(_buttons()[0].button_pressed)
	assert_string_starts_with(screen.get_node("%ShipNameLabel").text, Ships.get_name_of(1))
	assert_eq(Ships.selected, 0, "selection only commits on confirm")


func test_confirm_selects_and_emits() -> void:
	watch_signals(screen)
	screen.highlight(1)
	screen.get_node("%ConfirmButton").pressed.emit()
	assert_eq(Ships.selected, 1)
	assert_signal_emitted_with_parameters(screen, "ship_chosen", [1])


func test_highlight_clamps_bad_index() -> void:
	screen.highlight(99)
	assert_eq(screen.get_highlighted(), 0)


# --- Palettes ---

func _palette_buttons() -> Array:
	return screen.get_node("%PaletteGrid").get_children().filter(func(c): return c is Button)


func test_one_button_per_palette_with_name() -> void:
	var buttons := _palette_buttons()
	assert_eq(buttons.size(), Ships.palette_count())
	for p in buttons.size():
		var label: Label = buttons[p].find_children("*", "Label", true, false)[0]
		assert_eq(label.text, Ships.get_palette_name(p))


func test_swatches_show_slots_2_to_9() -> void:
	var swatches: HBoxContainer = _palette_buttons()[2].find_child("Swatches", true, false)
	var colors := Ships.get_palette_colors(0, 2)
	assert_eq(swatches.get_child_count(), colors.size() - 1)
	assert_eq((swatches.get_child(0) as ColorRect).color, colors[1])


func test_factory_starts_pressed() -> void:
	assert_true(_palette_buttons()[0].button_pressed)
	assert_false(_palette_buttons()[1].button_pressed)


func test_choosing_palette_updates_preview_and_label_but_not_saved() -> void:
	_palette_buttons()[3].pressed.emit()
	assert_true(_palette_buttons()[3].button_pressed)
	assert_false(_palette_buttons()[0].button_pressed)
	assert_same(screen._icons[0].texture, Ships.get_texture(0, 3))
	assert_string_contains(screen.get_node("%ShipNameLabel").text, Ships.get_palette_name(3))
	assert_eq(Ships.palette_for(0), 0, "only committed on confirm")


func test_palette_is_remembered_per_ship_on_screen() -> void:
	screen.choose_palette(2)
	screen.highlight(1)
	assert_true(_palette_buttons()[0].button_pressed, "ship 1 still on Factory")
	screen.choose_palette(5)
	screen.highlight(0)
	assert_true(_palette_buttons()[2].button_pressed)
	assert_same(screen._icons[1].texture, Ships.get_texture(1, 5))


func test_confirm_commits_palettes() -> void:
	screen.choose_palette(4)
	screen.highlight(1)
	screen.choose_palette(1)
	screen.get_node("%ConfirmButton").pressed.emit()
	assert_eq(Ships.palette_for(0), 4)
	assert_eq(Ships.palette_for(1), 1)
	assert_eq(Ships.selected, 1)


func test_back_discards_pending_palettes() -> void:
	screen.choose_palette(4)
	screen.get_node("%BackButton").pressed.emit()
	assert_eq(Ships.palette_for(0), 0)


func test_reopening_screen_drops_unconfirmed_picks() -> void:
	screen.choose_palette(4)
	screen.highlight(1)
	screen.visible = false
	screen.visible = true
	assert_eq(screen.get_highlighted(), Ships.selected)
	assert_eq(screen.get_palette(0), 0)
	assert_true(_palette_buttons()[0].button_pressed)


func test_palette_buttons_pass_drags_to_scroll() -> void:
	var scroll := screen.get_node("%PaletteGrid").get_parent()
	assert_is(scroll, ScrollContainer)
	assert_gt(scroll.scroll_deadzone, 0)
	for b in _palette_buttons():
		assert_eq(b.mouse_filter, Control.MOUSE_FILTER_PASS, b.name)
