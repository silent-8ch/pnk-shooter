class_name Rival
extends RefCounted
## The brain of a RIVAL (Enemy): a ship that flies and fights like a player,
## facing down. The host runs it: it holds the top of the screen, lines up
## over the nearest player (leading them), fires photon-style shots straight
## down when lined up, and dodges players' shots, ships and obstacles the way
## the AI pilot does (scoring a fan of moves a moment ahead). From stage
## DOUBLE_AT it fires pairs, from TRIPLE_AT threes. Other peers just follow
## the positions the host sends (Enemy.rival_at).

const SPEED := 260.0  # px/s
const TOP := Vector2(40, 90)  # its area: from here...
const BOTTOM_Y := 330.0  # ...down to here
const HOME_Y := 170.0
const AIM := 14.0  # px: lined up enough to fire
const LEAD := 0.25  # s of a player's sideways drift it aims ahead
const FIRE_INTERVAL := 0.55  # s between shots at stage 0
const FIRE_MIN := 0.3
const SPREAD := 9.0  # px between shots of a pair or three
const DOUBLE_AT := 2
const TRIPLE_AT := 4
const STEPS: Array[float] = [0.1, 0.25, 0.45, 0.7]
const DIRECTIONS := 12
const RADIUS := 20.0
const MARGIN := 26.0
const HIT := 60.0
const GOAL_WEIGHT := 0.012
const KEEP_COST := 0.2
const SMOOTH := 0.3

var move := Vector2.ZERO
var _cooldown := 0.6  # a moment before its first shot
var _last := {}  # player instance id -> position, for their drift
var _vel := {}


## Host, each physics frame: where the rival at `at` goes and whether it fires.
## Returns {pos, fire} (fire: how many shots, 0 for none).
func step(e: Node2D, game: Node, delta: float) -> Dictionary:
	_track(game, delta)
	var target := _nearest_player(e, game)
	var goal := Vector2(e.position.x, HOME_Y)
	if target:
		var v: Vector2 = _vel.get(target.get_instance_id(), Vector2.ZERO)
		goal.x = target.position.x + v.x * LEAD
	goal = goal.clamp(TOP, Vector2(540.0 - TOP.x, BOTTOM_Y))
	move = move.lerp(best_move(e, game, goal), SMOOTH)
	var pos: Vector2 = (e.position + move * SPEED * e.speed_mult() * delta).clamp(TOP, Vector2(540.0 - TOP.x, BOTTOM_Y))
	if e.position.y < TOP.y:  # still flying in from the top
		pos = Vector2(e.position.x, e.position.y + SPEED * delta)
	_cooldown -= delta
	var shots := 0
	if target and _cooldown <= 0.0 and absf(target.position.x - pos.x) < AIM and target.position.y > pos.y:
		_cooldown = maxf(FIRE_MIN, FIRE_INTERVAL * pow(0.88, e.stage))
		shots = shots_for(e.stage)
	return {"pos": pos, "fire": shots}


## Shots per volley at `stage`.
static func shots_for(stage: int) -> int:
	if stage >= TRIPLE_AT:
		return 3
	if stage >= DOUBLE_AT:
		return 2
	return 1


## Where each shot of a volley of `n` starts, beside `at`.
static func volley(at: Vector2, n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in n:
		out.append(at + Vector2((i - (n - 1) / 2.0) * SPREAD, 24.0))
	return out


func _nearest_player(e: Node2D, game: Node) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in game.players.get_children():
		if not p.is_alive():
			continue
		var d: float = absf(p.position.x - e.position.x) + absf(p.position.y - e.position.y) * 0.3
		if d < best_d:
			best_d = d
			best = p
	return best


func _track(game: Node, delta: float) -> void:
	if delta <= 0.0:
		return
	for p in game.players.get_children():
		var id: int = p.get_instance_id()
		if _last.has(id):
			_vel[id] = (p.position - _last[id]) / delta
		_last[id] = p.position


## The safest move toward `goal` (length at most 1), dodging players' shots,
## ships and obstacles a moment ahead.
func best_move(e: Node2D, game: Node, goal: Vector2) -> Vector2:
	var threats: Array = []
	for b in game.bullets.get_children():
		if b.is_queued_for_deletion() or b.is_hostile() or b.is_heal():
			continue
		if b.position.distance_to(e.position) < 360.0:
			threats.append({"pos": b.position, "vel": b.velocity(), "r": 6.0})
	for p in game.players.get_children():
		if p.is_alive():
			threats.append({"pos": p.position, "vel": Vector2.ZERO, "r": 20.0})
	for o in game.obstacles.get_children():
		for part in o.parts:
			var size: Vector2 = o.piece(part.piece).size
			threats.append({"pos": o.position + Vector2(part.offset).rotated(o.rotation), "vel": Vector2(0, 60), "r": maxf(size.x, size.y) * 0.5})
	var moves: Array[Vector2] = [Vector2.ZERO]
	for i in DIRECTIONS:
		var d := Vector2.from_angle(TAU * i / DIRECTIONS)
		moves.append(d)
		moves.append(d * 0.5)
	var best := Vector2.ZERO
	var best_cost := INF
	var lo := TOP
	var hi := Vector2(540.0 - TOP.x, BOTTOM_Y)
	for m in moves:
		var cost := 0.0
		var at: Vector2 = e.position
		for t in STEPS:
			at = (e.position + m * SPEED * t).clamp(lo, hi)
			for th in threats:
				var gap: float = at.distance_to(th.pos + th.vel * t) - th.r - RADIUS
				if gap < 0.0:
					cost += HIT
				elif gap < MARGIN:
					cost += pow(1.0 - gap / MARGIN, 2.0) * 4.0
		cost += goal.distance_to(Geometry2D.get_closest_point_to_segment(goal, e.position, at)) * GOAL_WEIGHT
		cost += (m - move).length() * KEEP_COST
		if cost < best_cost - 0.0001:
			best_cost = cost
			best = m
	return best
