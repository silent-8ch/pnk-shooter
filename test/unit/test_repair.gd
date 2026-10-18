extends GutTest
## ARMOR (more max hp) and REPAIR (a button that drops a repair kit shaped like
## your ship; the first damaged ship over it heals).

const PlayerScript := preload("res://scripts/player.gd")
const RepairScript := preload("res://scripts/repair_kit.gd")

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
	player.position = Vector2(270, 700)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _buy(id: StringName) -> void:
	for i in player.price(id):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(id), "bought %s" % id)


func _kits() -> Array:
	return game.get_node("Pickups").get_children().filter(func(n): return n.is_in_group("repair_kit"))


func test_armor_adds_max_hp() -> void:
	_buy(&"armor")
	assert_eq(player.max_hp(), PlayerScript.MAX_HP + PlayerScript.HIT_HP)
	assert_eq(player.hp, PlayerScript.MAX_HP + PlayerScript.HIT_HP)
	assert_false(player.can_upgrade(&"armor"), "tier I max 1")
	assert_eq(PowerMeter.max_level(&"armor", 2), 2)


func test_armor_is_lost_with_the_ship() -> void:
	_buy(&"armor")
	player.take_damage(player.hp)
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_eq(player.hp, PlayerScript.MAX_HP)


func test_repair_slot_adds_the_button() -> void:
	player._gather_input()
	assert_false(bar.is_shown(&"repair"))
	_buy(&"repair")
	player._gather_input()
	assert_true(bar.is_shown(&"repair"))


func test_button_drops_a_kit_that_looks_like_you() -> void:
	_buy(&"repair")
	player._gather_input()
	assert_true(bar.press(&"repair"))
	player._gather_input()
	player._simulate(0.01)
	assert_eq(_kits().size(), 1)
	var kit: Node = _kits()[0]
	assert_eq(kit.position, player.position)
	assert_eq(kit.body.texture, player.body.texture)
	assert_almost_eq(kit.body.scale.x, player.body.scale.x * RepairScript.SCALE, 0.0001)


func test_cannot_drop_without_repair_or_during_cooldown() -> void:
	assert_false(player.drop_repair())
	_buy(&"repair")
	assert_true(player.drop_repair())
	assert_false(player.drop_repair(), "cooling down")
	player._simulate(PlayerScript.REPAIR_COOLDOWN + 0.01)
	assert_true(player.drop_repair())
	assert_eq(_kits().size(), 2)
	assert_ne(_kits()[0].name, _kits()[1].name)


func test_damaged_ship_heals_from_a_kit() -> void:
	_buy(&"repair")
	player.drop_repair()
	var kit: Node = _kits()[0]
	player.take_damage(2)
	kit._age = RepairScript.ARM_TIME
	kit.claim_from([player])
	assert_eq(player.hp, PlayerScript.MAX_HP - PlayerScript.HIT_HP)
	assert_eq(_kits().size(), 0, "used up")


func test_full_health_ship_leaves_it() -> void:
	_buy(&"repair")
	player.drop_repair()
	var kit: Node = _kits()[0]
	kit._age = RepairScript.ARM_TIME
	kit.claim_from([player])
	assert_eq(_kits().size(), 1)


func test_kit_waits_before_it_can_be_taken() -> void:
	_buy(&"repair")
	player.drop_repair()
	player.take_damage(1)
	var kit: Node = _kits()[0]
	kit.claim_from([player])
	assert_eq(_kits().size(), 1, "not armed yet")


func test_heal_stops_at_max() -> void:
	player.heal(5)
	assert_eq(player.hp, PlayerScript.MAX_HP)


func test_another_player_takes_it() -> void:
	game.spawn_repair(Vector2(10, 10), "Repair1_9", 0, 0)
	game.take_repair("Repair1_9", 2)
	assert_eq(_kits().size(), 0)
	assert_eq(player.hp, PlayerScript.MAX_HP, "peer 2 healed, not us")


func test_kit_blinks_out() -> void:
	game.spawn_repair(Vector2(10, 10), "Repair1_9", 0, 0)
	var kit: Node = _kits()[0]
	kit._process(RepairScript.LIFETIME + 0.1)
	assert_true(kit.is_queued_for_deletion())


func test_six_buttons_fit_the_bar() -> void:
	for a in ActionBar.ACTIONS:
		bar.set_shown(a.id, true)
	var last := bar.button_rect(ActionBar.ACTIONS.size() - 1)
	assert_lte(last.end.x, bar.bar_rect().end.x)
	assert_gt(bar.button_rect(1).position.x, bar.button_rect(0).end.x, "no overlap")
