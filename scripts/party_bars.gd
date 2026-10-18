extends Control
## MMO-style party frames in the HUD: one row per player (yours first), with
## their name in their color over a green health bar (hp / max_health, both
## replicated). A ship that's down shows an empty bar marked DOWN.

const ROW_HEIGHT := 30.0
const BAR_SIZE := Vector2(150, 10)
const NAME_SIZE := 13
const BAR_BACK := Color(0.05, 0.15, 0.07, 0.75)
const BAR_FILL := Color("4cdc5a")
const BAR_EDGE := Color(1, 1, 1, 0.35)
const DOWN_COLOR := Color(1, 0.45, 0.45)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## Players in display order: the local one first, then by join order.
func rows() -> Array[Node]:
	var game := get_tree().get_first_node_in_group("game")
	var out: Array[Node] = []
	if game == null:
		return out
	var me: Node = game.local_player()
	if me:
		out.append(me)
	for p in game.players.get_children():
		if p != me and not p.is_queued_for_deletion():
			out.append(p)
	return out


## Fraction of the bar filled for `p`.
static func fill_of(p: Node) -> float:
	return clampf(p.hp / maxf(p.max_health, 1.0), 0.0, 1.0)


func _draw() -> void:
	var font := get_theme_default_font()
	var y := 0.0
	for p in rows():
		draw_string(font, Vector2(0, y + NAME_SIZE), p.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, p.color)
		var bar := Rect2(Vector2(0, y + NAME_SIZE + 4), BAR_SIZE)
		draw_rect(bar, BAR_BACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill_of(p), bar.size.y)), BAR_FILL)
		draw_rect(bar, BAR_EDGE, false, 1.0)
		if not p.is_alive():
			draw_string(font, Vector2(bar.end.x + 6, bar.end.y), "DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DOWN_COLOR)
		y += ROW_HEIGHT
