extends Control
## Virtual joystick (left side) and fire button (right side) for touch screens.

const STICK_RADIUS := 70.0
const KNOB_RADIUS := 30.0
const FIRE_RADIUS := 60.0

var direction := Vector2.ZERO
var firing := false

var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _fire_index := -1


## CanvasLayer visibility does not reliably propagate to is_visible_in_tree().
func is_active() -> bool:
	return visible and get_parent().visible


func _fire_center() -> Vector2:
	return Vector2(size.x - 100.0, size.y - 120.0)


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _stick_index:
			_stick_pos = event.position
			_update_direction()
			queue_redraw()


func _touch_down(index: int, pos: Vector2) -> void:
	if pos.distance_to(_fire_center()) <= FIRE_RADIUS * 1.4:
		_fire_index = index
		firing = true
	elif _stick_index == -1 and pos.x < size.x * 0.6:
		_stick_index = index
		_stick_origin = pos
		_stick_pos = pos
		_update_direction()
	queue_redraw()


func _touch_up(index: int) -> void:
	if index == _stick_index:
		_stick_index = -1
		direction = Vector2.ZERO
	if index == _fire_index:
		_fire_index = -1
		firing = false
	queue_redraw()


func _update_direction() -> void:
	var delta := _stick_pos - _stick_origin
	direction = (delta / STICK_RADIUS).limit_length(1.0)


func _draw() -> void:
	var fc := _fire_center()
	draw_circle(fc, FIRE_RADIUS, Color(1, 1, 1, 0.25 if firing else 0.12))
	draw_arc(fc, FIRE_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	if _stick_index != -1:
		draw_circle(_stick_origin, STICK_RADIUS, Color(1, 1, 1, 0.1))
		draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)
		draw_circle(_stick_origin + direction * STICK_RADIUS, KNOB_RADIUS, Color(1, 1, 1, 0.4))
