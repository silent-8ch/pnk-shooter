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
const RepairScript := preload("res://scripts/repair_kit.gd")
const ObstacleScript := preload("res://scripts/obstacle.gd")
const OBSTACLE_INTERVAL := 6.0  # seconds between random obstacles (no level, or after it ends)
const OBSTACLE_POINTS := 5  # per hp of a destructible obstacle shot apart
const CLUSTER_SPREAD := Vector2(70, 60)  # random offsets of a cluster's copies
const BUDDY_ID := 2147483000  # peer id of the host's AI buddy (ENet ids are random, far apart)
const RESCUE_POINTS := 25  # per rescued pod turned in at a station
const StationScript := preload("res://scripts/station.gd")
const PlayerScript := preload("res://scripts/player.gd")
const STATION_INTERVAL := 30.0  # s between rescue stations (always, level or not)
const STATION_EDGE := 90.0  # stations enter at least this far from the sides
const SpriteEffect := preload("res://scripts/sprite_effect.gd")

const ARENA := Rect2(0, 0, 540, 960)
const BOSS_KILLS := 30  # kills before the first boss ...
const BOSS_KILLS_STEP := 10  # ... and this many more each stage
const BOSS_ADD_INTERVAL := 8.0  # s between small groups during a boss fight
const BOSS_ADD_TYPES: Array[int] = [EnemyScript.WEAVER, EnemyScript.DIVER]
const START_SPARES := 4  # spare ships a run starts with, shared by everyone
const GAME_OVER_GRACE := 1.5  # s with nobody alive and no spares before the run ends
const RESULTS_TIME := 4.0  # s the results stay up before the run starts over
const BOSS_PICKUPS := 6  # pickups a boss bursts into
const BOSS_SHOT_COLOR := Color("ff4d6d")
const BANNER_TIME := 2.5  # s a stage banner stays up
const GROUP_INTERVAL := 6.0  # seconds between random enemy groups (no level, or after it ends)
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
@onready var obstacles: Node2D = $Obstacles
@onready var stations: Node2D = $Stations
@onready var shoot_sound: AudioStreamPlayer = $ShootSound
@onready var hit_sound: AudioStreamPlayer = $HitSound
@onready var score_label: Label = $HUD/ScoreLabel
@onready var info_label: Label = $HUD/InfoLabel
@onready var hud: CanvasLayer = $HUD
@onready var pointer_controls: CanvasLayer = $PointerControls

var score := 0  # replicated by ScoreSync
var stage := 0  # replicated by ScoreSync: bosses beaten; enemies sent in get tougher with it
var spares := START_SPARES  # replicated by ScoreSync: spare ships left; a dead ship needs one to come back
var kills := 0  # replicated by ScoreSync: enemies shot down toward the next boss
var over := false  # the run ended; the results are up
var _boss_add_timer := 0.0
var _over_timer := 0.0  # server: s with nobody alive and no spares
var _results_left := 0.0
var _run_players: Array = []  # server: names of everyone who flew this run, for the high scores

signal run_ended  # the results were up for RESULTS_TIME; the host starts the next run
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
var _obstacle_timer := 0.0
var _station_timer := 0.0
var _station_count := 0  # server: names stations uniquely
var _obstacle_count := 0  # server: names obstacles uniquely
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
	_station_timer = 0.0
	_boss_add_timer = 0.0
	_over_timer = 0.0
	over = false
	active = true
	hud.visible = true
	pointer_controls.visible = true
	if multiplayer.is_server():
		score = 0
		stage = 0
		kills = 0
		spares = START_SPARES
		_run_players = []
		info_label.text = "Hosting at %s" % Net.get_local_ip()
		_add_player(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))
		if Net.ai_buddy:
			_add_buddy()
	else:
		info_label.text = "Connected"
		register_player.rpc_id(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))


func stop() -> void:
	active = false
	input_enabled = true
	hud.visible = false
	pointer_controls.visible = false
	for group in [players, enemies, bullets, effects, pickups, pods, obstacles, stations]:
		for child in group.get_children():
			group.remove_child(child)  # now, so a restarted run can reuse the names
			child.queue_free()
	for b in get_tree().get_nodes_in_group("banner"):
		b.queue_free()
	score = 0
	stage = 0
	kills = 0
	spares = START_SPARES
	over = false
	_player_count = 0
	ready_peers = {1: true}


func _process(delta: float) -> void:
	if not active or multiplayer.multiplayer_peer == null:
		return
	score_label.text = "Score %d    Stage %d    Ships %d" % [score, stage + 1, spares]
	var bar: ProgressBar = hud.get_node_or_null("BossBar")
	if bar:
		bar.value = 1.0 if boss_alive() else float(kills) / boss_kills_needed()
	if over:
		_results_left -= delta
		if _results_left <= 0.0:
			over = false
			run_ended.emit()


func _physics_process(delta: float) -> void:
	if not active or multiplayer.multiplayer_peer == null or over:
		return
	var from := level_time
	var boss_up := boss_alive()
	if not boss_up:
		level_time += delta  # the level holds its place while a boss is up
	if not multiplayer.is_server():
		return
	_check_game_over(delta)
	_station_timer += delta
	if _station_timer >= STATION_INTERVAL:
		_station_timer = 0.0
		_station_count += 1
		spawn_station.rpc(Vector2(randf_range(STATION_EDGE, ARENA.size.x - STATION_EDGE), -StationScript.OFFSCREEN), "Station%d" % _station_count)
	if boss_up:  # small groups keep coming so everyone can still earn exp
		_boss_add_timer += delta
		if _boss_add_timer >= BOSS_ADD_INTERVAL:
			_boss_add_timer = 0.0
			spawn_group(BOSS_ADD_TYPES[randi() % BOSS_ADD_TYPES.size()])
		return
	_boss_add_timer = 0.0
	if kills >= boss_kills_needed():
		kills = 0
		spawn_boss()
		return
	if level and not level.finished(from):
		for e in level.events_between(from, level_time):
			if e.has("piece"):
				spawn_obstacles(e.piece, ObstacleScript.center_x(e.piece, e.count, e.lane, ARENA.size.x), e.count, e.dir)
			else:
				spawn_group(e.type, LevelScript.center_x(e, ARENA.size.x), e.count, e.dir)
		return
	_enemy_timer += delta
	if _enemy_timer >= GROUP_INTERVAL:
		_enemy_timer = 0.0
		spawn_group(randi() % EnemyScript.WAVE_TYPES)
	_obstacle_timer += delta
	if _obstacle_timer >= OBSTACLE_INTERVAL:
		_obstacle_timer = 0.0
		_spawn_random_obstacle()


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
	for o in obstacles.get_children():
		if not o.is_queued_for_deletion():
			spawn_obstacle.rpc_id(id, {"name": String(o.name), "piece": o.piece_id, "x": o.position.x,
				"y": o.position.y, "count": o.count, "dir": -1.0 if o.mirror else 1.0})
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
## `ai`: the host's AI buddy (BUDDY_ID), flown by the host.
func _add_player(id: int, pname: String, ship: int, palette: int, ai := false) -> void:
	var idx := _player_count
	_player_count += 1
	var data := {
		"id": id,
		"name": pname.left(12),
		"ship": Ships.clamp_index(ship),
		"palette": Ships.clamp_palette(palette),
		"color": PLAYER_COLORS[idx % PLAYER_COLORS.size()],
		"pos": Vector2(ARENA.size.x * (0.2 + 0.6 * fposmod(idx * 0.37, 1.0)), ARENA.size.y - 120),
	}
	if ai:
		data.ai = true
		data.owner = 1
	if not _run_players.has(data.name):
		_run_players.append(data.name)
	add_player.rpc(data)


## Host: adds an AI wingman in a different ship from the host's.
func _add_buddy() -> void:
	var ship := (Ships.selected + 1) % Ships.LIST.size()
	_add_player(BUDDY_ID, "Buddy", ship, Ships.palette_for(ship), true)


## True if this peer flies the ship `peer` (its own, or the host's AI buddy).
func controls(peer: int) -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	if peer == multiplayer.get_unique_id():
		return true
	var p := players.get_node_or_null(str(peer))
	return p != null and p.ai and p.get_multiplayer_authority() == multiplayer.get_unique_id()


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
	p.ai = data.get("ai", false)
	p.set_multiplayer_authority(data.get("owner", data.id))  # the owner flies it and replicates it
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
		var group: Array = EnemyScript.TYPES[type].group
		count = randi_range(group[0], group[1])
	if center < 0.0:
		var margin := EnemyScript.group_half_width(type, count) + 20.0
		center = randf_range(margin, ARENA.size.x - margin)
	if dir == 0.0:
		dir = 1.0 if randf() < 0.5 else -1.0
	for pos in EnemyScript.group_layout(type, count, center):
		_enemy_count += 1
		spawn_enemy.rpc({"x": pos.x, "y": pos.y, "type": type, "group_x": center, "dir": dir,
			"id": _enemy_count, "stage": stage})


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
	e.stage = data.get("stage", 0)
	enemies.add_child(e)
	if data.has("time"):
		e.restore(data.time, data.pos)


## Kills that bring in the next boss.
func boss_kills_needed() -> int:
	return BOSS_KILLS + BOSS_KILLS_STEP * stage


## Is a boss on the field? (Every peer has the same enemies.)
func boss_alive() -> bool:
	for e in enemies.get_children():
		if e.is_boss() and not e.is_queued_for_deletion():
			return true
	return false


## Server: sends in a boss, as tough as the current stage.
func spawn_boss() -> void:
	_enemy_count += 1
	spawn_enemy.rpc({"x": ARENA.size.x / 2.0, "y": EnemyScript.SPAWN_Y - 60.0, "type": EnemyScript.BOSS,
		"id": _enemy_count, "stage": stage})
	show_banner.rpc("WARNING\nBoss approaching")


## Host -> everyone: render the new stage's enemy colors now, not on the first spawn.
@rpc("authority", "call_local", "reliable")
func warm_stage(new_stage: int) -> void:
	Ships.prewarm_enemy_parts(new_stage)


## Host -> everyone: the boss took a hit; its bar shows the host's hp.
@rpc("authority", "call_local", "unreliable")
func boss_hp(enemy_name: String, hp: int) -> void:
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		e.shown_hp = hp


## Host -> everyone: a boss's bullet, aimed along `dir`.
@rpc("authority", "call_local", "reliable")
func fire_enemy_bullet(pos: Vector2, dir: Vector2) -> void:
	var b := BulletScene.instantiate()
	b.position = pos
	b.color = BOSS_SHOT_COLOR
	b.direction = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	b.kind = b.ENEMY_SHOT
	b.shooter = b.ENEMY_SHOOTER
	bullets.add_child(b)


## Host -> everyone: a big message across the middle of the screen for a moment.
@rpc("authority", "call_local", "reliable")
func show_banner(text: String, time := BANNER_TIME) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color("ffd45a"))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.add_to_group("banner")
	hud.add_child(label)
	var tw := label.create_tween()
	tw.tween_interval(time)
	tw.tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)


## Server: removes an enemy and has every peer play its wreck effect.
func destroy_enemy(enemy: Node2D, award_points: bool) -> void:
	if not multiplayer.is_server():
		return
	if award_points:
		add_score(enemy.points())
		if not enemy.is_boss() and not boss_alive():
			kills += 1  # shooting the boss's escorts doesn't bring the next one sooner
	_wreck_count += 1
	var wreck_name := "Wreck%d" % _wreck_count
	var pod_name := ""
	if award_points:  # shot down, not rammed: drop a pickup (a boss: a ring of them) and launch a pod where it died
		for i in (BOSS_PICKUPS if enemy.is_boss() else 1):
			_pickup_count += 1
			var at: Vector2 = enemy.position + (Vector2.from_angle(TAU * i / BOSS_PICKUPS) * 50.0 if enemy.is_boss() else Vector2.ZERO)
			spawn_pickup.rpc(at, "Pickup%d" % _pickup_count)
		_pod_count += 1
		pod_name = "Pod%d" % _pod_count
	play_wreck.rpc(enemy.position, enemy.type, randi(), wreck_name, pod_name, enemy.stage)
	if pod_name != "":
		spawn_pod.rpc(enemy.position, enemy.type, pod_name, wreck_name)
	remove_enemy.rpc(String(enemy.name))
	if enemy.is_boss():
		stage += 1
		kills = 0
		show_banner.rpc("STAGE %d\nEnemies grow stronger" % (stage + 1))
		warm_stage.rpc(stage)


@rpc("authority", "call_local", "reliable")
func remove_enemy(enemy_name: String) -> void:
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		e.queue_free()


@rpc("authority", "call_local", "reliable")
func play_wreck(pos: Vector2, type: int, fx_seed: int, wreck_name := "", pod_name := "", stage_of := 0) -> void:
	if wreck_name != "" and effects.has_node(wreck_name):
		return
	var ship: int = EnemyScript.TYPES[clampi(type, 0, EnemyScript.TYPES.size() - 1)].ship
	var tex := Ships.get_enemy_texture(ship, stage_of)
	var wreck := WreckScript.new()
	if wreck_name != "":
		wreck.name = wreck_name
	wreck.pod_name = pod_name
	wreck.position = pos
	var parts := Ships.get_enemy_parts(ship, fx_seed, stage_of)
	var height: float = EnemyScript.TYPES[clampi(type, 0, EnemyScript.TYPES.size() - 1)].get("height", EnemyScript.HEIGHT)
	wreck.setup(tex, Ships.scale_for(tex, height), fx_seed, parts)
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
## `by`: the ship firing, if not the sender's own (the host's AI buddy).
func spawn_bullet(pos: Vector2, color: Color, dir := Vector2.UP, kind := 0, by := 0) -> void:
	fire_bullet.rpc(pos, color, dir, kind, by)


@rpc("any_peer", "call_local", "reliable")
func fire_bullet(pos: Vector2, color: Color, dir := Vector2.UP, kind := 0, by := 0) -> void:
	var b := BulletScene.instantiate()
	b.position = pos
	b.color = color
	b.direction = dir.normalized() if dir != Vector2.ZERO else Vector2.UP
	b.kind = kind
	b.shooter = _sender()
	if by != 0 and by != b.shooter:  # only for a ship the sender flies
		var p := players.get_node_or_null(str(by))
		if p and p.ai and p.get_multiplayer_authority() == b.shooter:
			b.shooter = by
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


# --- Obstacles ------------------------------------------------------------------

## Server: sends in an obstacle event: a tile piece as one run of `count`
## segments, anything else as a loose cluster of `count` copies.
func spawn_obstacles(piece: String, center: float, count: int, dir := 1.0) -> void:
	if not ObstacleScript.placeable(piece):
		return
	var y := ObstacleScript.spawn_y(piece)
	if ObstacleScript.piece(piece).tile or count <= 1:
		_announce_obstacle(piece, Vector2(center, y), count, dir)
		return
	for i in count:
		var off := Vector2(randf_range(-1, 1) * CLUSTER_SPREAD.x, -randf() * CLUSTER_SPREAD.y * i)
		_announce_obstacle(piece, Vector2(center, y) + off, 1, dir)


func _announce_obstacle(piece: String, pos: Vector2, count: int, dir: float) -> void:
	_obstacle_count += 1
	spawn_obstacle.rpc({"name": "Obstacle%d" % _obstacle_count, "piece": piece, "x": pos.x, "y": pos.y,
		"count": count, "dir": dir})


func _spawn_random_obstacle() -> void:
	var ids := ObstacleScript.catalog().keys().filter(func(id): return ObstacleScript.placeable(id))
	if ids.is_empty():
		return
	var piece: String = ids[randi() % ids.size()]
	var count := randi_range(2, 5) if ObstacleScript.piece(piece).tile else randi_range(1, 3)
	spawn_obstacles(piece, ObstacleScript.center_x(piece, count, randi() % ObstacleScript.LANES, ARENA.size.x),
		count, 1.0 if randf() < 0.5 else -1.0)


## Every peer adds the obstacle and scrolls it locally.
@rpc("authority", "call_local", "reliable")
func spawn_obstacle(data: Dictionary) -> void:
	var obstacle_name := str(data.get("name", ""))
	if not obstacle_name.begins_with("Obstacle") or obstacles.has_node(obstacle_name):
		return
	if not ObstacleScript.placeable(str(data.get("piece", ""))):
		return
	var o := ObstacleScript.new()
	o.name = obstacle_name
	o.piece_id = data.piece
	o.count = clampi(int(data.get("count", 1)), 1, LevelScript.MAX_COUNT)
	o.mirror = float(data.get("dir", 1.0)) < 0.0
	o.position = Vector2(data.get("x", 0.0), data.get("y", 0.0))
	obstacles.add_child(o)


## Pushes a ship (circle at `at`, radius `r`) out of every obstacle it touches.
## Returns {pos, touching}; `below`: the obstacle pushing it sits below it.
func resolve_obstacles(at: Vector2, r: float) -> Dictionary:
	var out := {"pos": at, "touching": false, "below": false}
	for o in obstacles.get_children():
		if o.is_queued_for_deletion():
			continue
		var moved: Vector2 = o.push_out(out.pos, r)
		if moved.distance_to(out.pos) > 0.01:
			out.touching = true
			out.below = moved.y < out.pos.y
			out.pos = moved
	return out


func overlaps_obstacle(at: Vector2, r: float) -> bool:
	for o in obstacles.get_children():
		if not o.is_queued_for_deletion() and o.touches(at, r):
			return true
	return false


## Shooter -> host: its bullet hit a destructible obstacle.
@rpc("any_peer", "call_local", "reliable")
func report_obstacle_hit(obstacle_name: String, damage := 1.0) -> void:
	if not multiplayer.is_server():
		return
	var o := obstacles.get_node_or_null(obstacle_name)
	if o == null or o.is_queued_for_deletion() or not o.destructible():
		return
	o.hp -= clampf(damage, 0.0, 1.0)
	if o.hp > 0.0001:
		play_hit.rpc()
		flash_obstacle.rpc(obstacle_name)
		return
	add_score(int(ObstacleScript.piece(o.piece_id).hp) * OBSTACLE_POINTS)
	destroy_obstacle.rpc(obstacle_name)


@rpc("authority", "call_local", "unreliable")
func flash_obstacle(obstacle_name: String) -> void:
	var o := obstacles.get_node_or_null(obstacle_name)
	if o:
		o.flash()


@rpc("authority", "call_local", "reliable")
func destroy_obstacle(obstacle_name: String) -> void:
	var o := obstacles.get_node_or_null(obstacle_name)
	if o == null:
		return
	_detach(obstacles, o)
	o.burst(effects)
	o.queue_free()


# --- Chain reactions ----------------------------------------------------------

const SHIP_RADIUS := 14.0  # player and enemy reach, for wreck collisions


const BLAST_DAMAGE := 1.0  # to a player's escape pod


## Every peer, each frame a wreck veers: it blows up on touching a player or a
## pod (other enemy ships it passes through), and the blast does the damage.
## Players: every peer sees the touch. Pods: the host decides and tells everyone
## to blow the wreck up.
func wreck_moved(w: Node2D) -> void:
	var at: Vector2 = w.hull_position()
	var reach: float = w.reach()
	for p in players.get_children():
		if p.is_alive() and p.position.distance_to(at) < reach + SHIP_RADIUS:
			w.explode()
			return
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	for pod in pods.get_children():
		if not pod.taken and pod.from_wreck != String(w.name) and pod.position.distance_to(at) < reach + pod.RADIUS:
			explode_wreck.rpc(String(w.name))
			return


@rpc("authority", "call_local", "reliable")
func explode_wreck(wreck_name: String) -> void:
	var w := effects.get_node_or_null(wreck_name)
	if w:
		w.explode()


## Every peer, when something explodes at `at`: the local ship takes a hit if
## it's inside; the host damages pods inside (a pod's own blast can chain to
## the next). Enemy ships aren't hurt by blasts.
## `spare_pod`: a wreck's own escape pod, which its blast doesn't take.
func blast(at: Vector2, radius: float, spare_pod := "") -> void:
	var me := local_player()
	if me and me.is_alive() and me.position.distance_to(at) < radius + SHIP_RADIUS:
		me.take_damage(1, at.y > me.position.y)
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	for pod in pods.get_children():
		if not pod.taken and String(pod.name) != spare_pod and pod.position.distance_to(at) < radius + pod.RADIUS:
			damage_pod(pod, BLAST_DAMAGE)


## Shooter -> host: its bullet hit `pod_name` for `damage`.
@rpc("any_peer", "call_local", "reliable")
func report_pod_hit(pod_name: String, damage := 1.0) -> void:
	if not multiplayer.is_server():
		return
	var p := pods.get_node_or_null(pod_name)
	if p and not p.taken:
		damage_pod(p, clampf(damage, 0.0, 1.0))


## Host: an enemy's pod goes at once; a player's pod wears down first.
func damage_pod(pod: Node, amount: float) -> void:
	if pod.taken:
		return
	if pod.is_player_pod():
		pod.hp -= amount
		if pod.hp > 0.0001:
			play_hit.rpc()
			flash_pod.rpc(String(pod.name))
			return
	destroy_pod.rpc(String(pod.name))


@rpc("authority", "call_local", "unreliable")
func flash_pod(pod_name: String) -> void:
	var p := pods.get_node_or_null(pod_name)
	if p:
		p.flash()


## Every peer: the pod blows up with a very small explosion, which can chain.
@rpc("authority", "call_local", "reliable")
func destroy_pod(pod_name: String) -> void:
	var p := pods.get_node_or_null(pod_name)
	if p == null or p.taken:
		return
	p.taken = true
	var me := local_player()
	if me and p.owner_peer == multiplayer.get_unique_id():
		me.forget_pod(pod_name)
	_detach(pods, p)
	p.burst(effects)
	blast(p.position, p.BLAST_RADIUS)
	p.queue_free()


## Drone or ship owner -> host: its drone reached a pod, or (`by_drone` false)
## its ship touched a player's pod; the first claim wins.
@rpc("any_peer", "call_local", "reliable")
func request_rescue(pod_name: String, by_drone := true) -> void:
	if not multiplayer.is_server():
		return
	var p := pods.get_node_or_null(pod_name)
	if p and not p.taken and (by_drone or p.is_player_pod()):
		p.taken = true
		rescue_pod.rpc(pod_name, _sender(), by_drone, p.owner_peer)


## Server: `peer` saved the pod; it leaves the field everywhere. A drone counts
## it toward its haul; a player's pod gives its owner their upgrades back.
@rpc("authority", "call_local", "reliable")
func rescue_pod(pod_name: String, peer: int, by_drone := true, pod_owner := 0) -> void:
	var p := pods.get_node_or_null(pod_name)
	if p:
		_detach(pods, p)
		p.queue_free()
	var me := local_player()
	if me == null:
		return
	if by_drone and peer == multiplayer.get_unique_id():
		me.drone_picked_up(pod_name)
	if pod_owner != 0 and pod_owner == multiplayer.get_unique_id():
		me.recover_upgrades(pod_name)


## Ship owner, as its ship is destroyed: every peer launches its escape pod.
## Named by the owner ("PlayerPod<peer>_<n>"), so no host round trip is needed.
@rpc("any_peer", "call_local", "reliable")
func spawn_player_pod(pos: Vector2, pod_name: String, beacon: Color, ship: int, palette: int) -> void:
	var owner_id := _sender()
	if not pod_name.begins_with("PlayerPod%d_" % owner_id) or pods.has_node(pod_name):
		return
	var p := PodScript.new()
	p.name = pod_name
	p.position = pos
	p.owner_peer = owner_id
	p.beacon_color = beacon
	p.ship = Ships.clamp_index(ship)
	p.palette = Ships.clamp_palette(palette)
	pods.add_child(p)


## Takes `child` out of `parent` now (so its name is free), or at the end of
## the physics step when called from a collision callback, where removing a
## CollisionObject isn't allowed.
static func _detach(parent: Node, child: Node) -> void:
	if Engine.is_in_physics_frame():
		parent.remove_child.call_deferred(child)
	else:
		parent.remove_child(child)


# --- Repair kits ----------------------------------------------------------------

## Dropper: every peer adds its repair kit (named "Repair<peer>_<n>" by the dropper).
@rpc("any_peer", "call_local", "reliable")
func spawn_repair(pos: Vector2, kit_name: String, ship: int, palette: int) -> void:
	if not kit_name.begins_with("Repair%d_" % _sender()) or pickups.has_node(kit_name):
		return
	var k := RepairScript.new()
	k.name = kit_name
	k.position = pos
	k.ship = Ships.clamp_index(ship)
	k.palette = Ships.clamp_palette(palette)
	pickups.add_child(k)


## Ship owner -> host: it touched a repair kit; the first claim wins.
@rpc("any_peer", "call_local", "reliable")
func request_repair(kit_name: String) -> void:
	if not multiplayer.is_server():
		return
	var k := pickups.get_node_or_null(kit_name)
	if k and k.is_in_group("repair_kit") and not k.taken:
		k.taken = true
		take_repair.rpc(kit_name, _sender())


## Server: `peer` took the kit; it's gone everywhere and their ship heals.
@rpc("authority", "call_local", "reliable")
func take_repair(kit_name: String, peer: int) -> void:
	var k := pickups.get_node_or_null(kit_name)
	if k:
		_detach(pickups, k)
		k.queue_free()
	var me := local_player()
	if me and peer == multiplayer.get_unique_id():
		me.heal(RepairScript.HEAL)


## Ship owner -> a TANK's owner: the tank takes `amount` of a shipmate's hit.
@rpc("any_peer", "call_local", "reliable")
func cover_hit(tank_name: String, amount: float, from_behind: bool) -> void:
	var p := players.get_node_or_null(tank_name)
	if p and controls(int(tank_name)):
		p.take_damage(clampf(amount, 0.0, 5.0), from_behind, true)


## Host -> everyone: a rescue station drifts in.
@rpc("authority", "call_local", "reliable")
func spawn_station(pos: Vector2, station_name: String) -> void:
	if stations.has_node(station_name):
		return
	var st := StationScript.new()
	st.name = station_name
	st.position = pos
	stations.add_child(st)


## Ship owner -> everyone: its tail of rescued pods (enemy `types`, flying from
## `from`) piles into the station. The owner already counted the exp; the host
## scores RESCUE_POINTS each.
@rpc("any_peer", "call_local", "reliable")
func dock_tail(station_name: String, from: Array, types: Array) -> void:
	var st := stations.get_node_or_null(station_name)
	if st:
		st.receive(from, types)
	if multiplayer.is_server():
		add_score(RESCUE_POINTS * clampi(types.size(), 0, PlayerScript.TAIL_MAX))


## Ship owner -> host: it touched a pickup; the first claim wins.
@rpc("any_peer", "call_local", "reliable")
func request_pickup(pickup_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := pickups.get_node_or_null(pickup_name)
	if p is PickupScript and not p.collected:
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
	for pod in pods.get_children():
		if pod.owner_peer == old_id:
			pod.owner_peer = me_id
	_enemy_count = maxi(_enemy_count, _max_suffix(enemies, "Enemy"))
	_pickup_count = maxi(_pickup_count, _max_suffix(pickups, "Pickup"))
	_pod_count = maxi(_pod_count, _max_suffix(pods, "Pod"))
	_wreck_count = maxi(_wreck_count, _max_suffix(effects, "Wreck"))
	_obstacle_count = maxi(_obstacle_count, _max_suffix(obstacles, "Obstacle"))
	info_label.text = "Host left - playing solo"


## Highest N among children named <prefix>N, so new names don't collide.
static func _max_suffix(parent: Node, prefix: String) -> int:
	var n := 0
	for c in parent.get_children():
		var s := String(c.name)
		if s.begins_with(prefix) and s.substr(prefix.length()).is_valid_int():
			n = maxi(n, s.substr(prefix.length()).to_int())
	return n


# --- Spare ships and the end of a run --------------------------------------------

## Ship owner -> host: our ship `ship_name` is ready to come back; it takes a
## spare ship if there's one left.
@rpc("any_peer", "call_local", "reliable")
func request_spare(ship_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := players.get_node_or_null(ship_name)
	if p == null or over:
		return
	var ok := spares > 0
	if ok:
		spares -= 1
	grant_spare.rpc_id(_sender(), ship_name, ok)


## Host -> ship owner: the spare ship request was answered.
@rpc("authority", "call_local", "reliable")
func grant_spare(ship_name: String, ok: bool) -> void:
	var p := players.get_node_or_null(ship_name)
	if p and p.is_local():
		p.spare_answered(ok)


## Buyer -> host: someone bought a spare ship (+SHIP) for everyone.
@rpc("any_peer", "call_local", "reliable")
func add_spare() -> void:
	if multiplayer.is_server() and not over:
		spares += 1


## Host: with no spare ships left and nobody alive for GAME_OVER_GRACE, the run is over.
func _check_game_over(delta: float) -> void:
	var all_dead := players.get_child_count() > 0
	for p in players.get_children():
		if p.is_alive():
			all_dead = false
			break
	if spares > 0 or not all_dead:
		_over_timer = 0.0
		return
	_over_timer += delta
	if _over_timer >= GAME_OVER_GRACE:
		_over_timer = 0.0
		game_over.rpc(score, stage, _run_players)


## Host -> everyone: the run is over. Every peer logs it in its high scores and
## shows the results; RESULTS_TIME later the host starts the next run.
@rpc("authority", "call_local", "reliable")
func game_over(final_score: int, final_stage: int, names: Array) -> void:
	if over:
		return
	over = true
	input_enabled = false
	_results_left = RESULTS_TIME
	var rank := HighScores.add({"score": final_score, "stage": final_stage + 1, "players": names,
		"date": Time.get_datetime_string_from_system(false, true)})
	var best := "New high score!" if rank == 1 else "Rank #%d" % rank
	show_banner("GAME OVER\nStage %d    Score %d\n%s" % [final_stage + 1, final_score, best], RESULTS_TIME)
	var sound := get_node_or_null("GameOverSound")
	if sound:
		sound.play()


## Host -> everyone: the next run starts with the same players.
@rpc("authority", "call_local", "reliable")
func restart_run() -> void:
	stop()
	start()


func add_score(points: int) -> void:
	if multiplayer.is_server():
		score += points
