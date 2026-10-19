class_name Scenery
extends Node2D
## The look and hazards of a kind of level (LevelKinds), behind the action.
## Game swaps it when the kind changes (Game.scenery). This base is deep
## space: nothing beyond the starfield. Kinds extend it and override the hooks.
## Every peer runs its own copy. Anything that must match between peers
## (hazard timing and placement) comes from `run_seed` and `time` only, never
## from randf(); each peer applies hazards to the ships it flies (hurt_local).

var game: Node  # set by Game before adding
var kind := LevelKinds.FIRST
var run_seed := 0  # same on every peer: from the kind and stage
var time := 0.0  # s since this scenery came in


func _process(delta: float) -> void:
	time += delta
	step(delta)
	queue_redraw()


## Per frame, every peer (animation, hazards).
func step(_delta: float) -> void:
	pass


## Extra drift (px/s) the scenery puts on a ship at `pos`: wind, gravity. Applied by the ship's owner.
func push_at(_pos: Vector2) -> Vector2:
	return Vector2.ZERO


## How likely a ship at `pos` is to be hurt by the scenery `ahead` s from
## now, 0 (safe) to 1 (a hit): what the AI pilot steers clear of (AiPilot).
func danger_at(_pos: Vector2, _ahead: float) -> float:
	return 0.0


## Host: this kind's boss fires at `target` with `n` bullets' worth of attack.
## Return true if handled; false fires the default aimed spread.
func boss_attack(_boss: Node2D, _target: Node2D, _n: int) -> bool:
	return false


## Host: a destructible obstacle (`piece` id) was shot apart at `at`.
func on_obstacle_destroyed(_piece: String, _at: Vector2) -> void:
	pass


## Hits every ship this peer flies within `radius` of `at` for `hits` hits.
func hurt_local(at: Vector2, radius: float, hits: float) -> void:
	if game == null:
		return
	for p in game.players.get_children():
		if p.is_local() and p.is_alive() and p.position.distance_to(at) < radius + game.SHIP_RADIUS:
			p.take_damage(hits, at.y > p.position.y)


## A repeatable random number in [0, 1) for hazard `i` (same on every peer).
func roll(i: int, salt := 0) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = hash([run_seed, i, salt])
	return r.randf()
