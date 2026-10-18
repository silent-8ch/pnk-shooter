class_name PowerMeter
extends Control
## Gradius-style power meter down the right edge, just above the ActionBar.
## Each exp the local player collects moves the lit slot one step down the
## column (wrapping); tapping the meter buys the lit slot's upgrade and clears
## the light. The upgrades themselves live on the player (see Player.buy_upgrade).
## Also shows how many exp the local player has collected.
## The last slot, TIER II, takes TIER_CHARGES buys; then the meter switches to
## tier II: the TIER slot goes away and every upgrade can go further (`max` is
## per tier; DOUBLE 2 = triple shot, SHIELD 2 = a second shield behind you).
## Touches are read directly like the ActionBar; PointerControls ignores them.

const SLOTS: Array[Dictionary] = [
	{"id": &"speed", "label": "SPEED", "max": [3, 6]},
	{"id": &"rapid", "label": "RAPID", "max": [3, 6]},
	{"id": &"double", "label": "DOUBLE", "label2": "TRIPLE", "max": [1, 2]},
	{"id": &"option", "label": "OPTION", "max": [2, 3]},
	{"id": &"shield", "label": "SHIELD", "max": [1, 2]},
	{"id": &"rescue", "label": "RESCUE", "max": [1, 1]},  # unlocks the RESCUE button
	{"id": &"missile", "label": "MISSILE", "max": [1, 1]},  # unlocks the MISSILE button
	{"id": &"auto", "label": "AUTOCAN", "max": [1, 2]},  # unlocks the AUTO button; 2 = fires twice as fast
	{"id": &"beam", "label": "BEAM", "max": [0, 3]},  # tier II: unlocks BEAM; levels thicken and lengthen it
	{"id": &"tier", "label": "TIER II", "max": [3, 0]},  # charges; gone once in tier II
]
const TIER_CHARGES := 3
const TIER2_COLOR := Color("c08dff")
const SLOT_SIZE := Vector2(76, 48)
const GAP := 6.0
const MARGIN := 8.0
const COUNT_HEIGHT := 28.0  # exp counter above the slots
const LIT_COLOR := Color("ffd45a")
const MOUSE_INDEX := -2


## The slots shown in `tier` (1 or 2), top to bottom.
static func slots_for(tier: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in SLOTS:
		if max_level(s.id, tier) > 0:
			out.append(s)
	return out


## Index of `id` among the slots shown in `tier`, or -1.
static func slot_index(id: StringName, tier := 1) -> int:
	var shown := slots_for(tier)
	for i in shown.size():
		if shown[i].id == id:
			return i
	return -1


static func max_level(id: StringName, tier: int) -> int:
	for s in SLOTS:
		if s.id == id:
			return s.max[clampi(tier, 1, 2) - 1]
	return 0


## Slot label for `tier`: tier II names the next step where it differs.
static func label_for(s: Dictionary, tier: int, level: int) -> String:
	if tier >= 2 and s.has("label2") and level >= 1:
		return s.label2
	return s.label


func _tier() -> int:
	var p := _local_player()
	return p.tier if p else 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return visible and get_parent().visible


## The whole meter (counter plus slots), in canvas coordinates.
func meter_rect() -> Rect2:
	var n := slots_for(_tier()).size()
	var top := slot_rect(0).position.y - COUNT_HEIGHT
	return Rect2(Vector2(slot_rect(0).position.x, top), Vector2(SLOT_SIZE.x, slot_rect(n - 1).end.y - top))


## Slot i of the current tier's slots; the column grows up from above the ActionBar.
func slot_rect(i: int) -> Rect2:
	var n := slots_for(_tier()).size()
	var size := get_viewport_rect().size
	var bottom := size.y - ActionBar.BAR_HEIGHT - MARGIN
	var y := bottom - (n - i) * (SLOT_SIZE.y + GAP) + GAP
	return Rect2(Vector2(size.x - MARGIN - SLOT_SIZE.x, y), SLOT_SIZE)


## True if a screen position falls on the meter (so it isn't a move tap).
func contains(screen_pos: Vector2) -> bool:
	return is_active() and meter_rect().has_point(_to_canvas(screen_pos))


func _to_canvas(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _local_player() -> Node:
	var game := get_tree().get_first_node_in_group("game")
	return game.local_player() if game else null


func _accepting_input() -> bool:
	if not is_active():
		return false
	var game := get_tree().get_first_node_in_group("game")
	return game == null or game.input_enabled


func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	else:
		return
	if not contains(pos):
		return
	get_viewport().set_input_as_handled()
	if not _accepting_input():
		return
	var p := _local_player()
	if p:
		p.buy_upgrade()


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()


func _draw() -> void:
	var p := _local_player()
	var font := get_theme_default_font()
	var tier := _tier()
	var count := "EXP %d" % (p.exp_total if p else 0)
	if tier >= 2:
		count += "  II"
	var top := meter_rect().position
	var frame := TIER2_COLOR if tier >= 2 else Color.WHITE
	_draw_centered(font, count, Rect2(top, Vector2(SLOT_SIZE.x, COUNT_HEIGHT)), 16, frame)
	var shown := slots_for(tier)
	for i in shown.size():
		var s: Dictionary = shown[i]
		var r := slot_rect(i)
		var lit: bool = p != null and p.lit_slot() == i
		var maxed: bool = p != null and not p.can_upgrade(s.id)
		var fill := Color(LIT_COLOR, 0.85) if lit else Color(0.1, 0.12, 0.2, 0.55)
		draw_rect(r, fill)
		draw_rect(r, Color(LIT_COLOR if lit else frame, 0.9), false, 2.0)
		var text_color := Color.BLACK if lit else Color(1, 1, 1, 0.35 if maxed else 0.9)
		var level: int = p.level(s.id) if p else 0
		_draw_centered(font, label_for(s, tier, level), Rect2(r.position, Vector2(r.size.x, r.size.y - 12)), 14, text_color)
		var pips := max_level(s.id, tier)
		var step := minf(12.0, (r.size.x - 12.0) / pips)
		for k in pips:  # level pips
			var pip := Rect2(r.position + Vector2(6 + k * step, r.size.y - 12), Vector2(step - 4, 5))
			draw_rect(pip, text_color if k < level else Color(text_color, 0.25))


func _draw_centered(font: Font, text: String, r: Rect2, fs: int, c: Color) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, r.position + Vector2((r.size.x - tw) / 2.0, r.size.y / 2.0 + fs / 3.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
