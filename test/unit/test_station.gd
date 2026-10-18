extends GutTest
## Rescued enemy pods trail behind the ship like a tail; flying near a rescue
## station turns the whole tail in for an exp per pod and score.

const PlayerScript := preload("res://scripts/player.gd")
const StationScript := preload("res://scripts/station.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

var game: Node2D
var player: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	player = preload("res://scenes/player.tscn").instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 800)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _tail(types: Array[int]) -> void:
	player._add_to_tail(types)


func _station(pos: Vector2) -> Node2D:
	game.spawn_station(pos, "Station1")
	return game.get_node("Stations/Station1")


# --- Tail ------------------------------------------------------------------------

func test_rescued_enemy_pods_join_the_tail_in_order() -> void:
	_tail([EnemyScript.TANK, EnemyScript.WEAVER])
	assert_eq(player.tail, [EnemyScript.TANK, EnemyScript.WEAVER])


func test_player_pods_never_join_the_tail() -> void:
	_tail([-1, EnemyScript.DIVER, -1])
	assert_eq(player.tail, [EnemyScript.DIVER])


func test_tail_is_capped() -> void:
	var many: Array[int] = []
	for i in PlayerScript.TAIL_MAX + 5:
		many.append(EnemyScript.WEAVER)
	_tail(many)
	assert_eq(player.tail.size(), PlayerScript.TAIL_MAX)


func test_tail_follows_the_flown_path_behind_the_options() -> void:
	player.options = 2
	_tail([EnemyScript.WEAVER, EnemyScript.STRIKER])
	for i in 60:  # fly straight up
		player.position.y -= 4.0
		player._process(0.0)
	var at: Array[Vector2] = player.tail_positions()
	assert_eq(at.size(), 2)
	var behind_options := PlayerScript.OPTION_GAP * 2
	assert_almost_eq(at[0].y - player.position.y, behind_options + PlayerScript.TAIL_GAP, PlayerScript.TRAIL_STEP)
	assert_almost_eq(at[1].y - at[0].y, PlayerScript.TAIL_GAP, PlayerScript.TRAIL_STEP)
	assert_eq(at[0].x, player.position.x)


func test_tail_sprites_show_each_enemy_ship() -> void:
	_tail([EnemyScript.TANK, EnemyScript.ORBITER])
	player._process(0.0)
	assert_eq(player._tail_sprites.size(), 2)
	assert_same(player._tail_sprites[0].texture, Ships.get_lit_enemy_texture(EnemyScript.TYPES[EnemyScript.TANK].ship))
	assert_same(player._tail_sprites[1].texture, Ships.get_lit_enemy_texture(EnemyScript.TYPES[EnemyScript.ORBITER].ship))
	player.tail = []
	player._process(0.0)
	assert_eq(player._tail_sprites.size(), 0)


func test_tail_is_lost_with_the_ship() -> void:
	_tail([EnemyScript.WEAVER])
	player._lose_upgrades()
	assert_eq(player.tail.size(), 0)


func test_tail_replicates() -> void:
	var cfg: SceneReplicationConfig = player.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:tail")))


func test_drone_leaves_pods_when_the_tail_is_full() -> void:
	var many: Array[int] = []
	for i in PlayerScript.TAIL_MAX:
		many.append(EnemyScript.WEAVER)
	_tail(many)
	player.levels[&"rescue"] = 1
	game.spawn_pod(Vector2(270, 600), 0, "Pod1")
	player.launch_drone()
	for i in 120:
		player._simulate(1.0 / 60.0)
	assert_eq(game.get_node("Pods").get_child_count(), 1, "no room, left it")


# --- Station ---------------------------------------------------------------------

func test_docking_turns_in_the_whole_tail_for_exp_and_score() -> void:
	_tail([EnemyScript.WEAVER, EnemyScript.TANK, EnemyScript.DIVER])
	var exp_before: int = player.exp_total
	var st := _station(player.position + Vector2(0, -40))
	player._simulate(0.016)
	assert_eq(player.tail.size(), 0, "all piled in")
	assert_eq(player.exp_total, exp_before + 3, "an exp per pod")
	assert_eq(game.score, 3 * game.RESCUE_POINTS)
	assert_eq(st.get_child_count(), 3, "three pods flying in")
	await wait_seconds(StationScript.FLY_TIME + StationScript.FLY_STAGGER * 3 + 0.2)
	assert_eq(st.get_child_count(), 0, "and gone into the core")


func test_out_of_reach_nothing_happens() -> void:
	_tail([EnemyScript.WEAVER])
	_station(player.position + Vector2(0, -(StationScript.RADIUS + 10)))
	player._simulate(0.016)
	assert_eq(player.tail.size(), 1)
	assert_eq(game.score, 0)


func test_empty_tail_does_nothing() -> void:
	var exp_before: int = player.exp_total
	_station(player.position)
	player._simulate(0.016)
	assert_eq(player.exp_total, exp_before)
	assert_eq(game.score, 0)


func test_station_drifts_down_and_leaves() -> void:
	var st := _station(Vector2(270, -60))
	st._process(1.0)
	assert_almost_eq(st.position.y, -60 + StationScript.SPEED, 0.001)
	st.position.y = EnemyScript.EXIT_Y + StationScript.OFFSCREEN + 1
	st._process(0.0)
	assert_true(st.is_queued_for_deletion())


func test_host_sends_stations_in_regularly() -> void:
	game.active = true
	for i in int(game.STATION_INTERVAL * 60) + 2:
		game._physics_process(1.0 / 60.0)
	var s := game.get_node("Stations")
	assert_eq(s.get_child_count(), 1)
	var x: float = s.get_child(0).position.x
	assert_between(x, game.STATION_EDGE, game.ARENA.size.x - game.STATION_EDGE)


func test_stop_clears_stations() -> void:
	_station(Vector2(270, 100))
	game.stop()
	await wait_physics_frames(1)
	assert_eq(game.get_node("Stations").get_child_count(), 0)
