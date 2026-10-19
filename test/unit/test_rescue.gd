extends GutTest
## Search and rescue: shot-down enemies launch escape pods with a flashing green
## beacon that drift off screen; buying RESCUE drones (and DRONES power to run
## them) adds a button that launches option-sized drones (one per powered unit) which fetch pods one at a time and bring
## them home, where they trail behind the ship until turned in at a station
## (test_station.gd).

const PlayerScript := preload("res://scripts/player.gd")
const PodScript := preload("res://scripts/escape_pod.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")

var game: Node2D
var player: Area2D
var bar: ActionBar
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	bar = game.get_node("PointerControls/ActionBar")
	player = preload("res://scenes/player.tscn").instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 800)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _buy_rescue() -> void:
	for i in player.price(&"rescue"):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(&"rescue"))
	_power_drones(player.levels[&"rescue"])


## DRONES capacity and power for `bars` drones, with the reactor to spare.
func _power_drones(bars: int) -> void:
	player.levels[&"reactor"] = 2 + bars
	player.levels[&"drones"] = bars
	while player.add_power(&"drones"):
		pass


func _pod(pos: Vector2, pod_name := "Pod1") -> Node2D:
	game.spawn_pod(pos, 0, pod_name)
	return game.get_node("Pods/" + pod_name)


func _fly(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		player._simulate(1.0 / 60.0)
		for pod in game.get_node("Pods").get_children():
			pod._process(1.0 / 60.0)  # they drift as the drones chase them
		t += 1.0 / 60.0


func test_shot_down_enemy_launches_a_pod() -> void:
	var e: Area2D = EnemyScene.instantiate()
	e.position = Vector2(120, 300)
	game.get_node("Enemies").add_child(e)
	e.take_damage(99)
	var pods := game.get_node("Pods")
	assert_eq(pods.get_child_count(), 1)
	assert_eq(pods.get_child(0).position, Vector2(120, 300))


func test_rammed_enemy_launches_no_pod() -> void:
	var e: Area2D = EnemyScene.instantiate()
	game.get_node("Enemies").add_child(e)
	e.ram()
	assert_eq(game.get_node("Pods").get_child_count(), 0)


func test_pod_is_option_sized_and_drifts_slowly_off_the_nearest_side() -> void:
	var pod := _pod(Vector2(100, 300))
	var body: Sprite2D = pod.body
	var full := Ships.scale_for(body.texture, EnemyScript().HEIGHT)
	assert_almost_eq(body.scale, full * PodScript.SCALE, Vector2(0.0001, 0.0001))
	var start := pod.position
	pod._process(1.0)
	assert_lt(pod.position.x, start.x, "left half drifts left")
	assert_almost_eq(pod.position.distance_to(start), PodScript.SPEED, 0.01, "slowly")
	var right := _pod(Vector2(450, 300), "Pod2")
	right._process(1.0)
	assert_gt(right.position.x, 450.0)
	for i in 30:
		pod._process(1.0)
	assert_true(pod.is_queued_for_deletion(), "gone off screen")


func EnemyScript():
	return preload("res://scripts/enemy.gd")


func test_pod_beacon_flashes_green() -> void:
	var pod := _pod(Vector2(100, 300))
	assert_eq(pod.beacon.color, PodScript.GREEN)
	assert_eq(pod.beacon.range_item_cull_mask, Ships.LIGHT_MASK, "lights nearby ships")
	var seen := {}
	for i in 60:
		pod._process(1.0 / 60.0)
		seen[pod.beacon.enabled] = true
		assert_eq(pod.beacon.enabled, pod.beacon_on())
	assert_eq(seen.size(), 2, "blinks on and off")
	assert_eq(pod.body.modulate, Color.WHITE, "pod itself isn't tinted")


func test_rescue_slot_adds_the_button_next_to_lasers() -> void:
	player._gather_input()
	assert_false(bar.is_shown(&"rescue"))
	assert_eq(bar.shown_actions(), [0] as Array[int])
	_buy_rescue()
	player._gather_input()
	assert_true(bar.is_shown(&"rescue"))
	var lasers := bar.button_rect(0)
	var rescue := bar.button_rect(ActionBar.ACTIONS.map(func(a): return a.id).find(&"rescue"))
	assert_gt(rescue.position.x, lasers.end.x, "right of lasers")
	assert_eq(rescue.position.y, lasers.position.y)


func test_hidden_button_cannot_be_pressed() -> void:
	assert_false(bar.press(&"rescue"))


func test_button_launches_the_drone() -> void:
	_buy_rescue()
	_pod(Vector2(270, 100))  # something to fetch, so it stays out
	player._gather_input()
	assert_true(bar.press(&"rescue"))
	player._gather_input()
	player._simulate(0.016)
	assert_eq(player.drones.size(), 1)
	player._gather_input()
	assert_false(bar.press(&"rescue"), "greyed out while it's out")


func test_drone_is_an_option_sized_copy() -> void:
	_buy_rescue()
	player.launch_drone()
	player._process(0.0)
	var s: Sprite2D = player._drone_sprites[0]
	assert_true(s.visible)
	assert_same(s.texture, player.body.texture)
	assert_almost_eq(s.scale, player.body.scale * PlayerScript.OPTION_SCALE * PlayerScript.DRONE_SCALE, Vector2(0.0001, 0.0001))
	assert_lt(PlayerScript.DRONE_SCALE, 1.0, "smaller than an option")
	assert_true(s.has_node("Lights"), "emergency lights")


func test_cannot_launch_without_rescue() -> void:
	assert_false(player.launch_drone())


func test_drone_fetches_pods_and_brings_them_home() -> void:
	_buy_rescue()
	var exp_before: int = player.exp_total
	_pod(Vector2(220, 640), "Pod1")
	_pod(Vector2(330, 630), "Pod2")
	player.launch_drone()
	_fly(PlayerScript.DRONE_TIME + 3.0)
	assert_eq(game.get_node("Pods").get_child_count(), 0, "both picked up")
	assert_eq(player.drones.size(), 0, "back home")
	assert_eq(player.tail.size(), 2, "they join the tail")
	assert_eq(player.exp_total, exp_before, "exp comes when they're turned in at a station")
	assert_eq(game.score, 0)


func test_drone_fetches_one_at_a_time_and_comes_back_each_time() -> void:
	_buy_rescue()
	_pod(Vector2(250, 600), "Pod1")
	_pod(Vector2(290, 600), "Pod2")
	player.launch_drone()
	var most := 0
	var tail_when_second_claimed := -1
	for i in 600:
		_fly(1.0 / 60.0)
		most = maxi(most, player.drone_carrying)
		if tail_when_second_claimed < 0 and game.get_node("Pods").get_child_count() == 0:
			tail_when_second_claimed = player.tail.size()
	assert_eq(most, 1, "never more than one on board")
	assert_eq(tail_when_second_claimed, 1, "the first was home before it fetched the second")
	assert_eq(player.tail.size(), 2)


func test_each_rescue_level_adds_a_drone() -> void:
	player.levels[&"rescue"] = 2
	_power_drones(2)
	_pod(Vector2(150, 550), "Pod1")
	_pod(Vector2(390, 550), "Pod2")
	assert_true(player.launch_drone())
	assert_eq(player.drones.size(), 2, "both go out")
	assert_false(player.launch_drone(), "none left at home")
	for i in 300:
		_fly(1.0 / 60.0)
		if game.get_node("Pods").get_child_count() == 0:
			break
	assert_eq(game.get_node("Pods").get_child_count(), 0, "one each, at the same time")
	assert_eq(player.drone_carrying, 2)


func test_rescue_drones_need_drones_power() -> void:
	player.levels[&"rescue"] = 2
	assert_eq(player.drone_count(), 0, "bought, not powered")
	assert_false(player.launch_drone())
	_power_drones(1)
	assert_eq(player.drone_count(), 1, "one bar, one drone")


func test_options_take_drones_power_first() -> void:
	assert_eq(Systems.max_level(&"rescue"), 4)
	player.levels[&"option"] = 1
	player.levels[&"rescue"] = 2
	_power_drones(2)
	assert_eq(player.level(&"option"), 1)
	assert_eq(player.drone_count(), 1, "what's left after the option")


func test_drone_docks_for_good_when_its_time_is_up() -> void:
	_buy_rescue()
	_pod(Vector2(270, 600), "Pod1")
	player.launch_drone()
	player._runs[0].time = PlayerScript.DRONE_TIME
	_fly(1.0)
	assert_eq(player.drones.size(), 0)
	assert_true(game.get_node("Pods").has_node("Pod1"), "left it")


func test_launch_sounds_the_siren() -> void:
	_buy_rescue()
	var siren: AudioStreamPlayer = game.get_node("SirenSound")
	assert_false(siren.playing)
	player.launch_drone()
	assert_true(siren.playing)


func test_with_nothing_to_find_it_looks_around_then_comes_back() -> void:
	_buy_rescue()
	player.launch_drone()
	var farthest := 0.0
	var headings := []
	var t := 0.0
	while t < 12.0 and player.drones.size() > 0:
		_fly(1.0 / 60.0)
		t += 1.0 / 60.0
		if player.drones.size() > 0:
			farthest = maxf(farthest, player.position.distance_to(player.drones[0]))
			if player._runs[0].search == PlayerScript.SEARCH_LOOK_PHASE:
				headings.append(angle_difference(-PI / 2.0, float(player.drone_headings[0])))  # from straight up
	assert_gt(farthest, PlayerScript.DRONE_SEARCH_OUT * 0.7, "goes out")
	assert_false(headings.is_empty(), "hovers and looks")
	assert_lt(headings.min(), -0.8, "looks one way")
	assert_gt(headings.max(), 0.8, "and the other")
	assert_eq(player.drones.size(), 0, "then comes home")
	assert_eq(game.score, 0)


func test_it_can_be_shot_while_looking_around() -> void:
	_buy_rescue()
	player.launch_drone()
	_fly(2.0)
	assert_eq(player.drones.size(), 1)
	game.fire_bullet(player.drones[0], Color.BLUE)
	var b: Area2D = game.get_node("Bullets").get_children().back()
	b._travelled = PlayerScript.DRONE_SAFE_SHOT + 1.0
	_fly(1.0 / 60.0)
	assert_eq(player.drones.size(), 0)


func test_something_turning_up_while_it_looks_gets_fetched() -> void:
	_buy_rescue()
	player.launch_drone()
	_fly(1.0)
	var pod := _pod(Vector2(320, 650))
	pod.velocity = Vector2.ZERO
	_fly(6.0)
	assert_true(pod.taken or not is_instance_valid(pod))


func test_pod_claimed_by_someone_else_is_skipped() -> void:
	_buy_rescue()
	var pod := _pod(Vector2(100, 200))
	game.request_rescue("Pod1")  # another drone got there first (as us here; host marks it taken)
	assert_true(pod.taken)
	assert_eq(player._drone_target(), null)


func test_ship_lost_loses_the_drones_but_lets_their_pods_out() -> void:
	_buy_rescue()
	_pod(Vector2(270, 700))
	player.launch_drone()
	for i in 300:
		_fly(1.0 / 60.0)
		if player.drone_carrying == 1:
			break
	assert_eq(player.drone_carrying, 1)
	var at: Vector2 = player.drones[0]
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(0.016)
	assert_eq(player.drones.size(), 0)
	assert_eq(player.drone_carrying, 0)
	assert_eq(game.score, 0)
	var astronauts := game.get_node("Pods").get_children().filter(func(n): return n.astronaut)
	assert_eq(astronauts.size(), 2, "the pod it carried, as two astronauts")
	for a in astronauts:
		assert_lt(a.position.distance_to(at), 10.0, "where the drone was")


func test_drone_replicates() -> void:
	var cfg: SceneReplicationConfig = player.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:drones")))


func test_stop_clears_pods() -> void:
	_pod(Vector2(100, 200))
	game.stop()
	assert_false(game.has_node("Pods/Pod1"))


# --- Thrusters and danger -------------------------------------------------------------

func _steer_to(goal: Vector2, seconds: float, from := Vector2.ZERO) -> Dictionary:
	var pos := from
	var vel := Vector2.ZERO
	var heading := -PI / 2.0
	var top := 0.0
	var first_burn := -1.0
	var t := 0.0
	var log: Array = []
	while t < seconds:
		var st := PlayerScript.drone_steer(pos, vel, heading, goal, Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
		vel = st.vel
		heading = st.heading
		pos += vel / 60.0
		top = maxf(top, vel.length())
		if st.burning and first_burn < 0.0:
			first_burn = t
		log.append({"pos": pos, "vel": vel, "heading": heading, "burning": st.burning})
		t += 1.0 / 60.0
	return {"pos": pos, "vel": vel, "top": top, "first_burn": first_burn, "log": log}


func test_drones_turn_before_they_burn() -> void:
	var r := _steer_to(Vector2(300, 0), 2.0)  # off to the right; it starts facing up
	assert_gt(r.first_burn, 0.1, "turns first")
	for e in r.log:
		if e.burning:
			assert_lt(absf(angle_difference(e.heading, e.vel.angle())), 1.2, "burns along its heading")
			break


func test_drones_have_a_top_speed() -> void:
	var r := _steer_to(Vector2(0, -3000), 8.0)
	assert_almost_eq(r.top, PlayerScript.DRONE_SPEED, 5.0)


func test_drones_turn_round_and_slow_down_to_arrive() -> void:
	var r := _steer_to(Vector2(0, -400), 8.0)
	assert_lt(r.pos.distance_to(Vector2(0, -400)), PlayerScript.DRONE_REACH, "gets there")
	assert_lt(r.vel.length(), PlayerScript.DRONE_DOCK_SPEED, "and slows down")
	var reversed := false
	for e in r.log:
		if e.burning and e.heading > 0.0:  # facing down while it flies up: braking
			reversed = true
	assert_true(reversed, "flips and burns the other way")


func test_close_and_slow_grabs_at_once() -> void:
	_buy_rescue()
	var pod := _pod(Vector2(270, 600))
	pod.velocity = Vector2.ZERO
	player.launch_drone()
	player.drones = [Vector2(270, 600 + PlayerScript.DRONE_GRAB_RANGE - 5.0)]
	player._runs[0].vel = Vector2(0, -30)
	player._fly_drones(1.0 / 60.0)
	assert_true(pod.taken, "no creeping the last bit")


func test_too_fast_to_grab() -> void:
	_buy_rescue()
	var pod := _pod(Vector2(270, 600))
	player.launch_drone()
	player.drones = [Vector2(270, 600)]
	player._runs[0].vel = Vector2(0, -PlayerScript.DRONE_SPEED)
	player._fly_drones(1.0 / 60.0)
	assert_false(pod.taken, "flew past it")


func test_drones_steer_clear_of_enemies() -> void:
	var e := preload("res://scenes/enemy.tscn").instantiate()
	e.position = Vector2(270, 500)
	game.get_node("Enemies").add_child(e)
	var push: Vector2 = player.drone_avoidance(game, Vector2(290, 520))
	assert_gt(push.x, 0.0)
	assert_gt(push.y, 0.0, "away from it")
	assert_eq(player.drone_avoidance(game, Vector2(270, 900)), Vector2.ZERO)


func _drone_out_at(at: Vector2) -> void:
	_buy_rescue()
	player.launch_drone()
	player.drones = [at]


func test_touching_an_enemy_destroys_a_drone() -> void:
	_drone_out_at(Vector2(270, 400))
	var e := preload("res://scenes/enemy.tscn").instantiate()
	e.position = Vector2(270, 400)
	game.get_node("Enemies").add_child(e)
	player._fly_drones(1.0 / 60.0)
	assert_eq(player.drones.size(), 0, "gone")
	assert_eq(player.drones_ready(), 0, "rebuilding")


func test_touching_an_obstacle_destroys_a_drone() -> void:
	_drone_out_at(Vector2(270, 400))
	game.spawn_obstacle({"name": "Obstacle1", "piece": "asteroid_l", "x": 270.0, "y": 400.0, "count": 1, "dir": 1.0})
	player._fly_drones(1.0 / 60.0)
	assert_eq(player.drones.size(), 0)


func test_any_shot_destroys_a_drone_even_its_owners() -> void:
	_drone_out_at(Vector2(270, 400))
	game.fire_bullet(Vector2(270, 400), Color.RED)
	var b: Area2D = game.get_node("Bullets").get_children().back()
	b._travelled = PlayerScript.DRONE_SAFE_SHOT + 1.0
	player._fly_drones(1.0 / 60.0)
	assert_eq(player.drones.size(), 0)
	assert_true(b.is_queued_for_deletion(), "the shot's used up")


func test_a_shot_leaving_the_muzzle_spares_it() -> void:
	_drone_out_at(Vector2(270, 400))
	game.fire_bullet(Vector2(270, 400), Color.RED)
	player._fly_drones(1.0 / 60.0)
	assert_eq(player.drones.size(), 1)


func test_a_destroyed_drone_spills_what_it_carried_and_rebuilds() -> void:
	_buy_rescue()
	_pod(Vector2(270, 700))
	player.launch_drone()
	for i in 300:
		_fly(1.0 / 60.0)
		if player.drone_carrying == 1:
			break
	assert_eq(player.drone_carrying, 1)
	var at: Vector2 = player.drones[0]
	var e := preload("res://scenes/enemy.tscn").instantiate()
	e.position = at
	game.get_node("Enemies").add_child(e)
	player._fly_drones(1.0 / 60.0)
	assert_eq(player.drone_carrying, 0)
	var astronauts := game.get_node("Pods").get_children().filter(func(n): return n.astronaut)
	assert_eq(astronauts.size(), 2, "the pod, as two astronauts")
	e.queue_free()
	await wait_frames(1)
	assert_false(player.launch_drone(), "still rebuilding")
	_fly(PlayerScript.DRONE_REBUILD + 0.1)
	assert_eq(player.drones_ready(), 1)


func test_drone_faces_its_heading_everywhere() -> void:
	_drone_out_at(Vector2(270, 600))
	_pod(Vector2(450, 600))
	_fly(0.5)
	assert_eq(player.drone_headings.size(), player.drones.size())
	assert_ne(float(player.drone_headings[0]), -PI / 2.0, "turned toward it")
	player._process(0.0)
	assert_almost_eq(player._drone_sprites[0].global_rotation, wrapf(float(player.drone_headings[0]) + PI / 2.0, -PI, PI), 0.01)



func test_lights_flash_red_then_blue() -> void:
	var seen := {}
	for i in 20:
		seen[PlayerScript.drone_light(i * 0.05)] = true
	assert_eq(seen.size(), 2, "both lights take turns")


func test_options_launch_a_set_of_drones_each() -> void:
	_buy_rescue()
	player.levels[&"option"] = 2
	player.levels[&"drones"] = 3
	player.levels[&"reactor"] = 8
	player.add_power(&"option")
	player.add_power(&"option")
	player._simulate(0.016)
	assert_eq(player.options, 2)
	assert_eq(player.drones_ready(), player.drone_count() * 3, "the ship's and each option's")
	assert_true(player.launch_drone())
	assert_eq(player.drones.size(), player.drone_count() * 3)
