extends Node2D
## Rescue station: drifts slowly down the screen. A ship that flies within
## RADIUS hands over its tail of rescued enemy pods and astronauts (Player._dock_tail): they
## pile in one after another, and the pilot gets an exp (the team
## Game.RESCUE_POINTS) for each. Local on every peer, like escape pods; the host
## sends it in (Game.spawn_station) and the ship's owner decides when it docks.
## Drawn in code until it has art: a slowly turning hexagonal ring with
## blinking lights around a core that flares as each pod arrives.

const EnemyScript := preload("res://scripts/enemy.gd")
const PlayerScript := preload("res://scripts/player.gd")
const PodScript := preload("res://scripts/escape_pod.gd")
const SPEED := 40.0  # px/s down the screen
const RADIUS := 70.0  # px from the center: close enough to hand over a tail
const SIZE := 34.0  # ring radius
const OFFSCREEN := 80.0
const FLY_TIME := 0.35  # s for a pod to fly in
const FLY_STAGGER := 0.08  # s between pods
const RING_COLOR := Color(0.45, 0.95, 0.85)
const CORE_COLOR := Color(0.35, 1.0, 0.45)  # escape pod beacon green
const SPIN := 0.6  # radians per second
const BLINK_RATE := 1.5

var _age := 0.0
var _flare := 0.0  # 1 as a pod arrives, fades out


func _ready() -> void:
	add_to_group("station")


func _process(delta: float) -> void:
	_age += delta
	_flare = maxf(0.0, _flare - delta * 3.0)
	position.y += SPEED * delta
	queue_redraw()
	if position.y > EnemyScript.EXIT_Y + OFFSCREEN:
		queue_free()


## Whether a ship at `pos` (same space as the station) is close enough to dock.
func in_reach(pos: Vector2) -> bool:
	return position.distance_to(pos) <= RADIUS


## Every peer: the pods of enemy `types`, starting at `from` (game space),
## fly in one after another and vanish into the core.
func receive(from: Array, types: Array) -> void:
	for i in mini(from.size(), types.size()):
		var entry := int(types[i])
		var s := Sprite2D.new()
		s.texture = PlayerScript.tail_texture(entry)
		s.scale = PlayerScript.tail_scale(entry)
		s.flip_v = entry != PodScript.ASTRONAUT
		s.light_mask = Ships.LIGHT_MASK
		s.position = from[i] - position
		add_child(s)
		var tw := s.create_tween()
		tw.tween_interval(FLY_STAGGER * i)
		tw.tween_property(s, "position", Vector2.ZERO, FLY_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(s, "scale", s.scale * 0.3, FLY_TIME)
		tw.tween_callback(_arrived.bind(s))


func _arrived(s: Sprite2D) -> void:
	_flare = 1.0
	s.queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(RING_COLOR, 0.05))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(RING_COLOR, 0.18), 1.5, true)
	var a0 := _age * SPIN
	var pts := PackedVector2Array()
	for i in 7:
		pts.append(Vector2.from_angle(a0 + TAU * i / 6.0) * SIZE)
	draw_polyline(pts, RING_COLOR, 3.0, true)
	for i in 6:
		var p := pts[i]
		draw_line(p * 0.35, p, Color(RING_COLOR, 0.6), 2.0, true)
		var lit := fposmod(_age * BLINK_RATE + i / 6.0, 1.0) < 0.5
		draw_circle(p, 3.0, CORE_COLOR if lit else Color(CORE_COLOR, 0.25))
	draw_circle(Vector2.ZERO, SIZE * 0.32 * (1.0 + 0.4 * _flare), Color(CORE_COLOR, 0.55 + 0.45 * _flare))
