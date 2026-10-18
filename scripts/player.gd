extends Area2D
## A player ship. The owning peer simulates it (movement, firing, damage to
## itself) and replicates position and hp to everyone else, so it never waits
## on the network.
## Upgrades bought on the PowerMeter (speed, rapid fire, double/triple shot,
## options, front and rear shields, tier II) live here too; they are lost when
## the ship is destroyed.
## Options are small copies of the ship that trail along the path it flew
## (every peer builds the trail from the replicated position) and fire whatever
## the ship fires.
## Friendly fire is always on: other players' bullets hurt (your own never do).
## RESCUE adds a button that launches a search-and-rescue drone, an option-sized
## copy of the ship: it flies to the nearest enemy escape pods, picks up to
## DRONE_CAPACITY, and brings them home for exp and score. The owner flies it;
## its position replicates so everyone sees it.
## MISSILE adds a MISSILE button: the ship and each option fire a seeking
## missile (same damage as a laser, twice its base cooldown).
## BEAM (tier II) adds a BEAM button: for a moment the ship pours a dense
## stream of laser bullets straight up from the spot where it was fired (the
## stream stays there even as the ship moves). Each level makes it thicker
## (more columns) and last longer.
## AUTOCAN adds an AUTO on/off button for a vulcan cannon: while on, it hoses
## whatever is closest within AUTO_RANGE (enemies and other players alike) with
## tiny, fast, weak rounds.

const BulletScript := preload("res://scripts/bullet.gd")
const SPEED := 340.0
const FIRE_COOLDOWN := 0.45  # min time between shots; matches the Lasers button cooldown
const RESPAWN_TIME := 2.0
const MAX_HP := 3
const SPEED_STEP := 0.2  # +20% move speed per SPEED level
const RAPID_STEP := 0.8  # cooldown x0.8 per RAPID level
const DOUBLE_SPREAD := 9.0  # side offset of each DOUBLE shot
const TRIPLE_SPREAD := 13.0  # side offset of the outer TRIPLE shots
const SHIELD_HITS := 3  # hits each shield (front, rear) absorbs
const SHIELD_RADIUS := 26.0
const OPTION_SCALE := 0.5  # option size relative to the ship
const OPTION_GAP := 40.0  # px of flown path between the ship and each option
const TRAIL_STEP := 4.0  # px between recorded trail points
const DRONE_SPEED := 420.0
const DRONE_REACH := 14.0  # px: close enough to grab a pod or dock
const DRONE_CAPACITY := 3  # pods per trip
const DRONE_TIME := 10.0  # s: heads home after this long out
const DRONE_TINT := Color(0.7, 1.0, 0.75)
const MISSILE_COOLDOWN := FIRE_COOLDOWN * 2.0  # matches the MISSILE button cooldown
const BEAM_COOLDOWN := 3.0  # matches the BEAM button cooldown
const BEAM_INTERVAL := 0.05  # s between bullets in each column
const BEAM_TIMES: Array[float] = [0.8, 1.2, 1.6]  # s the beam lasts, by level
const BEAM_SPACING := 7.0  # px between columns; level n has 2n-1 columns
const AUTO_RANGE := 130.0  # px: targets this close
const AUTO_COOLDOWN := 0.07  # s between vulcan rounds (halved at level 2)
const AUTO_SPREAD := 0.09  # rad: rounds scatter up to this much either way

@export var peer_id := 1
@export var player_name := "Player"
@export var color := Color.WHITE
@export var ship := 0  # index into Ships.LIST
@export var palette := 0  # index into Ships.PALETTES
var spawn_position := Vector2.ZERO
var spawn_data := {}  # what Game.add_player built it from, re-sent to late joiners

var hp := MAX_HP  # replicated
var shield := 0  # replicated: hits left on the front shield (blocks hits from ahead)
var rear_shield := 0  # replicated: hits left on the rear shield (tier II; blocks hits from behind)
var tier := 1  # local: PowerMeter tier
var drone_out := false  # replicated: the rescue drone is away from the ship
var drone_pos := Vector2.ZERO  # replicated: drone position (same space as the ship's)
var drone_carrying := 0  # local: pods the host confirmed on board
var _drone_time := 0.0
var _drone_claimed := {}  # local: pod names grabbed this trip (claims sent to the host)
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
var options := 0  # replicated: option count
var exp_total := 0  # local: exp this player has collected
var levels := {}  # local: upgrade id -> level bought
var _lit := -1  # local: PowerMeter slot lit by banked exp (-1 = none)
var _trail: Array[Vector2] = []  # flown path, newest first, TRAIL_STEP apart
var _option_sprites: Array[Sprite2D] = []
var input_dir := Vector2.ZERO
var _fire_requested := false  # a Lasers press waiting for the cooldown check
var _seen_presses := -1  # local: Lasers button press count already handled (-1 = not synced yet)
var _cooldown := 0.0
var _respawn_timer := 0.0
var _damage_carry := 0.0  # fractions of a hit not yet adding up to one

@onready var body: Sprite2D = $Body
@onready var label: Label = $Label


func _ready() -> void:
	label.text = player_name
	body.texture = Ships.get_lit_texture(ship, palette)
	body.scale = Ships.get_scale(ship, palette)
	body.light_mask = Ships.LIGHT_MASK
	area_entered.connect(_on_area_entered)
	if Net.all_weapons and multiplayer.multiplayer_peer != null and is_local():
		max_upgrades()


func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()


func is_alive() -> bool:
	return hp > 0


func _process(_delta: float) -> void:
	body.modulate.a = 1.0 if is_alive() else 0.25
	queue_redraw()  # shield ring
	_update_options()
	_update_drone_sprite()
	if multiplayer.multiplayer_peer == null:
		return
	if is_local():
		_gather_input()


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and is_local():
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
	var game := get_tree().get_first_node_in_group("game")
	if game and not game.input_enabled:
		dir = Vector2.ZERO
		fire = false
	input_dir = dir
	if bar:
		bar.set_cooldown(&"lasers", fire_cooldown())
		bar.set_shown(&"rescue", level(&"rescue") > 0)
		bar.set_enabled(&"rescue", is_alive() and not drone_out)
		bar.set_shown(&"missile", level(&"missile") > 0)
		bar.set_shown(&"beam", level(&"beam") > 0)
		bar.set_shown(&"auto", level(&"auto") > 0)
		bar.set_lit(&"auto", autocannon_on)
	if fire:
		_fire_requested = true


func _simulate(delta: float) -> void:
	if not is_alive():
		_fire_requested = false
		_launch_requested = false
		_missile_requested = false
		_beam_requested = false
		_beam_left = 0.0
		_recall_drone()
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			hp = MAX_HP
			_lose_upgrades()
			if Net.all_weapons:
				max_upgrades()
			position = spawn_position
		return

	position += input_dir * move_speed() * delta
	var bounds := _movement_bounds()
	position = position.clamp(bounds.position, bounds.end)

	if _launch_requested:
		_launch_requested = false
		launch_drone()
	if drone_out:
		_fly_drone(delta)
	_run_autocannon(delta)
	_fire_missiles(delta)
	_run_beam(delta)

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
			if level(&"double") >= 2:
				for x in [-TRIPLE_SPREAD, 0.0, TRIPLE_SPREAD]:
					game.spawn_bullet(muzzle + Vector2(x, 0), color)
			elif level(&"double") == 1:
				game.spawn_bullet(muzzle + Vector2(-DOUBLE_SPREAD, 0), color)
				game.spawn_bullet(muzzle + Vector2(DOUBLE_SPREAD, 0), color)
			else:
				game.spawn_bullet(muzzle, color)


# --- Upgrades ----------------------------------------------------------------

func level(id: StringName) -> int:
	if id == &"shield":
		return (1 if shield > 0 else 0) + (1 if rear_shield > 0 else 0)
	if id == &"option":
		return options
	return levels.get(id, 0)


func can_upgrade(id: StringName) -> bool:
	return level(id) < PowerMeter.max_level(id, tier)


func move_speed() -> float:
	return SPEED * (1.0 + SPEED_STEP * level(&"speed"))


func fire_cooldown() -> float:
	return FIRE_COOLDOWN * pow(RAPID_STEP, level(&"rapid"))


## PowerMeter slot the banked exp lights, or -1.
func lit_slot() -> int:
	return _lit


## One exp collected: count it and light the next meter slot (wrapping).
func add_exp() -> void:
	exp_total += 1
	_lit = (_lit + 1) % PowerMeter.slots_for(tier).size()


## Buys the lit slot's upgrade, spending the banked exp. A maxed slot can't be
## bought and keeps the exp banked. Returns whether it bought.
func buy_upgrade() -> bool:
	if _lit < 0 or not is_alive():
		return false
	var id: StringName = PowerMeter.slots_for(tier)[_lit].id
	if not can_upgrade(id):
		return false
	_lit = -1
	if id == &"shield":
		if shield <= 0:
			shield = SHIELD_HITS
		else:
			rear_shield = SHIELD_HITS
	elif id == &"option":
		options += 1
	else:
		levels[id] = level(id) + 1
		if id == &"tier" and levels[id] >= PowerMeter.TIER_CHARGES:
			tier = 2  # the meter switches to tier II
	return true


## Every upgrade at its tier II max (the all-weapons cheat, see Net.ALL_WEAPONS_NAME).
func max_upgrades() -> void:
	tier = 2
	_lit = -1
	levels[&"tier"] = PowerMeter.TIER_CHARGES
	for s in PowerMeter.SLOTS:
		var top := PowerMeter.max_level(s.id, 2)
		if s.id == &"shield":
			shield = SHIELD_HITS
			rear_shield = SHIELD_HITS
		elif s.id == &"option":
			options = top
		elif top > 0:
			levels[s.id] = top


# --- Missiles -----------------------------------------------------------------

func _fire_missiles(delta: float) -> void:
	_missile_cooldown -= delta
	if not _missile_requested:
		return
	_missile_requested = false  # like lasers: a press during the cooldown is dropped
	if level(&"missile") <= 0 or _missile_cooldown > 0.0:
		return
	_missile_cooldown = MISSILE_COOLDOWN
	var game := get_tree().get_first_node_in_group("game")
	var guns: Array[Vector2] = [position]
	guns.append_array(option_positions())
	for g in guns:
		game.spawn_bullet(g + Vector2(0, -20), color, Vector2.UP, BulletScript.MISSILE)


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
			game.spawn_bullet(_beam_origin + Vector2(x, 0), color)


# --- Autocannon ---------------------------------------------------------------

## Closest enemy or other living player within AUTO_RANGE, or null.
func auto_target() -> Node2D:
	var best: Node2D = null
	var best_d := AUTO_RANGE
	for group in [&"enemy", &"player"]:
		for n in get_tree().get_nodes_in_group(group):
			if n == self or n.is_queued_for_deletion() or (group == &"player" and not n.is_alive()):
				continue
			var d := position.distance_to(n.position)
			if d <= best_d:
				best_d = d
				best = n
	return best


func _run_autocannon(delta: float) -> void:
	_auto_cooldown -= delta
	if not autocannon_on or level(&"auto") <= 0 or _auto_cooldown > 0.0:
		return
	var target := auto_target()
	if target == null:
		return
	_auto_cooldown = AUTO_COOLDOWN / level(&"auto")
	var dir := (target.position - position).normalized().rotated(randf_range(-AUTO_SPREAD, AUTO_SPREAD))
	get_tree().get_first_node_in_group("game").spawn_bullet(position + dir * 18.0, color, dir, BulletScript.VULCAN)


# --- Search and rescue ---------------------------------------------------------

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
	if _drone_claimed.size() < DRONE_CAPACITY and _drone_time < DRONE_TIME:
		target = _drone_target()
	var goal := target.position if target else position
	drone_pos = drone_pos.move_toward(goal, DRONE_SPEED * delta)
	if drone_pos.distance_to(goal) > DRONE_REACH:
		return
	if target:
		_drone_claimed[String(target.name)] = true
		get_tree().get_first_node_in_group("game").request_rescue.rpc_id(1, String(target.name))
	else:
		_dock_drone()


## The host confirmed a pod is ours. If the drone already docked, it counts now.
func drone_picked_up() -> void:
	if drone_out:
		drone_carrying += 1
	elif is_alive():
		_deliver(1)


func _dock_drone() -> void:
	drone_out = false
	_deliver(drone_carrying)
	drone_carrying = 0


func _deliver(count: int) -> void:
	if count <= 0:
		return
	for i in count:
		add_exp()
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.report_rescue.rpc_id(1, count)


## Ship lost: the drone and anything on board are lost too.
func _recall_drone() -> void:
	drone_out = false
	drone_carrying = 0
	_drone_claimed.clear()


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


func _lose_upgrades() -> void:
	levels.clear()
	shield = 0
	rear_shield = 0
	options = 0
	tier = 1
	_lit = -1
	autocannon_on = false


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
	var keep := int(OPTION_GAP * PowerMeter.max_level(&"option", 2) / TRAIL_STEP) + 2
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


func _draw() -> void:
	if not is_alive():
		return
	if shield > 0:  # front: the top half
		draw_arc(Vector2.ZERO, SHIELD_RADIUS, PI, TAU, 24, Color(0.35, 0.8, 1.0, 0.3 + 0.2 * shield), 2.5, true)
	if rear_shield > 0:  # rear: the bottom half
		draw_arc(Vector2.ZERO, SHIELD_RADIUS, 0.0, PI, 24, Color(0.75, 0.55, 1.0, 0.3 + 0.2 * rear_shield), 2.5, true)


func _movement_bounds() -> Rect2:
	var arena: Rect2 = get_parent().get_parent().ARENA
	var r := arena.grow(-20)
	r.end.y = arena.end.y - ActionBar.BAR_HEIGHT - 20  # stay above the button bar
	return r


## Owner only: each peer decides damage to its own ship. `from_behind`: the hit
## came from below (rear shield) rather than ahead (front shield). `amount` may
## be a fraction of a hit (vulcan rounds); fractions add up, and each whole hit
## takes a shield charge or 1 hp.
func take_damage(amount: float, from_behind := false) -> void:
	if not is_local() or not is_alive():
		return
	_damage_carry += amount
	var hits := floori(_damage_carry + 0.0001)
	_damage_carry = maxf(0.0, _damage_carry - hits)
	for i in hits:
		if is_alive():
			_take_hit(from_behind)


func _take_hit(from_behind: bool) -> void:
	if from_behind and rear_shield > 0:
		rear_shield -= 1
		return
	if not from_behind and shield > 0:
		shield -= 1
		return
	hp -= 1
	if hp <= 0:
		hp = 0
		_respawn_timer = RESPAWN_TIME


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
