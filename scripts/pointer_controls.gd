extends Control
## Tap/click-to-move controls for touch and mouse: pressing sets a destination
## the ship flies to, dragging moves it, and the ship fires while pressed. A
## quick tap or click always fires at least once.

const TOUCH_OFFSET := Vector2(0, -80)  # keep the ship above the finger
const MOUSE_INDEX := -2  # pointer index used for the mouse
const ARRIVE_DISTANCE := 4.0
const SLOW_RADIUS := 40.0  # ease in over this distance to avoid overshoot
const TAP_FIRE_TIME := 0.2  # > player FIRE_COOLDOWN, so a tap always shoots
const MARKER_RADIUS := 10.0

var target := Vector2.ZERO
var has_target := false
var firing := false

var _pointer_index := -1
var _tap_fire_timer := 0.0


func _ready() -> void:
	var layer := get_parent()
	if layer is CanvasLayer:
		layer.visibility_changed.connect(reset)


## CanvasLayer visibility does not reliably propagate to is_visible_in_tree().
func is_active() -> bool:
	return visible and get_parent().visible


func reset() -> void:
	_pointer_index = -1
	_tap_fire_timer = 0.0
	has_target = false
	firing = false
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
		_handle_press(event.pressed, event.index, event.position + TOUCH_OFFSET)
	elif event is InputEventScreenDrag:
		if _accepting_input():
			pointer_drag(event.index, event.position + TOUCH_OFFSET)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press(event.pressed, MOUSE_INDEX, event.position)
	elif event is InputEventMouseMotion:
		if _accepting_input():
			pointer_drag(MOUSE_INDEX, event.position)


func _handle_press(pressed: bool, index: int, screen_pos: Vector2) -> void:
	if not pressed:
		pointer_up(index)
	elif _accepting_input():
		pointer_down(index, screen_pos)


func pointer_down(index: int, screen_pos: Vector2) -> void:
	if _pointer_index != -1:
		return
	_pointer_index = index
	_tap_fire_timer = TAP_FIRE_TIME
	_set_target(screen_pos)


func pointer_drag(index: int, screen_pos: Vector2) -> void:
	if index == _pointer_index:
		_set_target(screen_pos)


func pointer_up(index: int) -> void:
	if index == _pointer_index:
		_pointer_index = -1
		_update_firing()


func _set_target(screen_pos: Vector2) -> void:
	target = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	has_target = true
	_update_firing()
	queue_redraw()


func _update_firing() -> void:
	firing = _pointer_index != -1 or _tap_fire_timer > 0.0


func _process(delta: float) -> void:
	if _tap_fire_timer > 0.0:
		_tap_fire_timer -= delta
		_update_firing()


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
