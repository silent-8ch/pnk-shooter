class_name ActionBar
extends Control
## Row of action buttons along the bottom of the screen. Each button counts its
## presses (`presses[id]`; readers compare against the count they last saw, like
## PointerControls did for taps) and shows its cooldown as a draining overlay.
## Touches are read directly so a button works with any finger, even while
## another finger is steering the ship; PointerControls ignores touches here.
## Buttons marked "hidden" appear (left to right, after the others) once
## set_shown; set_enabled greys one out without moving it; set_lit marks an
## armed gun (or a switched-on toggle), and a gun button that isn't lit shows
## OFF; set_power shows the WEAPONS bars it needs as pips.
## Holding a button for LONG_PRESS (or right-clicking it, or Shift + its number
## key) counts a long press in `holds[id]` as well, which disarms a gun.
## Drawn LCARS-style (see LCARS): rounded pills on a black strip, lit ones
## solid with black labels, an unarmed gun outlined with OFF.
## Right-handed controls (Settings) line the buttons up from the right edge
## instead, LASERS rightmost.
## On desktop the number keys press the shown buttons left to right (1 = LASERS,
## 2 = the next one, ...); each button shows its key where there's no touchscreen.

const BAR_HEIGHT := 96.0
const BUTTON_SIZE := Vector2(88, 72)
const MARGIN := 12.0
const ACTIONS: Array[Dictionary] = [
	{"id": &"lasers", "label": "PHOTONS", "cooldown": 0.45, "color": LCARS.ORANGE},
	{"id": &"missile", "label": "MISSILE", "cooldown": 0.9, "color": LCARS.LAVENDER, "hidden": true},  # 2x lasers
	{"id": &"rescue", "label": "RESCUE", "cooldown": 0.5, "color": LCARS.BLUE, "hidden": true},
	{"id": &"beam", "label": "BEAM", "cooldown": 3.0, "color": LCARS.PEACH, "hidden": true},
	{"id": &"auto", "label": "AUTO", "cooldown": 0.3, "color": LCARS.TAN, "hidden": true},  # on/off
	{"id": &"repair", "label": "REPAIR", "cooldown": 10.0, "color": LCARS.RED, "hidden": true},
	{"id": &"heal", "label": "HEAL", "cooldown": 0.3, "color": LCARS.LAVENDER, "hidden": true},  # on/off
]
const MOUSE_INDEX := -2
const LONG_PRESS := 0.45  # s a finger stays on a button for a long press

var presses := {}  # action id -> total accepted presses
var _cooldown := {}  # action id -> seconds left
var _cooldown_override := {}  # action id -> cooldown in seconds, set by upgrades (RAPID)
var _held := {}  # pointer index -> action id, while a finger is on a button
var _shown := {}  # action id -> bool
var _enabled := {}  # action id -> bool
var _lit := {}  # action id -> bool: a toggle that's on
var _power := {}  # action id -> WEAPONS bars its gun needs (0 = not a gun)
var holds := {}  # action id -> total long presses
var _held_for := {}  # pointer index -> s it has been down on its button (-1 once it counted as a long press)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for a in ACTIONS:
		presses[a.id] = 0
		holds[a.id] = 0
		_cooldown[a.id] = 0.0
		_shown[a.id] = not a.get("hidden", false)
		_enabled[a.id] = true
	var layer := get_parent()
	if layer is CanvasLayer:
		layer.visibility_changed.connect(reset)


static func cooldown_of(id: StringName) -> float:
	for a in ACTIONS:
		if a.id == id:
			return a.cooldown
	return 0.0


## The bar strip, in canvas coordinates.
func bar_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(0, size.y - BAR_HEIGHT, size.x, BAR_HEIGHT)


func set_shown(id: StringName, on: bool) -> void:
	if _shown.get(id) != on:
		_shown[id] = on
		queue_redraw()


func set_lit(id: StringName, on: bool) -> void:
	if _lit.get(id, false) != on:
		_lit[id] = on
		queue_redraw()


func set_power(id: StringName, bars: int) -> void:
	if _power.get(id, 0) != bars:
		_power[id] = bars
		queue_redraw()


## Counts a long press on `id` (shown buttons only).
func hold(id: StringName) -> bool:
	if not holds.has(id) or not _shown[id] or not _accepting_input():
		return false
	holds[id] += 1
	queue_redraw()
	return true


func set_enabled(id: StringName, on: bool) -> void:
	if _enabled.get(id) != on:
		_enabled[id] = on
		queue_redraw()


func is_shown(id: StringName) -> bool:
	return _shown.get(id, false)


## ACTIONS indices of the buttons on the bar, left to right.
func shown_actions() -> Array[int]:
	var out: Array[int] = []
	for i in ACTIONS.size():
		if _shown[ACTIONS[i].id]:
			out.append(i)
	return out


## Rect of the button for ACTIONS[i] (its slot among the shown buttons).
func button_rect(i: int) -> Rect2:
	var slot := shown_actions().find(i)
	if slot < 0:
		return Rect2()
	var bar := bar_rect()
	var n := shown_actions().size()
	var w := minf(BUTTON_SIZE.x, (bar.size.x - MARGIN * (n + 1)) / n)  # narrower when they wouldn't fit
	var x := MARGIN + slot * (w + MARGIN)
	if not Settings.left_handed:
		x = bar.size.x - MARGIN - w - slot * (w + MARGIN)
	return Rect2(Vector2(x, bar.position.y + (BAR_HEIGHT - BUTTON_SIZE.y) / 2.0), Vector2(w, BUTTON_SIZE.y))


## True if a screen position falls on the bar (so it isn't a move tap).
func contains(screen_pos: Vector2) -> bool:
	return is_active() and bar_rect().has_point(_to_canvas(screen_pos))


func is_active() -> bool:
	return visible and get_parent().visible


func reset() -> void:
	_held.clear()
	_held_for.clear()
	for id in _cooldown:
		_cooldown[id] = 0.0
	queue_redraw()


## Cooldown for `id` on this bar: the upgraded value if set, else ACTIONS'.
func cooldown_for(id: StringName) -> float:
	return _cooldown_override.get(id, cooldown_of(id))


func set_cooldown(id: StringName, seconds: float) -> void:
	_cooldown_override[id] = seconds


func cooldown_left(id: StringName) -> float:
	return _cooldown.get(id, 0.0)


## Presses `id` if it's off cooldown; returns whether it fired.
func press(id: StringName) -> bool:
	if not presses.has(id) or not _shown[id] or not _enabled[id] or _cooldown[id] > 0.0 or not _accepting_input():
		return false
	presses[id] += 1
	_cooldown[id] = cooldown_for(id)
	queue_redraw()
	return true


func _accepting_input() -> bool:
	if not is_active():
		return false
	var game := get_tree().get_first_node_in_group("game")
	return game == null or game.input_enabled


func _to_canvas(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _action_at(screen_pos: Vector2) -> int:
	var p := _to_canvas(screen_pos)
	for i in shown_actions():
		if button_rect(i).has_point(p):
			return i
	return -1


func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		_pointer(event.pressed, event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer(event.pressed, MOUSE_INDEX, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var i := _action_at(event.position) if is_active() else -1
		if i >= 0:
			hold(ACTIONS[i].id)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var id := action_for_key(event.keycode)
		if id != &"" and is_active():
			if event.shift_pressed:
				hold(id)
			else:
				press(id)
			get_viewport().set_input_as_handled()


## The action number key `keycode` presses (1 = first shown button), or &"".
func action_for_key(keycode: Key) -> StringName:
	var n := -1
	if keycode >= KEY_1 and keycode <= KEY_9:
		n = keycode - KEY_1
	elif keycode >= KEY_KP_1 and keycode <= KEY_KP_9:
		n = keycode - KEY_KP_1
	var shown := shown_actions()
	return ACTIONS[shown[n]].id if n >= 0 and n < shown.size() else &""


func _pointer(pressed: bool, index: int, screen_pos: Vector2) -> void:
	if not pressed:
		_held.erase(index)
		_held_for.erase(index)
		queue_redraw()
		return
	if not is_active():
		return
	var i := _action_at(screen_pos)
	if i < 0:
		return
	_held[index] = ACTIONS[i].id
	_held_for[index] = 0.0
	press(ACTIONS[i].id)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	for index in _held_for:
		if _held_for[index] < 0.0:
			continue
		_held_for[index] += delta
		if _held_for[index] >= LONG_PRESS:
			_held_for[index] = -1.0  # once per hold
			hold(_held[index])
	var changed := false
	for id in _cooldown:
		if _cooldown[id] > 0.0:
			_cooldown[id] = maxf(0.0, _cooldown[id] - delta)
			changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var strip := bar_rect()
	draw_rect(strip, Color(0, 0, 0, 0.85))
	LCARS.pill(self, Rect2(strip.position + Vector2(MARGIN, 3), Vector2(strip.size.x - 2.0 * MARGIN, 5)), Color(LCARS.ORANGE, 0.8))
	for i in shown_actions():
		var a: Dictionary = ACTIONS[i]
		var r := button_rect(i)
		var held: bool = _held.values().has(a.id)
		var lit: bool = _lit.get(a.id, false)
		var bars: int = _power.get(a.id, 0)
		var off := bars > 0 and not lit  # a gun that isn't armed
		var c: Color = a.color.lightened(0.25) if held else a.color
		var radius := minf(LCARS.RADIUS, r.size.x / 2.0)
		if off:
			draw_style_box(LCARS.box(c, radius), r)
			draw_style_box(LCARS.box(LCARS.BLACK, radius - 2.0), r.grow(-2.0))
		else:
			draw_style_box(LCARS.box(c, radius), r)
		var left := cooldown_left(a.id) / maxf(cooldown_for(a.id), 0.001)
		if left > 0.0:  # draining overlay: full right after firing, gone when ready
			draw_style_box(LCARS.box(Color(0, 0, 0, 0.55), minf(radius, r.size.y * left / 2.0)),
				Rect2(r.position, Vector2(r.size.x, r.size.y * left)))
		if not _enabled[a.id]:
			draw_style_box(LCARS.box(Color(0, 0, 0, 0.6), radius), r)
		var ink := c if off else LCARS.BLACK
		if not DisplayServer.is_touchscreen_available():  # key hint, top-left
			draw_string(font, r.position + Vector2(10, 16), str(shown_actions().find(i) + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(ink, 0.7))
		for k in bars:  # WEAPONS bars it needs, top right
			draw_rect(Rect2(r.end.x - 14.0 - k * 7.0, r.position.y + 7.0, 5.0, 8.0), ink)
		if off:
			LCARS.label(self, Rect2(r.position + Vector2(0, r.size.y - 22.0), Vector2(r.size.x, 16)), "OFF", font, c, 11)
		LCARS.label(self, r, a.label, font, ink, 16)
