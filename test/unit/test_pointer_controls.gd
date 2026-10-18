extends GutTest
## Tap/click-to-move pointer controls: target, steering, arrival, action-bar exclusion,
## and touch vs mouse event handling.

const PointerControls := preload("res://scripts/pointer_controls.gd")
const BOUNDS := Rect2(20, 20, 500, 920)

var layer: CanvasLayer
var pointer: Control


func before_each() -> void:
	layer = CanvasLayer.new()
	pointer = PointerControls.new()
	layer.add_child(pointer)
	add_child_autofree(layer)


func _touch(pressed: bool, pos: Vector2, index := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	pointer._input(ev)


func _drag(pos: Vector2, index := 0) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	pointer._input(ev)


func _click(pressed: bool, pos: Vector2, device := 0) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.device = device
	pointer._input(ev)


func _mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	pointer._input(ev)


# --- Touch ------------------------------------------------------------------

func test_touch_sets_target_above_finger() -> void:
	_touch(true, Vector2(200, 500))
	assert_true(pointer.has_target)
	assert_eq(pointer.target, Vector2(200, 500) + PointerControls.TOUCH_OFFSET)


func test_touch_drag_moves_target() -> void:
	_touch(true, Vector2(200, 500))
	_drag(Vector2(300, 600))
	assert_eq(pointer.target, Vector2(300, 600) + PointerControls.TOUCH_OFFSET)


func test_drag_from_other_finger_ignored() -> void:
	_touch(true, Vector2(200, 500))
	_drag(Vector2(300, 600), 1)
	assert_eq(pointer.target, Vector2(200, 500) + PointerControls.TOUCH_OFFSET)


func test_second_finger_does_not_steal_target() -> void:
	_touch(true, Vector2(200, 500))
	_touch(true, Vector2(400, 800), 1)
	assert_eq(pointer.target, Vector2(200, 500) + PointerControls.TOUCH_OFFSET)


func test_target_kept_after_release() -> void:
	_touch(true, Vector2(200, 500))
	_touch(false, Vector2(200, 500))
	assert_true(pointer.has_target)


# --- Mouse ------------------------------------------------------------------

func test_click_sets_target_at_cursor() -> void:
	_click(true, Vector2(200, 500))
	assert_eq(pointer.target, Vector2(200, 500))


func test_mouse_drag_moves_target_while_held() -> void:
	_click(true, Vector2(200, 500))
	_mouse_move(Vector2(250, 450))
	assert_eq(pointer.target, Vector2(250, 450))


func test_mouse_move_without_press_ignored() -> void:
	_click(true, Vector2(200, 500))
	_click(false, Vector2(200, 500))
	_mouse_move(Vector2(250, 450))
	assert_eq(pointer.target, Vector2(200, 500))


func test_right_click_ignored() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = Vector2(200, 500)
	pointer._input(ev)
	assert_false(pointer.has_target)


func test_touch_emulated_mouse_ignored() -> void:
	_click(true, Vector2(200, 500), InputEvent.DEVICE_ID_EMULATION)
	assert_false(pointer.has_target)


func test_mouse_release_does_not_end_touch() -> void:
	_touch(true, Vector2(200, 500))
	_click(false, Vector2(200, 500))
	_drag(Vector2(300, 600))
	assert_eq(pointer.target, Vector2(300, 600) + PointerControls.TOUCH_OFFSET, "touch still held")


# --- Steering ---------------------------------------------------------------

func test_direction_full_speed_when_far() -> void:
	_click(true, Vector2(400, 500))
	var dir: Vector2 = pointer.direction_from(Vector2(100, 500), BOUNDS)
	assert_almost_eq(dir.x, 1.0, 0.001)
	assert_almost_eq(dir.y, 0.0, 0.001)


func test_direction_slows_near_target() -> void:
	_click(true, Vector2(200, 500))
	var dir: Vector2 = pointer.direction_from(Vector2(180, 500), BOUNDS)
	assert_almost_eq(dir.length(), 20.0 / PointerControls.SLOW_RADIUS, 0.001)


func test_arrival_clears_target() -> void:
	_click(true, Vector2(200, 500))
	_click(false, Vector2(200, 500))
	assert_eq(pointer.direction_from(Vector2(201, 500), BOUNDS), Vector2.ZERO)
	assert_false(pointer.has_target)


func test_no_target_no_direction() -> void:
	assert_eq(pointer.direction_from(Vector2(100, 100), BOUNDS), Vector2.ZERO)


func test_target_clamped_to_bounds() -> void:
	_click(true, Vector2(5, -40))
	pointer.direction_from(Vector2(100, 100), BOUNDS)
	assert_eq(pointer.target, Vector2(20, 20))


# --- Action bar -------------------------------------------------------------

func _with_bar() -> Control:
	var bar: Control = ActionBar.new()
	bar.add_to_group("action_bar")
	layer.add_child(bar)
	return bar


func test_press_on_action_bar_does_not_move() -> void:
	_with_bar()
	_click(true, Vector2(270, 940))
	assert_false(pointer.has_target)
	_touch(true, Vector2(270, 940), 1)
	assert_false(pointer.has_target, "finger on the bar, even with the touch offset")


func test_steering_finger_keeps_working_while_other_finger_on_bar() -> void:
	_with_bar()
	_touch(true, Vector2(200, 500))
	_touch(true, Vector2(40, 910), 1)
	_drag(Vector2(300, 500))
	assert_eq(pointer.target, Vector2(300, 500) + PointerControls.TOUCH_OFFSET)


# --- Activation -------------------------------------------------------------

func test_hiding_layer_resets() -> void:
	_click(true, Vector2(200, 500))
	layer.visible = false
	assert_false(pointer.has_target)


func test_hidden_ignores_input() -> void:
	layer.visible = false
	_click(true, Vector2(200, 500))
	assert_false(pointer.has_target)


func test_release_while_hidden_still_ends_press() -> void:
	_click(true, Vector2(200, 500))
	pointer.visible = false  # inactive without the layer's reset
	_click(false, Vector2(200, 500))
	pointer.visible = true
	_click(true, Vector2(300, 500))
	assert_eq(pointer.target, Vector2(300, 500), "a new press is accepted")
