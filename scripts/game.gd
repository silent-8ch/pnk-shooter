extends Node2D
## Game world, lightly authoritative so joining players don't feel lag:
## - each peer flies its own ship (movement, firing, damage to itself) and
##   replicates its position/hp to the others;
## - bullets are local on every peer, created from one fire_bullet rpc; only the
##   shooter's copy reports hits, to the host;
## - enemies are announced by the host (spawn_enemy rpc) but move on every peer
##   from their deterministic patterns, with no per-frame sync;
## - the host still decides enemy damage/deaths, score, and who gets a pickup.
## Everything is created by rpc into each peer's own copy of the world (no
## MultiplayerSpawner, which would delete the host's nodes when it leaves); a
## late joiner gets a snapshot of the current players and enemies.
##
## Lighting: ship bodies sit on Ships.LIGHT_MASK. ShipShade (a SUB PointLight2D covering the
## arena, very high so it subtracts evenly) dims them to ~45%; bullet lights add color back.
## Not a DirectionalLight2D: the Compatibility renderer ignores its range_item_cull_mask and
## would darken everything. Not CanvasModulate either, for the same reason.

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const WreckScript := preload("res://scripts/wreck.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const LevelScript := preload("res://scripts/level.gd")
const PodScript := preload("res://scripts/escape_pod.gd")
const RESCUE_POINTS := 25  # per escape pod brought home
const SpriteEffect := preload("res://scripts/sprite_effect.gd")

const ARENA := Rect2(0, 0, 540, 960)
const GROUP_INTERVAL := 4.0  # seconds between random enemy groups (no level, or after it ends)
const PLAYER_COLORS: Array[Color] = [
	Color("5ad1ff"), Color("ff7ad9"), Color("8dff7a"), Color("ffd45a"),
	Color("c08dff"), Color("ff9c5a"), Color("7afff2"), Color("ffffff"),
]

@onready var players: Node2D = $Players
@onready var enemies: Node2D = $Enemies
@onready var bullets: Node2D = $Bullets
@onready var effects: Node2D = $Effects
@onready var pickups: Node2D = $Pickups
@onready var pods: Node2D = $Pods
@onready var shoot_sound: AudioStreamPlayer = $ShootSound
@onready var hit_sound: AudioStreamPlayer = $HitSound
@onready var score_label: Label = $HUD/ScoreLabel
@onready var hp_label: Label = $HUD/HPLabel
@onready var info_label: Label = $HUD/InfoLabel
@onready var hud: CanvasLayer = $HUD
@onready var pointer_controls: CanvasLayer = $PointerControls

var score := 0  # replicated by ScoreSync
var active := false
var input_enabled := true  # false while the pause menu is open
var _enemy_timer := 0.0
var level: RefCounted  # the level being played (see level.gd), or null for random waves
## Seconds into the level. Every peer runs this clock (joiners get it from the
## host) so a player left alone when the host quits carries on from the same spot.
var level_time := 0.0
var _player_count := 0
var _pickup_count := 0  # server: names pickups uniquely
var _pod_count := 0  # server: names escape pods uniquely
var _wreck_count := 0  # server: names wrecks uniquely (chain reactions name them)
var _enemy_count := 0  # server: names enemies uniquely (peers report hits by name)
## Peers that have the whole world (caught up after joining). Ships only send
## position updates to these, so a joiner never gets updates for nodes it lacks.
var ready_peers := {1: true}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	hud.visible = false
	pointer_controls.visible = false


func start() -> void:
	Ships.prewarm_enemy_parts()  # avoid a hitch on the first kill
	for ramp in WreckScript.FIRE_RAMPS:
		SpriteEffect.explosion_frames(ramp)  # recolor the painted explosion once per ramp
	PickupScript.warm()  # render the pickup's palette cycle up front
	level = LevelScript.load_file(LevelScript.first_level_path())
	level_time = 0.0
	_enemy_timer = 0.0
	active = true
	hud.visible = true
	pointer_controls.visible = true
	if multiplayer.is_server():
		score = 0
		info_label.text = "Hosting at %s" % Net.get_local_ip()
		_add_player(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))
	else:
		info_label.text = "Connected"
		register_player.rpc_id(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))


func stop() -> void:
	active = false
	input_enabled = true
	hud.visible = false
	pointer_controls.visible = false
	for group in [players, enemies, bullets, effects, pickups, pods]:
		for child in group.get_children():
			child.queue_free()
	score = 0
	_player_count = 0
	ready_peers = {1: true}


func _process(_delta: float) -> void:
	if not active or multiplayer.multiplayer_peer == null:
		return
	score_label.text = "Score %d" % score
	var me := local_player()
	hp_label.text = "HP %d" % me.hp if me else "HP -"


func _physics_process(delta: float) -> void:
	if not active or multiplayer.multiplayer_peer == null:
		return
	var from := level_time
	level_time += delta
	if not multiplayer.is_server():
		return
	if level and not level.finished(from):
		for e in level.events_between(from, level_time):
			spawn_group(e.type, LevelScript.center_x(e, ARENA.size.x), e.count, e.dir)
		return
	_enemy_timer += delta
	if _enemy_timer >= GROUP_INTERVAL:
		_enemy_timer = 0.0
		spawn_group(randi() % EnemyScript.TYPES.size())


# --- Players ---------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String, ship: int, palette: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has_node(str(id)):
		return
	# Catch the newcomer up on the world before announcing it to everyone.
	for p in players.get_children():
		add_player.rpc_id(id, p.spawn_data.merged({"pos": p.position}, true))
	for e in enemies.get_children():
		spawn_enemy.rpc_id(id, e.snapshot())
	set_ready_peers.rpc_id(id, ready_peers.keys())
	set_level_time.rpc_id(id, level_time)
	_add_player(id, pname, ship, palette)
	peer_ready.rpc(id)


@rpc("authority", "call_remote", "reliable")
func set_level_time(t: float) -> void:
	level_time = t


@rpc("authority", "call_local", "reliable")
func peer_ready(id: int) -> void:
	ready_peers[id] = true


@rpc("authority", "call_remote", "reliable")
func set_ready_peers(ids: Array) -> void:
	for id in ids:
		ready_peers[id] = true


func _peer_has_world(peer: int) -> bool:
	return ready_peers.has(peer)


## Host: picks a color and spot for a new player and announces it to every peer.
func _add_player(id: int, pname: String, ship: int, palette: int) -> void:
	var idx := _player_count
	_player_count += 1
	add_player.rpc({
		"id": id,
		"name": pname.left(12),
		"ship": Ships.clamp_index(ship),
		"palette": Ships.clamp_palette(palette),
		"color": PLAYER_COLORS[idx % PLAYER_COLORS.size()],
		"pos": Vector2(ARENA.size.x * (0.2 + 0.6 * fposmod(idx * 0.37, 1.0)), ARENA.size.y - 120),
	})


@rpc("authority", "call_local", "reliable")
func add_player(data: Dictionary) -> void:
	if players.has_node(str(data.id)):
		return
	var p := PlayerScene.instantiate()
	p.spawn_data = data
	p.name = str(data.id)
	p.peer_id = data.id
	p.player_name = data.name
	p.color = data.color
	p.ship = data.get("ship", 0)
	p.palette = data.get("palette", 0)
	p.position = data.pos
	p.spawn_position = data.pos
	p.set_multiplayer_authority(data.id)  # the owner flies it and replicates it
	p.get_node("Sync").add_visibility_filter(_peer_has_world)
	print("[peer %d] spawned player %s (%d)" % [multiplayer.get_unique_id(), data.name, data.id])
	players.add_child(p)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		remove_player.rpc(id)


@rpc("authority", "call_local", "reliable")
func remove_player(id: int) -> void:
	ready_peers.erase(id)
	var p := players.get_node_or_null(str(id))
	if p:
		p.queue_free()


# --- Enemies / bullets (server only callers) --------------------------------

## Server: sends in a group. Anything left out (center < 0, count 0, dir 0) is random.
func spawn_group(type: int, center := -1.0, count := 0, dir := 0.0) -> void:
	if count <= 0:
		count = EnemyScript.DIVER_GROUP
		if type == EnemyScript.WEAVER:
			count = randi_range(EnemyScript.WEAVER_GROUP_MIN, EnemyScript.WEAVER_GROUP_MAX)
	if center < 0.0:
		var margin := EnemyScript.group_half_width(type, count) + 20.0
		center = randf_range(margin, ARENA.size.x - margin)
	if dir == 0.0:
		dir = 1.0 if randf() < 0.5 else -1.0
	for pos in EnemyScript.group_layout(type, count, center):
		_enemy_count += 1
		spawn_enemy.rpc({"x": pos.x, "y": pos.y, "type": type, "group_x": center, "dir": dir,
			"id": _enemy_count})


## Every peer adds the enemy and flies it locally. `data` may carry a snapshot
## (time/pos, see Enemy.snapshot) for a player joining mid-flight.
@rpc("authority", "call_local", "reliable")
func spawn_enemy(data: Dictionary) -> void:
	var enemy_name := "Enemy%d" % data.get("id", 0)
	if enemies.has_node(enemy_name):
		return
	var e := EnemyScene.instantiate()
	e.name = enemy_name
	e.position = Vector2(data.x, data.get("y", EnemyScript.SPAWN_Y))
	e.type = data.get("type", EnemyScript.WEAVER)
	e.group_x = data.get("group_x", -1.0)
	e.zig_dir = data.get("dir", 1.0)
	enemies.add_child(e)
	if data.has("time"):
		e.restore(data.time, data.pos)


## Server: removes an enemy and has every peer play its wreck effect.
func destroy_enemy(enemy: Node2D, award_points: bool) -> void:
	if not multiplayer.is_server():
		return
	if award_points:
		add_score(enemy.points())
	_wreck_count += 1
	var wreck_name := "Wreck%d" % _wreck_count
	var pod_name := ""
	if award_points:  # shot down, not rammed: drop a pickup and launch a pod where it died
		_pickup_count += 1
		spawn_pickup.rpc(enemy.position, "Pickup%d" % _pickup_count)
		_pod_count += 1
		pod_name = "Pod%d" % _pod_count
	play_wreck.rpc(enemy.position, enemy.type, randi(), wreck_name, pod_name)
	if pod_name != "":
		spawn_pod.rpc(enemy.position, enemy.type, pod_name, wreck_name)
	remove_enemy.rpc(String(enemy.name))


@rpc("authority", "call_local", "reliable")
func remove_enemy(enemy_name: String) -> void:
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		e.queue_free()


@rpc("authority", "call_local", "reliable")
func play_wreck(pos: Vector2, type: int, fx_seed: int, wreck_name := "", pod_name := "") -> void:
	if wreck_name != "" and effects.has_node(wreck_name):
		return
	var ship: int = EnemyScript.TYPES[clampi(type, 0, EnemyScript.TYPES.size() - 1)].ship
	var tex := Ships.get_enemy_texture(ship)
	var wreck := WreckScript.new()
	if wreck_name != "":
		wreck.name = wreck_name
	wreck.pod_name = pod_name
	wreck.position = pos
	var parts := Ships.get_enemy_parts(ship, fx_seed)
	wreck.setup(tex, Ships.scale_for(tex, EnemyScript.HEIGHT), fx_seed, parts)
	effects.add_child(wreck)


## Server: a bullet damaged an enemy without destroying it; every peer hears the hit.
@rpc("authority", "call_local", "unreliable")
func play_hit() -> void:
	hit_sound.play()


## Every peer adds the same pickup under the same name, so the server can name it
## in collect_pickup.
@rpc("authority", "call_local", "reliable")
func spawn_pickup(pos: Vector2, pickup_name: String) -> void:
	var p := PickupScript.new()
	p.name = pickup_name
	p.position = pos
	pickups.add_child(p)


## Server: `peer` took the pickup; every peer plays its collect animation, and
## the taker's own ship banks the exp (see PowerMeter).
@rpc("authority", "call_local", "reliable")
func collect_pickup(pickup_name: String, peer: int) -> void:
	var p := pickups.get_node_or_null(pickup_name)
	if p:
		p.collect()
	var me := local_player()
	if me and peer == multiplayer.get_unique_id():
		me.add_exp()


## This device's own ship, if it has one.
func local_player() -> Node:
	if multiplayer.multiplayer_peer == null:
		return null
	return players.get_node_or_null(str(multiplayer.get_unique_id()))


## Owner: fires a shot; every peer creates its own copy of the bullet.
## `dir` for aimed shots; `kind` is a BulletScript kind (laser, missile, vulcan).
func spawn_bullet(pos: Vector2, color: Color, dir := Vector2.UP, kind := 0) -> void:
	fire_bullet.rpc(pos, color, dir, kind)


@rpc("any_peer", "call_local", "reliable")
func fire_bullet(pos: Vector2, color: Color, dir := Vector2.UP, kind := 0) -> void:
	var b := BulletScene.instantiate()
	b.position = pos
	b.color = color
	b.direction = dir.normalized() if dir != Vector2.ZERO else Vector2.UP
	b.kind = kind
	b.shooter = _sender()
	bullets.add_child(b)
	if b.kind != b.VULCAN:  # a vulcan's stream of rounds would drown everything out
		shoot_sound.play()  # every peer hears every shot


## Peer that sent the rpc being handled (ourselves for a local call).
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


## Shooter -> host: its bullet hit `enemy_name` for `damage` (a laser is 1).
@rpc("any_peer", "call_local", "reliable")
func report_hit(enemy_name: String, damage := 1.0) -> void:
	if not multiplayer.is_server():
		return
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		e.take_damage(clampf(damage, 0.0, 1.0))


## Ship owner -> host: it rammed `enemy_name`.
@rpc("any_peer", "call_local", "reliable")
func report_ram(enemy_name: String) -> void:
	if not multiplayer.is_server():
		return
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		e.ram()


## Every peer launches the same escape pod under the same name.
@rpc("authority", "call_local", "reliable")
func spawn_pod(pos: Vector2, type: int, pod_name: String, from_wreck := "") -> void:
	if pods.has_node(pod_name):
		return
	var p := PodScript.new()
	p.name = pod_name
	p.position = pos
	p.type = type
	p.from_wreck = from_wreck
	pods.add_child(p)


# --- Chain reactions ----------------------------------------------------------

const SHIP_RADIUS := 14.0  # player and enemy reach, for wreck collisions


## Every peer, each frame a wreck veers: it blows up on touching a ship or pod.
## Players: every peer sees the touch, only the owner takes the damage. Enemies
## and pods: the host decides (they're destroyed, and it tells everyone to blow
## the wreck up).
func wreck_moved(w: Node2D) -> void:
	var at: Vector2 = w.hull_position()
	var reach: float = w.reach()
	for p in players.get_children():
		if p.is_alive() and p.position.distance_to(at) < reach + SHIP_RADIUS:
			if p.is_local():
				p.take_damage(1, at.y > p.position.y)
			w.explode()
			return
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	for e in enemies.get_children():
		if not e.is_queued_for_deletion() and e.position.distance_to(at) < reach + SHIP_RADIUS:
			destroy_enemy(e, true)
			explode_wreck.rpc(String(w.name))
			return
	for pod in pods.get_children():
		if not pod.taken and pod.from_wreck != String(w.name) and pod.position.distance_to(at) < reach + pod.RADIUS:
			destroy_pod.rpc(String(pod.name))
			explode_wreck.rpc(String(w.name))
			return


@rpc("authority", "call_local", "reliable")
func explode_wreck(wreck_name: String) -> void:
	var w := effects.get_node_or_null(wreck_name)
	if w:
		w.explode()


## Every peer, when something explodes at `at`: the local ship takes a hit if
## it's inside; the host destroys enemies and pods inside (chain reaction).
## `spare_pod`: a wreck's own escape pod, which its blast doesn't take.
func blast(at: Vector2, radius: float, spare_pod := "") -> void:
	var me := local_player()
	if me and me.is_alive() and me.position.distance_to(at) < radius + SHIP_RADIUS:
		me.take_damage(1, at.y > me.position.y)
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	for e in enemies.get_children():
		if not e.is_queued_for_deletion() and e.position.distance_to(at) < radius + SHIP_RADIUS:
			destroy_enemy(e, true)
	for pod in pods.get_children():
		if not pod.taken and String(pod.name) != spare_pod and pod.position.distance_to(at) < radius + pod.RADIUS:
			destroy_pod.rpc(String(pod.name))


## Shooter -> host: its bullet hit `pod_name`.
@rpc("any_peer", "call_local", "reliable")
func report_pod_hit(pod_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := pods.get_node_or_null(pod_name)
	if p and not p.taken:
		destroy_pod.rpc(pod_name)


## Every peer: the pod blows up with a very small explosion, which can chain.
@rpc("authority", "call_local", "reliable")
func destroy_pod(pod_name: String) -> void:
	var p := pods.get_node_or_null(pod_name)
	if p == null or p.taken:
		return
	p.taken = true
	pods.remove_child(p)
	p.burst(effects)
	blast(p.position, p.BLAST_RADIUS)
	p.queue_free()


## Drone owner -> host: its drone reached a pod; the first claim wins.
@rpc("any_peer", "call_local", "reliable")
func request_rescue(pod_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := pods.get_node_or_null(pod_name)
	if p and not p.taken:
		p.taken = true
		rescue_pod.rpc(pod_name, _sender())


## Server: `peer`'s drone has the pod; it leaves the field everywhere.
@rpc("authority", "call_local", "reliable")
func rescue_pod(pod_name: String, peer: int) -> void:
	var p := pods.get_node_or_null(pod_name)
	if p:
		pods.remove_child(p)
		p.queue_free()
	var me := local_player()
	if me and peer == multiplayer.get_unique_id():
		me.drone_picked_up()


## Drone owner -> host: it brought `count` pods home.
@rpc("any_peer", "call_local", "reliable")
func report_rescue(count: int) -> void:
	if multiplayer.is_server():
		add_score(RESCUE_POINTS * clampi(count, 0, 10))


## Ship owner -> host: it touched a pickup; the first claim wins.
@rpc("any_peer", "call_local", "reliable")
func request_pickup(pickup_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := pickups.get_node_or_null(pickup_name)
	if p and not p.collected:
		collect_pickup.rpc(pickup_name, _sender())


## The host left and we're now offline as peer 1 (see Net): drop the other
## players, take over our ship and bullets as peer 1, and become the host of
## this copy of the world, so enemies keep coming and the score carries on.
func continue_solo(old_id: int) -> void:
	var me_id := multiplayer.get_unique_id()
	for p in players.get_children():
		if p.peer_id != old_id:
			players.remove_child(p)  # now, so its name (often "1") is free for us
			p.queue_free()
			continue
		p.peer_id = me_id
		p.name = str(me_id)
		p.set_multiplayer_authority(me_id)
	for b in bullets.get_children():
		b.shooter = me_id if b.shooter == old_id else -1  # others' shots stay cosmetic
	_enemy_count = maxi(_enemy_count, _max_suffix(enemies, "Enemy"))
	_pickup_count = maxi(_pickup_count, _max_suffix(pickups, "Pickup"))
	_pod_count = maxi(_pod_count, _max_suffix(pods, "Pod"))
	_wreck_count = maxi(_wreck_count, _max_suffix(effects, "Wreck"))
	info_label.text = "Host left - playing solo"


## Highest N among children named <prefix>N, so new names don't collide.
static func _max_suffix(parent: Node, prefix: String) -> int:
	var n := 0
	for c in parent.get_children():
		var s := String(c.name)
		if s.begins_with(prefix) and s.substr(prefix.length()).is_valid_int():
			n = maxi(n, s.substr(prefix.length()).to_int())
	return n


func add_score(points: int) -> void:
	if multiplayer.is_server():
		score += points
