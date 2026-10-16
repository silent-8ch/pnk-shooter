extends Node2D
## Scrolling star background, purely cosmetic and local.

const COUNT := 70
var _stars: Array[Vector3] = []  # x, y, speed


func _ready() -> void:
	for i in COUNT:
		_stars.append(Vector3(randf() * 540.0, randf() * 960.0, randf_range(40.0, 160.0)))


func _process(delta: float) -> void:
	for i in _stars.size():
		_stars[i].y += _stars[i].z * delta
		if _stars[i].y > 970.0:
			_stars[i].y = -10.0
			_stars[i].x = randf() * 540.0
	queue_redraw()


func _draw() -> void:
	for s in _stars:
		var a := remap(s.z, 40.0, 160.0, 0.25, 0.8)
		draw_circle(Vector2(s.x, s.y), 1.0 + s.z / 120.0, Color(1, 1, 1, a))
