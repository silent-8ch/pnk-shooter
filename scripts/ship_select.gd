extends CanvasLayer
## Ship selection screen shown before the lobby.

signal ship_chosen(index: int)
signal back_pressed

@onready var ship_row: GridContainer = %ShipRow  # rows of 3 so it fits the portrait screen
@onready var ship_name_label: Label = %ShipNameLabel
@onready var confirm_button: Button = %ConfirmButton
@onready var back_button: Button = %BackButton
@onready var palette_grid: GridContainer = %PaletteGrid

var _buttons: Array[Button] = []
var _icons: Array[TextureRect] = []
var _palette_buttons: Array[Button] = []
var _highlighted := 0
var _pending := {}  # ship -> palette chosen on this screen, committed on confirm


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)
	back_button.pressed.connect(back_pressed.emit)
	_build_buttons()
	_build_palette_buttons()
	visibility_changed.connect(_on_visibility_changed)
	highlight(Ships.selected)


func _build_buttons() -> void:
	for child in ship_row.get_children():
		child.queue_free()
	_buttons.clear()
	_icons.clear()
	for i in Ships.count():
		var button := Button.new()
		button.name = "Ship%d" % i
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(140, 150)
		button.focus_mode = Control.FOCUS_NONE

		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(vbox)

		var icon := TextureRect.new()
		icon.texture = Ships.get_texture(i)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(0, 100)
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(icon)
		_icons.append(icon)

		var label := Label.new()
		label.text = Ships.get_name_of(i)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(label)

		button.pressed.connect(highlight.bind(i))
		ship_row.add_child(button)
		_buttons.append(button)


func _build_palette_buttons() -> void:
	for child in palette_grid.get_children():
		child.queue_free()
	_palette_buttons.clear()
	for p in Ships.palette_count():
		var button := Button.new()
		button.name = "Palette%d" % p
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_PASS  # let drags scroll the grid

		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 4)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(vbox)

		var label := Label.new()
		label.text = Ships.get_palette_name(p)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(label)

		var swatches := HBoxContainer.new()
		swatches.name = "Swatches"
		swatches.alignment = BoxContainer.ALIGNMENT_CENTER
		swatches.add_theme_constant_override("separation", 2)
		swatches.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(swatches)

		button.pressed.connect(choose_palette.bind(p))
		palette_grid.add_child(button)
		_palette_buttons.append(button)


## Swatches show slots 2-9 (the outline is left out); Factory varies per ship.
func _refresh_swatches() -> void:
	for p in _palette_buttons.size():
		var swatches: HBoxContainer = _palette_buttons[p].find_child("Swatches", true, false)
		for child in swatches.get_children():
			swatches.remove_child(child)
			child.queue_free()
		var colors := Ships.get_palette_colors(_highlighted, p)
		for c in colors.slice(1):
			var rect := ColorRect.new()
			rect.color = c
			rect.custom_minimum_size = Vector2(9, 12)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			swatches.add_child(rect)


func highlight(index: int) -> void:
	_highlighted = Ships.clamp_index(index)
	for i in _buttons.size():
		_buttons[i].button_pressed = i == _highlighted
	_refresh_swatches()
	_update_palette_ui()


func choose_palette(palette: int) -> void:
	_pending[_highlighted] = Ships.clamp_palette(palette)
	_update_palette_ui()


func get_palette(ship: int) -> int:
	return _pending.get(ship, Ships.palette_for(ship))


func _update_palette_ui() -> void:
	var current := get_palette(_highlighted)
	for p in _palette_buttons.size():
		_palette_buttons[p].button_pressed = p == current
	for i in _icons.size():
		_icons[i].texture = Ships.get_texture(i, get_palette(i))
	ship_name_label.text = "%s  ·  %s" % [Ships.get_name_of(_highlighted), Ships.get_palette_name(current)]


## Each visit starts from the saved choices; unconfirmed picks are dropped.
func _on_visibility_changed() -> void:
	if visible:
		_pending.clear()
		highlight(Ships.selected)


func get_highlighted() -> int:
	return _highlighted


func _on_confirm_pressed() -> void:
	for ship in _pending:
		Ships.set_palette(ship, _pending[ship])
	_pending.clear()
	Ships.select(_highlighted)
	ship_chosen.emit(_highlighted)
