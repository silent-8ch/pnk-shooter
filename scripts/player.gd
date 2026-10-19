extends Area2D
## A player ship. The owning peer simulates it (movement, firing, damage to
## itself) and replicates position and hp to everyone else, so it never waits
## on the network.
## Exp is a currency: `exp_balance` is the spendable balance, `exp_total` the lifetime
## count. The ship is built FTL-style from Systems: exp buys reactor bars,
## system capacity, guns, drones and hull (ShipPanel, `levels`), and the
## pilot shares the reactor's power out between the systems (ShipPanel,
## `power`) and arms guns from the action bar (`armed`). What's in effect
## follows the power, not what was bought (level()). It's all lost when the
## ship is destroyed, but the ship drops an escape pod carrying it
## (Game.spawn_player_pod): if it's saved (touched by any ship or picked up by
## any rescue drone) it comes back (recover_upgrades).
## Health is HIT_HP per hit out of MAX_HP, so partial hits (vulcan rounds) show.
## ARMOR adds one hit's worth of max hp per level.
## MEDBAY 1 adds a REPAIR button that drops a repair kit (RepairKit) where the
## ship is; the first damaged ship over it heals. MEDBAY 2 heals every ship
## within HEAL_RANGE (itself included) HEAL_HITS every HEAL_INTERVAL s (each
## peer applies it to its own ship from the replicated `medbay`); MEDBAY 3
## brings kits back twice as fast.
## SHIELDS recharge a hit every SHIELD_REGEN s while powered (the front at 1,
## the rear too at 2, twice as fast at 3) and drop when switched off.
## Options are small copies of the ship that trail along the path it flew
## (every peer builds the trail from the replicated position) and fire whatever
## the ship fires.
## Friendly fire is always on: other players' bullets hurt (your own never do).
## RESCUE adds a button that launches search-and-rescue drones, option-sized
## copies of the ship, one per powered rescue drone, to a siren. Each fetches one escape
## pod or astronaut at a time: out to the nearest, back to the ship with it,
## and out again until DRONE_TIME is up or there's nothing left to fetch. The
## owner flies them; their positions replicate so everyone sees them. Rescued
## enemy pods and astronauts then trail behind the ship (and its options) like
## a tail, up to TAIL_MAX; flying near a rescue Station turns them all in for
## an exp each and score. When the ship is lost, its tail and whatever its
## drones carry spill out as astronauts (two per pod) to be rescued again.
## MISSILE adds a MISSILE button: the ship and each option fire a salvo of
## seeking missiles (each does a laser's damage), one per MISSILE level, fanned
## out sideways before they curl in on targets, trailing smoke. Each level also
## reloads MISSILE_RELOAD faster (base: twice the laser cooldown).
## BEAM adds a BEAM button: for a moment the ship pours a dense
## stream of laser bullets straight up from the spot where it was fired (the
## stream stays there even as the ship moves). Each level makes it thicker
## (more columns) and last longer.
## BEACON turns on a friendly beacon (a blinking ring in the ship's color):
## other players' autocannons and missiles won't pick this ship as a target,
## and fly straight through it if it's in the way.
## +SHIP buys a spare ship for the whole party (Game.spares): a
## destroyed ship only comes back while there's a spare left.
## AUTOPILOT flies the ship while you're not steering it: it holds the spot
## you last moved it to (`autopilot_anchor`), sliding out of the way of
## enemies, obstacles and incoming shots and coming back after.
## Guns fire from the action bar once armed: a tap on a gun's button arms it
## (if WEAPONS has the bars, adding them from the reactor if it can), the next
## taps fire, and a long press disarms it. AUTO and HEAL fire on their own
## while armed, so for them a tap is the on/off switch.
## AUTOCAN adds an AUTO on/off button for a vulcan cannon: while on, it hoses
## whatever is closest within AUTO_RANGE with tiny, fast rounds: enemy shots
## first (point defence, leading them), then enemies and other players alike.
## HEALBEAM adds a HEAL on/off button: while on, the ship streams fast HEAL
## shots straight up (HEALBEAM_INTERVAL, halved at level 2). Another ship they
## hit heals a tenth of a hit per shot; an enemy they hit gets stronger and
## bigger instead (Enemy.strengthen), so aim it with care.

const BulletScript := preload("res://scripts/bullet.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const PodScript := preload("res://scripts/escape_pod.gd")
const SPEED := 340.0
const FIRE_COOLDOWN := 0.45  # min time between shots; matches the Lasers button cooldown
const RESPAWN_TIME := 2.0
const MAX_HP := 100.0
const HIT_HP := 34.0  # hp one hit takes (3 hits from full)
const SPEED_STEP := 0.2  # +20% move speed per SPEED level
const RAPID_STEP := 0.8  # cooldown x0.8 per RAPID level
const DOUBLE_SPREAD := 9.0  # side offset of each DOUBLE shot
const TRIPLE_SPREAD := 13.0  # side offset of the outer TRIPLE shots
const SHIELD_HITS := 3  # hits each shield (front, rear) absorbs
const SHIELD_RADIUS := 26.0
const BEACON_RADIUS := 31.0  # friendly beacon ring, just outside the shields
const BEACON_BLINK := 1.5  # blinks per second
const SHIELD_REGEN := 4.0  # s per shield hit recharged while SHIELDS are powered (halved at 3)
const HEAL_RANGE := 120.0  # MEDBAY 2 heals ships this close
const HEAL_INTERVAL := 3.0
const HEAL_HITS := 0.5  # per HEAL_INTERVAL
const AURA_ALPHA := 0.12
const AURA_COLOR := Color("6dff7a")
const OPTION_SCALE := 0.5  # option size relative to the ship
const OPTION_GAP := 40.0  # px of flown path between the ship and each option
const TAIL_GAP := 22.0  # px of flown path between rescued pods in the tail
const TAIL_MAX := 12  # rescued pods the tail holds
const TAIL_SCALE := 0.5  # tail pod size relative to an enemy (EscapePod.SCALE)
const TRAIL_STEP := 4.0  # px between recorded trail points
const DRONE_SPEED := 220.0  # px/s top speed
const DRONE_THRUST := 260.0  # px/s² along its heading, while it burns
const DRONE_TURN := 5.0  # rad/s
const DRONE_BURN_ANGLE := 0.35  # rad: only burns when facing this close to where it wants to go
const DRONE_BRAKE := 0.7  # of its thrust it plans to stop with (it has to turn round first)
const DRONE_REACH := 14.0  # px: close enough to grab a pod or dock
const DRONE_APPROACH := 40.0  # px/s it creeps in at for the last stretch
const DRONE_GRAB_RANGE := 40.0  # px: once this close and slow enough, it grabs or docks
const DRONE_DOCK_SPEED := 80.0  # px/s: slow enough (against what it meets) to grab or dock
const DRONE_RADIUS := 8.0  # px: what touches it
const DRONE_AVOID := 70.0  # px of clearance it tries to keep from enemies and obstacles
const DRONE_SAFE_SHOT := 40.0  # px a shot travels before it can hit a drone (not the muzzle flash at launch)
const DRONE_SEARCH_OUT := 170.0  # px ahead it flies to look around when there's nothing to fetch
const DRONE_LOOK_TIME := 1.6  # s it hovers there looking one side, then the other
const DRONE_LOOK_ANGLE := 1.3  # rad either side of straight ahead it looks
enum { SEARCH_OUT_PHASE, SEARCH_LOOK_PHASE, SEARCH_DONE }
const DRONE_REBUILD := 6.0  # s before a destroyed drone can launch again
const DRONE_TIME := 10.0  # s: each drone heads home for good after this long out
const DRONE_TINT := Color(0.7, 1.0, 0.75)
const MISSILE_COOLDOWN := FIRE_COOLDOWN * 2.0  # at level 1; matches the MISSILE button cooldown
const MISSILE_RELOAD := 0.9  # cooldown x this per MISSILE level after the first
const MISSILE_FAN := 1.2  # rad: a salvo fans out up to this far either side of straight up
const BEAM_COOLDOWN := 3.0  # matches the BEAM button cooldown
const BEAM_INTERVAL := 0.05  # s between bullets in each column
const BEAM_TIMES: Array[float] = [0.8, 1.2, 1.6]  # s the beam lasts, by level
const BEAM_SPACING := 7.0  # px between columns; level n has 2n-1 columns
const AUTO_RANGE := 130.0  # px: targets this close
const AUTO_COOLDOWN := 0.035  # s between vulcan rounds (halved at level 2)
const AUTO_SPREAD := 0.09  # rad: rounds scatter up to this much either way
const HEALBEAM_INTERVAL := 0.1  # s between heal shots (halved at level 2)
const HEAL_SOUND_GAP := 0.5  # s: a stream of heals chimes at most this often
const REPAIR_COOLDOWN := 10.0  # matches the REPAIR button cooldown
const AI_WINGMAN_GAP := 80.0  # px beside its leader
const AI_SIDE_SWITCH := 60.0  # leader this far off center: buddy takes the other side
const AI_HUNT_RANGE := 160.0  # px either side of its post it will slide to hunt
const AI_MIN_ABOVE := 40.0  # only hunts enemies at least this far above it
const AI_LOOKAHEAD := 220.0
const AI_AIM := 14.0  # px: lined up enough to fire
const AI_SAFE_LINE := 26.0  # px: a player this close to its column blocks its fire
const AI_DANGER := 70.0  # px: starts dodging
const AI_SPACING := 50.0  # px: keeps this far from other ships
const AI_SLOWDOWN := 40.0  # px from its target where it eases off
const AI_DODGE := 2.5  # how hard dodging outweighs heading for its target
const AUTOPILOT_SHOT_LOOKAHEAD := 0.3  # s ahead it dodges shots coming at it
const AUTOPILOT_SHOT_DANGER := 45.0  # px
const SHIP_RADIUS := 14.0  # obstacle reach (the collision circle)
const BUMP_DAMAGE := 0.25  # hits, running into an obstacle
const BUMP_COOLDOWN := 0.6
const CRUSH_DPS := 2.0  # hits per second while pinned

@export var peer_id := 1
@export var player_name := "Player"
@export var color := Color.WHITE
@export var ship := 0  # index into Ships.LIST
@export var palette := 0  # index into Ships.PALETTES
var spawn_position := Vector2.ZERO
var spawn_data := {}  # what Game.add_player built it from, re-sent to late joiners

var hp := MAX_HP  # replicated
var max_health := MAX_HP  # replicated: max_hp(), for other peers' health bars
var shield := 0  # replicated: hits left on the front shield (blocks hits from ahead)
var rear_shield := 0  # replicated: hits left on the rear shield (blocks hits from behind)
var drone_headings: Array = []  # replicated (untyped): which way each drone faces, radians
var _rebuild: Array[float] = []  # local: s left rebuilding each destroyed drone
var drones: Array = []  # replicated (untyped, so the synchronizer can set it): where each drone that's out is (same space as the ship's)
var drone_carrying := 0  # local: rescues the host confirmed on board, across the drones
var _runs: Array[Dictionary] = []  # local, one per drone out (same order as `drones`): time out, the pod it's heading for, the pod it's bringing back ("" = none) and whether the host confirmed it
var _drone_claimed := {}  # local: pod name -> its tail entry (_tail_entry), for claims sent to the host and not yet unloaded
var beacon := false  # replicated: friendly beacon on (PILOTING 2)
var medbay := 0  # replicated: MEDBAY power, so every peer knows who heals nearby
var _heal_timer := 0.0
var _regen_timer := 0.0
var tail: Array = []  # replicated (untyped, so the synchronizer can set it): enemy types of the pods rescued, trailing behind the options
var _tail_sprites: Array[Sprite2D] = []
var _launch_requested := false
var _seen_rescues := -1  # local: RESCUE button press count already handled
var _drone_sprites: Array[Sprite2D] = []
var _healbeam_cooldown := 0.0
var _seen_heals := -1  # local: HEAL button press count already handled
var _heal_sound_at := -INF  # local: when this ship last chimed (s, engine time)
var _missile_requested := false
var _missile_cooldown := 0.0
var _seen_missiles := -1  # local: MISSILE button press count already handled
var _beam_requested := false
var _beam_cooldown := 0.0
var _beam_left := 0.0  # s of beam still to fire
var _beam_tick := 0.0  # s until its next volley
var _beam_origin := Vector2.ZERO  # where it was fired; the stream stays here
var _seen_beams := -1  # local: BEAM button press count already handled
var _auto_cooldown := 0.0
var _seen_autos := -1  # local: AUTO button press count already handled
var _repair_requested := false
var _bump_cooldown := 0.0
var ai := false  # the host's AI buddy: the host flies it with _think()
var pilot: AiPilot  # an AI flying this player's own ship for them (the demo, "AI plays for me")
var _ai_side := 1.0  # which side of its leader it flies on
var _repair_cooldown := 0.0
var _seen_repairs := -1  # local: REPAIR button press count already handled
var _drops := 0  # local: escape pods and repair kits named so far
var _stashes := {}  # local: our escape pod name -> upgrades it carries
var _recovered: Array[Dictionary] = []  # local: saved while we were dead; applied at respawn
var options := 0  # replicated: option count
var exp_total := 0  # local: exp this player has collected (lifetime)
var exp_balance := 0  # local: spendable exp balance
var levels := {}  # local: Systems item id -> level bought (system capacity, reactor bars, gun levels, ...)
var power := {}  # local: system id -> bars powered
var armed := {}  # local: gun id -> true while armed
var _seen_holds := {}  # local: action id -> long-press count already handled
var _trail: Array[Vector2] = []  # flown path, newest first, TRAIL_STEP apart
var _option_sprites: Array[Sprite2D] = []
var input_dir := Vector2.ZERO
var _fire_requested := false  # a Lasers press waiting for the cooldown check
var _seen_presses := -1  # local: Lasers button press count already handled (-1 = not synced yet)
var _cooldown := 0.0
var _respawn_timer := 0.0
var _awaiting_spare := false
var autopilot_anchor := Vector2.ZERO  # local: where the autopilot holds (the last spot you moved to)
var _anchored := false  # local: asked the host for a spare ship, no answer yet
var _damage_carry := 0.0  # fractions of a hit not yet adding up to one

@onready var body: Sprite2D = $Body
@onready var label: Label = $Label


func _ready() -> void:
	label.text = player_name
	body.texture = Ships.get_lit_texture(ship, palette)
	body.scale = Ships.get_scale(ship, palette)
	body.light_mask = Ships.LIGHT_MASK
	Ships.apply_hitbox(self, ship, body)
	area_entered.connect(_on_area_entered)
	_start_loadout()
	if Net.all_weapons and multiplayer.multiplayer_peer != null and is_local() and not ai:
		max_upgrades()


## True on the peer that flies this ship: its owner, or the host for an AI buddy.
func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id() or (ai and multiplayer.is_server())


func is_alive() -> bool:
	return hp > 0


func _process(delta: float) -> void:
	body.modulate.a = 1.0 if is_alive() else 0.25
	queue_redraw()  # shield ring
	_update_options()
	_update_drone_sprites()
	if multiplayer.multiplayer_peer == null:
		return
	if is_local():
		if pilot:
			pilot.think(self, delta)
		elif ai:
			_think()
		else:
			_gather_input()


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and is_local():
		max_health = max_hp()
		_simulate(delta)


func _gather_input() -> void:
	var dir := Vector2.ZERO
	var fire := false
	var pointer := get_tree().get_first_node_in_group("pointer_controls")
	var steering := false
	if pointer and pointer.is_active():
		dir = pointer.direction_from(position, _movement_bounds())
		steering = pointer.is_touching() or pointer.has_target
		if steering:
			autopilot_anchor = pointer.target.clamp(_movement_bounds().position, _movement_bounds().end)
			_anchored = true
	var bar := get_tree().get_first_node_in_group("action_bar")
	if bar and bar.is_active():
		var count: int = bar.presses[&"lasers"]
		fire = _seen_presses >= 0 and count != _seen_presses
		_seen_presses = count
		var rescues: int = bar.presses[&"rescue"]
		if _seen_rescues >= 0 and rescues != _seen_rescues:
			_launch_requested = true
		_seen_rescues = rescues
		var missiles: int = bar.presses[&"missile"]
		if _seen_missiles >= 0 and missiles != _seen_missiles:
			if is_armed(&"missile"):
				_missile_requested = true
			else:
				arm(&"missile")
		_seen_missiles = missiles
		var beams: int = bar.presses[&"beam"]
		if _seen_beams >= 0 and beams != _seen_beams:
			if is_armed(&"beam"):
				_beam_requested = true
			else:
				arm(&"beam")
		_seen_beams = beams
		var autos: int = bar.presses[&"auto"]
		if _seen_autos >= 0 and autos != _seen_autos:
			toggle_gun(&"auto")
		_seen_autos = autos
		var heals: int = bar.presses[&"heal"]
		if _seen_heals >= 0 and heals != _seen_heals:
			toggle_gun(&"healbeam")
		_seen_heals = heals
		for g in [&"lasers", &"missile", &"beam"]:  # a long press disarms
			var holds: int = bar.holds.get(g, 0)
			if _seen_holds.get(g, -1) >= 0 and holds != _seen_holds[g]:
				disarm(g)
			_seen_holds[g] = holds
		var repairs: int = bar.presses[&"repair"]
		if _seen_repairs >= 0 and repairs != _seen_repairs:
			_repair_requested = true
		_seen_repairs = repairs
	var game := get_tree().get_first_node_in_group("game")
	if not steering and level(&"autopilot") > 0 and game and is_alive():
		dir = autopilot_dir(game)
	if game and not game.input_enabled:
		dir = Vector2.ZERO
		fire = false
	input_dir = dir
	if fire:  # before the bar is drawn, so an armed laser lights at once
		if is_armed(&"lasers"):
			_fire_requested = true
		else:
			arm(&"lasers")
	if bar:
		bar.set_cooldown(&"lasers", fire_cooldown())
		bar.set_cooldown(&"missile", missile_cooldown())
		bar.set_shown(&"rescue", level(&"rescue") > 0)
		bar.set_enabled(&"rescue", is_alive() and drones_ready() > 0)
		for g in Systems.guns():
			var action := Systems.gun_action(g.id)
			bar.set_shown(action, levels.get(g.id, 0) > 0)
			bar.set_lit(action, is_armed(g.id))
			bar.set_power(action, g.power)
		bar.set_shown(&"repair", level(&"repair") > 0)


func _simulate(delta: float) -> void:
	if not is_alive():
		_fire_requested = false
		_launch_requested = false
		_missile_requested = false
		_beam_requested = false
		_beam_left = 0.0
		_repair_requested = false
		_recall_drone()
		_respawn_timer -= delta
		if _respawn_timer <= 0.0 and not _awaiting_spare:
			var game := get_tree().get_first_node_in_group("game")
			if game == null or not "spares" in game:
				respawn()
			elif game.spares > 0:  # none left: wait (spectating) until someone buys one
				_awaiting_spare = true
				game.request_spare.rpc_id(1, String(name))
		return

	beacon = level(&"beacon") > 0
	medbay = power_of(&"medbay")
	options = level(&"option")
	_run_shields(delta)
	_run_medbay(delta)
	position += input_dir * move_speed() * delta
	var world := get_tree().get_first_node_in_group("game")
	if world and world.get("scenery"):
		position += world.scenery.push_at(position) * delta  # wind, gravity
	var bounds := _movement_bounds()
	position = position.clamp(bounds.position, bounds.end)
	_avoid_obstacles(delta, bounds)

	if _launch_requested:
		_launch_requested = false
		launch_drone()
	_dock_tail()
	_fly_drones(delta)
	_run_autocannon(delta)
	_run_healbeam(delta)
	_fire_missiles(delta)
	_run_beam(delta)
	_repair_cooldown -= delta
	if _repair_requested:
		_repair_requested = false
		drop_repair()

	_cooldown -= delta
	if _fire_requested:
		_fire_requested = false  # a press during the cooldown is dropped, not queued
		if _cooldown > 0.0:
			return
		if not is_armed(&"lasers"):
			return
		_cooldown = fire_cooldown()
		var game := get_tree().get_first_node_in_group("game")
		var guns: Array[Vector2] = [position]
		guns.append_array(option_positions())
		for g in guns:
			var muzzle := g + Vector2(0, -26)
			if level(&"double") >= 2:
				for x in [-TRIPLE_SPREAD, 0.0, TRIPLE_SPREAD]:
					game.spawn_bullet(muzzle + Vector2(x, 0), color, Vector2.UP, BulletScript.LASER, peer_id)
			elif level(&"double") == 1:
				game.spawn_bullet(muzzle + Vector2(-DOUBLE_SPREAD, 0), color, Vector2.UP, BulletScript.LASER, peer_id)
				game.spawn_bullet(muzzle + Vector2(DOUBLE_SPREAD, 0), color, Vector2.UP, BulletScript.LASER, peer_id)
			else:
				game.spawn_bullet(muzzle, color, Vector2.UP, BulletScript.LASER, peer_id)


## Owner: the host answered our request for a spare ship.
func spare_answered(ok: bool) -> void:
	_awaiting_spare = false
	if ok and not is_alive():
		respawn()


## Owner: back in a fresh ship at the spawn point, with only what our saved pods carried.
func respawn() -> void:
	_awaiting_spare = false
	_lose_upgrades()
	hp = max_hp()  # alive first, so guns can be armed again
	for st in _recovered:
		_apply_upgrades(st)
	_recovered.clear()
	if Net.all_weapons and not ai:
		max_upgrades()
	hp = max_hp()
	position = spawn_position
	autopilot_anchor = spawn_position
	if pilot:
		pilot.manage(self)


## Obstacles are solid: they push the ship out. Running into one scrapes off
## BUMP_DAMAGE (at most once per BUMP_COOLDOWN); one pinning the ship against
## the edge of its movement area crushes it at CRUSH_DPS.
func _avoid_obstacles(delta: float, bounds: Rect2) -> void:
	_bump_cooldown -= delta
	var game := get_tree().get_first_node_in_group("game")
	if game == null or not "obstacles" in game:
		return
	var res: Dictionary = game.resolve_obstacles(position, SHIP_RADIUS)
	if not res.touching:
		return
	position = res.pos.clamp(bounds.position, bounds.end)
	if position.distance_to(res.pos) > 0.5 and game.overlaps_obstacle(position, SHIP_RADIUS):
		take_damage(CRUSH_DPS * delta, res.below)  # pinned
	elif _bump_cooldown <= 0.0:
		_bump_cooldown = BUMP_COOLDOWN
		take_damage(BUMP_DAMAGE, res.below)


# --- AI buddy -------------------------------------------------------------------

## Host, each frame for an AI buddy: steers and fires in place of player input.
## It flies beside its leader (the host's ship), slides under the nearest
## enemy above it (or a breakable rock in its way) and shoots when lined up, as
## long as no other player is in the line of fire, and dodges enemies, wrecks,
## obstacles and other ships.
func _think() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null or not is_alive():
		input_dir = Vector2.ZERO
		return
	var home := position
	var leader: Node2D = game.local_player()
	if leader and leader != self and leader.is_alive():
		var mid: float = game.ARENA.size.x / 2.0
		if absf(leader.position.x - mid) > AI_SIDE_SWITCH:  # take the roomier side
			_ai_side = -1.0 if leader.position.x > mid else 1.0
		home = leader.position + Vector2(_ai_side * AI_WINGMAN_GAP, 0)
	var target := home
	var prey := ai_target(game, home)
	if prey:
		target.x = prey.position.x
	var dir := (target - position) / AI_SLOWDOWN
	dir += ai_avoidance(game) * AI_DODGE
	input_dir = dir.limit_length(1.0)
	if prey and absf(prey.position.x - position.x) < AI_AIM and not ai_friend_in_line(game):
		_fire_requested = true


## Autopilot steering: back toward the anchor, away from danger (what the AI
## buddy dodges, plus shots about to hit it).
func autopilot_dir(game: Node) -> Vector2:
	if not _anchored:
		autopilot_anchor = position
		_anchored = true
	var dir := (autopilot_anchor - position) / AI_SLOWDOWN
	dir += (ai_avoidance(game) + shot_avoidance(game)) * AI_DODGE
	return dir.limit_length(1.0)


## Push away from shots that can hurt it, where they'll be in a moment.
func shot_avoidance(game: Node) -> Vector2:
	var push := Vector2.ZERO
	for b in game.bullets.get_children():
		if b.shooter == peer_id or b.is_queued_for_deletion():
			continue
		var ahead: Vector2 = b.position + b.direction * BulletScript.KINDS[b.kind].speed * AUTOPILOT_SHOT_LOOKAHEAD
		var closest := Geometry2D.get_closest_point_to_segment(position, b.position, ahead)
		var d := position.distance_to(closest)
		if d >= AUTOPILOT_SHOT_DANGER:
			continue
		var away := (position - closest) / d if d > 0.5 else Vector2(-b.direction.y, b.direction.x)  # dead on: sidestep
		if d <= 0.5 and away.x * (position.x - 270.0) > 0.0:
			away = -away  # sidestep toward the middle, not into the edge
		push += away * (1.0 - d / AUTOPILOT_SHOT_DANGER)
	return push


## The nearest enemy above it within AI_HUNT_RANGE of `home`, or a breakable
## obstacle in its column; null if none.
func ai_target(game: Node, home: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for e in game.enemies.get_children():
		if e.is_queued_for_deletion() or e.position.y > position.y - AI_MIN_ABOVE or e.position.y < 0.0:
			continue
		if absf(e.position.x - home.x) > AI_HUNT_RANGE:
			continue
		var d := position.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	if best:
		return best
	for o in game.obstacles.get_children():
		if o.destructible() and o.position.y < position.y and position.y - o.position.y < AI_LOOKAHEAD \
				and absf(o.position.x - position.x) < AI_HUNT_RANGE / 2.0:
			return o
	return null


## Push away from nearby danger: enemies, obstacles (looking
## ahead, since they scroll down), and other ships (to keep spacing).
func ai_avoidance(game: Node) -> Vector2:
	var push := Vector2.ZERO
	for e in game.enemies.get_children():
		push += _repel(e.position, AI_DANGER)
	for o in game.obstacles.get_children():
		for part in o.parts:
			var size: Vector2 = o.piece(part.piece).size
			var c: Vector2 = o.position + Vector2(part.offset).rotated(o.rotation)
			var ahead := c + Vector2(0, AI_LOOKAHEAD * 0.5)  # where it will be shortly
			var r := maxf(size.x, size.y) / 2.0
			push += _repel(c, AI_DANGER + r) + _repel(ahead, AI_DANGER + r) * 0.5
	for p in game.players.get_children():
		if p != self and p.is_alive():
			push += _repel(p.position, AI_SPACING)
	return push


func _repel(from: Vector2, reach: float) -> Vector2:
	var d := position - from
	var dist := d.length()
	if dist >= reach:
		return Vector2.ZERO
	var away := d / dist if dist > 0.01 else Vector2.DOWN
	return away * (1.0 - dist / reach)


## True if another player is in the column its shots would fly up.
func ai_friend_in_line(game: Node) -> bool:
	for p in game.players.get_children():
		if p != self and p.is_alive() and p.position.y < position.y and absf(p.position.x - position.x) < AI_SAFE_LINE:
			return true
	return false


# --- Upgrades ----------------------------------------------------------------

## What's in effect: guns only count while armed, and what systems do follows
## their power (SPEED = ENGINES, options and rescue drones = DRONES, ...).
## Anything else is the level bought.
func level(id: StringName) -> int:
	match id:
		&"shield":
			return (1 if shield > 0 else 0) + (1 if rear_shield > 0 else 0)
		&"speed":
			return power_of(&"engines")
		&"option":
			if not is_local():
				return options
			return mini(levels.get(&"option", 0), power_of(&"drones"))
		&"rescue":
			return mini(levels.get(&"rescue", 0), power_of(&"drones") - mini(levels.get(&"option", 0), power_of(&"drones")))
		&"repair":
			return 1 if power_of(&"medbay") >= 1 else 0
		&"autopilot":
			return 1 if power_of(&"piloting") >= 1 else 0
		&"beacon":
			if not is_local():
				return 1 if beacon else 0
			return 1 if power_of(&"piloting") >= 2 else 0
		&"double", &"rapid":
			return levels.get(id, 0) if is_armed(&"lasers") else 0
		&"missile", &"auto", &"beam", &"healbeam":
			return levels.get(id, 0) if is_armed(id) else 0
	return levels.get(id, 0)


## Back to what a fresh ship has: Systems' start levels, power and armed guns.
func _start_loadout() -> void:
	levels.clear()
	for it in Systems.ITEMS:
		if it.get("start", 0) > 0:
			levels[it.id] = it.start
	power = Systems.START_POWER.duplicate()
	armed.clear()
	for g in Systems.START_ARMED:
		armed[g] = true


# --- Power ------------------------------------------------------------------------

func reactor() -> int:
	return levels.get(&"reactor", 0)


func power_of(system: StringName) -> int:
	return power.get(system, 0)


func power_used() -> int:
	var n := 0
	for s in power:
		n += power[s]
	return n


func power_spare() -> int:
	return reactor() - power_used()


## One more bar to `system`, if it has room for it and the reactor a bar spare.
func add_power(system: StringName) -> bool:
	if not Systems.is_system(system) or power_of(system) >= levels.get(system, 0) or power_spare() <= 0:
		return false
	power[system] = power_of(system) + 1
	_power_changed(system)
	return true


## One bar of `system` back to the reactor.
func remove_power(system: StringName) -> bool:
	if power_of(system) <= 0:
		return false
	_set_power(system, power_of(system) - 1)
	return true


## Switches `system` off: all its bars go back to the reactor.
func drain_power(system: StringName) -> void:
	if power_of(system) == 0:
		return
	power[system] = 0
	_power_changed(system)


## Takes `system` down to `bars` (no more than it has).
func _set_power(system: StringName, bars: int) -> void:
	power[system] = clampi(bars, 0, power_of(system))
	_power_changed(system)


## Keeps what depends on a system's power in step with it.
func _power_changed(system: StringName) -> void:
	match system:
		&"weapons":
			while weapons_used() > power_of(&"weapons"):  # not enough left for every gun: the last ones go
				var last := &""
				for g in Systems.guns():
					if is_armed(g.id):
						last = g.id
				armed.erase(last)
		&"shields":
			if power_of(&"shields") < 1:
				shield = 0
			if power_of(&"shields") < 2:
				rear_shield = 0


# --- Guns -------------------------------------------------------------------------

func is_armed(gun: StringName) -> bool:
	return armed.get(gun, false)


## WEAPONS bars the armed guns draw on.
func weapons_used() -> int:
	var n := 0
	for g in Systems.guns():
		if is_armed(g.id):
			n += g.power
	return n


## Arms `gun`, if it's bought and WEAPONS has the bars free, powering WEAPONS
## up from the reactor as far as it needs and can. Returns whether it armed.
func arm(gun: StringName) -> bool:
	if not is_alive() or not Systems.is_gun(gun) or levels.get(gun, 0) <= 0 or is_armed(gun):
		return false
	var before := power_of(&"weapons")
	while power_of(&"weapons") - weapons_used() < Systems.gun_power(gun):
		if not add_power(&"weapons"):
			_set_power(&"weapons", before)  # couldn't: leave WEAPONS as it was
			return false
	armed[gun] = true
	return true


func disarm(gun: StringName) -> void:
	armed.erase(gun)


## AUTO and HEAL: a tap switches them on (arming) or off.
func toggle_gun(gun: StringName) -> void:
	if is_armed(gun):
		disarm(gun)
	else:
		arm(gun)


# --- Upgrades ---------------------------------------------------------------------

## Whether `id` can go up a level (not at its max, and what it needs bought).
func can_upgrade(id: StringName) -> bool:
	var it := Systems.item(id)
	if it.is_empty() or levels.get(id, 0) >= it.max:
		return false
	return not it.has("needs") or levels.get(it.needs, 0) > 0


func max_hp() -> float:
	return MAX_HP + HIT_HP * level(&"armor")


func needs_repair() -> bool:
	return is_alive() and hp < max_hp()


## Owner: heals `hits` hits' worth, up to max hp (a repair kit).
func heal(hits: float) -> void:
	if is_local() and is_alive():
		var before := hp
		hp = minf(hp + hits * HIT_HP, max_hp())
		if hp > before:
			_heal_sound()


func move_speed() -> float:
	return SPEED * (1.0 + SPEED_STEP * level(&"speed"))


func fire_cooldown() -> float:
	return FIRE_COOLDOWN * pow(RAPID_STEP, level(&"rapid"))


## One exp collected: count it and add it to the spendable balance.
func add_exp() -> void:
	exp_total += 1
	exp_balance += 1


## Exp the next level of `id` costs.
func price(id: StringName) -> int:
	return Systems.price(id, levels.get(id, 0))


func can_afford(id: StringName) -> bool:
	return can_upgrade(id) and exp_balance >= price(id)


## Buys the next level of `id`, spending its price. Returns whether it bought
## (not if dead, maxed or unaffordable). New capacity and guns come unpowered.
func buy_upgrade(id: StringName) -> bool:
	if not is_alive() or not can_afford(id):
		return false
	exp_balance -= price(id)
	levels[id] = levels.get(id, 0) + 1
	if id == &"armor":
		hp += HIT_HP  # the new plating comes intact
	elif id == &"ship":
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.add_spare.rpc_id(1)  # a spare ship for everyone
	return true


## Owner: a fork's Full repair: hull and both shields.
func repair_fully() -> void:
	if not is_alive():
		return
	var before := [hp, shield, rear_shield]
	hp = max_hp()
	if shield > 0:
		shield = SHIELD_HITS
	if rear_shield > 0:
		rear_shield = SHIELD_HITS
	if [hp, shield, rear_shield] != before:
		_heal_sound()


## Everyone hears a ship heal (a stream of heal shots at most every HEAL_SOUND_GAP).
func _heal_sound() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _heal_sound_at < HEAL_SOUND_GAP:
		return
	_heal_sound_at = now
	var game := get_tree().get_first_node_in_group("game")
	if game and multiplayer.multiplayer_peer != null:
		game.play_heal.rpc()


## Owner: a fork's Free upgrade: one more level of a random upgrade it can
## still take (not a spare ship). Returns its id, or &"".
func free_upgrade(rng: RandomNumberGenerator) -> StringName:
	if not is_alive():
		return &""
	var ids: Array[StringName] = []
	for it in Systems.ITEMS:
		if it.id != &"ship" and can_upgrade(it.id):
			ids.append(it.id)
	if ids.is_empty():
		return &""
	var id := ids[rng.randi_range(0, ids.size() - 1)]
	exp_balance += price(id)
	buy_upgrade(id)
	return id


## Everything at its max, with a reactor big enough to run it all, every
## system fully powered and every gun armed (the all-weapons cheat, see
## Net.ALL_WEAPONS_NAME). Spare ships are bought, never given.
func max_upgrades() -> void:
	var needed := 0
	for it in Systems.ITEMS:
		if it.id != &"ship":
			levels[it.id] = it.max
		if it.get("system", false):
			needed += it.max
	levels[&"reactor"] = maxi(Systems.max_level(&"reactor"), needed)
	for sys in Systems.systems():
		while add_power(sys.id):
			pass
	for g in Systems.guns():
		arm(g.id)
	shield = SHIELD_HITS
	rear_shield = SHIELD_HITS
	hp = max_hp()


# --- Shields and medbay -----------------------------------------------------------

## Owner: powered shields recharge a hit every SHIELD_REGEN s (twice as fast at
## SHIELDS 3), the front first, then the rear at SHIELDS 2.
func _run_shields(delta: float) -> void:
	var p := power_of(&"shields")
	var full := (p < 1 or shield >= SHIELD_HITS) and (p < 2 or rear_shield >= SHIELD_HITS)
	if p <= 0 or full:
		_regen_timer = 0.0
		return
	_regen_timer += delta
	if _regen_timer < SHIELD_REGEN / (2.0 if p >= 3 else 1.0):
		return
	_regen_timer = 0.0
	if shield < SHIELD_HITS:
		shield += 1
	elif p >= 2:
		rear_shield += 1


## A living ship with MEDBAY 2 or more within HEAL_RANGE of this one (itself
## included), if any.
func near_medbay() -> bool:
	if not is_inside_tree():
		return false
	for p in get_tree().get_nodes_in_group("player"):
		var bay: int = p.power_of(&"medbay") if p == self else p.medbay
		if bay >= 2 and p.is_alive() and (p == self or position.distance_to(p.position) <= HEAL_RANGE):
			return true
	return false


## Owner: heals HEAL_HITS every HEAL_INTERVAL s near a MEDBAY 2.
func _run_medbay(delta: float) -> void:
	_heal_timer += delta
	if _heal_timer >= HEAL_INTERVAL:
		_heal_timer = 0.0
		if near_medbay():
			heal(HEAL_HITS)


## The MEDBAY 2 aura, a soft ring teammates can stand in.
func _draw_aura() -> void:
	if medbay < 2:
		return
	draw_circle(Vector2.ZERO, HEAL_RANGE, Color(AURA_COLOR, AURA_ALPHA * 0.4))
	draw_arc(Vector2.ZERO, HEAL_RANGE, 0.0, TAU, 48, Color(AURA_COLOR, AURA_ALPHA * 2.0), 1.5, true)


# --- Missiles -----------------------------------------------------------------

func _fire_missiles(delta: float) -> void:
	_missile_cooldown -= delta
	if not _missile_requested:
		return
	_missile_requested = false  # like lasers: a press during the cooldown is dropped
	if level(&"missile") <= 0 or _missile_cooldown > 0.0:
		return
	_missile_cooldown = missile_cooldown()
	var game := get_tree().get_first_node_in_group("game")
	var guns: Array[Vector2] = [position]
	guns.append_array(option_positions())
	for g in guns:
		for dir in missile_directions():
			game.spawn_bullet(g + Vector2(0, -20), color, dir, BulletScript.MISSILE, peer_id)


func missile_cooldown() -> float:
	return MISSILE_COOLDOWN * pow(MISSILE_RELOAD, maxi(0, level(&"missile") - 1))


## Launch directions of one gun's salvo: one per level, an even step apart
## either side of straight up. The step is set so only the top level spans
## the full +-MISSILE_FAN: a small salvo starts narrow and branches out as it
## levels up (a single missile goes straight up).
func missile_directions() -> Array[Vector2]:
	var n := level(&"missile")
	var step := MISSILE_FAN * 2.0 / maxf(Systems.max_level(&"missile") - 1, 1)  # the fan is only full at the top level
	var out: Array[Vector2] = []
	for i in n:
		out.append(Vector2.UP.rotated((i - (n - 1) / 2.0) * step))
	return out


# --- Beam ---------------------------------------------------------------------

func beam_columns() -> int:
	return maxi(0, level(&"beam") * 2 - 1)


func beam_time() -> float:
	var lv := level(&"beam")
	return BEAM_TIMES[clampi(lv, 1, BEAM_TIMES.size()) - 1] if lv > 0 else 0.0


func beam_active() -> bool:
	return _beam_left > 0.0


func _run_beam(delta: float) -> void:
	_beam_cooldown -= delta
	if _beam_requested:
		_beam_requested = false
		if level(&"beam") > 0 and _beam_cooldown <= 0.0 and not beam_active():
			_beam_cooldown = BEAM_COOLDOWN
			_beam_left = beam_time()
			_beam_tick = 0.0
			_beam_origin = position + Vector2(0, -26)
	if not beam_active():
		return
	_beam_left -= delta
	_beam_tick -= delta
	var game := get_tree().get_first_node_in_group("game")
	while _beam_tick <= 0.0:
		_beam_tick += BEAM_INTERVAL
		var n := beam_columns()
		for i in n:
			var x := (i - (n - 1) / 2.0) * BEAM_SPACING
			game.spawn_bullet(_beam_origin + Vector2(x, 0), color, Vector2.UP, BulletScript.LASER, peer_id)


# --- Autocannon ---------------------------------------------------------------

## The closest enemy shot within AUTO_RANGE, else the closest enemy or other
## living player, or null.
func auto_target() -> Node2D:
	var best: Node2D = null
	var best_d := AUTO_RANGE
	for b in get_tree().get_nodes_in_group(&"bullet"):
		if b.is_hostile() and not b.is_queued_for_deletion():
			var d := position.distance_to(b.position)
			if d <= best_d:
				best_d = d
				best = b
	if best:
		return best
	for group in [&"enemy", &"player"]:
		for n in get_tree().get_nodes_in_group(group):
			if n == self or n.is_queued_for_deletion() or (group == &"player" and not is_targetable(n)):
				continue
			var d := position.distance_to(n.position)
			if d <= best_d:
				best_d = d
				best = n
	return best


## Whether a player ship may be targeted by another player's autocannon or
## missiles: alive and not showing a friendly beacon.
static func is_targetable(p: Node) -> bool:
	return p.is_alive() and not p.beacon


func _run_autocannon(delta: float) -> void:
	_auto_cooldown -= delta
	if level(&"auto") <= 0 or _auto_cooldown > 0.0:
		return
	var target := auto_target()
	if target == null:
		_auto_cooldown = 0.0
		return
	while _auto_cooldown <= 0.0:  # faster than the frame rate: several rounds a frame
		var lag := -_auto_cooldown  # how long ago within this frame it was due
		_auto_cooldown += AUTO_COOLDOWN / level(&"auto")
		_fire_vulcan(target, lag)


## One round at `target`; `lag` s late, so it starts that much further along
## and a frame's rounds string out instead of bunching.
func _fire_vulcan(target: Node2D, lag := 0.0) -> void:
	var aim := target.position
	if target.is_in_group(&"bullet"):  # lead it: where it'll be when the round gets there
		aim += target.velocity() * position.distance_to(target.position) / BulletScript.KINDS[BulletScript.VULCAN].speed
	var dir := (aim - position).normalized().rotated(randf_range(-AUTO_SPREAD, AUTO_SPREAD))
	var ahead: float = 18.0 + BulletScript.KINDS[BulletScript.VULCAN].speed * lag
	get_tree().get_first_node_in_group("game").spawn_bullet(position + dir * ahead, color, dir, BulletScript.VULCAN, peer_id)


func _run_healbeam(delta: float) -> void:
	_healbeam_cooldown -= delta
	if level(&"healbeam") <= 0:
		_healbeam_cooldown = maxf(_healbeam_cooldown, 0.0)
		return
	if _healbeam_cooldown > 0.0:
		return
	_healbeam_cooldown += HEALBEAM_INTERVAL / level(&"healbeam")  # added, so the rate holds whatever the frame rate
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.spawn_bullet(position + Vector2(0, -26), BulletScript.HEAL_COLOR, Vector2.UP, BulletScript.HEAL, peer_id)


# --- Search and rescue ---------------------------------------------------------

## One drone per RESCUE level.
func drone_count() -> int:
	return level(&"rescue")


## Drones ready to launch: RESCUE's, less those out and those still rebuilding.
func drones_ready() -> int:
	return maxi(0, drone_count() - drones.size() - _rebuild.size())


## Sends out every drone that's home, if RESCUE is bought, to a siren.
## Returns whether any went.
func launch_drone() -> bool:
	if not is_alive() or drones_ready() <= 0:
		return false
	var out := drones.duplicate()
	var faces := drone_headings.duplicate()
	for k in drones_ready():
		out.append(position)
		faces.append(-PI / 2.0)  # facing up, like the ship
		_runs.append({"time": 0.0, "goal": "", "claim": "", "got": false, "vel": Vector2.ZERO, "heading": -PI / 2.0,
			"search": SEARCH_OUT_PHASE, "search_at": (position + Vector2(0, -DRONE_SEARCH_OUT)).clamp(Vector2(30, 60), Vector2(510, 900)), "look": 0.0})
	drones = out  # reassigned, not appended, so the synchronizer sees the change
	drone_headings = faces
	var game := get_tree().get_first_node_in_group("game")
	if game and multiplayer.multiplayer_peer != null:
		game.play_siren.rpc()
	return true


## The nearest pod or astronaut none of our drones has claimed or is heading
## for (`skip`: a drone's own goal, which it may keep), or null.
func _drone_target(from := Vector2.ZERO, skip := "") -> Node2D:
	var heading := {}
	for run in _runs:
		if run.goal != skip:
			heading[run.goal] = true
	var best: Node2D = null
	var best_d := INF
	for pod in get_tree().get_nodes_in_group("escape_pod"):
		var n := String(pod.name)
		if pod.taken or pod.is_queued_for_deletion() or _drone_claimed.has(n) or heading.has(n):
			continue
		if pod.get_parent() != get_parent().get_parent().get_node_or_null("Pods"):
			continue
		var d := from.distance_to(pod.position)
		if d < best_d:
			best_d = d
			best = pod
	return best


## What a rescued pod adds to the tail: its enemy type, ASTRONAUT, or -1 for
## a player's pod (which gives its owner their upgrades back instead).
static func _tail_entry(pod: Node) -> int:
	if pod.is_player_pod():
		return -1
	return PodScript.ASTRONAUT if pod.astronaut else pod.type


## Each drone fetches one rescue at a time: out to the nearest, back to the
## ship with it, and out again until DRONE_TIME is up, there's nothing left
## or the tail has no room; then it docks. They fly like Asteroids ships: they
## turn, burn along their heading, and to stop they turn round and burn the
## other way, so they have to slow down before they can grab a rescue or dock:
## within DRONE_GRAB_RANGE and under DRONE_DOCK_SPEED, it happens at once. They steer clear of enemies and obstacles as best they
## can, but touching one, or being hit by any shot, destroys a drone (what it
## carried spills out as astronauts); it rebuilds in DRONE_REBUILD s.
## Launched with nothing to fetch, a drone flies DRONE_SEARCH_OUT ahead, hovers
## looking to either side, then comes home (out there it can still be hit);
## anything that turns up meanwhile, it goes for.
func _fly_drones(delta: float) -> void:
	for k in range(_rebuild.size() - 1, -1, -1):
		_rebuild[k] -= delta
		if _rebuild[k] <= 0.0:
			_rebuild.remove_at(k)
	if _runs.is_empty():
		return
	var game := get_tree().get_first_node_in_group("game")
	var out := drones.duplicate()
	var faces := drone_headings.duplicate()
	faces.resize(out.size())
	var i := 0
	while i < _runs.size():
		var run := _runs[i]
		run.time += delta
		var target: Node2D = null
		if run.claim == "" and run.time < DRONE_TIME and tail.size() + _drone_claimed.size() < TAIL_MAX:
			target = _drone_target(out[i], run.goal)
		run.goal = String(target.name) if target else ""
		if target or run.claim != "":
			run.search = SEARCH_DONE  # found something: no need to look around
		var goal := target.position if target else position
		var goal_vel: Vector2 = target.get("velocity") if target and target.get("velocity") is Vector2 else Vector2.ZERO
		if target == null:
			goal_vel = input_dir * move_speed()
		var pos: Vector2 = out[i]
		var searching: bool = target == null and run.claim == "" and run.search != SEARCH_DONE and run.time < DRONE_TIME
		if searching:
			goal = run.search_at
			goal_vel = Vector2.ZERO
			if run.search == SEARCH_OUT_PHASE and pos.distance_to(goal) <= DRONE_GRAB_RANGE and run.vel.length() <= DRONE_DOCK_SPEED:
				run.search = SEARCH_LOOK_PHASE
			if run.search == SEARCH_LOOK_PHASE:
				run.look += delta
				if run.look >= DRONE_LOOK_TIME:
					run.search = SEARCH_DONE
		var avoid := drone_avoidance(game, pos) if game else Vector2.ZERO
		if searching and run.search == SEARCH_LOOK_PHASE:  # hovering: turn to look one side, then the other
			run.vel = (run.vel as Vector2).move_toward(Vector2.ZERO, DRONE_THRUST * delta)  # trims out the drift
			var side := -1.0 if run.look < DRONE_LOOK_TIME / 2.0 else 1.0
			var look_at := -PI / 2.0 + side * DRONE_LOOK_ANGLE
			run.heading += clampf(angle_difference(run.heading, look_at), -DRONE_TURN * delta, DRONE_TURN * delta)
		else:
			var step := drone_steer(pos, run.vel, run.heading, goal, goal_vel, avoid, delta)
			run.vel = step.vel
			run.heading = step.heading
		pos += run.vel * delta
		out[i] = pos
		faces[i] = run.heading
		if game and drone_hit(game, pos):
			_lose_drone(game, i, pos)
			out.remove_at(i)
			faces.remove_at(i)
			continue
		var slow: bool = (run.vel - goal_vel).length() <= DRONE_DOCK_SPEED
		if not searching and pos.distance_to(goal) <= DRONE_GRAB_RANGE and slow:
			if target:
				run.claim = String(target.name)
				run.goal = ""
				_drone_claimed[run.claim] = _tail_entry(target)
				game.request_rescue.rpc_id(1, run.claim)
			elif not _unload(run):
				out.remove_at(i)
				faces.remove_at(i)
				_runs.remove_at(i)
				continue
		i += 1
	drones = out
	drone_headings = faces


## Asteroids-style flight for one drone: the velocity it wants (toward `goal`,
## no faster than it can still stop from, matching the goal's own `goal_vel`,
## pushed off by `avoid`), then it turns toward the change that needs and
## burns only once it faces it. Returns {vel, heading, burning}.
static func drone_steer(pos: Vector2, vel: Vector2, heading: float, goal: Vector2, goal_vel: Vector2,
		avoid: Vector2, delta: float) -> Dictionary:
	var to := goal - pos
	var dist := to.length()
	# The fastest it can go and still stop in time: it flips round (up to half a turn) then burns.
	var brake := DRONE_THRUST * DRONE_BRAKE
	var flip := PI / DRONE_TURN
	var stop_speed := -brake * flip + sqrt(pow(brake * flip, 2.0) + 2.0 * brake * maxf(dist - DRONE_REACH * 0.5, 0.0))
	if dist > DRONE_REACH * 0.5:
		stop_speed = maxf(stop_speed, DRONE_APPROACH)  # slow enough to grab from anyway
	var want := goal_vel + (to / dist * minf(DRONE_SPEED, stop_speed) if dist > 0.01 else Vector2.ZERO)
	want += avoid * DRONE_SPEED
	want = want.limit_length(DRONE_SPEED)
	var change := want - vel
	var burning := false
	if change.length() > 4.0:
		var face := change.angle()
		heading += clampf(angle_difference(heading, face), -DRONE_TURN * delta, DRONE_TURN * delta)
		if absf(angle_difference(heading, face)) < DRONE_BURN_ANGLE:
			burning = true
			vel += Vector2.from_angle(heading) * minf(DRONE_THRUST * delta, change.length())
	return {"vel": vel.limit_length(DRONE_SPEED), "heading": heading, "burning": burning}


## Push away from enemies and obstacles near a drone at `at` (0..1 each).
func drone_avoidance(game: Node, at: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for e in game.enemies.get_children():
		var r: float = EnemyScript.TYPES[e.type].get("height", EnemyScript.HEIGHT) * 0.5 * e.scale.x
		push += _push_from(at, e.position, r + DRONE_RADIUS + DRONE_AVOID)
	for o in game.obstacles.get_children():
		for part in o.parts:
			var size: Vector2 = o.piece(part.piece).size
			var c: Vector2 = o.position + Vector2(part.offset).rotated(o.rotation)
			push += _push_from(at, c, maxf(size.x, size.y) * 0.5 + DRONE_RADIUS + DRONE_AVOID)
	return push


static func _push_from(at: Vector2, from: Vector2, reach: float) -> Vector2:
	var d := at - from
	var dist := d.length()
	if dist >= reach:
		return Vector2.ZERO
	return (d / dist if dist > 0.01 else Vector2.UP) * (1.0 - dist / reach)


## Whether a drone at `at` touches an enemy (its hitbox), an obstacle, or a
## shot (any shot, past the muzzle; the shot is used up).
func drone_hit(game: Node, at: Vector2) -> bool:
	for e in game.enemies.get_children():
		if e.is_queued_for_deletion():
			continue
		var r: float = EnemyScript.TYPES[e.type].get("height", EnemyScript.HEIGHT) * 0.4 * e.scale.x
		if e.is_tetran():
			r = preload("res://scripts/tetran.gd").CORE_RADIUS * e.scale.x
		if at.distance_to(e.position) < r + DRONE_RADIUS:
			return true
	for h in get_tree().get_nodes_in_group("hazard"):
		if h.has_method("touches") and h.touches(at, DRONE_RADIUS):
			return true
	for o in game.obstacles.get_children():
		if not o.is_queued_for_deletion() and o.push_out(at, DRONE_RADIUS).distance_to(at) > 0.01:
			return true
	for b in game.bullets.get_children():
		if b.is_queued_for_deletion() or b._travelled < DRONE_SAFE_SHOT:
			continue
		if at.distance_to(b.position) < DRONE_RADIUS + 4.0:
			b.queue_free()
			return true
	return false


## Drone `i` is destroyed at `at`: what it carried spills out as astronauts,
## everyone sees it blow, and it rebuilds.
func _lose_drone(game: Node, i: int, at: Vector2) -> void:
	var run := _runs[i]
	var spill: Array = []
	if run.claim != "":
		if run.got:
			drone_carrying -= 1
			_astronauts_at(spill, _drone_claimed.get(run.claim, -1), at)
		_drone_claimed.erase(run.claim)
	_runs.remove_at(i)
	_rebuild.append(DRONE_REBUILD)
	game.drone_destroyed.rpc(at)
	if not spill.is_empty():
		var names: Array = []
		for k in spill.size():
			names.append(_drop_name(game.pods, "Astronaut", multiplayer.get_unique_id()))
		game.release_astronauts.rpc(names, spill)


## A drone back at the ship hands over what it brought. Returns whether it
## goes out again (it brought something and has time left).
func _unload(run: Dictionary) -> bool:
	if run.claim == "":
		return false
	if run.got:
		drone_carrying -= 1
		_add_to_tail([_drone_claimed[run.claim]])
	_drone_claimed.erase(run.claim)  # never confirmed: someone else got it
	run.claim = ""
	run.got = false
	return run.time < DRONE_TIME


## The host confirmed a pod is ours: it rides home on the drone that claimed it.
func drone_picked_up(pod_name := "") -> void:
	for run in _runs:
		if run.claim == pod_name and not run.got:
			run.got = true
			drone_carrying += 1
			return


## Rescued enemy pods (types >= 0) and astronauts join the end of the tail,
## up to TAIL_MAX.
func _add_to_tail(types: Array) -> void:
	var grown := tail.duplicate()
	for t in types:
		if (t >= 0 or t == PodScript.ASTRONAUT) and grown.size() < TAIL_MAX:
			grown.append(t)
	tail = grown  # reassigned, not appended, so the synchronizer sees the change


## Owner: near a station, the whole tail piles in; an exp for each pod.
func _dock_tail() -> void:
	if tail.is_empty() or not is_alive():
		return
	for st in get_tree().get_nodes_in_group("station"):
		if st.is_queued_for_deletion() or not st.in_reach(position):
			continue
		var from: Array = tail_positions()
		var types: Array = tail.duplicate()
		tail = []
		for i in types.size():
			add_exp()
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.dock_tail.rpc(String(st.name), from, types)
		return


## Ship lost: the drones are lost too (what they carried is let out first,
## by _release_rescued).
func _recall_drone() -> void:
	if not drones.is_empty():
		drones = []
		drone_headings = []
	_rebuild.clear()
	drone_carrying = 0
	_runs.clear()
	_drone_claimed.clear()


## Owner, as the ship is lost: its tail and what its drones carry spill out
## as astronauts (two per pod, one per astronaut) where they were.
func _release_rescued() -> void:
	var at: Array = []
	var tail_at := tail_positions()
	for i in tail.size():
		_astronauts_at(at, tail[i], tail_at[i])
	for i in mini(_runs.size(), drones.size()):
		if _runs[i].got:
			_astronauts_at(at, _drone_claimed.get(_runs[i].claim, -1), drones[i])
	tail = []
	_recall_drone()
	var game := get_tree().get_first_node_in_group("game")
	if at.is_empty() or game == null:
		return
	var names: Array = []
	for i in at.size():
		names.append(_drop_name(game.pods, "Astronaut", multiplayer.get_unique_id()))
	game.release_astronauts.rpc(names, at)


static func _astronauts_at(at: Array, entry: int, pos: Vector2) -> void:
	if entry == PodScript.ASTRONAUT:
		at.append(pos)
	elif entry >= 0:
		at.append(pos + Vector2(-PodScript.ASTRONAUT_GAP, 0))
		at.append(pos + Vector2(PodScript.ASTRONAUT_GAP, 0))


func _update_drone_sprites() -> void:
	while _drone_sprites.size() < drones.size():
		var s := Sprite2D.new()
		s.texture = body.texture
		s.scale = body.scale * OPTION_SCALE
		s.modulate = DRONE_TINT
		s.light_mask = body.light_mask
		s.top_level = true
		add_child(s)
		_drone_sprites.append(s)
	for i in _drone_sprites.size():
		var s := _drone_sprites[i]
		s.visible = i < drones.size() and is_alive()
		if s.visible:
			s.global_position = get_parent().to_global(drones[i])
			if i < drone_headings.size():
				s.global_rotation = float(drone_headings[i]) + PI / 2.0  # the art faces up


## Owner: drops a repair kit here, if REPAIR is bought and off cooldown.
func drop_repair() -> bool:
	if level(&"repair") <= 0 or not is_alive() or _repair_cooldown > 0.0:
		return false
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return false
	_repair_cooldown = REPAIR_COOLDOWN * (0.5 if power_of(&"medbay") >= 3 else 1.0)
	game.spawn_repair.rpc(position, _drop_name(game.pickups, "Repair"), ship, palette)
	return true


## A new name for something this ship drops: "<prefix><peer>_<n>", unused in
## `parent`. `by`: the peer to name it for, if not this ship's.
func _drop_name(parent: Node, prefix: String, by := 0) -> String:
	while true:
		_drops += 1
		var n := "%s%d_%d" % [prefix, by if by != 0 else peer_id, _drops]
		if not parent.has_node(n):
			return n
	return ""


# --- Escape pod -----------------------------------------------------------------

## The upgrades a pod carries: what was bought, how it was powered and armed.
func upgrade_state() -> Dictionary:
	return {"levels": levels.duplicate(), "power": power.duplicate(), "armed": armed.keys(),
		"shield": shield, "rear_shield": rear_shield}


## Owner, as the ship is destroyed: launches its escape pod with its upgrades.
## (Not for an AI buddy: it has none.)
func _drop_pod() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null or ai:
		return
	var pod_name := _drop_name(game.pods, "PlayerPod")
	_stashes[pod_name] = upgrade_state()
	game.spawn_player_pod.rpc(position, pod_name, color, ship, palette)


## Owner: our pod `pod_name` was saved; its upgrades come back (at respawn if
## we're still dead).
func recover_upgrades(pod_name: String) -> void:
	if not _stashes.has(pod_name):
		return
	var st: Dictionary = _stashes[pod_name]
	_stashes.erase(pod_name)
	if is_alive():
		_apply_upgrades(st)
	else:
		_recovered.append(st)


## Takes the better of what we have and what `st` carries, upgrade by
## upgrade, then powers systems back up to how `st` had them and re-arms its
## guns, as far as the reactor allows.
func _apply_upgrades(st: Dictionary) -> void:
	var armor_before := level(&"armor")
	for id in st.get("levels", {}):
		levels[id] = maxi(levels.get(id, 0), st.levels[id])
	var was: Dictionary = st.get("power", {})
	for sys in was:
		while power_of(sys) < was[sys] and add_power(sys):
			pass
	for g in st.get("armed", []):
		arm(g)
	if power_of(&"shields") >= 1:
		shield = maxi(shield, st.get("shield", 0))
	if power_of(&"shields") >= 2:
		rear_shield = maxi(rear_shield, st.get("rear_shield", 0))
	if is_alive():
		hp = minf(hp + HIT_HP * (level(&"armor") - armor_before), max_hp())


func _lose_upgrades() -> void:
	_start_loadout()
	shield = 0
	rear_shield = 0
	options = 0
	tail = []
	medbay = 0


## Where each option is: OPTION_GAP apart along the flown path, bunched up on
## the ship until it has flown that far.
func option_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in options:
		var back := int(round(OPTION_GAP * (i + 1) / TRAIL_STEP))
		out.append(_trail[mini(back, _trail.size() - 1)] if not _trail.is_empty() else position)
	return out


## Records the flown path and moves the option sprites onto it (every peer).
func _update_options() -> void:
	if not is_alive():
		_trail.clear()
	if _trail.is_empty():
		_trail.push_front(position)
	while _trail[0].distance_to(position) >= TRAIL_STEP:
		_trail.push_front(_trail[0].move_toward(position, TRAIL_STEP))
	var keep := int((OPTION_GAP * Systems.max_level(&"option") + TAIL_GAP * TAIL_MAX) / TRAIL_STEP) + 2
	if _trail.size() > keep:
		_trail.resize(keep)
	while _option_sprites.size() < options:
		var s := Sprite2D.new()
		s.texture = body.texture
		s.scale = body.scale * OPTION_SCALE
		s.light_mask = body.light_mask
		s.top_level = true  # positioned in world space, not following the ship
		add_child(s)
		_option_sprites.append(s)
	while _option_sprites.size() > options:
		_option_sprites.pop_back().queue_free()
	var at := option_positions()
	for i in options:
		_option_sprites[i].global_position = get_parent().to_global(at[i])
		_option_sprites[i].visible = is_alive()
	_update_tail()


## Where each rescued pod in the tail is: TAIL_GAP apart along the flown path,
## starting behind the last option.
func tail_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in tail.size():
		var back := int(round((OPTION_GAP * options + TAIL_GAP * (i + 1)) / TRAIL_STEP))
		out.append(_trail[mini(back, _trail.size() - 1)] if not _trail.is_empty() else position)
	return out


## How a tail entry looks: an enemy's pod, or an astronaut.
static func tail_texture(entry: int) -> Texture2D:
	if entry == PodScript.ASTRONAUT:
		return PodScript.astronaut_texture()
	return Ships.get_lit_enemy_texture(EnemyScript.TYPES[clampi(entry, 0, EnemyScript.TYPES.size() - 1)].ship)


static func tail_scale(entry: int) -> Vector2:
	if entry == PodScript.ASTRONAUT:
		return Vector2.ONE
	return Ships.scale_for(tail_texture(entry), EnemyScript.HEIGHT) * TAIL_SCALE


func _update_tail() -> void:
	while _tail_sprites.size() > tail.size():
		_tail_sprites.pop_back().queue_free()
	for i in tail.size():
		if i == _tail_sprites.size():
			var s := Sprite2D.new()
			s.light_mask = body.light_mask
			s.top_level = true
			add_child(s)
			_tail_sprites.append(s)
		var sprite := _tail_sprites[i]
		var tex := tail_texture(tail[i])
		if sprite.texture != tex:
			sprite.texture = tex
			sprite.scale = tail_scale(tail[i])
			sprite.flip_v = tail[i] != PodScript.ASTRONAUT  # a pod still faces the way the enemy flew
	var at := tail_positions()
	for i in tail.size():
		_tail_sprites[i].global_position = get_parent().to_global(at[i])
		_tail_sprites[i].visible = is_alive()


func _draw() -> void:
	if not is_alive():
		return
	_draw_aura()
	if shield > 0:  # front: the top half
		draw_arc(Vector2.ZERO, SHIELD_RADIUS, PI, TAU, 24, Color(0.35, 0.8, 1.0, 0.3 + 0.2 * shield), 2.5, true)
	if rear_shield > 0:  # rear: the bottom half
		draw_arc(Vector2.ZERO, SHIELD_RADIUS, 0.0, PI, 24, Color(0.75, 0.55, 1.0, 0.3 + 0.2 * rear_shield), 2.5, true)
	if beacon:  # friendly beacon: a dashed ring in the ship's color, blinking
		var on := fposmod(Time.get_ticks_msec() / 1000.0 * BEACON_BLINK, 1.0) < 0.6
		var c := Color(color, 0.8 if on else 0.25)
		for i in 8:
			var a := TAU * i / 8.0
			draw_arc(Vector2.ZERO, BEACON_RADIUS, a, a + TAU / 16.0, 4, c, 2.0, true)


func _movement_bounds() -> Rect2:
	var arena: Rect2 = get_parent().get_parent().ARENA
	var r := arena.grow(-20)
	r.end.y = arena.end.y - ActionBar.BAR_HEIGHT - 20  # stay above the button bar
	return r


## Owner only: each peer decides damage to its own ship. `from_behind`: the hit
## came from below (rear shield) rather than ahead (front shield). `amount` may
## be a fraction of a hit (vulcan rounds). With the facing shield up, it soaks
## whole hits (fractions add up), one charge each; otherwise each hit takes
## HIT_HP, fractions included.
func take_damage(amount: float, from_behind := false) -> void:
	if not is_local() or not is_alive():
		return
	var game := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	if game and game.between_levels():
		return  # nothing hurts from a boss kill until the next stage starts
	if _shield_facing(from_behind) <= 0:
		_lose_hp(amount * HIT_HP)
		return
	_damage_carry += amount
	var hits := floori(_damage_carry + 0.0001)
	_damage_carry = maxf(0.0, _damage_carry - hits)
	for i in hits:
		if not is_alive():
			return
		if _shield_facing(from_behind) <= 0:
			_lose_hp(HIT_HP)
		elif from_behind:
			rear_shield -= 1
		else:
			shield -= 1


func _shield_facing(from_behind: bool) -> int:
	return rear_shield if from_behind else shield


func _lose_hp(amount: float) -> void:
	hp -= amount
	if hp <= 0.001:
		hp = 0.0
		_respawn_timer = RESPAWN_TIME
		_release_rescued()
		_drop_pod()


func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not is_alive():
		return
	if area.is_in_group("bullet"):  # friendly fire
		if area.shooter == peer_id:
			return  # your own (and your options') shots pass through
		if beacon and not area.is_hostile() and (area.kind == BulletScript.MISSILE or area.kind == BulletScript.VULCAN):
			return  # a friendly beacon: other players' missiles and autocannon rounds fly through it
		area.queue_free()  # every peer removes it; the owner takes the hit
		if area.is_heal():
			heal(area.damage())
		else:
			take_damage(area.damage(), area.position.y > position.y)
		return
	if not is_local():
		return
	if area.is_in_group("enemy"):
		take_damage(1, area.position.y > position.y)
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.report_ram.rpc_id(1, String(area.name))
	elif area.is_in_group("hazard"):  # a boss's arm: it hurts, but there's nothing to ram
		take_damage(1, area.global_position.y > global_position.y)
