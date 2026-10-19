class_name AiPilot
extends RefCounted
## An AI that flies a player's own ship in their place (Player.pilot): the
## idle demo's ship, or the host's with "AI plays for me" (Net.ai_pilot).
## Each frame it scores a fan of moves a moment ahead against where every
## threat will be by then (enemy shots and other ships' shots, enemies and
## obstacles from how they're moving, Tetran's arms from their turn, the
## scenery's warnings, Scenery.danger_at) and takes the safest one that gets
## closest to its goal: under the enemy it's hunting (leading it), an exp
## pickup, a rescue station while it has a tail, or a gate at a fork.
## It uses everything it has: lasers whenever something is above it, missiles
## and the beam at worthwhile targets, the autocannon (off while a friendly
## ship is close enough for it to pick), rescue drones when there's someone to
## fetch, a repair kit when hurt. It shares the reactor out, re-arms after a
## respawn, spends its exp at refits and taps READY.
## It never switches on the HEAL BEAM: it heals enemies as much as friends.

const PlayerScript := preload("res://scripts/player.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const TetranScript := preload("res://scripts/tetran.gd")

const STEPS: Array[float] = [0.08, 0.2, 0.35, 0.55, 0.8, 1.1]  # s ahead each move is checked (it holds still after the last)
const STEP_WEIGHT: Array[float] = [1.0, 0.85, 0.65, 0.5, 0.35, 0.25]  # nearer trouble counts more
const DIRECTIONS := 16  # moves at full speed (and as many at half)
const SHIP_RADIUS := 16.0
const MARGIN := 34.0  # px of clearance it likes to keep
const HIT := 60.0  # cost of a predicted hit, against a few px of goal distance
const GOAL_WEIGHT := 0.012  # per px from the goal
const HOME_Y := 140.0  # px above the bottom of its movement area it hunts from
const LEAD := 0.35  # s of an enemy's sideways drift it aims ahead
const AIM := 16.0  # px: lined up enough to fire
const SAFE_LINE := 26.0  # px: a friendly ship this close to its column holds its fire
const PICKUP_REACH := 520.0  # px it detours for exp (nearly anywhere on screen)
const THREAT_REACH := 420.0  # px: farther things are ignored
const TETRAN_RANGE := 280.0  # px from Tetran's core it likes to sit
const TETRAN_GAP_MARGIN := 0.35  # rad it keeps from either arm of its gap
const KEEP_COST := 0.2  # per unit of change from its current move: no flip-flopping between equals
const STEER_SMOOTH := 0.3  # of the way to the new best move each frame
const MANAGE_EVERY := 1.0  # s between loadout checks (power, guns)
const READY_DELAY := 1.5  # s it browses the refit before tapping READY
const SYSTEM_ORDER: Array[StringName] = [&"shields", &"engines", &"option", &"rescue", &"medbay", &"autopilot", &"beacon", &"weapons"]
const SKIP_BUYS: Array[StringName] = [&"healbeam"]

var _move := Vector2.ZERO  # the move it's making, eased toward each frame's best
var _last := {}  # instance id -> position last frame, for how things are moving
var _vel := {}  # instance id -> px/s
var _manage_left := 0.0
var _refit_wait := READY_DELAY
var _readied := false
var _bought_refit := false
var _gate := -1  # the gate it picked at this fork
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## Owner, each frame in place of the player's input.
func think(ship: Node2D, delta: float) -> void:
	var game: Node = ship.get_tree().get_first_node_in_group("game")
	if game == null or not ship.is_alive() or game.over:
		ship.input_dir = Vector2.ZERO
		_track(game, delta)
		return
	_manage_left -= delta
	if _manage_left <= 0.0:
		_manage_left = MANAGE_EVERY
		manage(ship)
	_track(game, delta)
	_refit(ship, game, delta)
	var goal := goal_for(ship, game)
	_move = _move.lerp(best_move(ship, game, goal), STEER_SMOOTH)  # eases between choices instead of snapping
	ship.input_dir = _move
	if not game.refit and not game.fork_open():
		_use_guns(ship, game)


# --- Loadout ----------------------------------------------------------------------

## Random upgrades for a demo ship: `count` free levels, then powered and armed.
static func random_loadout(ship: Node2D, r: RandomNumberGenerator, count: int) -> void:
	for i in count:
		ship.free_upgrade(r)
	share_power(ship)
	arm_guns(ship)


## Arms every gun it has (but the HEAL BEAM), lasers first, as WEAPONS allows.
static func arm_guns(ship: Node2D) -> void:
	for g in [&"lasers", &"missile", &"beam", &"auto"]:
		if ship.levels.get(g, 0) > 0 and not ship.is_armed(g):
			ship.arm(g)


## Spare reactor bars go out to the systems, a bar at a time round SYSTEM_ORDER.
static func share_power(ship: Node2D) -> void:
	var added := true
	while added and ship.power_spare() > 0:
		added = false
		for s in SYSTEM_ORDER:
			if ship.add_power(s):
				added = true


func manage(ship: Node2D) -> void:
	arm_guns(ship)
	share_power(ship)


## At a refit: spends its exp (a random affordable buy at a time), powers it
## all up, then READY a moment later.
func _refit(ship: Node2D, game: Node, delta: float) -> void:
	if not game.refit:
		_refit_wait = READY_DELAY
		_readied = false
		_bought_refit = false
		return
	if not _bought_refit:
		_bought_refit = true
		spend_exp(ship, rng)
		manage(ship)
	_refit_wait -= delta
	if _refit_wait <= 0.0 and not _readied:
		_readied = true
		game.set_refit_ready.rpc_id(1, true)


## Buys random affordable upgrades until nothing more is affordable.
static func spend_exp(ship: Node2D, r: RandomNumberGenerator) -> void:
	while true:
		var ids: Array[StringName] = []
		for it in Systems.ITEMS:
			if not SKIP_BUYS.has(it.id) and ship.can_afford(it.id):
				ids.append(it.id)
		if ids.is_empty():
			return
		ship.buy_upgrade(ids[r.randi_range(0, ids.size() - 1)])


# --- Guns -------------------------------------------------------------------------

func _use_guns(ship: Node2D, game: Node) -> void:
	var friend_close := false
	var friend_in_line := false
	for p in game.players.get_children():
		if p == ship or not p.is_alive():
			continue
		if p.position.y < ship.position.y and absf(p.position.x - ship.position.x) < SAFE_LINE:
			friend_in_line = true
		if PlayerScript.is_targetable(p) and p.position.distance_to(ship.position) < PlayerScript.AUTO_RANGE + 30.0:
			friend_close = true
	var prey := hunt(ship, game)
	var lined := prey != null and absf(aim_x(prey) - ship.position.x) < AIM + _half_width(prey)
	if ship.levels.get(&"auto", 0) > 0:
		if friend_close:
			ship.disarm(&"auto")
		elif not ship.is_armed(&"auto"):
			ship.arm(&"auto")
	if friend_in_line:
		return
	if _anything_above(ship, game):
		if ship.is_armed(&"lasers"):
			ship._fire_requested = true
		else:
			ship.arm(&"lasers")
	if ship.is_armed(&"missile") and _missile_safe(ship, game) and game.enemies.get_child_count() > 0:
		ship._missile_requested = true
	if ship.is_armed(&"beam") and lined and (prey.is_in_group("enemy") and (prey.has_bar() or _column_count(ship, game) >= 3)):
		ship._beam_requested = true
	if ship.level(&"rescue") > 0 and ship.drones_ready() > 0 and _someone_to_fetch(game):
		ship._launch_requested = true
	if ship.level(&"repair") > 0 and ship.hp <= ship.max_hp() - PlayerScript.HIT_HP:
		ship._repair_requested = true


## Something to shoot in its column, above it.
func _anything_above(ship: Node2D, game: Node) -> bool:
	for e in game.enemies.get_children():
		if not e.is_queued_for_deletion() and e.position.y < ship.position.y and e.position.y > -20.0 \
				and absf(aim_x(e) - ship.position.x) < AIM + _half_width(e):
			return true
	for o in game.obstacles.get_children():
		if o.destructible() and o.position.y < ship.position.y and o.position.y > 0.0 and absf(o.position.x - ship.position.x) < 40.0:
			return true
	return false


func _column_count(ship: Node2D, game: Node) -> int:
	var n := 0
	for e in game.enemies.get_children():
		if e.position.y < ship.position.y and absf(e.position.x - ship.position.x) < 40.0:
			n += 1
	return n


## Missiles seek the nearest ship too: only while an enemy is nearer than any friendly one.
func _missile_safe(ship: Node2D, game: Node) -> bool:
	var nearest_friend := INF
	for p in game.players.get_children():
		if p != ship and PlayerScript.is_targetable(p):
			nearest_friend = minf(nearest_friend, p.position.distance_to(ship.position))
	for e in game.enemies.get_children():
		if e.position.distance_to(ship.position) < nearest_friend:
			return true
	return false


func _someone_to_fetch(game: Node) -> bool:
	for pod in game.pods.get_children():
		if not pod.taken and not pod.is_queued_for_deletion():
			return true
	return false


# --- Goals ------------------------------------------------------------------------

## The enemy it's after: the nearest one above it on screen (the core of a
## boss with arms included), else a breakable obstacle above it; null if none.
func hunt(ship: Node2D, game: Node) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for e in game.enemies.get_children():
		if e.is_queued_for_deletion() or e.position.y < -10.0 or e.position.y > ship.position.y - 30.0:
			continue
		var d: float = absf(e.position.x - ship.position.x) + (ship.position.y - e.position.y) * 0.3
		if d < best_d:
			best_d = d
			best = e
	if best:
		return best
	for o in game.obstacles.get_children():
		if o.destructible() and o.position.y > 0.0 and o.position.y < ship.position.y - 30.0:
			var d: float = absf(o.position.x - ship.position.x)
			if d < best_d:
				best_d = d
				best = o
	return best


## Where to put its column to hit `n`: ahead of its sideways drift.
func aim_x(n: Node2D) -> float:
	var v: Vector2 = _vel.get(n.get_instance_id(), Vector2.ZERO)
	return n.position.x + v.x * LEAD


func _half_width(n: Node2D) -> float:
	if n.is_in_group("enemy"):
		var h: float = EnemyScript.TYPES[n.type].get("height", EnemyScript.HEIGHT) * n.scale.x
		return h * 0.35
	return 20.0


func goal_for(ship: Node2D, game: Node) -> Vector2:
	var bounds: Rect2 = ship._movement_bounds()
	var home := Vector2(ship.position.x, bounds.end.y - HOME_Y)
	if game.fork_open():
		var gates: Array = game._gates()
		if gates.is_empty():
			return home
		if _gate < 0 or _gate >= gates.size():
			_gate = rng.randi_range(0, gates.size() - 1)
		return gates[_gate].position
	_gate = -1
	if not ship.tail.is_empty():
		for st in game.stations.get_children():
			if not st.is_queued_for_deletion() and st.position.y > 0.0:
				return st.position
	var best_pickup: Node2D = null
	var best_d := PICKUP_REACH
	for p in game.pickups.get_children():
		if p.get("collected"):
			continue
		var d: float = p.position.distance_to(ship.position)
		if d < best_d:
			best_d = d
			best_pickup = p
	if best_pickup:
		return best_pickup.position
	var tetran := _tetran(game)
	if tetran:
		return tetran_spot(ship, tetran, bounds)
	var prey := hunt(ship, game)
	if prey:
		home.x = aim_x(prey)
	else:
		home.x = lerpf(ship.position.x, bounds.get_center().x, 0.02)
	return home.clamp(bounds.position, bounds.end)


func _tetran(game: Node) -> Node2D:
	for e in game.enemies.get_children():
		if e.is_tetran() and not e.is_queued_for_deletion():
			return e
	return null


## Against Tetran: its arms can't be crossed, so it rides the gap it's in, as
## close to straight under the core as the gap allows (where its shots get through).
func tetran_spot(ship: Node2D, e: Node2D, bounds: Rect2) -> Vector2:
	var tetran: Node = e.get_node_or_null("Tetran")
	var turn := TetranScript.angle_at(tetran._time() if tetran else 0.0)
	var quarter := TAU / TetranScript.ARMS
	var mine := (ship.position - e.position).angle()
	var gap_start := turn + floorf((mine - turn) / quarter) * quarter  # the arm before it, going round
	var down := PI / 2.0
	var margin := TETRAN_GAP_MARGIN
	var want := gap_start + clampf(wrapf(down - gap_start, 0.0, TAU), margin, quarter - margin)
	if wrapf(down - gap_start, 0.0, TAU) > quarter:  # straight down isn't in this gap: the nearer end
		var to_end := wrapf(down - (gap_start + quarter), -PI, PI)
		var to_start := wrapf(down - gap_start, -PI, PI)
		want = gap_start + (quarter - margin if absf(to_end) < absf(to_start) else margin)
	for r in [TETRAN_RANGE, TETRAN_RANGE * 0.7, TETRAN_RANGE * 0.45]:
		var at: Vector2 = e.position + Vector2.from_angle(want) * r
		if bounds.has_point(at):
			return at
	return (e.position + Vector2.from_angle(want) * TETRAN_RANGE * 0.45).clamp(bounds.position, bounds.end)


# --- Moving -----------------------------------------------------------------------

## How things are moving, from where they were last frame.
func _track(game: Node, delta: float) -> void:
	if game == null or delta <= 0.0:
		return
	var seen := {}
	for group in [game.enemies, game.obstacles]:
		for n in group.get_children():
			var id: int = n.get_instance_id()
			seen[id] = true
			if _last.has(id):
				_vel[id] = (n.position - _last[id]) / delta
			_last[id] = n.position
	for id in _last.keys():
		if not seen.has(id):
			_last.erase(id)
			_vel.erase(id)


## The safest move toward `goal`, length at most 1.
func best_move(ship: Node2D, game: Node, goal: Vector2) -> Vector2:
	var threats := _threats(ship, game)
	var bounds: Rect2 = ship._movement_bounds()
	var speed: float = ship.move_speed()
	var best_dir := Vector2.ZERO
	var best_cost := INF
	var moves: Array[Vector2] = [Vector2.ZERO]
	var to_goal := goal - ship.position
	if to_goal.length() > 1.0:
		moves.append(to_goal.normalized() * minf(1.0, to_goal.length() / (speed * STEPS[0] * 2.0)))
	for i in DIRECTIONS:
		var d := Vector2.from_angle(TAU * i / DIRECTIONS)
		moves.append(d)
		moves.append(d * 0.5)
	for m in moves:
		var cost := 0.0
		var at: Vector2 = ship.position
		for k in STEPS.size():
			at = (ship.position + m * speed * STEPS[k]).clamp(bounds.position, bounds.end)
			cost += _danger(at, STEPS[k], threats, game) * STEP_WEIGHT[k]
		# It replans every frame, so passing through the goal is as good as stopping on it.
		cost += goal.distance_to(Geometry2D.get_closest_point_to_segment(goal, ship.position, at)) * GOAL_WEIGHT
		if at.x <= bounds.position.x + 1.0 or at.x >= bounds.end.x - 1.0:
			cost += 0.3  # cornered against an edge
		cost += (m - _move).length() * KEEP_COST  # sticks with what it's doing unless something's better
		if cost < best_cost - 0.0001:
			best_cost = cost
			best_dir = m
	return best_dir.limit_length(1.0)


## What could hit it soon: [{pos, vel, r}] plus the arms of any boss that has them.
func _threats(ship: Node2D, game: Node) -> Dictionary:
	var moving: Array = []
	var arms: Array = []
	for b in game.bullets.get_children():
		if b.is_queued_for_deletion() or b.shooter == ship.peer_id or b.is_heal():
			continue
		if not b.is_hostile() and game.controls(b.shooter):
			continue  # its buddy's: the same side
		if b.position.distance_to(ship.position) < THREAT_REACH:
			moving.append({"pos": b.position, "vel": b.velocity(), "r": 6.0})
	for e in game.enemies.get_children():
		if e.is_queued_for_deletion():
			continue
		if not e.is_tetran() and e.position.distance_to(ship.position) > THREAT_REACH + 200.0:
			continue
		var r: float = EnemyScript.TYPES[e.type].get("height", EnemyScript.HEIGHT) * 0.42 * e.scale.x
		if e.is_tetran():
			r = TetranScript.CORE_RADIUS * e.scale.x
			arms.append(e)
		moving.append({"pos": e.position, "vel": _vel.get(e.get_instance_id(), Vector2.ZERO), "r": r})
	for o in game.obstacles.get_children():
		if o.is_queued_for_deletion() or o.position.distance_to(ship.position) > THREAT_REACH + 200.0:
			continue
		var v: Vector2 = _vel.get(o.get_instance_id(), Vector2.ZERO)
		for part in o.parts:
			var size: Vector2 = o.piece(part.piece).size
			var c: Vector2 = o.position + Vector2(part.offset).rotated(o.rotation)
			moving.append({"pos": c, "vel": v, "r": maxf(size.x, size.y) * 0.5})
	return {"moving": moving, "arms": arms}


## How dangerous `at` is `t` s from now.
func _danger(at: Vector2, t: float, threats: Dictionary, game: Node) -> float:
	var cost := 0.0
	for th in threats.moving:
		var p: Vector2 = th.pos + th.vel * t
		cost += _near(at.distance_to(p) - th.r - SHIP_RADIUS)
	for e in threats.arms:
		var tetran: Node = e.get_node_or_null("Tetran")
		if tetran == null:
			continue
		var turn := TetranScript.angle_at(tetran._time() + t)
		var reach: float = (TetranScript.CORE_RADIUS + TetranScript.arm_length()) * e.scale.x
		for a in TetranScript.ARMS:
			var tip: Vector2 = e.position + Vector2.from_angle(TetranScript.arm_angle(turn, a)) * reach
			var c := Geometry2D.get_closest_point_to_segment(at, e.position, tip)
			cost += _near(at.distance_to(c) - TetranScript.ARM_WIDTH * 0.5 * e.scale.x - SHIP_RADIUS)
	if game.get("scenery") and game.scenery.has_method("danger_at"):
		cost += game.scenery.danger_at(at, t) * HIT
	return cost


## Cost of passing `gap` px clear of something (negative: touching it).
static func _near(gap: float) -> float:
	if gap < 0.0:
		return HIT
	if gap < MARGIN:
		var f := 1.0 - gap / MARGIN
		return f * f * 4.0
	return 0.0
