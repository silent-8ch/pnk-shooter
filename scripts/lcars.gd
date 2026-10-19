class_name LCARS
## Star Trek LCARS look for the ship's panels: black panels framed by a
## rounded "elbow" (a thick bar down the left side sweeping into a bar along
## the top), rounded pill buttons in the classic orange / peach / lavender /
## blue palette, and black upper-case labels on them. Static helpers that
## draw onto any CanvasItem.

const ORANGE := Color("ff9900")
const PEACH := Color("ffcc99")
const TAN := Color("ff9966")
const LAVENDER := Color("cc99cc")
const BLUE := Color("9999ff")
const RED := Color("cc6666")
const DIM := Color("33302a")  # an unlit pill
const BLACK := Color.BLACK
const ELBOW := 28.0  # thickness of the frame's side bar
const TOP_BAR := 22.0  # thickness of its top bar
const RADIUS := 22.0  # the outer sweep of the elbow


static func box(c: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	return sb


## A rounded pill, filled `c`.
static func pill(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_style_box(box(c, r.size.y / 2.0), r)


## A pill outlined in `c` on black (an off switch).
static func pill_outline(ci: CanvasItem, r: Rect2, c: Color) -> void:
	pill(ci, r, c)
	pill(ci, r.grow(-2.0), BLACK)


## A panel framed by an elbow in `c`: `title` sits on the top bar, black
## behind the contents. Returns the content rect inside the frame.
static func panel(ci: CanvasItem, r: Rect2, c: Color, title: String, font: Font) -> Rect2:
	var outer := box(c, RADIUS)
	outer.corner_radius_top_right = 0
	outer.corner_radius_bottom_right = 0
	outer.corner_radius_bottom_left = int(RADIUS)
	ci.draw_style_box(outer, r)
	var inner := Rect2(r.position + Vector2(ELBOW, TOP_BAR), r.size - Vector2(ELBOW, TOP_BAR + 6.0))
	var hole := box(BLACK, RADIUS * 0.6)
	hole.corner_radius_top_right = 0
	hole.corner_radius_bottom_right = 0
	hole.corner_radius_bottom_left = 0
	ci.draw_style_box(hole, inner)
	ci.draw_rect(Rect2(r.end.x - 10.0, r.position.y, 10.0, TOP_BAR), BLACK)  # notch: the top bar ends short
	ci.draw_rect(Rect2(r.end.x - 6.0, r.position.y, 6.0, TOP_BAR), c)
	if title != "":
		var fs := 15
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := r.end.x - 18.0 - tw
		ci.draw_rect(Rect2(x - 6.0, r.position.y, tw + 12.0, TOP_BAR), BLACK)
		ci.draw_string(font, Vector2(x, r.position.y + TOP_BAR - 5.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	return inner.grow(-6.0)


## `text` in a pill's colors: black on a lit pill, `c` on an unlit one.
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
