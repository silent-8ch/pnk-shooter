class_name StatusBar
extends Control
## The HUD's top line in the same console look as the SHIP popups: a row of
## buttons for the score, the stage, the party's spare ships and this player's
## exp (what the SHIP popups spend).

const HEIGHT := 26.0
const GAP := 6.0
const FONT_SIZE := 14
const PAD := 22.0  # px of button either side of its text


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## The buttons left to right: [{text, color}].
func segments() -> Array[Dictionary]:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return []
	var me: Node = game.local_player()
	var out: Array[Dictionary] = [
		{"text": "SCORE %d" % game.score, "color": UiStyle.CYAN},
		{"text": "STAGE %d" % (game.stage + 1), "color": UiStyle.PALE},
		{"text": "SHIPS %d" % game.spares, "color": UiStyle.VIOLET},
	]
	if me:
		out.append({"text": "EXP %d" % me.exp_balance, "color": UiStyle.AMBER})
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	var x := 0.0
	for s in segments():
		var w: float = font.get_string_size(s.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + PAD
		var r := Rect2(Vector2(x, 0), Vector2(w, HEIGHT))
		UiStyle.button(self, r, s.color)
		UiStyle.label(self, r, s.text, font, UiStyle.INK, FONT_SIZE)
		x += w + GAP
