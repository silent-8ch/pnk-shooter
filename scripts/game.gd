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
## A stage: enemies until halfway to the boss, when an ELITE mini boss comes
## in (mini_boss_kills); shooting it down starts a REFIT, then on to the boss;
## shooting the boss down starts another REFIT, then the fork. A refit clears
## the field of enemies, their shots and obstacles (pickups, pods and stations
## stay), and the party buys and sets upgrades in peace until everyone has
## tapped READY (RefitPanel). Ships can't be hurt from a boss kill until the
## next stage starts, refits and forks alike (between_levels).
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
const CleanupBotScript := preload("res://scripts/cleanup_bot.gd")
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
const DEMO_RESTART := 2.5  # s after the demo's ship goes down before a new demo
const DEMO_UPGRADES := Vector2i(3, 14)  # free upgrade levels a demo ship starts with
const BOSS_KILLS := 30  # kills before the first boss ...
const BOSS_KILLS_STEP := 10  # ... and this many more each stage
const BOSS_ADD_INTERVAL := 8.0  # s between small groups during a boss fight
const BOSS_ADD_TYPES: Array[int] = [EnemyScript.WEAVER, EnemyScript.DIVER]
const START_SPARES := 4  # spare ships a run starts with, shared by everyone
const GAME_OVER_GRACE := 1.5  # s with nobody alive and no spares before the run ends
const RESULTS_TIME := 4.0  # s the results stay up before the run starts over
const PACE_START := 0.3  # a run starts with enemies coming at this fraction of the level's pace ...
const PACE_STAGE := 0.15  # ... each later stage starts this much higher ...
const PACE_RAMP := 300.0  # ... and it eases up to full pace over this many s of the stage
const VULCAN_LINK_REACH := 45.0  # px from a new round to the last one of its strand
const VULCAN_LINK_AGE := 0.12  # s: an older round has moved on; a new strand starts
const VULCAN_BURST := 0.8  # s of rounds one vulcan sound covers (it ends with a spin-down tail)
const HEALBEAM_BURST := 0.55  # s of heal shots one burble covers
const FORK_TIME := 10.0  # s the party has to vote at a fork
const GATE_POS: Array[Vector2] = [Vector2(135, 330), Vector2(405, 330)]  # left, right
const GateScript := preload("res://scripts/gate.gd")
const BOSS_PICKUPS := 6  # pickups a boss bursts into
const BOSS_SHOT_COLOR := Color("ff4d6d")
const BANNER_TIME := 2.5  # s a stage banner stays up
const WARP_TIME := 0.3  # s an enemy cleared by a refit takes to warp out
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
@onready var status_bar: StatusBar = $HUD/StatusBar
@onready var info_label: Label = $HUD/InfoLabel
@onready var hud: CanvasLayer = $HUD
@onready var pointer_controls: CanvasLayer = $PointerControls

var score := 0  # replicated by ScoreSync
var stage := 0  # replicated by ScoreSync: bosses beaten; enemies sent in get tougher with it
var spares := START_SPARES  # replicated by ScoreSync: spare ships left; a dead ship needs one to come back
var kills := 0  # replicated by ScoreSync: enemies shot down toward the next boss
var over := false  # the run ended; the results are up
var kind := LevelKinds.FIRST  # replicated by ScoreSync: the kind of level this stage is (LevelKinds)
var fork_options: Array = []  # a fork is open: [{kind, reward}, {kind, reward}] (left, right)
var exp_mult := 1  # every peer: exp per pickup this stage (fork reward)
var score_mult := 1  # host: score multiplier this stage (fork reward)
var _fork_left := 0.0
var _rng := RandomNumberGenerator.new()
var _shown_kind := ""
var scenery: Node2D  # the current kind's look and hazards (Scenery), behind everything
var _scenery_clock := {}  # joiner: the host's scenery time, until our scenery for that kind is up
var _ready_votes := {}  # host, after a game over: peer id -> ready for the next run
var refit := false  # every peer: a refit is on (see start_refit)
var refit_after_boss := false  # every peer: this refit ends in a fork
var _refit_votes := {}  # host: peer id -> ready to leave the refit
var _elite_done := false  # host: this stage's mini boss has been sent in
var peer_names := {}  # host: peer id -> player name (kept between runs, for the ready screen)
var last_results := ""  # the last run's results, for the ready screen

signal ready_changed(list: Array)  # [{name, ready}] for the ready screen
signal run_started  # restart_run brought everyone into a new run
signal refit_changed(list: Array)  # [{name, ready}] for the RefitPanel
signal waiting_for_run  # we joined between runs: show the ready screen
var _boss_add_timer := 0.0
var _over_timer := 0.0  # server: s with nobody alive and no spares
var _results_left := 0.0
var _run_players: Array = []  # server: names of everyone who flew this run, for the high scores

signal run_ended  # the results were up for RESULTS_TIME; the host starts the next run
var active := false
var resume := {}  # host: a saved run (SaveGame) to pick up when start() runs
var demo := false  # the title screen's idle demo: an AI flies a random ship through a random kind of level
var _demo_dead := 0.0  # s the demo's ship has been down
var input_enabled := true  # false while the pause menu is open
var _enemy_timer := 0.0
var level: RefCounted  # the level being played (see level.gd), or null for random waves
## Seconds into the level. Every peer runs this clock (joiners get it from the
## host) so a player left alone when the host quits carries on from the same spot.
var level_time := 0.0
var _player_count := 0
var _pickup_count := 0  # server: names pickups uniquely
var _pod_count := 0  # server: names escape pods uniquely
var _cleanup_count := 0  # server: names cleanup bots uniquely
var _obstacle_timer := 0.0
var _station_timer := 0.0
var _vulcan_until := {}  # shooter peer -> when its burst sound runs out (s, engine time)
var _healbeam_until := {}  # shooter peer -> when its burble runs out (s, engine time)
var stage_time := 0.0  # s of fighting in this stage (boss fights and forks don't count), for pace()
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


## The idle demo (offline): a random ship with random upgrades, flown by an
## AiPilot through a random kind of level. When it's shot down the demo starts
## over with a new ship and kind (DEMO_RESTART s later); no high scores.
func start_demo() -> void:
	demo = true
	start()


func _restart_demo() -> void:
	stop()
	start_demo()


func start() -> void:
	Ships.prewarm_enemy_parts()  # avoid a hitch on the first kill
	for ramp in WreckScript.FIRE_RAMPS:
		SpriteEffect.explosion_frames(ramp)  # recolor the painted explosion once per ramp
	PickupScript.warm()  # render the pickup's palette cycle up front
	_rng.randomize()
	streak_aim = 0
	streak_untouched = 0
	best_aim = 0
	best_untouched = 0
	kind = LevelKinds.FIRST
	if demo:
		var kinds: Array = LevelKinds.KINDS.keys()
		kind = kinds[_rng.randi_range(0, kinds.size() - 1)]
	level = LevelKinds.load_level(kind)
	_demo_dead = 0.0
	_close_fork()
	_end_refit_here()
	_elite_done = false
	exp_mult = 1
	score_mult = 1
	level_time = 0.0
	_enemy_timer = 0.0
	_station_timer = 0.0
	stage_time = 0.0
	_boss_add_timer = 0.0
	_over_timer = 0.0
	over = false
	active = true
	hud.visible = true
	pointer_controls.visible = not demo and not (multiplayer.is_server() and Net.ai_pilot)
	if demo:
		score = 0
		stage = 0
		kills = 0
		spares = 0
		_run_players = []
		info_label.text = "DEMO  -  tap to play"
		var ship := _rng.randi_range(0, Ships.count() - 1)
		_add_player(1, "Demo", ship, _rng.randi_range(0, Ships.palette_count() - 1))
		var p := players.get_node_or_null("1")
		if p:
			AiPilot.random_loadout(p, _rng, _rng.randi_range(DEMO_UPGRADES.x, DEMO_UPGRADES.y))
	elif multiplayer.is_server():
		score = 0
		stage = 0
		kills = 0
		spares = START_SPARES
		_run_players = []
		info_label.text = "Hosting at %s" % Net.get_local_ip()
		if not resume.is_empty():
			_resume_run(resume)
			resume = {}
		else:
			_add_player(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))
		if Net.ai_buddy:
			_add_buddy()
	else:
		info_label.text = "Connected"
		register_player.rpc_id(1, Net.player_name, Ships.selected, Ships.palette_for(Ships.selected))


# --- Save and exit ------------------------------------------------------------

## Whether this run can be saved now: a solo host's own live run (no one else
## connected, not the demo), with its ship alive.
func can_save() -> bool:
	if not active or demo or over or multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return false
	if not multiplayer.get_peers().is_empty():
		return false
	var me := local_player()
	return me != null and me.is_alive()


## What a saved run keeps (SaveGame): the stage and the ship, to start that
## stage over from its beginning.
func run_state() -> Dictionary:
	var me := local_player()
	var st: Dictionary = me.upgrade_state()
	return {
		"kind": kind, "stage": stage, "score": score, "spares": spares,
		"exp_mult": exp_mult, "score_mult": score_mult, "name": Net.player_name,
		"ship": me.ship, "palette": me.palette, "hp": me.hp,
		"levels": st.levels, "power": st.power, "armed": st.armed,
		"shield": me.shield, "rear_shield": me.rear_shield,
		"exp_balance": me.exp_balance, "exp_total": me.exp_total, "tail": me.tail,
	}


func save_run() -> bool:
	return can_save() and SaveGame.write(run_state())


## Host, from start(): a saved run's stage from its beginning, and its ship
## with everything it had. Anything missing or unknown to this version of the
## game falls back to a fresh run's value.
func _resume_run(st: Dictionary) -> void:
	var k := str(st.get("kind", LevelKinds.FIRST))
	kind = k if LevelKinds.is_kind(k) else LevelKinds.FIRST
	level = LevelKinds.load_level(kind)
	stage = maxi(0, int(st.get("stage", 0)))
	score = maxi(0, int(st.get("score", 0)))
	spares = maxi(0, int(st.get("spares", START_SPARES)))
	exp_mult = clampi(int(st.get("exp_mult", 1)), 1, 2)
	score_mult = clampi(int(st.get("score_mult", 1)), 1, 2)
	warm_stage.rpc(stage)
	var ship := Ships.clamp_index(int(st.get("ship", Ships.selected)))
	_add_player(1, Net.player_name, ship, Ships.clamp_palette(int(st.get("palette", Ships.palette_for(ship)))))
	var me := players.get_node_or_null("1")
	if me == null:
		return
	me.levels = SaveGame.ids_map(st.get("levels", {}))
	me.power = {}
	me.armed = {}
	for sys in Systems.systems():
		me.power[sys.id] = 0
	var saved_power := SaveGame.ids_map(st.get("power", {}))
	for sys in saved_power:
		for i in saved_power[sys]:
			me.add_power(sys)
	for g in SaveGame.ids_list(st.get("armed", [])):
		me.arm(g)
	me.shield = int(st.get("shield", 0)) if me.power_of(&"shields") >= 1 else 0
	me.rear_shield = int(st.get("rear_shield", 0)) if me.power_of(&"shields") >= 2 else 0
	me.hp = clampf(float(st.get("hp", me.max_hp())), 1.0, me.max_hp())
	me.exp_balance = maxi(0, int(st.get("exp_balance", 0)))
	me.exp_total = maxi(0, int(st.get("exp_total", 0)))
	var t: Variant = st.get("tail", [])
	me.tail = (t as Array).map(func(x): return int(x)) if t is Array else []


func stop() -> void:
	active = false
	demo = false
	streak_aim = 0
	streak_untouched = 0
	best_aim = 0
	best_untouched = 0
	Music.set_boss(false)
	Music.set_fanfare(false)
	Music.set_level(Music.TRACK)
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
	kind = LevelKinds.FIRST
	exp_mult = 1
	score_mult = 1
	_close_fork()
	_end_refit_here()
	_elite_done = false
	_player_count = 0
	ready_peers = {1: true}


func _process(delta: float) -> void:
	if not active or multiplayer.multiplayer_peer == null:
		return
	if _shown_kind != kind:
		_shown_kind = kind
		_set_scenery()
		Music.set_level(load(LevelKinds.music_of(kind)))
	var bar: ProgressBar = hud.get_node_or_null("BossBar")
	if bar:
		bar.value = 1.0 if boss_alive() else float(kills) / boss_kills_needed()
	Music.set_boss((boss_alive() or elite_alive()) and not over, Music.BOSS_TRACK if boss_alive() else Music.MINI_BOSS_TRACK)
	Music.set_fanfare((refit or fork_open()) and not over)
	if over:
		_results_left -= delta
		if _results_left <= 0.0:
			over = false
			run_ended.emit()


func _physics_process(delta: float) -> void:
	if not active or multiplayer.multiplayer_peer == null or over:
		return
	var from := level_time
	var boss_up := boss_alive() or elite_alive()
	if refit:
		if multiplayer.is_server():
			_check_game_over(delta)
		return
	if fork_open():
		if multiplayer.is_server():
			_check_game_over(delta)
		_run_fork(delta)
		return
	if not boss_up:
		stage_time += delta
		level_time += delta * pace()  # the level holds its place while a boss is up, and starts slow
	if not multiplayer.is_server():
		return
	_check_game_over(delta)
	_send_cleanup_bots()
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
	if not _elite_done and kills >= mini_boss_kills():
		_elite_done = true
		spawn_elite()
		return
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
	_enemy_timer += delta * pace()
	if _enemy_timer >= GROUP_INTERVAL:
		_enemy_timer = 0.0
		var types := LevelKinds.wave_types(kind)
		spawn_group(types[randi() % types.size()])
	_obstacle_timer += delta * pace()
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
	if not active or over:  # between runs: they wait on the ready screen with everyone else
		peer_names[id] = pname.left(12)
		wait_for_run.rpc_id(id, last_results)
		if not active:
			_broadcast_ready()
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
	for e in enemies.get_children():
		if e.has_bar():
			boss_hp.rpc_id(id, String(e.name), e.hp)  # its bar starts where the host's is
	set_ready_peers.rpc_id(id, ready_peers.keys())
	set_level_time.rpc_id(id, level_time)
	if scenery:
		set_scenery_time.rpc_id(id, kind, scenery.time)  # hazards on the same schedule
	if fork_open():
		show_fork.rpc_id(id, fork_options, _fork_left)
	if refit:
		start_refit.rpc_id(id, refit_after_boss)
	_add_player(id, pname, ship, palette)
	peer_ready.rpc(id)


@rpc("authority", "call_remote", "reliable")
func set_level_time(t: float) -> void:
	level_time = t


## Host -> a joiner: how far into its `for_kind` scenery the host is (hazard
## timing comes from it). Applied now, or when that scenery comes in.
@rpc("authority", "call_remote", "reliable")
func set_scenery_time(for_kind: String, t: float) -> void:
	_scenery_clock = {"kind": for_kind, "time": t, "at": Time.get_ticks_msec() / 1000.0}
	_apply_scenery_clock()


func _apply_scenery_clock() -> void:
	if _scenery_clock.is_empty() or scenery == null or scenery.kind != _scenery_clock.kind:
		return
	scenery.time = _scenery_clock.time + Time.get_ticks_msec() / 1000.0 - _scenery_clock.at
	_scenery_clock = {}


## Host -> a peer joining between runs: no world to catch up on; it waits on
## the ready screen (Main shows it) and joins the next run with everyone.
@rpc("authority", "call_remote", "reliable")
func wait_for_run(results: String) -> void:
	stop()
	last_results = results
	waiting_for_run.emit()


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
	elif id == 1 and (demo or Net.ai_pilot):
		data.pilot = true
	if not _run_players.has(data.name):
		_run_players.append(data.name)
	if not ai:
		peer_names[id] = data.name
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
	if data.get("pilot", false):
		p.pilot = AiPilot.new()
	p.set_multiplayer_authority(data.get("owner", data.id))  # the owner flies it and replicates it
	p.get_node("Sync").add_visibility_filter(_peer_has_world)
	print("[peer %d] spawned player %s (%d)" % [multiplayer.get_unique_id(), data.name, data.id])
	players.add_child(p)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		peer_names.erase(id)
		_ready_votes.erase(id)
		remove_player.rpc(id)
		if not active and not _ready_votes.is_empty():
			_broadcast_ready()  # someone left the ready screen: maybe everyone left is ready
		_refit_votes.erase(id)
		if refit:
			_broadcast_refit()  # maybe everyone left is ready


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
	e.ship_override = int(data.get("ship", -1))
	enemies.add_child(e)
	if data.has("time"):
		e.restore(data.time, data.pos)


## How fast enemies come, 0..1 of the level's own pace: slow at the start of a
## run, easing up over PACE_RAMP s; later stages start faster.
func pace() -> float:
	var start := minf(1.0, PACE_START + PACE_STAGE * stage)
	return lerpf(start, 1.0, smoothstep(0.0, PACE_RAMP, stage_time))


## Kills that bring in the next boss.
func boss_kills_needed() -> int:
	return BOSS_KILLS + BOSS_KILLS_STEP * stage


## Kills that bring in the stage's mini boss: halfway to the boss.
func mini_boss_kills() -> int:
	return boss_kills_needed() / 2


## Is the mini boss on the field?
func elite_alive() -> bool:
	for e in enemies.get_children():
		if e.is_elite() and not e.is_queued_for_deletion():
			return true
	return false


## Server: sends in the mini boss, as tough as the current stage.
func spawn_elite() -> void:
	_enemy_count += 1
	spawn_enemy.rpc({"x": ARENA.size.x / 2.0, "y": EnemyScript.SPAWN_Y - 40.0, "type": EnemyScript.ELITE,
		"id": _enemy_count, "stage": stage})
	show_banner.rpc("WARNING\nElite approaching")


## Ships can't be hurt from a boss kill until the next stage gets going.
func between_levels() -> bool:
	return refit or fork_open()


## Is a boss on the field? (Every peer has the same enemies.)
func boss_alive() -> bool:
	for e in enemies.get_children():
		if e.is_boss() and not e.is_queued_for_deletion():
			return true
	return false


## Server: sends in a boss, as tough as the current stage.
func spawn_boss() -> void:
	_enemy_count += 1
	spawn_enemy.rpc({"x": ARENA.size.x / 2.0, "y": EnemyScript.SPAWN_Y - 60.0,
		"type": LevelKinds.info(kind).get("boss_type", EnemyScript.BOSS),
		"id": _enemy_count, "stage": stage, "ship": LevelKinds.info(kind).get("boss_ship", -1)})
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
		if not enemy.has_bar() and not boss_alive() and not elite_alive():
			kills += 1  # shooting the escorts doesn't bring the next big one sooner
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
	play_wreck.rpc(enemy.position, enemy.type, randi(), wreck_name, pod_name, enemy.stage, enemy.ship_index())
	if pod_name != "":
		spawn_pod.rpc(enemy.position, enemy.type, pod_name, wreck_name)
	remove_enemy.rpc(String(enemy.name))
	if enemy.is_elite():
		begin_refit(false)
	elif enemy.is_boss():
		stage += 1
		kills = 0
		_elite_done = false
		warm_stage.rpc(stage)
		begin_refit(true)


@rpc("authority", "call_local", "reliable")
func remove_enemy(enemy_name: String) -> void:
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		e.queue_free()


@rpc("authority", "call_local", "reliable")
func play_wreck(pos: Vector2, type: int, fx_seed: int, wreck_name := "", pod_name := "", stage_of := 0, ship_of := -1) -> void:
	if wreck_name != "" and effects.has_node(wreck_name):
		return
	var ship: int = ship_of if ship_of >= 0 else EnemyScript.TYPES[clampi(type, 0, EnemyScript.TYPES.size() - 1)].ship
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


## Ship owner -> everyone: one of its ships healed.
@rpc("any_peer", "call_local", "unreliable")
func play_heal() -> void:
	_play_sound("HealSound")


## Ship owner -> everyone: its rescue drones are heading out.
@rpc("any_peer", "call_local", "unreliable")
func play_siren() -> void:
	_play_sound("SirenSound")


func _play_sound(node_name: String) -> void:
	var sound := get_node_or_null(node_name)
	if sound:
		sound.play()


## Every peer adds the same pickup under the same name, so the server can name it
## in collect_pickup.
@rpc("authority", "call_local", "reliable")
func spawn_pickup(pos: Vector2, pickup_name: String) -> void:
	var p := PickupScript.new()
	p.name = pickup_name
	p.position = pos
	pickups.add_child(p)


## Server: `peer` took the pickup; every peer plays its collect animation, and
## the taker's own ship banks the exp (see ShipPanel).
@rpc("authority", "call_local", "reliable")
func collect_pickup(pickup_name: String, peer: int) -> void:
	var p := pickups.get_node_or_null(pickup_name)
	if p:
		p.collect()
	var me := local_player()
	if me and peer == multiplayer.get_unique_id():
		for i in exp_mult:
			me.add_exp()
		FloatText.spawn(effects, me.position + Vector2(0, -30), "+%d" % exp_mult, UiStyle.AMBER)


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
	if b.kind == b.VULCAN:
		b.link = _vulcan_link(b)
	bullets.add_child(b)
	if b.kind == b.VULCAN:
		_play_vulcan(b.shooter)
	elif b.kind == b.HEAL:
		_play_healbeam(b.shooter)
	else:
		shoot_sound.play()  # every peer hears every shot


# --- Streaks ------------------------------------------------------------------

## Each player keeps their own two streaks: photon shots in a row that hit
## something (a miss breaks it), and kills since they last took a hit. At
## each STREAK_MILESTONE they get a banner and STREAK_BONUS x the count in
## score; losing a streak of STREAK_LOST_AT or more says so.
const STREAK_MILESTONES: Array[int] = [10, 25, 50, 100]  # then every 100
const STREAK_BONUS := 10
const STREAK_LOST_AT := 25

var streak_aim := 0  # local: photon hits in a row
var streak_untouched := 0  # local: kills since our ship was last hit
var best_aim := 0
var best_untouched := 0


static func is_streak_milestone(n: int) -> bool:
	return STREAK_MILESTONES.has(n) or (n > 100 and n % 100 == 0)


## Local: one of our photon shots is gone, having `hit` something or not.
func photon_result(hit: bool) -> void:
	if hit:
		streak_aim += 1
		best_aim = maxi(best_aim, streak_aim)
		_streak_up(streak_aim, "%d IN A ROW")
	else:
		_streak_lost(streak_aim, "AIM")
		streak_aim = 0


## Host -> the shooter: their shot finished an enemy.
@rpc("authority", "call_local", "reliable")
func credit_kill() -> void:
	streak_untouched += 1
	best_untouched = maxi(best_untouched, streak_untouched)
	_streak_up(streak_untouched, "%d KILLS UNTOUCHED")


## Local: our ship took a hit.
func streak_hurt() -> void:
	_streak_lost(streak_untouched, "UNTOUCHED")
	streak_untouched = 0


func _streak_up(n: int, words: String) -> void:
	if not is_streak_milestone(n):
		return
	show_banner((words % n) + "\n+%d" % (n * STREAK_BONUS * score_mult))
	report(&"streak_bonus", [n * STREAK_BONUS])


func _streak_lost(n: int, what: String) -> void:
	if n >= STREAK_LOST_AT:
		show_banner("%s STREAK LOST\n%d" % [what, n])


## Player -> host: a streak milestone's score.
@rpc("any_peer", "call_local", "reliable")
func streak_bonus(points: int) -> void:
	add_score(clampi(points, 0, 100000))


## Sends a hit report (`method` with `args`) to the host from a collision
## callback. It goes at the end of the frame: on the host the report runs at
## once, and what it spawns (pickups, pods, astronauts) can't be added to the
## physics world while it's busy with the collisions.
func report(method: StringName, args: Array) -> void:
	_send_report.call_deferred(method, args)


func _send_report(method: StringName, args: Array) -> void:
	if multiplayer.multiplayer_peer != null:
		callv(&"rpc_id", [1, method] + args)


## The round a new vulcan round `b` joins onto: the same shooter's newest
## round still near the muzzle (its gun's last one), so each gun's stream is
## one strand. Every peer works it out from its own copies.
func _vulcan_link(b: Node2D) -> Node2D:
	var best: Node2D = null
	var best_d: float = VULCAN_LINK_REACH
	for o in bullets.get_children():
		if o.kind != o.VULCAN or o.shooter != b.shooter or o.is_queued_for_deletion() or o._age > VULCAN_LINK_AGE:
			continue
		var d: float = o.position.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = o
	return best


## One "buuuurt" per VULCAN_BURST of a ship's stream of rounds, not one per round.
func _play_vulcan(shooter: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _vulcan_until.get(shooter, 0.0):
		return
	_vulcan_until[shooter] = now + VULCAN_BURST
	var sound := get_node_or_null("VulcanSound")
	if sound:
		sound.play()


## One low burble per HEALBEAM_BURST of a ship's stream of heal shots.
func _play_healbeam(shooter: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _healbeam_until.get(shooter, 0.0):
		return
	_healbeam_until[shooter] = now + HEALBEAM_BURST
	_play_sound("HealBeamSound")


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
		if e.is_queued_for_deletion() or e.hp <= 0 or not e.is_in_group("enemy"):
			credit_kill.rpc_id(_sender())  # the shot that finished it


## Shooter -> host: its HEAL shot hit `enemy_name` for `amount`; the enemy
## gets stronger, and every peer sees it grow.
@rpc("any_peer", "call_local", "reliable")
func report_heal_hit(enemy_name: String, amount := 0.1) -> void:
	if not multiplayer.is_server():
		return
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		var hits: int = e.strengthen(clampf(amount, 0.0, 1.0))
		if hits > 0:
			grow_enemy.rpc(enemy_name, hits)


@rpc("authority", "call_local", "reliable")
func grow_enemy(enemy_name: String, hits: int) -> void:
	var e := enemies.get_node_or_null(enemy_name)
	if e:
		e.grow(clampi(hits, 0, 10))


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


## Server: one obstacle at exactly `pos` (scenery hazards: split rocks, showers).
func spawn_obstacle_at(piece: String, pos: Vector2, dir := 1.0) -> void:
	if ObstacleScript.placeable(piece):
		_announce_obstacle(piece, pos, 1, dir)


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
	if o.loot:
		_pickup_count += 1
		spawn_pickup.rpc(o.position, "Pickup%d" % _pickup_count)
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
	if scenery and multiplayer.is_server():
		scenery.on_obstacle_destroyed(o.piece_id, o.position)
	o.queue_free()


# --- Chain reactions ----------------------------------------------------------

const SHIP_RADIUS := 14.0  # player and enemy reach, for wreck collisions


const BLAST_DAMAGE := 1.0  # to a player's escape pod


## Every peer, when an escape pod blows up at `at`: the host damages pods
## inside (one pod's blast can chain to the next). Blasts never hurt ships, and
## wrecks (broken enemies) are harmless: they don't blast at all.
## `spare_pod`: a pod the blast doesn't take.
func blast(at: Vector2, radius: float, spare_pod := "") -> void:
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
## Astronauts can't be hurt.
func damage_pod(pod: Node, amount: float) -> void:
	if pod.taken or pod.astronaut:
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


## Every peer: the pod blows up with a very small explosion, which can chain,
## and leaves two astronauts (named after it, so every peer agrees). A
## player's pod's astronauts carry its owner's upgrades.
@rpc("authority", "call_local", "reliable")
func destroy_pod(pod_name: String) -> void:
	var p := pods.get_node_or_null(pod_name)
	if p == null or p.taken or p.astronaut:
		return
	p.taken = true
	_detach(pods, p)
	p.burst(effects)
	var stash := pod_name if p.is_player_pod() else ""
	for a in p.astronauts():
		_spawn_astronaut(a.name, a.position, a.velocity, p.owner_peer, stash, p.beacon_color)
	blast(p.position, p.BLAST_RADIUS)
	p.queue_free()


## Ship owner, as its ship is lost: the rescued it was carrying spill out as
## astronauts (named "Astronaut<sender>_<n>" by the owner) at `positions`.
@rpc("any_peer", "call_local", "reliable")
func release_astronauts(names: Array, positions: Array) -> void:
	var prefix := "Astronaut%d_" % _sender()
	for i in mini(names.size(), positions.size()):
		var n := str(names[i])
		if not n.begins_with(prefix) or pods.has_node(n) or not positions[i] is Vector2:
			continue
		# Same direction on every peer, from the name.
		var dir := Vector2.DOWN.rotated(fposmod(float(n.hash()), TAU))
		_spawn_astronaut(n, positions[i], dir * PodScript.ASTRONAUT_SPEED, 0, "", PodScript.GREEN)


## Host: a cleanup bot for every enemy astronaut left too long (EscapePod.needs_cleanup).
func _send_cleanup_bots() -> void:
	for p in pods.get_children():
		if p.is_queued_for_deletion() or not p.needs_cleanup():
			continue
		p.taken = true
		_cleanup_count += 1
		send_cleanup_bot.rpc(String(p.name), "Cleanup%d" % _cleanup_count)


## Drone owner -> everyone: one of its rescue drones was destroyed at `at`.
@rpc("any_peer", "call_local", "reliable")
func drone_destroyed(at: Vector2) -> void:
	SpriteEffect.spawn(effects, at, SpriteEffect.explosion_frames(WreckScript.FIRE_RAMPS[0]), PodScript.BURST_HEIGHT)
	var sound := AudioStreamPlayer.new()
	sound.stream = PodScript.BURST_SOUND
	sound.volume_db = -10.0
	sound.pitch_scale = 1.8
	sound.finished.connect(sound.queue_free)
	effects.add_child(sound)
	sound.play()


## Host -> everyone: a neutral bot comes in for astronaut `pod_name`; nobody
## gets credit (see CleanupBot).
@rpc("authority", "call_local", "reliable")
func send_cleanup_bot(pod_name: String, bot_name: String) -> void:
	var p := pods.get_node_or_null(pod_name)
	if p == null or effects.has_node(bot_name):
		return
	p.taken = true
	var bot := CleanupBotScript.new()
	bot.name = bot_name
	bot.target = p
	bot.home = CleanupBotScript.entry_for(p.position, ARENA.size.x)
	bot.position = bot.home
	effects.add_child(bot)


func _spawn_astronaut(astro_name: String, pos: Vector2, velocity: Vector2, owner_peer: int, stash: String, beacon: Color) -> void:
	if pods.has_node(astro_name):
		return
	var a := PodScript.new()
	a.name = astro_name
	a.astronaut = true
	a.position = pos
	a.velocity = velocity
	a.owner_peer = owner_peer
	a.stash = stash
	a.beacon_color = beacon
	pods.add_child(a)


## Drone or ship owner -> host: its drone reached a pod, or (`by_drone` false)
## its ship touched a player's pod; the first claim wins.
@rpc("any_peer", "call_local", "reliable")
func request_rescue(pod_name: String, by_drone := true) -> void:
	if not multiplayer.is_server():
		return
	var p := pods.get_node_or_null(pod_name)
	if p and not p.taken and (by_drone or (p.is_player_pod() and not p.astronaut)):
		p.taken = true
		rescue_pod.rpc(pod_name, _sender(), by_drone, p.owner_peer, p.stash if p.astronaut else pod_name)


## Server: `peer` saved the pod; it leaves the field everywhere. A drone counts
## it toward its haul; a player's pod gives its owner their upgrades back
## (`stash`: the pod they were stashed under, which an astronaut names).
@rpc("authority", "call_local", "reliable")
func rescue_pod(pod_name: String, peer: int, by_drone := true, pod_owner := 0, stash := "") -> void:
	var p := pods.get_node_or_null(pod_name)
	if p:
		_detach(pods, p)
		p.queue_free()
	_play_sound("RescueSound")
	var me := local_player()
	if me == null:
		return
	if by_drone and peer == multiplayer.get_unique_id():
		me.drone_picked_up(pod_name)
	if pod_owner != 0 and pod_owner == multiplayer.get_unique_id():
		me.recover_upgrades(stash if stash != "" else pod_name)


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
	if not types.is_empty():
		_play_sound("DockSound")
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
## Demo: once its ship is down for DEMO_RESTART s, a new demo.
func _run_demo(delta: float) -> void:
	var p := players.get_node_or_null("1")
	if p and p.is_alive():
		_demo_dead = 0.0
		return
	_demo_dead += delta
	if _demo_dead >= DEMO_RESTART:
		_demo_dead = -INF  # once
		_restart_demo.call_deferred()


func _check_game_over(delta: float) -> void:
	if demo:
		_run_demo(delta)
		return
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
	if multiplayer.is_server():
		SaveGame.clear()  # the saved run is over
	input_enabled = false
	_results_left = RESULTS_TIME
	var rank := HighScores.add({"score": final_score, "stage": final_stage + 1, "players": names,
		"date": Time.get_datetime_string_from_system(false, true), "aim": best_aim, "untouched": best_untouched})
	var best := "New high score!" if rank == 1 else "Rank #%d" % rank
	last_results = "Stage %d    Score %d\n%s" % [final_stage + 1, final_score, best]
	show_banner("GAME OVER\nStage %d    Score %d\n%s" % [final_stage + 1, final_score, best], RESULTS_TIME)
	var sound := get_node_or_null("GameOverSound")
	if sound:
		sound.play()


## Host -> everyone: the next run starts with the same players.
@rpc("authority", "call_local", "reliable")
func restart_run() -> void:
	stop()
	start()
	run_started.emit()


# --- Ready up (between runs) ----------------------------------------------------------

## The run is over and everyone is on the ready screen: the host shows who's ready.
func open_ready() -> void:
	_ready_votes.clear()
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_broadcast_ready()


## A peer taps Ready (or un-Ready) on the ready screen.
@rpc("any_peer", "call_local", "reliable")
func set_ready(on: bool) -> void:
	if not multiplayer.is_server():
		return
	_ready_votes[_sender()] = on
	_broadcast_ready()


## Host: everyone connected, ready or not; once all are ready the next run starts.
func _broadcast_ready() -> void:
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers())
	var list: Array = []
	var all_ready := true
	for id in ids:
		var on: bool = _ready_votes.get(id, false)
		all_ready = all_ready and on
		list.append({"name": peer_names.get(id, "Player"), "ready": on})
	ready_state.rpc(list)
	if all_ready:
		_ready_votes.clear()
		restart_run.rpc()


@rpc("authority", "call_local", "reliable")
func ready_state(list: Array) -> void:
	ready_changed.emit(list)


## Swaps in the scenery for `kind` behind the action, and its background.
func _set_scenery() -> void:
	if scenery:
		remove_child(scenery)
		scenery.queue_free()
	var info := LevelKinds.info(kind)
	var bg := get_node_or_null("Background")
	if bg:
		bg.color = info.bg
	var stars := get_node_or_null("Starfield")
	if stars:
		stars.visible = info.get("stars", true)
	scenery = LevelKinds.make_scenery(kind)
	scenery.name = "Scenery"
	scenery.game = self
	scenery.run_seed = hash([kind, stage])
	add_child(scenery)
	move_child(scenery, (stars.get_index() + 1) if stars else 1)
	_apply_scenery_clock()


func add_score(points: int) -> void:
	if multiplayer.is_server():
		score += points * score_mult


# --- Refits -------------------------------------------------------------------------

## Host, after the mini boss or the boss: a refit for everyone.
func begin_refit(after_boss: bool) -> void:
	_refit_votes.clear()
	start_refit.rpc(after_boss)
	_broadcast_refit()


## Host -> everyone: the field clears and the refit starts. Enemies warp out
## (no points, no drops), their shots and the obstacles go; pickups, pods and
## stations stay to be collected. The SHIP popup opens to get on with it.
@rpc("authority", "call_local", "reliable")
func start_refit(after_boss: bool) -> void:
	refit = true
	refit_after_boss = after_boss
	for e in enemies.get_children():
		_warp_out(e)
	for b in bullets.get_children():
		if b.is_hostile():
			bullets.remove_child(b)
			b.queue_free()
	for o in obstacles.get_children():
		obstacles.remove_child(o)
		o.queue_free()
	show_banner("REFIT\n%s" % ("Then choose your path" if after_boss else "Buy and set upgrades"))
	var panel := get_tree().get_first_node_in_group("ship_panel")
	if panel and is_ancestor_of(panel):
		panel.page = panel.SYSTEMS_PAGE


## An enemy cleared by a refit: out of play at once, flashing and squashing to nothing.
func _warp_out(e: Node2D) -> void:
	e.remove_from_group("enemy")
	enemies.remove_child(e)
	e.set_physics_process(false)
	e.set_deferred("monitoring", false)
	e.set_deferred("monitorable", false)
	effects.add_child(e)
	var tw := e.create_tween()
	tw.tween_property(e, "modulate", Color(3, 3, 3, 1), WARP_TIME * 0.4)
	tw.tween_property(e, "scale", Vector2(e.scale.x * 1.4, 0.0), WARP_TIME * 0.6)
	tw.tween_callback(e.queue_free)


## A peer taps READY (or un-READY) in the refit.
@rpc("any_peer", "call_local", "reliable")
func set_refit_ready(on: bool) -> void:
	if not multiplayer.is_server() or not refit:
		return
	_refit_votes[_sender()] = on
	_broadcast_refit()


## Host: who's ready; once everyone connected is, the refit ends (and after
## the boss the fork opens).
func _broadcast_refit() -> void:
	if not refit:
		return
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers())
	var list: Array = []
	var all_ready := true
	for id in ids:
		var on: bool = _refit_votes.get(id, false)
		all_ready = all_ready and on
		list.append({"name": peer_names.get(id, Net.player_name if id == 1 else "Player"), "ready": on})
	refit_state.rpc(list)
	if all_ready:
		var to_fork := refit_after_boss
		end_refit.rpc()
		if to_fork:
			show_banner.rpc("STAGE %d\nChoose your path" % (stage + 1))
			open_fork()


@rpc("authority", "call_local", "reliable")
func refit_state(list: Array) -> void:
	refit_changed.emit(list)


@rpc("authority", "call_local", "reliable")
func end_refit() -> void:
	_end_refit_here()


func _end_refit_here() -> void:
	refit = false
	refit_after_boss = false
	_refit_votes.clear()
	refit_changed.emit([])


# --- Forks --------------------------------------------------------------------------

## Host, after a boss: the party picks the next kind of level (and a reward) by flying into a gate.
func open_fork() -> void:
	if multiplayer.is_server():
		show_fork.rpc(LevelKinds.fork_options(kind, _rng))


func fork_open() -> bool:
	return not fork_options.is_empty()


## Host -> everyone: the gates open for FORK_TIME s.
@rpc("authority", "call_local", "reliable")
func show_fork(options: Array, time_left := FORK_TIME) -> void:
	_close_fork()
	if options.size() != 2:
		return
	fork_options = options
	_fork_left = clampf(time_left, 0.0, FORK_TIME)
	for i in 2:
		var g := GateScript.new()
		g.name = "Gate%d" % i
		g.kind = str(options[i].get("kind", LevelKinds.FIRST))
		g.reward = str(options[i].get("reward", ""))
		g.position = GATE_POS[i]
		g.add_to_group("gate")
		effects.add_child(g)


func _gates() -> Array:
	return get_tree().get_nodes_in_group("gate").filter(func(g): return is_ancestor_of(g) and not g.is_queued_for_deletion())


func _close_fork() -> void:
	fork_options = []
	for g in _gates():
		g.get_parent().remove_child(g)
		g.queue_free()


## Living ships inside each gate, [left, right], and how many are in neither.
func fork_votes() -> Dictionary:
	var votes := [0, 0]
	var outside := 0
	var gates := _gates()
	for p in players.get_children():
		if not p.is_alive():
			continue
		var side := -1
		for g in gates:
			if g.rect().has_point(p.position):
				side = 0 if g.position.x < ARENA.size.x / 2.0 else 1
		if side < 0:
			outside += 1
		else:
			votes[side] += 1
	return {"votes": votes, "outside": outside}


## The side the party picked: the most votes, where ships in neither gate and
## ties go with the host's side (the side of the screen its ship is on).
func fork_choice() -> int:
	var host := players.get_node_or_null("1")
	var host_side := 1 if host and host.position.x > ARENA.size.x / 2.0 else 0
	var v := fork_votes()
	var count: Array = v.votes.duplicate()
	count[host_side] += v.outside
	if count[0] == count[1]:
		return host_side
	return 0 if count[0] > count[1] else 1


func _run_fork(delta: float) -> void:
	_fork_left -= delta
	var v := fork_votes()
	for g in _gates():
		g.votes = v.votes[0 if g.position.x < ARENA.size.x / 2.0 else 1]
		g.time_left = maxf(_fork_left, 0.0)
	if not multiplayer.is_server():
		return
	var everyone_in: bool = v.outside == 0 and v.votes[0] + v.votes[1] > 0
	if _fork_left <= 0.0 or everyone_in:
		choose_fork.rpc(fork_choice())


## Host -> everyone: the party goes through gate `side` (0 left, 1 right): the
## next stage is that kind of level, and its reward applies.
@rpc("authority", "call_local", "reliable")
func choose_fork(side: int) -> void:
	if not fork_open():
		return
	var opt: Dictionary = fork_options[clampi(side, 0, 1)]
	_close_fork()
	kind = str(opt.get("kind", LevelKinds.FIRST))
	if not LevelKinds.is_kind(kind):
		kind = LevelKinds.FIRST
	level = LevelKinds.load_level(kind)
	level_time = 0.0
	stage_time = 0.0
	_enemy_timer = 0.0
	apply_reward(str(opt.get("reward", "")))
	show_banner("%s\n%s" % [LevelKinds.name_of(kind), LevelKinds.REWARDS.get(opt.get("reward", ""), "")])


## Every peer: a fork's reward. Each peer does its part for the ships it flies.
func apply_reward(reward: String) -> void:
	exp_mult = 2 if reward == "exp2" else 1
	score_mult = 2 if reward == "score2" else 1
	if reward == "spare" and multiplayer.is_server():
		spares += 1
	for p in players.get_children():
		if not p.is_local() or not p.is_alive():
			continue
		if reward == "repair":
			p.repair_fully()
		elif reward == "upgrade":
			p.free_upgrade(_rng)
