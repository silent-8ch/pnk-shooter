extends GutTest
## A pod that blows up leaves two tiny astronauts: bullets and blasts pass
## through them, and only a rescue drone can save them. A lost ship's tail
## spills out as astronauts too. Heals, rescues and hand-overs each have a sound.

const PlayerScript := preload("res://scripts/player.gd")
const PodScript := preload("res://scripts/escape_pod.gd")
const StationScript := preload("res://scripts/station.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScene := preload("res://scenes/bullet.tscn")

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


func _pods() -> Node:
	return game.get_node("Pods")


func _blow_up(pos := Vector2(200, 300)) -> Array:
	game.spawn_pod(pos, EnemyScript.WEAVER, "Pod1")
	game.destroy_pod("Pod1")
	return [_pods().get_node("Pod1_A"), _pods().get_node("Pod1_B")]


func _fly(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		player._simulate(1.0 / 60.0)
		for pod in game.get_node("Pods").get_children():
			pod._process(1.0 / 60.0)  # they drift as the drones chase them
		t += 1.0 / 60.0


# --- Astronauts ------------------------------------------------------------------

func test_astronauts_dont_flash() -> void:
	var a: Area2D = _blow_up()[0]
	for i in 120:
		a._process(1.0 / 60.0)
		assert_false(a.beacon.enabled, "no green light")
		assert_eq(a.body.modulate, Color.WHITE)


func test_destroyed_pod_leaves_two_astronauts_drifting_apart() -> void:
	var pair := _blow_up()
	var pod := _pods().get_node_or_null("Pod1")
	assert_true(pod == null or pod.is_queued_for_deletion(), "the pod's gone")
	for a in pair:
		assert_true(a.astronaut)
		assert_lt(a.position.distance_to(Vector2(200, 300)), 10.0, "where it blew up")
		assert_almost_eq(a.velocity.length(), PodScript.ASTRONAUT_SPEED, 0.001)
		assert_true(a.is_in_group("escape_pod"), "drones can find them")
		assert_false(a.is_player_pod())
	assert_ne(pair[0].velocity, pair[1].velocity, "they go separate ways")
	assert_same(pair[0].body.texture, PodScript.astronaut_texture())


func test_astronauts_are_tiny() -> void:
	var tex := PodScript.astronaut_texture()
	assert_lt(tex.get_height(), EnemyScript.HEIGHT * PodScript.SCALE, "smaller than a pod")


func test_astronauts_tumble() -> void:
	var a: Node = _blow_up()[0]
	a._process(0.5)
	assert_ne(a.body.rotation, 0.0)


func test_astronauts_are_indestructible() -> void:
	var pair := _blow_up()
	game.report_pod_hit("Pod1_A", 1.0)
	game.blast(pair[1].position, 50.0)
	game.destroy_pod("Pod1_B")
	assert_true(_pods().has_node("Pod1_A"))
	assert_true(_pods().has_node("Pod1_B"))
	assert_false(pair[0].taken)


func test_bullets_pass_through_astronauts() -> void:
	var a: Node = _blow_up()[0]
	assert_eq(a.collision_mask, 0, "nothing to hit")
	var b: Area2D = BulletScene.instantiate()
	b.shooter = 1
	b.position = a.position
	game.get_node("Bullets").add_child(b)
	a._on_area_entered(b)
	assert_false(b.is_queued_for_deletion(), "flies on")
	assert_true(_pods().has_node(String(a.name)))


func test_only_drones_rescue_astronauts() -> void:
	var a: Node = _blow_up()[0]
	game.request_rescue(String(a.name), false)
	assert_true(_pods().has_node(String(a.name)), "not by touch")
	game.request_rescue(String(a.name), true)
	assert_true(a.is_queued_for_deletion(), "a drone's claim takes it")


func test_drones_bring_astronauts_into_the_tail() -> void:
	player.levels[&"rescue"] = 1
	player.levels[&"drones"] = 1
	assert_true(player.add_power(&"drones"))
	_blow_up(Vector2(270, 650))
	player.launch_drone()
	_fly(8.0)
	assert_eq(_pods().get_child_count(), 0)
	assert_eq(player.tail, [PodScript.ASTRONAUT, PodScript.ASTRONAUT])
	player._process(0.0)
	assert_same(player._tail_sprites[0].texture, PodScript.astronaut_texture())
	assert_false(player._tail_sprites[0].flip_v)


func test_station_takes_astronauts_for_exp() -> void:
	player._add_to_tail([PodScript.ASTRONAUT, EnemyScript.TANK])
	var exp_before: int = player.exp_total
	game.spawn_station(player.position + Vector2(0, -40), "Station1")
	var st: Node2D = game.get_node("Stations/Station1")
	player._simulate(0.016)
	assert_eq(player.exp_total, exp_before + 2)
	assert_same(st.get_child(0).texture, PodScript.astronaut_texture())


# --- A lost ship's tail ---------------------------------------------------------

func test_lost_ship_spills_its_tail_as_astronauts() -> void:
	player._add_to_tail([EnemyScript.WEAVER, PodScript.ASTRONAUT])
	player._process(0.0)
	player.take_damage(player.hp + player.shield + player.rear_shield)
	assert_eq(player.tail.size(), 0)
	var astronauts := _pods().get_children().filter(func(n): return n.astronaut)
	assert_eq(astronauts.size(), 3, "two from the pod, one astronaut")
	for a in astronauts:
		assert_true(String(a.name).begins_with("Astronaut1_"))
		assert_eq(a.owner_peer, 0)


func test_released_astronauts_must_carry_the_senders_id() -> void:
	game.release_astronauts(["Astronaut7_1"], [Vector2(10, 10)])
	assert_eq(_pods().get_child_count(), 0)
	game.release_astronauts(["Astronaut1_1"], [Vector2(10, 10)])
	assert_eq(_pods().get_child_count(), 1)


# --- Sounds ----------------------------------------------------------------------

func test_heal_plays_a_sound_only_when_it_heals() -> void:
	var heal: AudioStreamPlayer = game.get_node("HealSound")
	player.heal(1.0)
	assert_false(heal.playing, "already at full health")
	player.hp = 10.0
	player.heal(1.0)
	assert_true(heal.playing)


func test_full_repair_plays_the_heal_sound() -> void:
	var heal: AudioStreamPlayer = game.get_node("HealSound")
	player.repair_fully()
	assert_false(heal.playing, "nothing to repair")
	player.hp = 10.0
	player.repair_fully()
	assert_true(heal.playing)


func test_rescue_plays_a_sound() -> void:
	game.spawn_pod(Vector2(100, 100), 0, "Pod1")
	game.request_rescue("Pod1")
	assert_true(game.get_node("RescueSound").playing)


func test_hand_over_plays_a_sound() -> void:
	player._add_to_tail([EnemyScript.WEAVER])
	game.spawn_station(player.position, "Station1")
	player._simulate(0.016)
	assert_true(game.get_node("DockSound").playing)


# --- Cleanup bot ---------------------------------------------------------------------

func _bots() -> Array:
	return game.get_node("Effects").get_children().filter(func(n): return n is CleanupBot)


func test_an_astronaut_left_long_enough_gets_a_cleanup_bot() -> void:
	var a: Area2D = _blow_up()[0]
	game.active = true
	game.level = null
	a._age = PodScript.CLEANUP_AFTER - 1.0
	game._physics_process(0.016)
	assert_eq(_bots().size(), 0, "not yet")
	assert_false(a.taken)
	a._age = PodScript.CLEANUP_AFTER + 0.1
	game._physics_process(0.016)
	assert_eq(_bots().size(), 1)
	assert_true(a.taken, "no drone goes for it now")
	game._physics_process(0.016)
	assert_eq(_bots().size(), 1, "one bot per astronaut")


func test_the_bot_flies_in_from_the_near_side_grabs_it_and_leaves() -> void:
	var a: Area2D = _blow_up(Vector2(120, 300))[0]
	game.send_cleanup_bot(String(a.name), "Cleanup1")
	var bot: Node2D = _bots()[0]
	assert_lt(bot.position.x, 0.0, "from the left, the nearer side")
	var score: int = game.score
	for i in 600:
		a.velocity = Vector2.ZERO
		bot._process(1.0 / 60.0)
		if bot.carrying:
			break
	assert_true(bot.carrying)
	assert_false(is_instance_valid(a) and a.is_inside_tree(), "astronaut gone")
	for i in 600:
		if bot.is_queued_for_deletion():
			break
		bot._process(1.0 / 60.0)
	assert_true(bot.is_queued_for_deletion(), "back off the screen")
	assert_eq(game.score, score, "nobody gets credit")
	assert_eq(player.tail.size(), 0)


func test_players_astronauts_are_never_cleaned_up_and_never_leave_the_screen() -> void:
	game.spawn_player_pod(Vector2(30, 600), "PlayerPod1_1", Color.RED, 0, 0)
	game.destroy_pod("PlayerPod1_1")
	var a: Area2D = _pods().get_node("PlayerPod1_1_A")
	assert_true(a.is_player_pod() and a.astronaut)
	a._age = PodScript.CLEANUP_AFTER * 10.0
	assert_false(a.needs_cleanup())
	a.velocity = Vector2(-200, 150)
	for i in 600:
		a._process(1.0 / 60.0)
		assert_true(a.position.x >= 0.0 and a.position.x <= 540.0 and a.position.y >= 0.0 and a.position.y <= 960.0 - ActionBar.BAR_HEIGHT)
	assert_true(a.is_inside_tree() and not a.is_queued_for_deletion(), "still waiting")


func test_the_cleanup_bot_is_a_random_ship_in_the_plain_palette() -> void:
	var textures := []
	for i in 12:
		var a: Area2D = _blow_up(Vector2(100 + i * 5, 300))[0]
		game.send_cleanup_bot(String(a.name), "Cleanup%d" % i)
		textures.append(_bots().back().body.texture)
		_pods().get_node("Pod1_B").name = "Spare%d" % i
		_pods().remove_child(a)
		a.free()
	var distinct := {}
	for t in textures:
		distinct[t] = true
	assert_gt(distinct.size(), 1, "ships vary")
	var factory := range(Ships.count()).map(func(k): return Ships.get_lit_texture(k, 0))
	for t in textures:
		assert_has(factory, t, "a ship in Factory colors")
