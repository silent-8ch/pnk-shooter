extends Control
## Tap/click-to-move controls for touch and mouse: pressing sets a destination
## the ship flies to and dragging moves it. Firing is on the ActionBar; presses
## that land on the bar, the RefitPanel or the ShipPanel (its tab, or anywhere while a popup
## is open) are left to them.

const TOUCH_OFFSET := Vector2(0, -80)  # keep the ship above the finger
const MOUSE_INDEX := -2  # pointer index used for the mouse
const ARRIVE_DISTANCE := 4.0
const SLOW_RADIUS := 40.0  # ease in over this distance to avoid overshoot
const MARKER_RADIUS := 10.0

var target := Vector2.ZERO
var has_target := false

var _pointer_index := -1


func _ready() -> void:
	var layer := get_parent()
	if layer is CanvasLayer:
		layer.visibility_changed.connect(reset)


## CanvasLayer visibility does not reliably propagate to is_visible_in_tree().
func is_active() -> bool:
	return visible and get_parent().visible


## A finger (or the mouse button) is down steering the ship.
func is_touching() -> bool:
	return _pointer_index != -1


func reset() -> void:
	_pointer_index = -1
	has_target = false
	queue_redraw()


func _accepting_input() -> bool:
	if not is_active():
		return false
	var game := get_tree().get_first_node_in_group("game")
	return game == null or game.input_enabled


func _input(event: InputEvent) -> void:
	# Mouse events emulated from touch would double up with the touch events.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		_handle_press(event.pressed, event.index, event.position + TOUCH_OFFSET, event.position)
	elif event is InputEventScreenDrag:
		if _accepting_input():
			pointer_drag(event.index, event.position + TOUCH_OFFSET)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press(event.pressed, MOUSE_INDEX, event.position, event.position)
	elif event is InputEventMouseMotion:
		if _accepting_input():
			pointer_drag(MOUSE_INDEX, event.position)


## screen_pos: where the target goes; touch_pos: where the finger actually is.
func _handle_press(pressed: bool, index: int, screen_pos: Vector2, touch_pos: Vector2) -> void:
	if not pressed:
		pointer_up(index)
	elif _accepting_input() and not _on_action_bar(touch_pos):
		pointer_down(index, screen_pos)


func _on_action_bar(screen_pos: Vector2) -> bool:
	for group in [&"action_bar", &"ship_panel", &"refit_panel"]:
		var c := get_tree().get_first_node_in_group(group)
		if c != null and c.contains(screen_pos):
			return true
	return false


func pointer_down(index: int, screen_pos: Vector2) -> void:
	if _pointer_index != -1:
		return
	_pointer_index = index
	_set_target(screen_pos)


func pointer_drag(index: int, screen_pos: Vector2) -> void:
	if index == _pointer_index:
		_set_target(screen_pos)


func pointer_up(index: int) -> void:
	if index == _pointer_index:
		_pointer_index = -1


func _set_target(screen_pos: Vector2) -> void:
	target = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	has_target = true
	queue_redraw()


## Movement input (length <= 1) steering a ship at `from` toward the target,
## clamped to `bounds` (the area the ship can reach). Clears the target once
## the ship arrives.
func direction_from(from: Vector2, bounds: Rect2) -> Vector2:
	if not has_target:
		return Vector2.ZERO
	target = target.clamp(bounds.position, bounds.end)
	var delta := target - from
	if delta.length() <= ARRIVE_DISTANCE:
		has_target = false
		queue_redraw()
		return Vector2.ZERO
	return (delta / SLOW_RADIUS).limit_length(1.0)


func _draw() -> void:
	if not has_target:
		return
	var pos := get_viewport().get_canvas_transform() * target
	draw_arc(pos, MARKER_RADIUS, 0, TAU, 24, Color(1, 1, 1, 0.5), 2.0)
