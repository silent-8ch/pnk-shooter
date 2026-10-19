extends Node2D
## One side of a fork (see Game.open_fork): a glowing box on the left or right
## of the screen with the kind of level beyond it, its reward, the ships voting
## for it and the time left. Purely visual; the host counts the votes.

const SIZE := Vector2(220, 230)
const FONT_SIZE := 22

var kind := LevelKinds.FIRST
var reward := ""
var votes := 0  # set by Game each frame
var time_left := 0.0
var chosen := false


func rect() -> Rect2:
	return Rect2(position - SIZE / 2.0, SIZE)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c: Color = LevelKinds.info(kind).color
	var r := Rect2(-SIZE / 2.0, SIZE)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	draw_rect(r, Color(c, 0.12 + 0.08 * pulse + (0.25 if chosen else 0.0)))
	draw_rect(r, Color(c, 0.9), false, 3.0)
	var font := ThemeDB.fallback_font
	var w := SIZE.x - 16.0
	draw_string(font, Vector2(-w / 2.0, -SIZE.y / 2.0 + 40), LevelKinds.name_of(kind), HORIZONTAL_ALIGNMENT_CENTER, w, FONT_SIZE, Color.WHITE)
	draw_multiline_string(font, Vector2(-w / 2.0, -10), LevelKinds.REWARDS.get(reward, ""), HORIZONTAL_ALIGNMENT_CENTER, w, FONT_SIZE - 6, 3, Color("ffd45a"))
	draw_string(font, Vector2(-w / 2.0, SIZE.y / 2.0 - 46), "%d ship%s" % [votes, "" if votes == 1 else "s"], HORIZONTAL_ALIGNMENT_CENTER, w, FONT_SIZE - 4, Color(1, 1, 1, 0.85))
	if time_left > 0.0:
		draw_string(font, Vector2(-w / 2.0, SIZE.y / 2.0 - 16), "%d" % ceili(time_left), HORIZONTAL_ALIGNMENT_CENTER, w, FONT_SIZE - 4, Color(1, 1, 1, 0.6))
