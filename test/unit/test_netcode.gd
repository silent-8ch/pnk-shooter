extends GutTest
## Light-authority netcode: owners fly their own ships, bullets are local copies
## from one rpc, enemies move without per-frame sync, the host decides hits,
## deaths and pickups.

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")

var _saved_peer: MultiplayerPeer
var game: Node2D


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _player(id: int) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.peer_id = id
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.position = Vector2(270, 700)
	game.get_node("Players").add_child(p)
	return p


func _enemy(pos := Vector2(270, 300)) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.name = "Enemy7"
	e.position = pos
	game.get_node("Enemies").add_child(e)
	return e


func _bullet(shooter: int) -> Area2D:
	var b: Area2D = BulletScene.instantiate()
	b.shooter = shooter
	game.get_node("Bullets").add_child(b)
	return b


# --- No per-frame sync for bullets and enemies -----------------------------

func test_bullets_and_enemies_have_no_synchronizer() -> void:
	assert_eq(BulletScene.instantiate().find_children("*", "MultiplayerSynchronizer").size(), 0)
	assert_eq(EnemyScene.instantiate().find_children("*", "MultiplayerSynchronizer").size(), 0)
	assert_null(game.get_node_or_null("BulletSpawner"), "bullets aren't network-spawned")


func test_player_is_owned_by_its_peer() -> void:
	game._add_player(42, "Remote", 0, 0)
	var p: Node = game.get_node("Players/42")
	assert_eq(p.get_multiplayer_authority(), 42)
	assert_eq(p.get_node("Sync").get_multiplayer_authority(), 42, "owner replicates its position")


# --- Owner simulation -------------------------------------------------------

func test_owner_moves_and_fires_its_own_ship_immediately() -> void:
	var p := _player(multiplayer.get_unique_id())
	p.input_dir = Vector2.RIGHT
	p._fire_requested = true
	p._physics_process(0.1)
	assert_gt(p.position.x, 270.0)
	assert_eq(game.get_node("Bullets").get_child_count(), 1)
	assert_eq(game.get_node("Bullets").get_child(0).shooter, multiplayer.get_unique_id())


func test_remote_ship_is_not_simulated_locally() -> void:
	var p := _player(99)
	p.input_dir = Vector2.RIGHT
	p._fire_requested = true
	p._physics_process(0.1)
	assert_eq(p.position, Vector2(270, 700))
	assert_eq(game.get_node("Bullets").get_child_count(), 0)


func test_damage_is_decided_by_the_owner() -> void:
	var mine := _player(multiplayer.get_unique_id())
	var theirs := _player(99)
	mine.take_damage(1)
	theirs.take_damage(1)
	assert_eq(mine.hp, mine.MAX_HP - mine.HIT_HP)
	assert_eq(theirs.hp, theirs.MAX_HP, "remote owner decides its own hp")


func test_owner_ramming_hurts_itself_and_reports_the_ram() -> void:
	var p := _player(multiplayer.get_unique_id())
	var e := _enemy()
	p._on_area_entered(e)
	assert_eq(p.hp, p.MAX_HP - p.HIT_HP)
	await wait_frames(1)  # hit reports reach the host at the end of the frame
	assert_true(not is_instance_valid(e) or e.is_queued_for_deletion(), "host destroyed the rammed enemy")


# --- Bullets ----------------------------------------------------------------

func test_bullets_move_on_every_peer() -> void:
	var b := _bullet(99)
	b.position = Vector2(100, 500)
	b._physics_process(0.1)
	assert_lt(b.position.y, 500.0)


func test_own_bullet_hit_reports_to_host() -> void:
	var e := _enemy()
	e.hp = 2
	var b := _bullet(multiplayer.get_unique_id())
	e._on_area_entered(b)
	assert_true(b.is_queued_for_deletion())
	await wait_frames(1)  # hit reports reach the host at the end of the frame
	assert_true(is_instance_valid(e))
	assert_eq(e.hp, 1)


func test_someone_elses_bullet_is_removed_but_not_reported() -> void:
	var e := _enemy()
	e.hp = 2
	var b := _bullet(99)
	e._on_area_entered(b)
	assert_true(b.is_queued_for_deletion(), "looks the same on every peer")
	assert_eq(e.hp, 2, "only the shooter reports")


func test_fire_bullet_records_the_shooter_and_plays_sound() -> void:
	game.fire_bullet(Vector2(100, 600), Color.RED)
	var b: Node = game.get_node("Bullets").get_child(0)
	assert_eq(b.shooter, multiplayer.get_unique_id())
	assert_eq(b.position, Vector2(100, 600))
	assert_true(game.get_node("ShootSound").playing)


# --- Enemies ----------------------------------------------------------------

func test_enemies_have_stable_names_from_the_host() -> void:
	game.active = true
	game.spawn_group(0)
	for e in game.get_node("Enemies").get_children():
		assert_true(String(e.name).begins_with("Enemy"), e.name)


func test_report_hit_for_unknown_enemy_is_ignored() -> void:
	game.report_hit("Enemy999")
	pass_test("no crash")


# --- Pickups ----------------------------------------------------------------

func test_local_player_claims_pickup_and_host_grants_once() -> void:
	var p := _player(multiplayer.get_unique_id())
	game.spawn_pickup(Vector2(270, 700), "Pickup1")
	var pk: Node = game.get_node("Pickups/Pickup1")
	pk._on_area_entered(p)
	assert_true(pk.collected)
	game.request_pickup("Pickup1")  # a late second claim
	assert_true(pk.collected)


func test_remote_player_touching_pickup_does_not_claim_it_here() -> void:
	var p := _player(99)
	game.spawn_pickup(Vector2(270, 700), "Pickup1")
	var pk: Node = game.get_node("Pickups/Pickup1")
	pk._on_area_entered(p)
	assert_false(pk.collected, "that player's own device claims it")


# --- Host leaves ------------------------------------------------------------

func test_host_leaving_keeps_my_world_running_solo() -> void:
	game.active = true
	var me := _player(5)  # my id while connected
	var other := _player(9)
	var e := _enemy()
	game.spawn_pickup(Vector2(10, 10), "Pickup4")
	var my_shot := _bullet(5)
	var their_shot := _bullet(9)
	game.score = 120
	game.continue_solo(5)
	var now := multiplayer.get_unique_id()
	assert_true(other.is_queued_for_deletion(), "other players are gone")
	assert_false(other.is_inside_tree())
	assert_false(me.is_queued_for_deletion())
	assert_eq(me.peer_id, now)
	assert_eq(String(me.name), str(now))
	assert_eq(me.get_multiplayer_authority(), now)
	assert_true(me.is_local(), "I keep flying my ship")
	assert_eq(my_shot.shooter, now, "my bullets still count")
	assert_ne(their_shot.shooter, now)
	assert_false(e.is_queued_for_deletion(), "enemies stay")
	assert_eq(game.score, 120, "score carries on")
	assert_string_contains(game.info_label.text, "solo")
	assert_true(multiplayer.is_server(), "I host my own copy now")


func test_my_ship_takes_the_departed_hosts_id_and_name() -> void:
	game.active = true
	_player(1)  # the host's ship, named "1"
	var me := _player(5)
	game.continue_solo(5)
	assert_eq(String(me.name), "1")
	assert_same(game.get_node("Players/1"), me, "the HUD finds my ship")


func test_after_host_leaves_new_names_do_not_collide() -> void:
	game.active = true
	_player(5)
	_enemy()  # Enemy7 from the old host
	game.spawn_pickup(Vector2(10, 10), "Pickup4")
	game.continue_solo(5)
	game.spawn_group(1)
	var names := {}
	for c in game.get_node("Enemies").get_children():
		assert_false(names.has(c.name), "unique: %s" % c.name)
		names[c.name] = true
	assert_eq(game._pickup_count, 4)


func test_after_host_leaves_my_hits_still_kill() -> void:
	game.active = true
	_player(5)
	var e := _enemy()
	game.continue_solo(5)
	var b := _bullet(multiplayer.get_unique_id())
	e._on_area_entered(b)
	await wait_frames(1)  # hit reports reach the host at the end of the frame
	assert_true(not is_instance_valid(e) or e.is_queued_for_deletion())


# --- No spawner: rpc-built world, late-join snapshots ------------------------

func test_world_is_not_built_by_multiplayer_spawners() -> void:
	assert_eq(game.find_children("*", "MultiplayerSpawner").size(), 0,
		"spawners delete the host's nodes on every client when the host leaves")


func test_add_player_and_spawn_enemy_are_idempotent() -> void:
	var data := {"id": 42, "name": "A", "ship": 0, "palette": 0, "color": Color.RED, "pos": Vector2(100, 800)}
	game.add_player(data)
	game.add_player(data)
	assert_eq(game.get_node("Players").get_child_count(), 1)
	assert_eq(game.get_node("Players/42").spawn_data, data)
	var e := {"x": 100.0, "y": 90.0, "type": 0, "group_x": 100.0, "dir": 1.0, "id": 3}
	game.spawn_enemy(e)
	game.spawn_enemy(e)
	assert_eq(game.get_node("Enemies").get_child_count(), 1)


func test_enemy_snapshot_restores_mid_flight() -> void:
	game.spawn_enemy({"x": 150.0, "y": -40.0, "type": 1, "group_x": 200.0, "dir": -1.0, "id": 9})
	var src: Node = game.get_node("Enemies/Enemy9")
	for i in 90:
		src._physics_process(1.0 / 60.0)
	var snap: Dictionary = src.snapshot()
	src.free()
	game.spawn_enemy(snap)  # what a late joiner receives
	var copy: Node = game.get_node("Enemies/Enemy9")
	assert_almost_eq(copy.position, snap.pos, Vector2(0.01, 0.01))
	# Both continue identically from here.
	var twin: Node = EnemyScene.instantiate()
	twin.type = 1
	twin.group_x = 200.0
	twin.zig_dir = -1.0
	twin.position = Vector2(150, -40)
	add_child_autofree(twin)
	twin.restore(snap.time, snap.pos)
	for i in 30:
		copy._physics_process(1.0 / 60.0)
		twin._physics_process(1.0 / 60.0)
	assert_almost_eq(copy.position, twin.position, Vector2(0.01, 0.01))


func test_enemy_leaves_the_bottom_on_every_peer() -> void:
	var e := _enemy(Vector2(270, EnemyScene.instantiate().EXIT_Y + 1.0))
	e._physics_process(0.016)
	assert_true(not is_instance_valid(e) or e.is_queued_for_deletion())


func test_host_removes_disconnected_player_everywhere() -> void:
	_player(42)
	game._on_peer_disconnected(42)
	assert_true(game.get_node("Players/42").is_queued_for_deletion())


func test_ships_only_sync_to_peers_that_have_the_world() -> void:
	game._add_player(1, "Host", 0, 0)
	assert_true(game._peer_has_world(1), "host always has it")
	assert_false(game._peer_has_world(77), "a joiner still catching up")
	game.peer_ready(77)
	assert_true(game._peer_has_world(77))
	game.remove_player(77)
	assert_false(game._peer_has_world(77))
