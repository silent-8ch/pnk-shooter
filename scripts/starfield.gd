extends Node2D
## Star background, purely cosmetic and local: stars stream out of the Depth
## vanishing point in every direction, growing and brightening as they near,
## like flying forward through space.

const COUNT := 220
const FOCAL := 60.0  # screen px of spread per unit of star offset at depth 1
const NEAR := 0.05  # stars closer than this wrap back to the far end
const FAR := 30.0
const SPEED := 9.0  # depth units per second
const SPAN := 30.0  # star offsets range over +/- this (sets how wide the stream is)
const SCREEN := Rect2(-8, -8, 556, 976)

var _stars: Array[Vector3] = []  # x, y offset around the point; z = depth


func _ready() -> void:
	for i in COUNT:
		# Biased near so the outer screen isn't empty at start (the stream evens it out).
		_stars.append(_random_star(lerpf(NEAR, FAR, pow(randf(), 1.5))))


func _random_star(z: float) -> Vector3:
	return Vector3(randf_range(-SPAN, SPAN), randf_range(-SPAN, SPAN), z)


## Screen position of a star.
static func project(s: Vector3) -> Vector2:
	return Vector2(Depth.VANISH_X, Depth.VANISH_Y) + Vector2(s.x, s.y) * FOCAL / s.z


func _process(delta: float) -> void:
	for i in _stars.size():
		_stars[i].z -= SPEED * delta
		if _stars[i].z < NEAR or not SCREEN.has_point(project(_stars[i])):
			_stars[i] = _random_star(randf_range(FAR * 0.8, FAR))
	queue_redraw()


func _draw() -> void:
	for s in _stars:
		var near := 1.0 / s.z  # apparent size falls off with depth
		draw_circle(project(s), clampf(0.4 + 6.0 * near, 0.4, 2.6), Color(1, 1, 1, clampf(0.1 + 3.0 * near, 0.1, 0.9)))
