extends GutTest
## Search and rescue: shot-down enemies launch escape pods with a flashing green
## beacon that drift off screen; buying RESCUE adds a button that launches an
## option-sized drone which collects pods and brings them home for exp and score.

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
	for i in PowerMeter.slot_index(&"rescue") + 1:
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade())


func _pod(pos: Vector2, pod_name := "Pod1") -> Node2D:
	game.spawn_pod(pos, 0, pod_name)
	return game.get_node("Pods/" + pod_name)


func _fly(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		player._simulate(1.0 / 60.0)
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
	assert_true(player.drone_out)
	player._gather_input()
	assert_false(bar.press(&"rescue"), "greyed out while it's out")


func test_drone_is_an_option_sized_copy() -> void:
	_buy_rescue()
	player.launch_drone()
	player._process(0.0)
	var s: Sprite2D = player._drone_sprite
	assert_true(s.visible)
	assert_same(s.texture, player.body.texture)
	assert_almost_eq(s.scale, player.body.scale * PlayerScript.OPTION_SCALE, Vector2(0.0001, 0.0001))


func test_cannot_launch_without_rescue() -> void:
	assert_false(player.launch_drone())


func test_drone_fetches_pods_and_brings_them_home() -> void:
	_buy_rescue()
	var exp_before: int = player.exp_total
	_pod(Vector2(100, 200), "Pod1")
	_pod(Vector2(400, 150), "Pod2")
	player.launch_drone()
	_fly(4.0)
	assert_eq(game.get_node("Pods").get_child_count(), 0, "both picked up")
	assert_false(player.drone_out, "back home")
	assert_eq(player.exp_total, exp_before + 2)
	assert_eq(game.score, 2 * game.RESCUE_POINTS)


func test_drone_carries_at_most_capacity() -> void:
	_buy_rescue()
	for i in PlayerScript.DRONE_CAPACITY + 2:
		_pod(Vector2(60 + i * 60, 200), "Pod%d" % i)
	player.launch_drone()
	_fly(5.0)
	assert_false(player.drone_out)
	assert_eq(game.get_node("Pods").get_child_count(), 2, "left the rest")


func test_drone_comes_back_with_nothing_to_find() -> void:
	_buy_rescue()
	player.launch_drone()
	_fly(0.1)
	assert_false(player.drone_out)
	assert_eq(game.score, 0)


func test_pod_claimed_by_someone_else_is_skipped() -> void:
	_buy_rescue()
	var pod := _pod(Vector2(100, 200))
	game.request_rescue("Pod1")  # another drone got there first (as us here; host marks it taken)
	assert_true(pod.taken)
	assert_eq(player._drone_target(), null)


func test_ship_lost_loses_the_drone_and_its_pods() -> void:
	_buy_rescue()
	_pod(Vector2(270, 700))
	player.launch_drone()
	_fly(0.3)
	assert_eq(player.drone_carrying, 1)
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(0.016)
	assert_false(player.drone_out)
	assert_eq(player.drone_carrying, 0)
	assert_eq(game.score, 0)


func test_drone_replicates() -> void:
	var cfg: SceneReplicationConfig = player.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:drone_out")))
	assert_true(cfg.has_property(NodePath(".:drone_pos")))


func test_stop_clears_pods() -> void:
	_pod(Vector2(100, 200))
	game.stop()
	assert_true(game.get_node("Pods/Pod1").is_queued_for_deletion())
