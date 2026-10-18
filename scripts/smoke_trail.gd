extends Line2D
## Missile smoke trail (Gundam style): a thick white line along the path the
## missile flew. Each point lives LIFE seconds; the newest end is thin and
## bright, older smoke swells and fades. Lives in world space (Game.effects),
## so it lingers and fades out after its missile is gone.

const LIFE := 0.7  # s a puff of smoke lingers
const SPACING := 6.0  # px between recorded points
const WIDTH := 7.0  # px at the oldest, widest point
const COLOR := Color(0.92, 0.93, 0.95)

var _ages: Array[float] = []  # per point, oldest first (same order as points)
var _done := false  # the missile is gone: fade out, then free


func _init() -> void:
	width = WIDTH
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = true
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))  # oldest: swollen
	curve.add_point(Vector2(1.0, 0.25))  # newest: thin, at the missile
	width_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(COLOR, 0.0))
	g.set_color(1, Color(COLOR, 0.75))
	gradient = g


## Moves the head to the missile's current position (world space); once it's
## SPACING past the last fixed point, the head stays as a new point.
func emit(pos: Vector2) -> void:
	var n := get_point_count()
	if n >= 2 and get_point_position(n - 2).distance_to(pos) < SPACING:
		set_point_position(n - 1, pos)  # the head rides on the missile
		return
	add_point(pos)
	_ages.append(0.0)


## The missile is gone: let the smoke fade out, then free.
func finish() -> void:
	_done = true


func _process(delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	while not _ages.is_empty() and _ages[0] > LIFE:
		_ages.pop_front()
		remove_point(0)
	if _done and _ages.is_empty():
		queue_free()
