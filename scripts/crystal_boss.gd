extends Area2D
## The Crystal boss's arms (Crystal Crevices): a three part boss. Two crystal
## arms reach out from the core, one each side, and each takes shots of its own.
## While either arm still stands the core is shielded and takes no damage at all
## (Enemy._shielded), so the party has to break both arms before the body —
## three targets, in that order. Touching an arm hurts a ship (group "hazard",
## see Player); the arms sway, so neither can be shot from one spot forever.
## Breaking one makes the boss angrier (CrystalCrevices.boss_attack reads
## arms_alive) and leaves a stump that no longer blocks.
##
## A child of its Enemy (type CRYSTAL), like Tetran's arms. The sway comes from
## the Enemy's flight time, so it needs no syncing; the host keeps each arm's hp
## and tells every peer when it changes (set_arm_hp) so the bars and the broken
## arms match everywhere. Only the shooter's copy reports a hit, like Enemy.
## Drawn in code until it has art: faceted shards down each arm, brightest at
## the tip, with a shield ring over the core while an arm lives.

const ARMS := 2
const SHARDS := 5  # crystals along one arm, root to tip
const ARM_LEN := 148.0  # px from the core's centre to the tip
const ARM_WIDTH := 34.0  # the hit box: this wide all along
const SHARD_RADIUS := Vector2(23.0, 11.0)  # root and tip
const CORE_RADIUS := 46.0  # the shield ring over the body
const ARM_HP_SHARE := 0.45  # each arm's hp, as a share of the core's (so it scales with the stage)
const SWAY := 0.5  # rad either side of straight out
const SWAY_FREQUENCY := 0.7  # rad/s
const SWAY_OFFSET := PI / 2.0  # the two arms sway out of step
const BAR_SIZE := Vector2(54, 4)
const BAR_LIFT := 14.0  # px above the arm's middle
const ARM_COLOR := Color("8de8ff")
const TIP_COLOR := Color("e8fbff")
const STUMP_COLOR := Color("4a6a7a")
const SHIELD_COLOR := Color("9ad9ff")
const CORE_COLOR := Color("ff7ad9")

var enemy: Node2D  # the core
var arm_hp: Array[int] = []  # host: shots left in each arm; every peer: what it was last told
var arm_max := 0
var _shapes: Array[CollisionShape2D] = []


func _ready() -> void:
	enemy = get_parent()
	add_to_group("hazard")
	collision_layer = 2  # ships run into it like an enemy
	collision_mask = 4  # bullets
	arm_max = maxi(1, roundi(enemy.max_hp * ARM_HP_SHARE))
	for a in ARMS:
		arm_hp.append(arm_max)
		var s := CollisionShape2D.new()
		s.shape = RectangleShape2D.new()
		s.shape.size = Vector2(ARM_LEN - CORE_RADIUS, ARM_WIDTH)
		add_child(s)
		_shapes.append(s)
	area_entered.connect(_on_area_entered)
	_place_shapes()


func _time() -> float:
	return enemy.get("_time") if enemy else 0.0


## Arms still standing. The core is shielded while this is above zero.
func arms_alive() -> int:
	var n := 0
	for hp in arm_hp:
		if hp > 0:
			n += 1
	return n


func is_broken(side: int) -> bool:
	return side < 0 or side >= arm_hp.size() or arm_hp[side] <= 0


## Which way arm `side` points at `time`: straight out left or right, swaying.
static func arm_angle(time: float, side: int) -> float:
	var out := PI if side == 0 else 0.0
	return out + sin(time * SWAY_FREQUENCY + side * SWAY_OFFSET) * SWAY


## The root and tip of arm `side` at `time`, relative to the core (unscaled).
static func arm_segment(time: float, side: int) -> Array:
	var dir := Vector2.from_angle(arm_angle(time, side))
	return [dir * CORE_RADIUS, dir * ARM_LEN]


## Where shard `i` of arm `side` sits, relative to the core (unscaled).
static func shard_at(time: float, side: int, i: int) -> Vector2:
	var seg := arm_segment(time, side)
	return (seg[0] as Vector2).lerp(seg[1] as Vector2, float(i) / maxi(SHARDS - 1, 1))


static func shard_radius(i: int) -> float:
	return lerpf(SHARD_RADIUS.x, SHARD_RADIUS.y, float(i) / maxi(SHARDS - 1, 1))


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_place_shapes()
	queue_redraw()


func _place_shapes() -> void:
	for a in ARMS:
		var seg := arm_segment(_time(), a)
		var root: Vector2 = seg[0]
		var tip: Vector2 = seg[1]
		_shapes[a].disabled = is_broken(a)
		_shapes[a].position = (root + tip) / 2.0
		_shapes[a].rotation = tip.angle()


## Whether a circle at `at` (game space), radius `r`, touches a standing arm.
## Droids use this to break on one (Droid), as they do on Tetran's.
func touches(at: Vector2, r: float) -> bool:
	for a in ARMS:
		if _reaches(at, r, a):
			return true
	return false


func _reaches(at: Vector2, r: float, side: int) -> bool:
	if is_broken(side):
		return false
	var s: float = enemy.scale.x
	var seg := arm_segment(_time(), side)
	var root: Vector2 = enemy.position + (seg[0] as Vector2) * s
	var tip: Vector2 = enemy.position + (seg[1] as Vector2) * s
	return at.distance_to(Geometry2D.get_closest_point_to_segment(at, root, tip)) < ARM_WIDTH * 0.5 * s + r


## How likely a ship at `at` is to be caught by an arm `ahead` s from now,
## 0 (clear) to 1 (touching it): what the AI pilot steers around (AiPilot).
func danger_at(at: Vector2, ahead: float) -> float:
	var s: float = enemy.scale.x
	var when := _time() + ahead
	for a in ARMS:
		if is_broken(a):
			continue
		var seg := arm_segment(when, a)
		var root: Vector2 = enemy.position + (seg[0] as Vector2) * s
		var tip: Vector2 = enemy.position + (seg[1] as Vector2) * s
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, root, tip)) < ARM_WIDTH * 0.5 * s + 18.0:
			return 1.0
	return 0.0


## The arm a shot at `at` (game space) landed on, or -1: the nearest standing
## one it actually reaches.
func arm_at(at: Vector2) -> int:
	var best := -1
	var best_d := INF
	for a in ARMS:
		if not _reaches(at, 0.0, a):
			continue
		var seg := arm_segment(_time(), a)
		var root: Vector2 = enemy.position + (seg[0] as Vector2) * enemy.scale.x
		var tip: Vector2 = enemy.position + (seg[1] as Vector2) * enemy.scale.x
		var d := at.distance_to(Geometry2D.get_closest_point_to_segment(at, root, tip))
		if d < best_d:
			best_d = d
			best = a
	return best


## Every peer removes a bullet that hits an arm; only the shooter's copy reports it.
func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not area.is_in_group("bullet") or area.is_hostile():
		return
	var side := arm_at(area.position)
	if side < 0:
		return  # a gap between the arms: let it fly on to the core
	area.queue_free()
	if not area.is_heal():
		Sparks.at_hit(self, area.position, area.direction, ARM_COLOR, 6)
	if area.is_mine() and not area.is_heal():
		_report.call_deferred(side, area.damage())
		if area.shooter == multiplayer.get_unique_id():
			DamageNumber.on(self, self, area.damage(), DamageNumber.DEAL, false)


func _report(side: int, damage: float) -> void:
	if multiplayer.multiplayer_peer != null:
		hit_arm.rpc_id(1, side, damage)


## A peer -> host: arm `side` took `damage`. The host keeps the hp and tells
## everyone; breaking the last arm uncovers the core.
@rpc("any_peer", "call_local", "reliable")
func hit_arm(side: int, damage: float) -> void:
	if not multiplayer.is_server() or is_broken(side):
		return
	arm_hp[side] = maxi(0, arm_hp[side] - maxi(1, floori(damage + 0.0001)))
	set_arm_hp.rpc(side, arm_hp[side])


## Host -> everyone: arm `side` is down to `hp` (0 = broken off).
@rpc("authority", "call_local", "reliable")
func set_arm_hp(side: int, hp: int) -> void:
	if side < 0 or side >= arm_hp.size():
		return
	arm_hp[side] = maxi(0, hp)
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.play_hit()
	if arm_hp[side] == 0:
		_shatter(side)
	queue_redraw()


## An arm breaks: its shards burst where they stood.
func _shatter(side: int) -> void:
	for i in SHARDS:
		var at: Vector2 = enemy.position + shard_at(_time(), side, i) * enemy.scale.x
		Sparks.at_hit(self, at, Vector2.ZERO, TIP_COLOR, 10)


## Everything here is drawn with straight edges and corners — flat facets, no
## circles or arcs: crystal, not rock.
func _draw() -> void:
	var time := _time()
	for a in ARMS:
		if is_broken(a):
			_draw_facet(arm_segment(time, a)[0], SHARD_RADIUS.x * 0.55, 0.0, 3, STUMP_COLOR)  # the stump it left
			continue
		for i in range(SHARDS - 1, -1, -1):  # tip first, so the root sits on top
			var p := shard_at(time, a, i)
			var r := shard_radius(i)
			var f := float(i) / maxi(SHARDS - 1, 1)
			var turn := arm_angle(time, a) + sin(time * 0.8 + a + i) * 0.25
			_draw_facet(p, r + 2.0, turn, 4, Color(0, 0, 0, 0.55))
			_draw_facet(p, r, turn, 4, ARM_COLOR.lerp(TIP_COLOR, f), true)
		_draw_bar(a, time)
	if arms_alive() > 0:  # the shield over the core, while an arm holds it up
		var pulse := 0.5 + 0.5 * sin(time * 3.0)
		_draw_facet(Vector2.ZERO, CORE_RADIUS, time * 0.2, 6, Color(SHIELD_COLOR, 0.10 + 0.05 * pulse))
		_draw_facet(Vector2.ZERO, CORE_RADIUS, time * 0.2, 6, Color(SHIELD_COLOR, 0.35 + 0.3 * pulse), false, 4.0)
	else:
		var pulse := 0.5 + 0.5 * sin(time * 7.0)  # uncovered: the core glows angrily
		_draw_facet(Vector2.ZERO, CORE_RADIUS * 0.6, -time * 0.3, 3, Color(CORE_COLOR, 0.25 + 0.2 * pulse))


## A flat sided crystal facet: `sides` corners at `r` from `at`, every other one
## pulled in so it reads as a shard rather than a disc. Filled, or an outline
## `width` thick; `glint` adds a bright edge along one face.
func _draw_facet(at: Vector2, r: float, turn: float, sides: int, c: Color, glint := false, width := 0.0) -> void:
	var pts := PackedVector2Array()
	for k in sides:
		var a := turn + TAU * k / sides
		pts.append(at + Vector2.from_angle(a) * (r if k % 2 == 0 or sides % 2 == 1 else r * 0.64))
	if width > 0.0:
		pts.append(pts[0])
		draw_polyline(pts, c, width)
		return
	draw_colored_polygon(pts, c)
	if glint:
		draw_line(pts[0], pts[1], Color(1, 1, 1, 0.5), 1.5)


## An arm's own hp bar, over its middle.
func _draw_bar(side: int, time: float) -> void:
	if arm_max <= 0:
		return
	var mid := shard_at(time, side, SHARDS / 2)
	var r := Rect2(mid + Vector2(-BAR_SIZE.x / 2.0, -BAR_LIFT - BAR_SIZE.y), BAR_SIZE)
	draw_rect(r.grow(1.0), Color(0, 0, 0, 0.6))
	var left := clampf(float(arm_hp[side]) / arm_max, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x * left, r.size.y)), ARM_COLOR)
