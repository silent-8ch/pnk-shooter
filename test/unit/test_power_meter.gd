extends GutTest
## PowerMeter: Gradius-style upgrade column on the right; exp collected by the
## local player lights slots in turn, a tap buys the lit upgrade, and the ship
## gets faster, fires faster, fires double, gains options or a shield. Three
## TIER II charges switch the meter to tier II with higher caps; friendly fire.

const PlayerScript := preload("res://scripts/player.gd")

var game: Node2D
var meter: Control
var player: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	meter = game.get_node("PointerControls/PowerMeter")
	player = preload("res://scenes/player.tscn").instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 600)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _tap(pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = pos
	meter._input(ev)


func _collect(n: int) -> void:
	for i in n:
		game.collect_pickup("none", 1)


func _buy(id: StringName) -> void:
	_collect(PowerMeter.slot_index(id) + 1)
	assert_true(player.buy_upgrade(), "bought %s" % id)


func test_sits_on_the_right_above_the_action_bar() -> void:
	var screen := meter.get_viewport_rect().size
	var r: Rect2 = meter.meter_rect()
	assert_gt(r.position.x, screen.x * 0.75, "right side")
	assert_lte(r.end.x, screen.x)
	assert_lte(r.end.y, screen.y - ActionBar.BAR_HEIGHT)
	assert_eq(PowerMeter.SLOTS.map(func(s): return s.id), [&"speed", &"rapid", &"double", &"option", &"shield", &"rescue", &"missile", &"auto", &"beam", &"tier"])


func test_each_exp_lights_the_next_slot_and_wraps() -> void:
	assert_eq(player.lit_slot(), -1)
	var n := PowerMeter.slots_for(1).size()
	for i in n + 1:
		_collect(1)
		assert_eq(player.lit_slot(), i % n)
	assert_eq(player.exp_total, n + 1, "counts every exp")


func test_only_the_takers_ship_gets_the_exp() -> void:
	game.collect_pickup("none", 42)
	assert_eq(player.exp_total, 0)
	assert_eq(player.lit_slot(), -1)


func test_collecting_a_pickup_counts() -> void:
	game.spawn_pickup(Vector2(100, 100), "Pickup1")
	game.request_pickup("Pickup1")
	assert_eq(player.exp_total, 1)
	assert_true(game.get_node("Pickups/Pickup1").collected)


func test_tap_buys_the_lit_slot_and_spends_the_exp() -> void:
	_collect(1)
	_tap(meter.slot_rect(3).get_center())  # anywhere on the meter buys the lit one
	assert_eq(player.level(&"speed"), 1)
	assert_eq(player.lit_slot(), -1)
	assert_eq(player.exp_total, 1, "counter keeps the total")


func test_tap_with_nothing_lit_does_nothing() -> void:
	_tap(meter.slot_rect(0).get_center())
	assert_eq(player.level(&"speed"), 0)


func test_tap_is_ignored_when_input_disabled() -> void:
	_collect(1)
	game.input_enabled = false
	_tap(meter.slot_rect(0).get_center())
	assert_eq(player.level(&"speed"), 0)


func test_meter_taps_do_not_move_the_ship() -> void:
	var pointer: Control = game.get_node("PointerControls/Control")
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = meter.slot_rect(1).get_center()
	pointer._input(ev)
	assert_false(pointer.has_target)


func test_speed_makes_the_ship_faster() -> void:
	var base: float = player.move_speed()
	_buy(&"speed")
	assert_almost_eq(player.move_speed(), base * (1.0 + PlayerScript.SPEED_STEP), 0.001)
	var x: float = player.position.x
	player.input_dir = Vector2.LEFT
	player._simulate(0.1)
	assert_almost_eq(x - player.position.x, player.move_speed() * 0.1, 0.01)


func test_rapid_shortens_the_cooldown_on_ship_and_button() -> void:
	_buy(&"rapid")
	assert_almost_eq(player.fire_cooldown(), PlayerScript.FIRE_COOLDOWN * PlayerScript.RAPID_STEP, 0.0001)
	player._gather_input()
	var bar: ActionBar = game.get_node("PointerControls/ActionBar")
	assert_almost_eq(bar.cooldown_for(&"lasers"), player.fire_cooldown(), 0.0001)
	assert_true(bar.press(&"lasers"))
	assert_almost_eq(bar.cooldown_left(&"lasers"), player.fire_cooldown(), 0.0001)


func test_double_fires_two_side_by_side() -> void:
	_buy(&"double")
	player._fire_requested = true
	player._simulate(0.016)
	var bullets := game.get_node("Bullets").get_children()
	assert_eq(bullets.size(), 2)
	assert_eq(bullets[0].position.y, bullets[1].position.y)
	assert_almost_eq(absf(bullets[0].position.x - bullets[1].position.x), PlayerScript.DOUBLE_SPREAD * 2, 0.01)


func test_shield_absorbs_hits_before_hp() -> void:
	_buy(&"shield")
	assert_eq(player.shield, PlayerScript.SHIELD_HITS)
	for i in PlayerScript.SHIELD_HITS:
		player.take_damage(1)
	assert_eq(player.hp, PlayerScript.MAX_HP)
	assert_eq(player.shield, 0)
	player.take_damage(1)
	assert_eq(player.hp, PlayerScript.MAX_HP - 1)


func test_maxed_slot_cannot_be_bought_and_keeps_the_exp() -> void:
	_buy(&"double")
	_collect(PowerMeter.slot_index(&"double") + 1)
	assert_false(player.can_upgrade(&"double"))
	assert_false(player.buy_upgrade())
	assert_eq(player.lit_slot(), PowerMeter.slot_index(&"double"), "still banked")


func test_shield_can_be_bought_again_once_used_up() -> void:
	_buy(&"shield")
	assert_false(player.can_upgrade(&"shield"))
	for i in PlayerScript.SHIELD_HITS:
		player.take_damage(1)
	assert_true(player.can_upgrade(&"shield"))


func test_upgrades_are_lost_when_destroyed_but_exp_count_stays() -> void:
	_buy(&"speed")
	_buy(&"shield")
	player.shield = 0
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_true(player.is_alive())
	assert_eq(player.level(&"speed"), 0)
	assert_eq(player.exp_total, 1 + PowerMeter.slot_index(&"shield") + 1)


func test_shield_replicates() -> void:
	var cfg: SceneReplicationConfig = player.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:shield")))


func test_option_trails_the_flown_path() -> void:
	_buy(&"option")
	assert_eq(player.options, 1)
	player._process(0.0)
	assert_eq(player.option_positions(), [player.position] as Array[Vector2], "starts on the ship")
	player.input_dir = Vector2.RIGHT
	for i in 30:
		player._simulate(1.0 / 60.0)
		player._update_options()  # _process would overwrite input_dir
	var opt: Vector2 = player.option_positions()[0]
	assert_almost_eq(opt, player.position - Vector2(PlayerScript.OPTION_GAP, 0), Vector2.ONE * PlayerScript.TRAIL_STEP, "a gap behind on the path")
	var sprite: Sprite2D = player._option_sprites[0]
	assert_almost_eq(sprite.global_position, player.get_parent().to_global(opt), Vector2(0.01, 0.01))
	assert_almost_eq(sprite.scale, player.body.scale * PlayerScript.OPTION_SCALE, Vector2(0.0001, 0.0001), "small copy")
	assert_same(sprite.texture, player.body.texture)


func test_options_fire_what_the_ship_fires() -> void:
	_buy(&"option")
	_buy(&"option")
	_buy(&"double")
	player._process(0.0)
	player._fire_requested = true
	player._simulate(0.016)
	assert_eq(game.get_node("Bullets").get_child_count(), 6, "ship + 2 options, double each")


func test_second_option_sits_further_back() -> void:
	_buy(&"option")
	_buy(&"option")
	player._process(0.0)
	player.input_dir = Vector2.UP
	for i in 60:
		player._simulate(1.0 / 60.0)
		player._update_options()  # _process would overwrite input_dir
	var at: Array[Vector2] = player.option_positions()
	assert_almost_eq(at[1].y - at[0].y, PlayerScript.OPTION_GAP, 1.0)
	assert_false(player.can_upgrade(&"option"), "max 2")


func test_options_lost_on_death_and_replicated() -> void:
	_buy(&"option")
	player._process(0.0)
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	player._process(0.0)
	assert_eq(player.options, 0)
	assert_eq(player._option_sprites.size(), 0)
	var cfg: SceneReplicationConfig = player.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:options")))


func _tier2() -> void:
	for i in PowerMeter.TIER_CHARGES:
		_buy(&"tier")
	assert_eq(player.tier, 2)


func test_tier_ii_is_the_last_slot_and_takes_three_charges() -> void:
	assert_eq(PowerMeter.slots_for(1).back().id, &"tier")
	assert_eq(PowerMeter.slots_for(1).back().label, "TIER II")
	_buy(&"tier")
	_buy(&"tier")
	assert_eq(player.tier, 1)
	assert_eq(player.level(&"tier"), 2)
	_buy(&"tier")
	assert_eq(player.tier, 2, "menu changes")
	assert_eq(player.lit_slot(), -1)


func test_tier_ii_menu_drops_the_tier_slot_and_raises_caps() -> void:
	var ids := PowerMeter.slots_for(2).map(func(s): return s.id)
	assert_eq(ids, [&"speed", &"rapid", &"double", &"option", &"shield", &"rescue", &"missile", &"auto", &"beam"])
	assert_eq(PowerMeter.max_level(&"speed", 2), 6)
	assert_eq(PowerMeter.max_level(&"rapid", 2), 6)
	assert_eq(PowerMeter.max_level(&"double", 2), 2)
	assert_eq(PowerMeter.max_level(&"option", 2), 3)
	assert_eq(PowerMeter.max_level(&"shield", 2), 2)
	_tier2()
	var n := PowerMeter.slots_for(2).size()
	for i in n:  # exp now wraps over the tier II slots
		_collect(1)
	assert_eq(player.lit_slot(), n - 1)
	_collect(1)
	assert_eq(player.lit_slot(), 0)


func test_tier_ii_speed_and_rapid_go_to_six() -> void:
	for i in 3:
		_buy(&"speed")
	assert_false(player.can_upgrade(&"speed"), "tier I caps at 3")
	_tier2()
	for i in 3:
		_buy(&"speed")
		_buy(&"rapid")
	assert_eq(player.level(&"speed"), 6)
	assert_false(player.can_upgrade(&"speed"))
	assert_true(player.can_upgrade(&"rapid"))


func test_tier_ii_double_becomes_triple() -> void:
	_tier2()
	_buy(&"double")
	_buy(&"double")
	assert_eq(PowerMeter.label_for(PowerMeter.SLOTS[2], 2, player.level(&"double")), "TRIPLE")
	player._fire_requested = true
	player._simulate(0.016)
	var xs := game.get_node("Bullets").get_children().map(func(b): return b.position.x - player.position.x)
	xs.sort()
	assert_eq(xs, [-PlayerScript.TRIPLE_SPREAD, 0.0, PlayerScript.TRIPLE_SPREAD])


func test_tier_ii_third_option() -> void:
	_tier2()
	for i in 3:
		_buy(&"option")
	assert_eq(player.options, 3)
	assert_false(player.can_upgrade(&"option"))


func test_tier_ii_shield_level_two_guards_behind() -> void:
	_tier2()
	_buy(&"shield")
	_buy(&"shield")
	assert_eq(player.shield, PlayerScript.SHIELD_HITS)
	assert_eq(player.rear_shield, PlayerScript.SHIELD_HITS)
	player.take_damage(1, true)
	assert_eq(player.rear_shield, PlayerScript.SHIELD_HITS - 1, "hit from behind takes the rear shield")
	assert_eq(player.shield, PlayerScript.SHIELD_HITS)
	assert_eq(player.hp, PlayerScript.MAX_HP)
	var cfg: SceneReplicationConfig = player.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:rear_shield")))


func test_front_shield_does_not_guard_behind() -> void:
	_buy(&"shield")
	player.take_damage(1, true)
	assert_eq(player.hp, PlayerScript.MAX_HP - 1)
	assert_eq(player.shield, PlayerScript.SHIELD_HITS)


func test_tier_lost_on_death() -> void:
	_tier2()
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_eq(player.tier, 1)
	assert_eq(player.level(&"tier"), 0)


func _bullet(shooter: int, pos: Vector2) -> Area2D:
	var b: Area2D = preload("res://scenes/bullet.tscn").instantiate()
	b.shooter = shooter
	b.position = pos
	game.get_node("Bullets").add_child(b)
	return b


func test_friendly_fire_hurts() -> void:
	assert_eq(player.collision_mask & 4, 4, "players detect bullets")
	var b := _bullet(42, player.position + Vector2(0, 10))
	player._on_area_entered(b)
	assert_eq(player.hp, PlayerScript.MAX_HP - 1)
	assert_true(b.is_queued_for_deletion())


func test_own_shots_pass_through() -> void:
	var b := _bullet(1, player.position)
	player._on_area_entered(b)
	assert_eq(player.hp, PlayerScript.MAX_HP)
	assert_false(b.is_queued_for_deletion())


func test_friendly_fire_from_behind_hits_the_rear_shield() -> void:
	_tier2()
	_buy(&"shield")
	_buy(&"shield")
	player._on_area_entered(_bullet(42, player.position + Vector2(0, 10)))
	assert_eq(player.rear_shield, PlayerScript.SHIELD_HITS - 1)
	player._on_area_entered(_bullet(42, player.position + Vector2(0, -10)))
	assert_eq(player.shield, PlayerScript.SHIELD_HITS - 1)


func test_remote_ship_removes_the_bullet_but_takes_no_damage_here() -> void:
	var other: Area2D = preload("res://scenes/player.tscn").instantiate()
	other.name = "42"
	other.peer_id = 42
	game.get_node("Players").add_child(other)
	var b := _bullet(1, other.position)
	other._on_area_entered(b)
	assert_true(b.is_queued_for_deletion())
	assert_eq(other.hp, PlayerScript.MAX_HP, "its owner decides")
