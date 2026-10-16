extends Area2D
## Player bullet. Server-simulated; position replicated.

const SPEED := 700.0

@export var color := Color.YELLOW


func _ready() -> void:
	$Body.color = color


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	position.y -= SPEED * delta
	if position.y < -40.0:
		queue_free()
