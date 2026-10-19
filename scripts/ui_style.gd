class_name UiStyle
## The interface look: a chamfered console. Panels are dark glass with cut
## corners and a thin bright edge, titled by a solid tab on their top edge;
## buttons are cut-corner plates, lit ones solid with dark ink on them, off
## ones just an outline. Neon cyan leads, magenta for alerts, amber for exp.
## Static helpers that draw onto any CanvasItem.

const CYAN := Color("2de2e6")  # the lead color
const PALE := Color("a8f4f6")
const AMBER := Color("ffb000")  # exp and warnings
const MAGENTA := Color("ff3d9a")  # alerts
const VIOLET := Color("b48cff")
const ICE := Color("6fa8ff")
const INK := Color("04121a")  # text on a lit plate
const GLASS := Color(0.02, 0.07, 0.11, 0.9)  # a panel's fill
const DIM := Color("1d3340")  # an unlit plate
const CUT := 8.0  # px cut off each corner
const EDGE := 2.0  # px of a panel's edge line
const SIDE := 10.0  # px from a panel's side to its contents
const HEADER := 22.0  # px of a panel's title tab


## The outline of `r` with its corners cut by `cut` (clockwise from top left).
static func chamfer(r: Rect2, cut := CUT) -> PackedVector2Array:
	var c := minf(cut, minf(r.size.x, r.size.y) / 2.0)
	return PackedVector2Array([
		r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c), r.end - Vector2(0, c),
		r.end - Vector2(c, 0), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), r.position + Vector2(0, c),
	])


## A cut-corner plate, filled `c`.
static func button(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_colored_polygon(chamfer(r), c)


## A plate outlined in `c` on glass (an off switch).
static func button_outline(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_colored_polygon(chamfer(r), GLASS)
	_edge(ci, chamfer(r.grow(-EDGE / 2.0)), c)


static func _edge(ci: CanvasItem, pts: PackedVector2Array, c: Color) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, c, EDGE, true)


## A glass panel edged in `c`, `title` on a solid tab along its top. Returns
## the content rect inside it.
static func panel(ci: CanvasItem, r: Rect2, c: Color, title: String, font: Font) -> Rect2:
	ci.draw_colored_polygon(chamfer(r, CUT * 1.5), GLASS)
	_edge(ci, chamfer(r.grow(-EDGE / 2.0), CUT * 1.5), c)
	if title != "":
		var fs := 15
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tab := Rect2(r.position + Vector2(CUT * 1.5, 0), Vector2(tw + 24.0, HEADER))
		ci.draw_colored_polygon(PackedVector2Array([tab.position, Vector2(tab.end.x, tab.position.y),
			Vector2(tab.end.x - CUT, tab.end.y), Vector2(tab.position.x + CUT, tab.end.y)]), c)
		ci.draw_string(font, Vector2(tab.position.x + 12.0, tab.position.y + HEADER - 6.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	return Rect2(r.position + Vector2(SIDE, HEADER + 4.0), r.size - Vector2(SIDE * 2.0, HEADER + 10.0))


## `text` in a plate's colors: ink on a lit plate, `c` on an unlit one.
static func label(ci: CanvasItem, r: Rect2, text: String, font: Font, color: Color, fs := 14, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while tw > r.size.x - 12.0 and fs > 9:  # shrink to fit
		fs -= 1
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := r.position.x + (r.size.x - tw) / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else r.position.x + 10.0
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = r.end.x - tw - 10.0
	ci.draw_string(font, Vector2(x, r.position.y + r.size.y / 2.0 + fs / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## A row of `n` pips, `on` of them lit, starting at `at`.
static func pips(ci: CanvasItem, at: Vector2, n: int, on: int, c: Color, size := Vector2(10, 14), gap := 3.0) -> void:
	for k in n:
		ci.draw_rect(Rect2(at + Vector2(k * (size.x + gap), 0), size), c if k < on else Color(c, 0.2))
