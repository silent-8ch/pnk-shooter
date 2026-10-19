extends Area2D
## Enemy ship. Server-simulated; `type` picks the look and behavior.
##   WEAVER (ship 01): weaves side to side as it drifts down; comes in lines.
##   DIVER  (ship 02): faster; comes in Vs that zigzag down together, bouncing
##                     off the screen edges while holding formation.
##   STRIKER (ship 03): comes in a slanted line, creeps in slowly, then each ship
##                      lunges straight down in turn, front ship first.
##   TANK    (ship 04): big and slow, takes TANK hp hits; sways gently, in pairs.
##   ORBITER (ship 05): a ring of ships circling a center that drifts down.
##   TURRET  (ship 03, small): a gun emplacement on the ground or a wall. Scrolls
##           down with the scenery (no ramp-in), fires single aimed shots.
##   BOSS    (big; its ship depends on the kind of level, `ship_override`): sent in by Game after enough kills (Game.boss_kills_needed). Glides down
##           to BOSS_Y, then weaves there and fires aimed spreads of hostile
##           bullets at the nearest player (host decides when). Never leaves;
##           its hp shows as a bar (the host sends it, see Game.boss_hp).
##   ELITE   (ship 04, big): the mini boss, sent in by Game halfway to the
##           boss. Glides down and weaves like the boss but never fires; it
##           just takes a lot of hits, with an hp bar like the boss's.
##   RIVAL   flies and fights like a player, facing down: a random player
##           ship in the stage's enemy colors, flown by the host (Rival).
##   TETRAN  (a boss, Deep Space's): a big armored core with four straight
##           arms that run off the screen and turn steadily one way, so ships
##           orbit it (see tetran.gd); only the core can be hurt, and it never
##           fires. Its look is drawn in code.
## `stage` (Game.stage at spawn, 0 first) makes every enemy tougher: more hp
## (STAGE_HP), faster (STAGE_SPEED, capped) and worth more (STAGE_POINTS), and
## changes its colors (Ships.enemy_colors).
## Shots hit the ship's outline, traced from its art (Ships.apply_hitbox).
## A player's HEAL shots make it stronger instead: every whole hit's worth adds
## a hit point (over its starting hp too) and it grows GROW_STEP bigger, up to
## GROW_MAX (Game.grow_enemy tells every peer).
## The host spawns enemies and decides damage and death; movement is deterministic
## from the spawn data, so every peer runs it locally with no per-frame sync.

enum { WEAVER, DIVER, STRIKER, TANK, ORBITER, BOSS, TURRET, ELITE, TETRAN, RIVAL }

## `group`: default [min, max] ships when a group is sent in without a count.
## `height`: on-screen height (px); defaults to HEIGHT.
const TYPES: Array[Dictionary] = [
	{"ship": 0, "hp": 1, "points": 10, "speed": 90.0, "group": [3, 5]},
	{"ship": 1, "hp": 1, "points": 15, "speed": 130.0, "group": [3, 3]},
	{"ship": 2, "hp": 1, "points": 20, "speed": 70.0, "group": [2, 4]},
	{"ship": 3, "hp": 4, "points": 40, "speed": 50.0, "group": [1, 2], "height": 42.0},
	{"ship": 4, "hp": 1, "points": 25, "speed": 80.0, "group": [4, 4]},
	{"ship": 4, "hp": 40, "points": 500, "speed": 90.0, "group": [1, 1], "height": 130.0, "boss": true},
	{"ship": 2, "hp": 3, "points": 30, "speed": 60.0, "group": [1, 2], "height": 34.0},
	{"ship": 3, "hp": 20, "points": 200, "speed": 70.0, "group": [1, 1], "height": 84.0, "elite": true},
	{"ship": 4, "hp": 60, "points": 800, "speed": 90.0, "group": [1, 1], "height": 112.0, "boss": true, "tetran": true},
	{"ship": 0, "hp": 4, "points": 60, "speed": 260.0, "group": [1, 1], "height": 44.0, "rival": true},
]
const RIVAL_SYNC := 0.05  # s between the host's position updates for a rival
const RIVAL_FOLLOW := 15.0  # how quickly other peers' copies catch up (per second)
const TetranScript := preload("res://scripts/tetran.gd")
const WAVE_TYPES := 5  # TYPES before BOSS: the ones deep space's random waves send in
const TURRET_SPACING := 140.0
const TURRET_FIRE_INTERVAL := 2.4  # s between shots at stage 0, shrinking like the boss's
const TURRET_FIRE_MIN := 1.0
const TURRET_RANGE := Vector2(40, 760)  # fires only while its y is in this band
const STAGE_HP := 0.6  # hp x (1 + this per stage), rounded up
const GROW_STEP := 0.08  # bigger per hit point a HEAL shot adds
const GROW_MAX := 1.6
const STAGE_SPEED := 0.08  # speed x (1 + this per stage) ...
const STAGE_SPEED_MAX := 1.4  # ... up to this
const STAGE_POINTS := 1.0  # points x (1 + this per stage)
const BOSS_Y := 170.0  # where the boss hovers
const BOSS_SWAY := 150.0  # px either side of center
const BOSS_SWAY_FREQUENCY := 0.6
const BOSS_BOB := 18.0
const BOSS_FIRE_INTERVAL := 1.8  # s between spreads at stage 0 ...
const BOSS_FIRE_MIN := 0.8  # ... shrinking with stage down to this
const BOSS_SPREAD := 0.22  # rad between bullets in a spread
const BOSS_RAM_DAMAGE := 2  # ramming the boss chips it instead of killing it
const BOSS_BAR := Vector2(110, 6)
const GLOW_SPEED := 5.0  # rad/s of the pulse once the stage colors loop
const HEIGHT := 36.0
const WEAVE_AMPLITUDE := 60.0
const WEAVE_FREQUENCY := 2.5  # radians per second
const ZIGZAG_SPEED := 110.0  # horizontal speed of a diver group
const EDGE_MARGIN := 20.0
const ARENA_WIDTH := 540.0
const EXIT_Y := 1020.0
const RAMP_TIME := 1.0  # seconds to go from RAMP_START to full speed
const RAMP_START := 0.5  # fraction of full speed when spawned
const WEAVER_SPACING := 70.0
const WEAVER_GROUP_MIN := 3
const WEAVER_GROUP_MAX := 5
const DIVER_GROUP := 3
const DIVER_V_OFFSET := Vector2(50, 40)  # each wing is this far out and back
const SPAWN_Y := -40.0
const STRIKER_GAP := Vector2(40, 60)  # each striker is this far right of and behind the one before
const LUNGE_TIME := 1.6  # s the front striker creeps before lunging
const LUNGE_STAGGER := 0.35  # s later each following striker lunges
const LUNGE_SPEED := 380.0
const TANK_SPACING := 120.0
const TANK_SWAY := 25.0
const TANK_SWAY_FREQUENCY := 1.2  # radians per second
const ORBIT_RADIUS := 50.0
const ORBIT_SPEED := 2.2  # radians per second; `zig_dir` picks the direction
const ORBIT_CENTER_Y := SPAWN_Y - ORBIT_RADIUS  # ring center at spawn

@export var type := WEAVER
var rival: Rival  # host: a RIVAL's brain
var _rival_target := Vector2.ZERO  # other peers: where the host last said this rival is
var _rival_sync := 0.0
@export var group_x := -1.0  # group center at spawn; < 0 means this ship's x
@export var zig_dir := 1.0  # initial horizontal direction of the group
@export var stage := 0  # Game.stage when it was sent in
@export var ship_override := -1  # look of this one (a boss per kind of level); -1 = its type's ship

var max_hp := 0
var shown_hp := 0  # boss: hp for its bar (the host's, sent to every peer)
var _fire_timer := 0.0

var hp := 0
var _damage_carry := 0.0  # fractions of a hit (vulcan rounds) not yet adding up to one
var _heal_carry := 0.0  # host: fractions of a heal shot's hit not yet adding up to one
var growth := 1.0  # every peer: how much bigger HEAL shots have made it
var _spawn_pos := Vector2.ZERO
var _base_x := 0.0
var _time := 0.0
var _orbit_angle := 0.0  # orbiter: angle around the ring center at spawn

@onready var body: Sprite2D = $Body


func _ready() -> void:
	type = clampi(type, 0, TYPES.size() - 1)
	hp = ceili(TYPES[type].hp * (1.0 + STAGE_HP * stage))
	max_hp = hp
	shown_hp = hp
	_spawn_pos = position
	_rival_target = position
	_base_x = position.x
	var center := group_x if group_x >= 0.0 else _base_x
	_orbit_angle = atan2(_spawn_pos.y - ORBIT_CENTER_Y, _spawn_pos.x - center)
	var tex := Ships.get_lit_enemy_texture(ship_index(), stage)
	body.texture = tex
	body.scale = Ships.scale_for(tex, TYPES[type].get("height", HEIGHT))
	# Godot flips the normal map's Y along with flip_v (checked empirically on 4.6), so
	# the shared normal map lights correctly upside down; no flipped variant needed.
	body.flip_v = true
	body.light_mask = Ships.LIGHT_MASK
	if not is_tetran():
		var jets := Thrusters.new()  # flare as it changes course
		jets.name = "Thrusters"
		jets.radius = TYPES[type].get("height", HEIGHT) / 2.0
		jets.layout = Thrusters.flipped(Ships.thruster_layout(ship_index()), TYPES[type].get("height", HEIGHT) / Ships.SHIP_HEIGHT)  # it faces down
		jets.flame = Color("ff6a4a")
		jets.core = Color("ffd2a0")
		add_child(jets)
	if is_tetran():
		body.visible = false  # it draws itself
		($Shape.shape as CircleShape2D).radius = TetranScript.CORE_RADIUS
		var arms := TetranScript.new()
		arms.name = "Tetran"
		add_child(arms)
	else:
		Ships.apply_hitbox(self, ship_index(), body)  # shots hit the art, not a circle
	area_entered.connect(_on_area_entered)


## Which ship this enemy looks like (Ships.LIST index).
func ship_index() -> int:
	return ship_override if ship_override >= 0 else TYPES[type].ship


func points() -> int:
	return roundi(TYPES[type].points * (1.0 + STAGE_POINTS * stage))


func is_boss() -> bool:
	return TYPES[type].get("boss", false)


func is_tetran() -> bool:
	return TYPES[type].get("tetran", false)


func is_rival() -> bool:
	return TYPES[type].get("rival", false)


func is_elite() -> bool:
	return TYPES[type].get("elite", false)


## The boss and the mini boss: they hold their ground, show an hp bar and shrug off rams.
func has_bar() -> bool:
	return is_boss() or is_elite()


## Speed multiplier for this enemy's stage (same on every peer: it's in the spawn data).
func speed_mult() -> float:
	return minf(1.0 + STAGE_SPEED * stage, STAGE_SPEED_MAX)


## Spawn data plus where this ship is in its flight, for a player joining late.
## A RIVAL: the host flies it (Rival) and sends where it is every RIVAL_SYNC
## s; everyone else eases their copy toward that.
func _fly_rival(delta: float) -> void:
	if not multiplayer.is_server():
		position = position.lerp(_rival_target, minf(1.0, RIVAL_FOLLOW * delta))
		return
	var game := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	if game == null:
		return
	if rival == null:
		rival = Rival.new()
	var step := rival.step(self, game, delta)
	position = step.pos
	if step.fire > 0:
		for at in Rival.volley(position, step.fire):
			game.fire_enemy_bullet.rpc(at, Vector2.DOWN)
	_rival_sync -= delta
	if _rival_sync <= 0.0:
		_rival_sync = RIVAL_SYNC
		rival_at.rpc(position)


## Host -> everyone else: where this rival is now.
@rpc("authority", "call_remote", "unreliable_ordered")
func rival_at(pos: Vector2) -> void:
	_rival_target = pos


func snapshot() -> Dictionary:
	return {"x": _spawn_pos.x, "y": _spawn_pos.y, "type": type, "group_x": group_x, "dir": zig_dir,
		"id": String(name).trim_prefix("Enemy").to_int(), "time": _time, "pos": position, "stage": stage,
		"ship": ship_override}


## Picks up a flight from a snapshot (see snapshot()).
func restore(time: float, pos: Vector2) -> void:
	_time = time
	position = pos


func _process(_delta: float) -> void:
	if Ships.enemy_glows(stage):  # the color ramp has looped: these ones pulse
		body.self_modulate = Color.WHITE * (1.15 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * GLOW_SPEED))


func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	simulate(delta)
	if has_bar():
		queue_redraw()  # hp bar
	if is_boss() and not is_tetran() and multiplayer.is_server():
		_boss_fire(delta)  # Tetran's arms do its firing
	elif type == TURRET and multiplayer.is_server():
		_turret_fire(delta)
	if position.y > EXIT_Y:
		queue_free()  # same on every peer: the paths are deterministic


func simulate(delta: float) -> void:
	_time += delta
	match type:
		RIVAL:
			_fly_rival(delta)
			return
		STRIKER:
			position.y = _spawn_pos.y + striker_fall(_time, lunge_time(), speed_mult())
			return
		BOSS, ELITE:
			position = boss_position(_spawn_pos, _time, speed_mult(), type)
			return
		TETRAN:
			position = TetranScript.core_position(_spawn_pos, _time, TYPES[TETRAN].speed * speed_mult())
			return
		TURRET:
			position.y = _spawn_pos.y + TYPES[TURRET].speed * _time  # bolted to the scenery
			return
		ORBITER:
			var center := Vector2(group_x if group_x >= 0.0 else _base_x, ORBIT_CENTER_Y + fall_distance(type, _time, speed_mult()))
			var a := _orbit_angle + signf(zig_dir) * ORBIT_SPEED * _time
			position = center + Vector2(cos(a), sin(a)) * ORBIT_RADIUS
			return
	position.y += speed_now() * delta
	match type:
		WEAVER:
			var x := _base_x + sin(_time * WEAVE_FREQUENCY) * WEAVE_AMPLITUDE
			position.x = clampf(x, 20.0, ARENA_WIDTH - 20.0)
		DIVER:
			var center := group_x if group_x >= 0.0 else _base_x
			position.x = zigzag_center(center, zig_dir, _time) + (_base_x - center)
		TANK:
			position.x = _base_x + sin(_time * TANK_SWAY_FREQUENCY) * TANK_SWAY


## Current falling speed: eases in from RAMP_START over RAMP_TIME.
func speed_now() -> float:
	var t := clampf(_time / RAMP_TIME, 0.0, 1.0)
	return TYPES[type].speed * speed_mult() * lerpf(RAMP_START, 1.0, t)


## Distance fallen after `time` s at the type's speed (x `mult`), easing in like speed_now().
static func fall_distance(t_type: int, time: float, mult := 1.0) -> float:
	var v: float = TYPES[t_type].speed * mult
	if time <= 0.0:
		return 0.0
	if time <= RAMP_TIME:
		return v * (RAMP_START * time + (1.0 - RAMP_START) * time * time / (2.0 * RAMP_TIME))
	return v * (RAMP_START * RAMP_TIME + (1.0 - RAMP_START) * RAMP_TIME / 2.0 + time - RAMP_TIME)


## Striker: creeps (normal ramp) until `lunge`, then drops at LUNGE_SPEED.
static func striker_fall(time: float, lunge: float, mult := 1.0) -> float:
	if time <= lunge:
		return fall_distance(STRIKER, time, mult)
	return fall_distance(STRIKER, lunge, mult) + LUNGE_SPEED * mult * (time - lunge)


## Boss (and the ELITE mini boss, `t_type`): glides down from `spawn` to
## BOSS_Y, then weaves across the top.
static func boss_position(spawn: Vector2, time: float, mult := 1.0, t_type := BOSS) -> Vector2:
	var y := minf(spawn.y + fall_distance(t_type, time, mult), BOSS_Y)
	var settled := maxf(0.0, time - _boss_arrival(spawn, mult, t_type))
	var x := ARENA_WIDTH / 2.0 + sin(settled * BOSS_SWAY_FREQUENCY) * BOSS_SWAY
	return Vector2(x, y + sin(settled * BOSS_SWAY_FREQUENCY * 2.2) * BOSS_BOB * minf(settled, 1.0))


## Seconds until the boss reaches BOSS_Y.
static func _boss_arrival(spawn: Vector2, mult: float, t_type := BOSS) -> float:
	var d := BOSS_Y - spawn.y
	var v: float = TYPES[t_type].speed * mult
	var ramp := v * (RAMP_START * RAMP_TIME + (1.0 - RAMP_START) * RAMP_TIME / 2.0)
	if d <= ramp:  # within the ramp; close enough for when the weave starts
		return RAMP_TIME * d / ramp
	return RAMP_TIME + (d - ramp) / v


func fire_interval() -> float:
	return maxf(BOSS_FIRE_MIN, BOSS_FIRE_INTERVAL * pow(0.85, stage))


## Host: once settled, fires a spread at the nearest living player now and then.
## Stage n fires 3 + n bullets (up to 7).
func _boss_fire(delta: float) -> void:
	if position.y < BOSS_Y - 1.0:
		return
	_fire_timer += delta
	if _fire_timer < fire_interval():
		return
	_fire_timer = 0.0
	var target: Node2D = null
	var best := INF
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_alive() and position.distance_to(p.position) < best:
			best = position.distance_to(p.position)
			target = p
	var game := get_tree().get_first_node_in_group("game")
	if target == null or game == null:
		return
	var aim := (target.position - position).normalized()
	var n := mini(3 + stage, 7)
	var scenery: Node = game.get("scenery")
	if scenery and scenery.boss_attack(self, target, n):
		return  # this kind of level's boss has its own attack
	for i in n:
		game.fire_enemy_bullet.rpc(position + aim * 50.0, aim.rotated((i - (n - 1) / 2.0) * BOSS_SPREAD))


## Host: a turret on screen fires one aimed shot at the nearest living player now and then.
func _turret_fire(delta: float) -> void:
	if position.y < TURRET_RANGE.x or position.y > TURRET_RANGE.y:
		return
	_fire_timer += delta
	if _fire_timer < maxf(TURRET_FIRE_MIN, TURRET_FIRE_INTERVAL * pow(0.85, stage)):
		return
	_fire_timer = 0.0
	var target := nearest_player()
	var game := get_tree().get_first_node_in_group("game")
	if target and game:
		var aim := (target.position - position).normalized()
		game.fire_enemy_bullet.rpc(position + aim * 20.0, aim)


## The nearest living player, or null.
func nearest_player() -> Node2D:
	var target: Node2D = null
	var best := INF
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_alive() and position.distance_to(p.position) < best:
			best = position.distance_to(p.position)
			target = p
	return target


## When this striker lunges: the front ship at LUNGE_TIME, each one behind it later.
func lunge_time() -> float:
	return LUNGE_TIME + LUNGE_STAGGER * maxf(0.0, roundf((SPAWN_Y - _spawn_pos.y) / STRIKER_GAP.y))


## Spawn positions for a group, centered on center_x: weavers and tanks in a
## horizontal line, divers in a V (leader in front), strikers in a slanted line
## (front ship on the left), orbiters evenly around a ring.
static func group_layout(group_type: int, count: int, center_x: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if group_type == STRIKER:
		for i in count:
			out.append(Vector2(center_x + STRIKER_GAP.x * (i - (count - 1) / 2.0), SPAWN_Y - STRIKER_GAP.y * i))
	elif group_type == ORBITER:
		for i in count:
			var a := TAU * i / count - PI / 2.0
			out.append(Vector2(center_x, ORBIT_CENTER_Y) + Vector2(cos(a), sin(a)) * ORBIT_RADIUS)
	elif group_type == TURRET:
		var left := center_x - TURRET_SPACING * (count - 1) / 2.0
		for i in count:
			out.append(Vector2(left + TURRET_SPACING * i, SPAWN_Y))
	elif group_type == TANK:
		var left := center_x - TANK_SPACING * (count - 1) / 2.0
		for i in count:
			out.append(Vector2(left + TANK_SPACING * i, SPAWN_Y))
	elif group_type == DIVER:
		out.append(Vector2(center_x, SPAWN_Y))
		for i in range(1, count):
			var rank := ceili(i / 2.0)
			var side := -1.0 if i % 2 == 1 else 1.0
			out.append(Vector2(center_x + side * DIVER_V_OFFSET.x * rank, SPAWN_Y - DIVER_V_OFFSET.y * rank))
	else:
		var left := center_x - WEAVER_SPACING * (count - 1) / 2.0
		for i in count:
			out.append(Vector2(left + WEAVER_SPACING * i, SPAWN_Y))
	return out


## Distance from a group's center to the farthest point it can reach sideways.
static func group_half_width(group_type: int, count: int) -> float:
	if group_type == DIVER:
		return DIVER_V_OFFSET.x * floorf(count / 2.0)
	if group_type == STRIKER:
		return STRIKER_GAP.x * (count - 1) / 2.0
	if group_type == TANK:
		return TANK_SPACING * (count - 1) / 2.0 + TANK_SWAY
	if group_type == ORBITER:
		return ORBIT_RADIUS
	if group_type == TURRET:
		return TURRET_SPACING * (count - 1) / 2.0
	return WEAVER_SPACING * (count - 1) / 2.0 + WEAVE_AMPLITUDE


## Group center x after `time` seconds: moves at ZIGZAG_SPEED and bounces
## between the edges so the whole V stays on screen. Shared by the group, so
## every ship in it turns at the same moment.
static func zigzag_center(start_x: float, dir: float, time: float) -> float:
	var margin := group_half_width(DIVER, DIVER_GROUP) + EDGE_MARGIN
	var lo := margin
	var span := ARENA_WIDTH - 2.0 * margin
	if span <= 0.0:
		return ARENA_WIDTH / 2.0
	var m := fposmod(start_x - lo + signf(dir) * ZIGZAG_SPEED * time, 2.0 * span)
	return lo + (m if m <= span else 2.0 * span - m)


## Host only. `amount` may be a fraction of a hit; fractions add up.
func take_damage(amount: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or hp <= 0:
		return
	_damage_carry += amount
	var hits := floori(_damage_carry + 0.0001)
	_damage_carry = maxf(0.0, _damage_carry - hits)
	if hits <= 0:
		return
	hp -= hits
	if hp <= 0:
		_destroy(true)
	else:
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.play_hit.rpc()
			if has_bar():
				game.boss_hp.rpc(String(name), hp)


## Rammed by a player: destroyed without scoring (the boss just takes BOSS_RAM_DAMAGE).
func ram() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or hp <= 0:
		return
	if has_bar():
		take_damage(BOSS_RAM_DAMAGE)
		return
	hp = 0
	_destroy(false)


func _destroy(award_points: bool) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.destroy_enemy(self, award_points)
	else:
		queue_free()


## Every peer removes a bullet that hits; only the shooter's copy reports the hit.
func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not area.is_in_group("bullet") or area.is_hostile():
		return
	area.queue_free()
	if not area.is_heal():
		Sparks.at_hit(self, area.position, area.direction, area.color, 6)
	if area.is_mine():
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.report(&"report_heal_hit" if area.is_heal() else &"report_hit", [String(name), area.damage()])
			if area.shooter == multiplayer.get_unique_id():
				DamageNumber.on(self, self, area.damage(), DamageNumber.HEAL if area.is_heal() else DamageNumber.DEAL, area.is_heal())


## Host: a HEAL shot hit it for `amount`. Each whole hit's worth adds a hit
## point (max_hp too, so a boss's bar stays honest). Returns how many it added.
func strengthen(amount: float) -> int:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or hp <= 0:
		return 0
	_heal_carry += amount
	var hits := floori(_heal_carry + 0.0001)
	_heal_carry = maxf(0.0, _heal_carry - hits)
	hp += hits
	max_hp += hits
	shown_hp = hp
	return hits


## Every peer: `hits` more hit points' worth of growth, up to GROW_MAX. The
## whole ship scales, its hitbox included.
func grow(hits: int) -> void:
	growth = minf(GROW_MAX, growth + GROW_STEP * hits)
	scale = Vector2.ONE * growth


func _draw() -> void:
	if not has_bar() or max_hp <= 0:
		return
	var r := Rect2(Vector2(-BOSS_BAR.x / 2.0, -TYPES[type].height / 2.0 - 16.0), BOSS_BAR)
	draw_rect(r.grow(1.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(float(shown_hp) / max_hp, 0.0, 1.0), r.size.y)), Color("ff4d6d"))
