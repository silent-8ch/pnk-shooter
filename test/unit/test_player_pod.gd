extends GutTest
## Player escape pods: a destroyed ship drops a pod carrying its upgrades. It
## drifts sideways off screen very slowly and takes a lot of damage to destroy.
## If its owner touches it again, or anyone saves it (ship or rescue drone), the
## owner gets the upgrades back.

const PlayerScript := preload("res://scripts/player.gd")
const PodScript := preload("res://scripts/escape_pod.gd")
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
	player.position = Vector2(200, 700)
	player.spawn_position = Vector2(270, 840)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _buy(id: StringName) -> void:
	for i in player.price(id):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(id), "bought %s" % id)


func _die() -> Node:
	player.take_damage(player.hp + player.shield + player.rear_shield)
	assert_false(player.is_alive())
	var pods := game.get_node("Pods").get_children()
	return pods.back() if not pods.is_empty() else null


func _respawn() -> void:
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_true(player.is_alive())


func test_dying_drops_a_pod_of_your_ship() -> void:
	var pod := _die()
	assert_not_null(pod)
	assert_true(pod.is_player_pod())
	assert_eq(pod.owner_peer, 1)
	assert_eq(pod.position, Vector2(200, 700))
	assert_eq(pod.beacon_color, player.color)
	assert_almost_eq(pod.body.scale.x, player.body.scale.x * PlayerScript.OPTION_SCALE, 0.0001, "option sized")
	assert_true(pod.is_in_group("escape_pod"), "drones can find it")


func test_pod_drifts_sideways_very_slowly() -> void:
	var pod := _die()
	assert_eq(pod.velocity.y, 0.0)
	assert_lt(pod.velocity.x, 0.0, "left half: off the left side")
	assert_lt(pod.velocity.length(), PodScript.SPEED, "slower than an enemy's pod")
	pod.position.x = -PodScript.OFFSCREEN - 1
	pod._process(0.01)
	assert_true(pod.is_queued_for_deletion())


func test_pod_takes_many_hits() -> void:
	var pod := _die()
	var pod_name := String(pod.name)
	for i in int(PodScript.PLAYER_HP) - 1:
		game.report_pod_hit(pod_name, 1.0)
	assert_true(game.get_node("Pods").has_node(pod_name), "still there")
	game.report_pod_hit(pod_name, 1.0)
	assert_false(game.get_node("Pods").has_node(pod_name), "destroyed")


func test_blasts_wear_it_down_too() -> void:
	var pod := _die()
	game.blast(pod.position, 20.0)
	assert_almost_eq(pod.hp, PodScript.PLAYER_HP - game.BLAST_DAMAGE, 0.0001)


func test_every_shot_hits_it_owners_too() -> void:
	var pod := _die()
	for shooter in [1, 2]:
		var b: Area2D = BulletScene.instantiate()
		b.shooter = shooter
		game.get_node("Bullets").add_child(b)
		pod._on_area_entered(b)
		assert_true(b.is_queued_for_deletion(), "shot from %d hits" % shooter)
	assert_almost_eq(pod.hp, PodScript.PLAYER_HP - 1.0, 0.0001, "the local shooter's hit counts")


func test_flashes_when_hit() -> void:
	var pod := _die()
	game.report_pod_hit(String(pod.name), 1.0)
	assert_gt(pod.body.modulate.r, 1.0)
	pod._process(PodScript.FLASH_TIME + 0.01)
	assert_eq(pod.body.modulate, Color.WHITE)


func test_drifts_off_screen_in_reasonable_time() -> void:
	var pod := _die()
	var t := 0.0
	while is_instance_valid(pod) and not pod.is_queued_for_deletion() and t < 30.0:
		pod._process(0.1)
		t += 0.1
	assert_lt(t, 15.0, "gone from x=200 within 15 s")


func test_upgrades_lost_on_respawn_come_back_when_you_touch_your_pod() -> void:
	_buy(&"speed")
	_buy(&"option")
	_buy(&"armor")
	var pod := _die()
	_respawn()
	assert_eq(player.level(&"speed"), 0)
	assert_eq(player.options, 0)
	assert_eq(player.hp, PlayerScript.MAX_HP)
	pod.claim_from([player])
	assert_false(game.get_node("Pods").has_node(String(pod.name)), "picked up")
	assert_eq(player.level(&"speed"), 1)
	assert_eq(player.options, 1)
	assert_eq(player.level(&"armor"), 1)
	assert_eq(player.max_hp(), PlayerScript.MAX_HP + PlayerScript.HIT_HP)
	assert_eq(player.hp, PlayerScript.MAX_HP + PlayerScript.HIT_HP, "armor plating back too")


func test_dead_ship_cannot_pick_it_up() -> void:
	var pod := _die()
	pod.claim_from([player])
	assert_true(game.get_node("Pods").has_node(String(pod.name)))


func test_rescued_by_another_player_while_dead_restores_at_respawn() -> void:
	_buy(&"speed")
	var pod := _die()
	game.rescue_pod(String(pod.name), 2, true, 1)  # peer 2's drone got it
	assert_eq(player.drone_carrying, 0, "not our drone's haul")
	_respawn()
	assert_eq(player.level(&"speed"), 1)


func test_another_ship_can_touch_it_but_drones_only_take_enemy_pods_by_touch() -> void:
	var pod := _die()
	_respawn()
	game.spawn_pod(Vector2(50, 50), 0, "EnemyPod")
	game.request_rescue("EnemyPod", false)
	assert_true(game.get_node("Pods").has_node("EnemyPod"), "enemy pods need a drone")
	game.request_rescue(String(pod.name), false)
	assert_false(game.get_node("Pods").has_node(String(pod.name)))


func test_destroyed_pod_forgets_the_upgrades() -> void:
	_buy(&"speed")
	var pod := _die()
	var pod_name := String(pod.name)
	game.destroy_pod(pod_name)
	_respawn()
	game.rescue_pod(pod_name, 1, false, 1)
	assert_eq(player.level(&"speed"), 0)


func test_restore_keeps_the_better_of_each_upgrade() -> void:
	_buy(&"speed")
	var pod := _die()
	_respawn()
	_buy(&"speed")
	_buy(&"speed")
	_buy(&"option")
	pod.claim_from([player])
	assert_eq(player.level(&"speed"), 2)
	assert_eq(player.options, 1)


func test_each_death_drops_its_own_pod() -> void:
	var a := _die()
	_respawn()
	var b := _die()
	assert_ne(a.name, b.name)
	assert_eq(game.get_node("Pods").get_child_count(), 2)


func test_pod_names_must_carry_the_senders_id() -> void:
	game.spawn_player_pod(Vector2(10, 10), "PlayerPod7_1", Color.RED, 0, 0)
	assert_eq(game.get_node("Pods").get_child_count(), 0, "peer 1 can't name another's pod")
