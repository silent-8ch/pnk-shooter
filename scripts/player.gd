extends Area2D
## A player ship. The owning peer simulates it (movement, firing, damage to
## itself) and replicates position and hp to everyone else, so it never waits
## on the network.
## Exp is a currency: `exp_balance` is the spendable balance, `exp_total` the lifetime
## count. Any upgrade on the PowerMeter shop (speed, rapid fire, double/triple
## shot, options, front and rear shields, armor, tier II, ...) can be bought
## whenever the balance covers its price, which grows with each level bought
## (PowerMeter.price). The upgrades live here too; they are
## lost when the ship is destroyed, but the ship drops an escape pod carrying
## them (Game.spawn_player_pod): if it's saved (touched by any ship or picked up
## by any rescue drone) they come back (recover_upgrades).
## Health is HIT_HP per hit out of MAX_HP, so partial hits (vulcan rounds) show.
## ARMOR adds one hit's worth of max hp per level.
## REPAIR adds a REPAIR button that drops a repair kit (RepairKit) where the
## ship is; the first damaged ship over it heals.
## Options are small copies of the ship that trail along the path it flew
## (every peer builds the trail from the replicated position) and fire whatever
## the ship fires.
## Friendly fire is always on: other players' bullets hurt (your own never do).
## RESCUE adds a button that launches a search-and-rescue drone, an option-sized
## copy of the ship: it flies to the nearest enemy escape pods, picks up to
## DRONE_CAPACITY, and brings them home. The owner flies it; its position
## replicates so everyone sees it. Rescued enemy pods then trail behind the
## ship (and its options) like a tail, up to TAIL_MAX; flying near a rescue
## Station turns them all in for an exp each and score. The tail is lost with
## the ship.
## MISSILE adds a MISSILE button: the ship and each option fire a salvo of
## seeking missiles (each does a laser's damage), one per MISSILE level, fanned
## out sideways before they curl in on targets, trailing smoke. Each level also
## reloads MISSILE_RELOAD faster (base: twice the laser cooldown).
## BEAM (tier II) adds a BEAM button: for a moment the ship pours a dense
## stream of laser bullets straight up from the spot where it was fired (the
## stream stays there even as the ship moves). Each level makes it thicker
## (more columns) and last longer.
## Party roles (tier III, one per ship, see PowerMeter.ROLES), shown as a tag
## on the name and a ring in the role's color:
##   DPS       the big guns: RAPID, MISSILE and BEAM go further, DOUBLE to a
##             5-way SPREAD.
##   TANK      shipmates within COVER_RANGE take only half of each hit; the tank
##             takes the other half. Its front shield recharges a hit every
##             SHIELD_REGEN s, and ARMOR goes further.
##   HEALER    every HEAL_INTERVAL s, ships within HEAL_RANGE (itself included)
##             heal HEAL_HITS; repair kits come back twice as fast and the
##             rescue drone carries twice as many pods.
##   MODIFIER  ships within MOD_RANGE (itself included) fire, reload and fly
##             faster (MOD_HASTE, MOD_SPEED); SPEED and OPTION go further.
## Each peer applies the auras to its own ship from the replicated role and
## position of the others, like damage.
## BEACON turns on a friendly beacon (a blinking ring in the ship's color):
## other players' autocannons and missiles won't pick this ship as a target.
## +SHIP (tier II) buys a spare ship for the whole party (Game.spares): a
## destroyed ship only comes back while there's a spare left.
## AUTOCAN adds an AUTO on/off button for a vulcan cannon: while on, it hoses
## whatever is closest within AUTO_RANGE (enemies and other players alike) with
## tiny, fast, weak rounds.

const BulletScript := preload("res://scripts/bullet.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
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
const COVER_RANGE := 110.0  # TANK covers shipmates this close
const COVER_SHARE := 0.5  # of each hit the tank takes instead
const SHIELD_REGEN := 8.0  # s per front-shield hit a TANK recharges
const HEAL_RANGE := 120.0
const HEAL_INTERVAL := 3.0
const HEAL_HITS := 0.5  # per HEAL_INTERVAL
const MOD_RANGE := 120.0
const MOD_HASTE := 0.75  # cooldowns x this near a MODIFIER
const MOD_SPEED := 1.15  # move speed x this near a MODIFIER
const ROLE_AURA_ALPHA := 0.12
const OPTION_SCALE := 0.5  # option size relative to the ship
const OPTION_GAP := 40.0  # px of flown path between the ship and each option
const TAIL_GAP := 22.0  # px of flown path between rescued pods in the tail
const TAIL_MAX := 12  # rescued pods the tail holds
const TAIL_SCALE := 0.5  # tail pod size relative to an enemy (EscapePod.SCALE)
const TRAIL_STEP := 4.0  # px between recorded trail points
const DRONE_SPEED := 420.0
const DRONE_REACH := 14.0  # px: close enough to grab a pod or dock
const DRONE_CAPACITY := 3  # pods per trip
const DRONE_TIME := 10.0  # s: heads home after this long out
const DRONE_TINT := Color(0.7, 1.0, 0.75)
const MISSILE_COOLDOWN := FIRE_COOLDOWN * 2.0  # at level 1; matches the MISSILE button cooldown
const MISSILE_RELOAD := 0.9  # cooldown x this per MISSILE level after the first
const MISSILE_FAN := 1.2  # rad: a salvo fans out up to this far either side of straight up
const BEAM_COOLDOWN := 3.0  # matches the BEAM button cooldown
const BEAM_INTERVAL := 0.05  # s between bullets in each column
const BEAM_TIMES: Array[float] = [0.8, 1.2, 1.6]  # s the beam lasts, by level
const BEAM_SPACING := 7.0  # px between columns; level n has 2n-1 columns
const AUTO_RANGE := 130.0  # px: targets this close
const AUTO_COOLDOWN := 0.07  # s between vulcan rounds (halved at level 2)
const AUTO_SPREAD := 0.09  # rad: rounds scatter up to this much either way
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
var rear_shield := 0  # replicated: hits left on the rear shield (tier II; blocks hits from behind)
var tier := 1  # local: PowerMeter tier
var drone_out := false  # replicated: the rescue drone is away from the ship
var drone_pos := Vector2.ZERO  # replicated: drone position (same space as the ship's)
var drone_carrying := 0  # local: pods the host confirmed on board
var _drone_time := 0.0
var _drone_claimed := {}  # local: pod name -> its enemy type (-1 = a player's pod), grabbed this trip (claims sent to the host)
var _cargo: Array[int] = []  # local: enemy types of the pods the host confirmed on board
var beacon := false  # replicated: friendly beacon on (BEACON bought)
var party_role := ""  # replicated: the role picked in tier III ("dps", "tank", "healer", "modifier"), or ""
var _heal_timer := 0.0
var _regen_timer := 0.0
var _shown_role := "-"  # local: role the label was last drawn with
var tail: Array = []  # replicated (untyped, so the synchronizer can set it): enemy types of the pods rescued, trailing behind the options
var _tail_sprites: Array[Sprite2D] = []
var _launch_requested := false
var _seen_rescues := -1  # local: RESCUE button press count already handled
var _drone_sprite: Sprite2D
var autocannon_on := false  # local: AUTO switched on
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
var _ai_side := 1.0  # which side of its leader it flies on
var _repair_cooldown := 0.0
var _seen_repairs := -1  # local: REPAIR button press count already handled
var _drops := 0  # local: escape pods and repair kits named so far
var _stashes := {}  # local: our escape pod name -> upgrades it carries
var _recovered: Array[Dictionary] = []  # local: saved while we were dead; applied at respawn
var options := 0  # replicated: option count
var exp_total := 0  # local: exp this player has collected (lifetime)
var exp_balance := 0  # local: spendable exp balance
var levels := {}  # local: upgrade id -> level bought
var _trail: Array[Vector2] = []  # flown path, newest first, TRAIL_STEP apart
var _option_sprites: Array[Sprite2D] = []
var input_dir := Vector2.ZERO
var _fire_requested := false  # a Lasers press waiting for the cooldown check
var _seen_presses := -1  # local: Lasers button press count already handled (-1 = not synced yet)
var _cooldown := 0.0
var _respawn_timer := 0.0
var _awaiting_spare := false  # local: asked the host for a spare ship, no answer yet
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
	if Net.all_weapons and multiplayer.multiplayer_peer != null and is_local() and not ai:
		max_upgrades()


## True on the peer that flies this ship: its owner, or the host for an AI buddy.
func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id() or (ai and multiplayer.is_server())


func is_alive() -> bool:
	return hp > 0


func _process(_delta: float) -> void:
	body.modulate.a = 1.0 if is_alive() else 0.25
	if _shown_role != party_role:
		_shown_role = party_role
		label.text = player_name + ("  [%s]" % party_role.to_upper() if party_role != "" else "")
	queue_redraw()  # shield ring
	_update_options()
	_update_drone_sprite()
	if multiplayer.multiplayer_peer == null:
		return
	if is_local():
		if ai:
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
	if pointer and pointer.is_active():
		dir = pointer.direction_from(position, _movement_bounds())
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
			_missile_requested = true
		_seen_missiles = missiles
		var beams: int = bar.presses[&"beam"]
		if _seen_beams >= 0 and beams != _seen_beams:
			_beam_requested = true
		_seen_beams = beams
		var autos: int = bar.presses[&"auto"]
		if _seen_autos >= 0 and autos != _seen_autos and level(&"auto") > 0:
			autocannon_on = not autocannon_on
		_seen_autos = autos
		var repairs: int = bar.presses[&"repair"]
		if _seen_repairs >= 0 and repairs != _seen_repairs:
			_repair_requested = true
		_seen_repairs = repairs
	var game := get_tree().get_first_node_in_group("game")
	if game and not game.input_enabled:
		dir = Vector2.ZERO
		fire = false
	input_dir = dir
	if bar:
		bar.set_cooldown(&"lasers", fire_cooldown())
		bar.set_cooldown(&"missile", missile_cooldown())
		bar.set_shown(&"rescue", level(&"rescue") > 0)
		bar.set_enabled(&"rescue", is_alive() and not drone_out)
		bar.set_shown(&"missile", level(&"missile") > 0)
		bar.set_shown(&"beam", level(&"beam") > 0)
		bar.set_shown(&"auto", level(&"auto") > 0)
		bar.set_lit(&"auto", autocannon_on)
		bar.set_shown(&"repair", level(&"repair") > 0)
	if fire:
		_fire_requested = true


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
	party_role = String(role())
	_run_role(delta)
	position += input_dir * move_speed() * delta
	var bounds := _movement_bounds()
	position = position.clamp(bounds.position, bounds.end)
	_avoid_obstacles(delta, bounds)

	if _launch_requested:
		_launch_requested = false
		launch_drone()
	_dock_tail()
	if drone_out:
		_fly_drone(delta)
	_run_autocannon(delta)
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
		_cooldown = fire_cooldown()
		var game := get_tree().get_first_node_in_group("game")
		var guns: Array[Vector2] = [position]
		guns.append_array(option_positions())
		for g in guns:
			var muzzle := g + Vector2(0, -26)
			if level(&"double") >= 3:  # SPREAD
				for x in [-2.0 * TRIPLE_SPREAD, -TRIPLE_SPREAD, 0.0, TRIPLE_SPREAD, 2.0 * TRIPLE_SPREAD]:
					game.spawn_bullet(muzzle + Vector2(x, 0), color, Vector2.UP, BulletScript.LASER, peer_id)
			elif level(&"double") >= 2:
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
	for st in _recovered:
		_apply_upgrades(st)
	_recovered.clear()
	if Net.all_weapons and not ai:
		max_upgrades()
	hp = max_hp()
	position = spawn_position


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


## Push away from nearby danger: enemies, veering wrecks, obstacles (looking
## ahead, since they scroll down), and other ships (to keep spacing).
func ai_avoidance(game: Node) -> Vector2:
	var push := Vector2.ZERO
	for e in game.enemies.get_children():
		push += _repel(e.position, AI_DANGER)
	for w in game.effects.get_children():
		if w.has_method("hull_position") and not w.exploded:
			push += _repel(w.hull_position(), AI_DANGER + w.reach())
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

func level(id: StringName) -> int:
	if id == &"shield":
		return (1 if shield > 0 else 0) + (1 if rear_shield > 0 else 0)
	if id == &"option":
		return options
	return levels.get(id, 0)


func can_upgrade(id: StringName) -> bool:
	return level(id) < PowerMeter.max_level(id, tier, role())


## The party role picked in tier III, or &"". Remote ships: the replicated one.
func role() -> StringName:
	for r in PowerMeter.ROLES:
		if levels.get(r, 0) > 0:
			return r
	return StringName(party_role) if not is_local() else &""


func max_hp() -> float:
	return MAX_HP + HIT_HP * level(&"armor")


func needs_repair() -> bool:
	return is_alive() and hp < max_hp()


## Owner: heals `hits` hits' worth, up to max hp (a repair kit).
func heal(hits: float) -> void:
	if is_local() and is_alive():
		hp = minf(hp + hits * HIT_HP, max_hp())


func move_speed() -> float:
	return SPEED * (1.0 + SPEED_STEP * level(&"speed")) * (MOD_SPEED if near_role(&"modifier", MOD_RANGE) else 1.0)


func fire_cooldown() -> float:
	return FIRE_COOLDOWN * pow(RAPID_STEP, level(&"rapid")) * _haste()


func _haste() -> float:
	return MOD_HASTE if near_role(&"modifier", MOD_RANGE) else 1.0


## One exp collected: count it and add it to the spendable balance.
func add_exp() -> void:
	exp_total += 1
	exp_balance += 1


## Exp the next level of `id` costs.
func price(id: StringName) -> int:
	return PowerMeter.price(id, level(id))


func can_afford(id: StringName) -> bool:
	return can_upgrade(id) and exp_balance >= price(id)


## Buys the next level of `id`, spending its price. Returns whether it bought
## (not if dead, maxed or unaffordable).
func buy_upgrade(id: StringName) -> bool:
	if not is_alive() or not can_afford(id):
		return false
	exp_balance -= price(id)
	if id == &"shield":
		if shield <= 0:
			shield = SHIELD_HITS
		else:
			rear_shield = SHIELD_HITS
	elif id == &"option":
		options += 1
	elif id == &"armor":
		levels[id] = level(id) + 1
		hp += HIT_HP  # the new plating comes intact
	else:
		levels[id] = level(id) + 1
		if id == &"tier":
			tier = mini(1 + levels[id] / PowerMeter.TIER_CHARGES, 3)  # the meter moves up a tier
		elif id == &"ship":
			var game := get_tree().get_first_node_in_group("game")
			if game:
				game.add_spare.rpc_id(1)  # a spare ship for everyone
	return true


## Every upgrade at its tier II max (the all-weapons cheat, see Net.ALL_WEAPONS_NAME).
func max_upgrades() -> void:
	tier = 2
	levels[&"tier"] = PowerMeter.TIER_CHARGES
	for s in PowerMeter.SLOTS:
		var top := PowerMeter.max_level(s.id, 2)
		if s.id == &"shield":
			shield = SHIELD_HITS
			rear_shield = SHIELD_HITS
		elif s.id == &"option":
			options = top
		elif top > 0 and s.id != &"ship":  # spare ships are bought, never given
			levels[s.id] = top
	hp = max_hp()


# --- Party roles ---------------------------------------------------------------

## A living ship with `r` within `range` of this one (itself included), if any.
func near_role(r: StringName, range: float) -> bool:
	if not is_inside_tree():
		return false
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_alive() and p.role() == r and (p == self or position.distance_to(p.position) <= range):
			return true
	return false


## Another living TANK close enough to take part of our hits, or null.
func covering_tank() -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p != self and p.is_alive() and p.role() == &"tank" and position.distance_to(p.position) <= COVER_RANGE:
			return p
	return null


## Owner: the auras and upkeep of roles near us (and our own).
func _run_role(delta: float) -> void:
	_heal_timer += delta
	if _heal_timer >= HEAL_INTERVAL:
		_heal_timer = 0.0
		if near_role(&"healer", HEAL_RANGE):
			heal(HEAL_HITS)
	if role() == &"tank" and shield < SHIELD_HITS:
		_regen_timer += delta
		if _regen_timer >= SHIELD_REGEN:
			_regen_timer = 0.0
			shield += 1
	else:
		_regen_timer = 0.0


func _draw_role() -> void:
	var r := StringName(party_role)
	if r == &"":
		return
	var c: Color = PowerMeter.ROLE_COLORS[r]
	var reach: float = {&"tank": COVER_RANGE, &"healer": HEAL_RANGE, &"modifier": MOD_RANGE}.get(r, 0.0)
	if reach > 0.0:  # the aura teammates stand in
		draw_circle(Vector2.ZERO, reach, Color(c, ROLE_AURA_ALPHA * 0.4))
		draw_arc(Vector2.ZERO, reach, 0.0, TAU, 48, Color(c, ROLE_AURA_ALPHA * 2.0), 1.5, true)
	else:  # DPS: a tight ring
		draw_arc(Vector2.ZERO, SHIELD_RADIUS - 4.0, 0.0, TAU, 24, Color(c, 0.5), 1.5, true)


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
	return MISSILE_COOLDOWN * pow(MISSILE_RELOAD, maxi(0, level(&"missile") - 1)) * _haste()


## Launch directions of one gun's salvo: one per level, fanned evenly across
## +-MISSILE_FAN (a single missile goes straight up).
func missile_directions() -> Array[Vector2]:
	var n := level(&"missile")
	var out: Array[Vector2] = []
	for i in n:
		var a := 0.0 if n == 1 else lerpf(-MISSILE_FAN, MISSILE_FAN, float(i) / (n - 1))
		out.append(Vector2.UP.rotated(a))
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

## Closest enemy or other living player within AUTO_RANGE, or null.
func auto_target() -> Node2D:
	var best: Node2D = null
	var best_d := AUTO_RANGE
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
	if not autocannon_on or level(&"auto") <= 0 or _auto_cooldown > 0.0:
		return
	var target := auto_target()
	if target == null:
		return
	_auto_cooldown = AUTO_COOLDOWN / level(&"auto")
	var dir := (target.position - position).normalized().rotated(randf_range(-AUTO_SPREAD, AUTO_SPREAD))
	get_tree().get_first_node_in_group("game").spawn_bullet(position + dir * 18.0, color, dir, BulletScript.VULCAN, peer_id)


# --- Search and rescue ---------------------------------------------------------

func drone_capacity() -> int:
	return DRONE_CAPACITY * (2 if role() == &"healer" else 1)


## Sends the drone out from the ship, if RESCUE is bought and it's docked.
func launch_drone() -> bool:
	if level(&"rescue") <= 0 or drone_out or not is_alive():
		return false
	drone_out = true
	drone_pos = position
	drone_carrying = 0
	_drone_time = 0.0
	_drone_claimed.clear()
	return true


## The nearest pod no drone has claimed, or null.
func _drone_target() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for pod in get_tree().get_nodes_in_group("escape_pod"):
		if pod.taken or pod.is_queued_for_deletion() or _drone_claimed.has(String(pod.name)):
			continue
		if pod.get_parent() != get_parent().get_parent().get_node_or_null("Pods"):
			continue
		var d := drone_pos.distance_to(pod.position)
		if d < best_d:
			best_d = d
			best = pod
	return best


func _fly_drone(delta: float) -> void:
	_drone_time += delta
	var target: Node2D = null
	if _drone_claimed.size() < drone_capacity() and _drone_time < DRONE_TIME and tail.size() + _drone_claimed.size() < TAIL_MAX:
		target = _drone_target()
	var goal := target.position if target else position
	drone_pos = drone_pos.move_toward(goal, DRONE_SPEED * delta)
	if drone_pos.distance_to(goal) > DRONE_REACH:
		return
	if target:
		_drone_claimed[String(target.name)] = -1 if target.is_player_pod() else target.type
		get_tree().get_first_node_in_group("game").request_rescue.rpc_id(1, String(target.name))
	else:
		_dock_drone()


## The host confirmed a pod is ours. If the drone already docked, it counts now.
func drone_picked_up(pod_name := "") -> void:
	var t: int = _drone_claimed.get(pod_name, -1)
	if drone_out:
		drone_carrying += 1
		_cargo.append(t)
	elif is_alive():
		_add_to_tail([t])


func _dock_drone() -> void:
	drone_out = false
	_add_to_tail(_cargo)
	drone_carrying = 0
	_cargo.clear()


## Rescued enemy pods (types >= 0) join the end of the tail, up to TAIL_MAX.
func _add_to_tail(types: Array[int]) -> void:
	var grown := tail.duplicate()
	for t in types:
		if t >= 0 and grown.size() < TAIL_MAX:
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


## Ship lost: the drone and anything on board are lost too.
func _recall_drone() -> void:
	drone_out = false
	drone_carrying = 0
	_drone_claimed.clear()
	_cargo.clear()


func _update_drone_sprite() -> void:
	if _drone_sprite == null:
		_drone_sprite = Sprite2D.new()
		_drone_sprite.texture = body.texture
		_drone_sprite.scale = body.scale * OPTION_SCALE
		_drone_sprite.modulate = DRONE_TINT
		_drone_sprite.light_mask = body.light_mask
		_drone_sprite.top_level = true
		add_child(_drone_sprite)
	_drone_sprite.visible = drone_out and is_alive()
	if _drone_sprite.visible:
		_drone_sprite.global_position = get_parent().to_global(drone_pos)


## Owner: drops a repair kit here, if REPAIR is bought and off cooldown.
func drop_repair() -> bool:
	if level(&"repair") <= 0 or not is_alive() or _repair_cooldown > 0.0:
		return false
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return false
	_repair_cooldown = REPAIR_COOLDOWN * (0.5 if role() == &"healer" else 1.0)
	game.spawn_repair.rpc(position, _drop_name(game.pickups, "Repair"), ship, palette)
	return true


## A new name for something this ship drops: "<prefix><peer>_<n>", unused in `parent`.
func _drop_name(parent: Node, prefix: String) -> String:
	while true:
		_drops += 1
		var n := "%s%d_%d" % [prefix, peer_id, _drops]
		if not parent.has_node(n):
			return n
	return ""


# --- Escape pod -----------------------------------------------------------------

## The upgrades a pod carries.
func upgrade_state() -> Dictionary:
	return {"levels": levels.duplicate(), "shield": shield, "rear_shield": rear_shield,
		"options": options, "tier": tier}


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


## Owner: our pod `pod_name` was destroyed; its upgrades are gone.
func forget_pod(pod_name: String) -> void:
	_stashes.erase(pod_name)


## Takes the better of what we have and what `st` carries, upgrade by upgrade.
func _apply_upgrades(st: Dictionary) -> void:
	var armor_before := level(&"armor")
	for id in st.get("levels", {}):
		levels[id] = maxi(level(id), st.levels[id])
	shield = maxi(shield, st.get("shield", 0))
	rear_shield = maxi(rear_shield, st.get("rear_shield", 0))
	options = maxi(options, st.get("options", 0))
	tier = maxi(tier, st.get("tier", 1))
	if is_alive():
		hp = minf(hp + HIT_HP * (level(&"armor") - armor_before), max_hp())


func _lose_upgrades() -> void:
	levels.clear()
	shield = 0
	rear_shield = 0
	options = 0
	tier = 1
	autocannon_on = false
	tail = []
	party_role = ""


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
	var keep := int((OPTION_GAP * PowerMeter.max_level(&"option", 3, &"modifier") + TAIL_GAP * TAIL_MAX) / TRAIL_STEP) + 2
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


func _update_tail() -> void:
	while _tail_sprites.size() > tail.size():
		_tail_sprites.pop_back().queue_free()
	for i in tail.size():
		var tex := Ships.get_lit_enemy_texture(EnemyScript.TYPES[clampi(tail[i], 0, EnemyScript.TYPES.size() - 1)].ship)
		if i == _tail_sprites.size():
			var s := Sprite2D.new()
			s.light_mask = body.light_mask
			s.flip_v = true  # still facing the way the enemy flew
			s.top_level = true
			add_child(s)
			_tail_sprites.append(s)
		var sprite := _tail_sprites[i]
		if sprite.texture != tex:
			sprite.texture = tex
			sprite.scale = Ships.scale_for(tex, EnemyScript.HEIGHT) * TAIL_SCALE
	var at := tail_positions()
	for i in tail.size():
		_tail_sprites[i].global_position = get_parent().to_global(at[i])
		_tail_sprites[i].visible = is_alive()


func _draw() -> void:
	if not is_alive():
		return
	_draw_role()
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
func take_damage(amount: float, from_behind := false, covered := false) -> void:
	if not is_local() or not is_alive():
		return
	if not covered:
		var tank := covering_tank()
		if tank:
			var share := amount * COVER_SHARE
			amount -= share
			var game := get_tree().get_first_node_in_group("game")
			if game:
				game.cover_hit.rpc_id(tank.get_multiplayer_authority(), String(tank.name), share, from_behind)
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
		_drop_pod()


func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not is_alive():
		return
	if area.is_in_group("bullet"):  # friendly fire
		if area.shooter == peer_id:
			return  # your own (and your options') shots pass through
		area.queue_free()  # every peer removes it; the owner takes the hit
		take_damage(area.damage(), area.position.y > position.y)
		return
	if not is_local():
		return
	if area.is_in_group("enemy"):
		take_damage(1, area.position.y > position.y)
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.report_ram.rpc_id(1, String(area.name))
