class_name RefitPanel
extends Control
## The refit (see Game.start_refit), as a small LCARS panel at the top of the
## screen: what's next, who's ready, and a big READY pill. Tapping READY tells
## the host (Game.set_refit_ready); tapping again takes it back. When everyone
## is ready the refit ends. Hidden the rest of the time. Touches are read
## directly like the ActionBar; PointerControls ignores touches here.

const MARGIN := 8.0
const WIDTH := 320.0
const LINE := 22.0
const READY_SIZE := Vector2(0, 46)  # full width of the content
const MOUSE_INDEX := -2

var list: Array = []  # [{name, ready}] from Game.refit_changed
var is_ready := false  # local: this player tapped READY


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var game := _game()
	if game:
		game.refit_changed.connect(_on_refit_changed)


func _game() -> Node:
	return get_tree().get_first_node_in_group("game") if is_inside_tree() else null


func _on_refit_changed(new_list: Array) -> void:
	list = new_list
	if list.is_empty():
		is_ready = false  # the refit is over
	queue_redraw()


func is_active() -> bool:
	var game := _game()
	return visible and get_parent().visible and game != null and game.refit


func panel_rect() -> Rect2:
	var w := get_viewport_rect().size.x
	var h := LCARS.TOP_BAR + 12.0 + LINE + maxi(list.size(), 1) * LINE + 8.0 + READY_SIZE.y + 14.0
	return Rect2(Vector2((w - WIDTH) / 2.0, MARGIN + 60.0), Vector2(WIDTH, h))


func ready_rect() -> Rect2:
	var r := panel_rect()
	var left := r.position.x + LCARS.ELBOW + 8.0
	return Rect2(Vector2(left, r.end.y - 14.0 - READY_SIZE.y), Vector2(r.end.x - 8.0 - left, READY_SIZE.y))


## True if a screen position falls on the panel (so it isn't a move tap).
func contains(screen_pos: Vector2) -> bool:
	return is_active() and panel_rect().has_point(_to_canvas(screen_pos))


func _to_canvas(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


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
	if ready_rect().has_point(_to_canvas(pos)):
		toggle_ready()


## Ready (or not any more): the host counts it.
func toggle_ready() -> void:
	var game := _game()
	if game == null or not game.refit or not game.input_enabled:
		return
	is_ready = not is_ready
	game.set_refit_ready.rpc_id(1, is_ready)
	queue_redraw()


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()


func _draw() -> void:
	if not is_active():
		return
	var game := _game()
	var font := get_theme_default_font()
	var inner := LCARS.panel(self, panel_rect(), LCARS.LAVENDER, "REFIT", font)
	var next := "THEN CHOOSE YOUR PATH" if game.refit_after_boss else "THEN ON TO THE BOSS"
	LCARS.label(self, Rect2(inner.position, Vector2(inner.size.x, LINE)), "BUY AND SET UPGRADES, " + next, font, LCARS.PEACH, 12, HORIZONTAL_ALIGNMENT_LEFT)
	for i in list.size():
		var p: Dictionary = list[i]
		var row := Rect2(inner.position + Vector2(0, LINE * (i + 1)), Vector2(inner.size.x, LINE))
		var on: bool = p.get("ready", false)
		LCARS.label(self, row, str(p.get("name", "Player")).to_upper(), font, LCARS.PEACH, 13, HORIZONTAL_ALIGNMENT_LEFT)
		LCARS.label(self, row, "READY" if on else "...", font, LCARS.ORANGE if on else Color(LCARS.PEACH, 0.5), 13, HORIZONTAL_ALIGNMENT_RIGHT)
	var rr := ready_rect()
	if is_ready:
		LCARS.pill(self, rr, LCARS.ORANGE)
		LCARS.label(self, rr, "READY  -  TAP TO WAIT", font, LCARS.BLACK, 16)
	else:
		LCARS.pill(self, rr, LCARS.PEACH)
		LCARS.label(self, rr, "READY", font, LCARS.BLACK, 22)
