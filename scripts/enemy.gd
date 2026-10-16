extends Area2D
## Basic enemy that drifts down the screen. Server-simulated.

const SPEED := 160.0
const HP := 2
const POINTS := 10

var hp := HP


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	position.y += SPEED * delta
	if position.y > 1020.0:
		queue_free()


func take_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	hp -= amount
	if hp <= 0:
		get_tree().get_first_node_in_group("game").add_score(POINTS)
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if not multiplayer.is_server():
		return
	if area.is_in_group("bullet"):
		area.queue_free()
		take_damage(1)
