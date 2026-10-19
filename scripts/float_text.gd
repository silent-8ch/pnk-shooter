class_name FloatText
extends Node2D
## A short bit of text that floats up from a spot and fades: the "+1" when
## this player collects exp (Game.collect_pickup). Local only.

const RISE := 34.0  # px it floats up
const LIFE := 0.8  # s
const FONT_SIZE := 18

var text := "+1"
var color := LCARS.BLUE
var _age := 0.0


static func spawn(parent: Node, at: Vector2, words: String, c: Color) -> FloatText:
	var f := FloatText.new()
	f.text = words
	f.color = c
	f.position = at
	f.z_index = 40
	parent.add_child(f)
	return f


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / LIFE, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var at := Vector2(-w / 2.0, -RISE * t)
	var a := 1.0 - t * t
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0, 0, 0, a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(color, a))
