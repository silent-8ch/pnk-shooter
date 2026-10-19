extends GutTest
## FTL-style systems: a REACTOR of power bars shared by SYSTEMS whose capacity
## is bought with exp. Bought capacity comes unpowered; what a system does
## follows its power. Guns are bought, then armed on WEAPONS power. Everything
## resets to the start loadout on death; the escape pod carries it back.

const PlayerScript := preload("res://scripts/player.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var player: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	player = PlayerScene.instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 600)
	player.spawn_position = Vector2(270, 840)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


## Buys the next level of `id`, handing the player exactly its price first.
func _buy(id: StringName) -> void:
	player.exp_balance += player.price(id)
	assert_true(player.buy_upgrade(id), "bought %s" % id)


func _buy_n(id: StringName, n: int) -> void:
	for i in n:
		_buy(id)


## Buys `n` bars of `system` and powers them, buying reactor bars as needed.
func _powered(system: StringName, n: int) -> void:
	while player.levels.get(system, 0) < n:
		_buy(system)
	while player.power_of(system) < n:
		if player.power_spare() <= 0:
			_buy(&"reactor")
		if not player.add_power(system):
			fail_test("couldn't power %s to %d" % [system, n])
			return


func _ship(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _die() -> Node:
	player.take_damage(player.hp + player.shield + player.rear_shield)
	assert_false(player.is_alive())
	var pods := game.get_node("Pods").get_children()
	return pods.back() if not pods.is_empty() else null


func _respawn() -> void:
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_true(player.is_alive())


func _start_levels() -> Dictionary:
	var out := {}
	for it in Systems.ITEMS:
		if it.get("start", 0) > 0:
			out[it.id] = it.start
	return out


# --- Start loadout ---------------------------------------------------------------

func test_start_loadout() -> void:
	assert_eq(player.reactor(), 3)
	assert_eq(player.levels, {&"reactor": 3, &"engines": 1, &"weapons": 1, &"lasers": 1, &"autopilot": 1, &"beacon": 1})
	assert_eq(player.power_of(&"engines"), 1)
	assert_eq(player.power_of(&"weapons"), 1)
	assert_eq(player.power_of(&"shields"), 0)
	assert_eq(player.power_used(), 2)
	assert_eq(player.power_spare(), 1)
	assert_true(player.is_armed(&"lasers"))
	assert_eq(player.armed.keys(), [&"lasers"])
	assert_eq(player.weapons_used(), 1)
	assert_eq(player.shield, 0)
	assert_eq(player.rear_shield, 0)


func test_start_loadout_matches_systems_constants() -> void:
	assert_eq(player.levels, _start_levels())
	assert_eq(player.power, Systems.START_POWER)
	for g in Systems.START_ARMED:
		assert_true(player.is_armed(g), String(g))


func test_start_power_fits_the_reactor_and_capacity() -> void:
	var used := 0
	for s in Systems.START_POWER:
		assert_true(Systems.is_system(s), String(s))
		assert_lte(Systems.START_POWER[s], Systems.start_level(s), "%s powered within capacity" % s)
		used += Systems.START_POWER[s]
	assert_lte(used, Systems.start_level(&"reactor"))


# --- Prices -------------------------------------------------------------------------

func test_prices_count_from_start() -> void:
	assert_eq(Systems.price(&"reactor", 3), 2, "first bar past the start")
	assert_eq(Systems.price(&"reactor", 4), 4)
	assert_eq(Systems.price(&"engines", 1), 1)
	assert_eq(Systems.price(&"engines", 2), 2)
	assert_eq(Systems.price(&"weapons", 1), 2)
	assert_eq(Systems.price(&"shields", 0), 3)
	assert_eq(Systems.price(&"shields", 1), 6)
	assert_eq(Systems.price(&"beam", 0), 6)
	assert_eq(Systems.price(&"option", 1), 8)
	assert_eq(Systems.price(&"nope", 0), 0, "unknown item")
	for it in Systems.ITEMS:
		if Systems.is_builtin(it.id):
			continue  # nothing to buy
		assert_gt(it.cost, 0, String(it.id))


func test_player_prices_climb_with_each_level() -> void:
	assert_eq(player.price(&"engines"), 1)
	_buy(&"engines")
	assert_eq(player.price(&"engines"), 2, "next level costs more")
	_buy(&"engines")
	assert_eq(player.price(&"engines"), 3)
	assert_eq(player.price(&"reactor"), 2)
	_buy(&"reactor")
	assert_eq(player.price(&"reactor"), 4)


func test_exp_adds_to_balance_and_total() -> void:
	game.collect_pickup("none", 1)
	var got: int = player.exp_balance
	assert_gt(got, 0)
	assert_eq(player.exp_total, got)
	player.exp_balance = 5
	assert_true(player.buy_upgrade(&"weapons"))  # costs 2
	assert_eq(player.exp_balance, 3, "spending lowers the balance")
	assert_eq(player.exp_total, got, "lifetime count stays")


func test_only_the_takers_ship_gets_the_exp() -> void:
	game.collect_pickup("none", 42)
	assert_eq(player.exp_total, 0)
	assert_eq(player.exp_balance, 0)


# --- Buying -------------------------------------------------------------------------

func test_buying_adds_capacity_unpowered() -> void:
	_buy(&"shields")
	assert_eq(player.levels[&"shields"], 1)
	assert_eq(player.power_of(&"shields"), 0, "comes unpowered")
	assert_eq(player.power_spare(), 1)
	_buy(&"engines")
	assert_eq(player.levels[&"engines"], 2)
	assert_eq(player.power_of(&"engines"), 1, "the new bar is unpowered")


func test_buying_a_gun_leaves_it_unarmed() -> void:
	_buy(&"missile")
	assert_eq(player.levels[&"missile"], 1)
	assert_false(player.is_armed(&"missile"))
	assert_eq(player.level(&"missile"), 0)


func test_buying_reactor_adds_a_spare_bar() -> void:
	_buy(&"reactor")
	assert_eq(player.reactor(), 4)
	assert_eq(player.power_spare(), 2)


func test_cannot_buy_when_unaffordable() -> void:
	player.exp_balance = 2
	assert_false(player.can_afford(&"shields"))
	assert_false(player.buy_upgrade(&"shields"))
	assert_eq(player.levels.get(&"shields", 0), 0)
	assert_eq(player.exp_balance, 2, "nothing spent")
	assert_true(player.can_afford(&"weapons"))


func test_cannot_buy_when_dead() -> void:
	player.exp_balance = 10
	_die()
	assert_false(player.buy_upgrade(&"engines"))
	assert_eq(player.exp_balance, 10)
	assert_eq(player.levels[&"engines"], 1)


func test_maxed_item_cannot_be_bought_and_keeps_the_exp() -> void:
	assert_false(player.can_upgrade(&"lasers"), "the laser starts at its max")
	_buy_n(&"piloting", Systems.max_level(&"piloting"))
	player.exp_balance = 20
	assert_false(player.can_upgrade(&"piloting"))
	assert_false(player.can_afford(&"piloting"))
	assert_false(player.buy_upgrade(&"piloting"))
	assert_eq(player.exp_balance, 20, "still banked")


func test_laser_rows_need_the_laser() -> void:
	assert_true(player.can_upgrade(&"double"))
	assert_true(player.can_upgrade(&"rapid"))
	player.levels.erase(&"lasers")
	assert_false(player.can_upgrade(&"double"))
	assert_false(player.can_upgrade(&"rapid"))
	assert_false(player.can_upgrade(&"nope"), "unknown item")


func test_armor_adds_max_hp_and_comes_intact() -> void:
	_buy(&"armor")
	assert_eq(player.level(&"armor"), 1, "passive: no power needed")
	assert_eq(player.max_hp(), PlayerScript.MAX_HP + PlayerScript.HIT_HP)
	assert_eq(player.hp, PlayerScript.MAX_HP + PlayerScript.HIT_HP)


func test_buying_a_ship_adds_a_spare_for_everyone() -> void:
	var before: int = game.spares
	_buy(&"ship")
	assert_eq(game.spares, before + 1)
	assert_eq(player.price(&"ship"), Systems.price(&"ship", 1))


# --- Power --------------------------------------------------------------------------

func test_add_power_uses_a_spare_bar() -> void:
	_buy(&"engines")
	assert_true(player.add_power(&"engines"))
	assert_eq(player.power_of(&"engines"), 2)
	assert_eq(player.power_used(), 3)
	assert_eq(player.power_spare(), 0)


func test_add_power_respects_capacity() -> void:
	assert_false(player.add_power(&"engines"), "engines already at its 1 bar")
	assert_false(player.add_power(&"shields"), "none bought")
	assert_eq(player.power_of(&"engines"), 1)
	assert_eq(player.power_spare(), 1)


func test_add_power_respects_the_reactor() -> void:
	_buy_n(&"engines", 2)
	assert_true(player.add_power(&"engines"))
	assert_false(player.add_power(&"engines"), "no spare bar")
	assert_eq(player.power_of(&"engines"), 2)
	_buy(&"reactor")
	assert_true(player.add_power(&"engines"))
	assert_eq(player.power_of(&"engines"), 3)


func test_add_power_only_to_systems() -> void:
	assert_false(player.add_power(&"lasers"))
	assert_false(player.add_power(&"reactor"))
	assert_false(player.add_power(&"armor"))
	assert_eq(player.power_spare(), 1)


func test_drain_power_returns_every_bar() -> void:
	_powered(&"engines", 3)
	var spare: int = player.power_spare()
	player.drain_power(&"engines")
	assert_eq(player.power_of(&"engines"), 0)
	assert_eq(player.power_spare(), spare + 3)
	assert_eq(player.levels[&"engines"], 3, "capacity stays")
	player.drain_power(&"engines")  # already off
	assert_eq(player.power_of(&"engines"), 0)


func test_power_used_and_spare_add_up_to_the_reactor() -> void:
	_powered(&"shields", 2)
	_powered(&"engines", 2)
	assert_eq(player.power_used(), 2 + 2 + 1)
	assert_eq(player.power_used() + player.power_spare(), player.reactor())


# --- Effective levels ----------------------------------------------------------------

func test_speed_follows_engines_power() -> void:
	assert_eq(player.level(&"speed"), 1)
	assert_almost_eq(player.move_speed(), PlayerScript.SPEED * (1.0 + PlayerScript.SPEED_STEP), 0.001)
	_powered(&"engines", 3)
	assert_eq(player.level(&"speed"), 3)
	player.drain_power(&"engines")
	assert_eq(player.level(&"speed"), 0)
	assert_almost_eq(player.move_speed(), PlayerScript.SPEED, 0.001)


func test_speed_moves_the_ship() -> void:
	_powered(&"engines", 2)
	var x: float = player.position.x
	player.input_dir = Vector2.LEFT
	player._simulate(0.1)
	assert_almost_eq(x - player.position.x, player.move_speed() * 0.1, 0.01)


func test_double_and_rapid_only_while_lasers_armed() -> void:
	_buy(&"double")
	_buy(&"rapid")
	assert_eq(player.level(&"double"), 1)
	assert_eq(player.level(&"rapid"), 1)
	assert_almost_eq(player.fire_cooldown(), PlayerScript.FIRE_COOLDOWN * PlayerScript.RAPID_STEP, 0.0001)
	player.disarm(&"lasers")
	assert_eq(player.level(&"double"), 0)
	assert_eq(player.level(&"rapid"), 0)
	assert_almost_eq(player.fire_cooldown(), PlayerScript.FIRE_COOLDOWN, 0.0001)


func test_disarmed_lasers_do_not_fire() -> void:
	player.disarm(&"lasers")
	player._fire_requested = true
	player._simulate(0.016)
	assert_eq(game.get_node("Bullets").get_child_count(), 0)
	assert_true(player.arm(&"lasers"))
	player._fire_requested = true
	player._simulate(0.016)
	assert_eq(game.get_node("Bullets").get_child_count(), 1)


func test_guns_only_count_while_armed() -> void:
	_powered(&"weapons", 8)
	for id in [&"missile", &"auto", &"beam", &"healbeam"]:
		_buy(id)
		assert_eq(player.level(id), 0, "%s bought but not armed" % id)
		assert_true(player.arm(id), "armed %s" % id)
		assert_eq(player.level(id), 1, String(id))
		player.disarm(id)
		assert_eq(player.level(id), 0, "%s disarmed" % id)


func test_options_and_rescue_each_take_their_own_bars() -> void:
	_buy_n(&"option", 2)
	_buy_n(&"rescue", 2)
	while player.levels.get(&"drones", 0) < 3:
		_buy(&"drones")
	while player.power_spare() < 4:
		_buy(&"reactor")
	assert_eq(player.level(&"option"), 0, "unpowered")
	assert_true(player.add_power(&"rescue"), "rescue first if you like")
	assert_eq(player.level(&"rescue"), 1)
	assert_eq(player.level(&"option"), 0)
	assert_true(player.add_power(&"option"))
	assert_true(player.add_power(&"option"))
	assert_eq(player.level(&"option"), 2)
	assert_false(player.add_power(&"rescue"), "DRONES is full: 3 bars between them")
	assert_eq(player.power_of(&"drones"), 3)
	assert_true(player.remove_power(&"option"))
	assert_true(player.add_power(&"rescue"), "moved a bar over")
	assert_eq(player.level(&"rescue"), 2)
	assert_false(player.add_power(&"rescue"), "no more than bought")
	player._simulate(0.016)
	assert_eq(player.options, 1, "replicated option count follows")


func test_autopilot_and_beacon_are_separate_bars() -> void:
	_buy_n(&"piloting", 1)
	assert_true(player.add_power(&"beacon"), "the beacon without the autopilot")
	assert_eq(player.level(&"beacon"), 1)
	assert_eq(player.level(&"autopilot"), 0)
	assert_false(player.add_power(&"autopilot"), "PILOTING 1 holds one bar")
	_buy(&"piloting")
	if player.power_spare() <= 0:
		_buy(&"reactor")
	assert_true(player.add_power(&"autopilot"))
	assert_eq(player.power_of(&"piloting"), 2)


func test_pools_arent_powered_themselves() -> void:
	assert_true(Systems.is_pool(&"drones") and Systems.is_pool(&"piloting"))
	assert_eq(Systems.pool_of(&"option"), &"drones")
	assert_eq(Systems.pool_of(&"beacon"), &"piloting")
	assert_eq(Systems.pool_of(&"shields"), &"")


func test_drones_with_only_rescue_bought() -> void:
	_buy(&"rescue")
	_powered(&"drones", 1)
	assert_eq(player.level(&"option"), 0)
	assert_eq(player.level(&"rescue"), 1)


func test_remote_ships_use_the_replicated_option_count() -> void:
	var other := _ship(42, Vector2(100, 600))
	other.options = 2
	assert_eq(other.level(&"option"), 2)


func test_medbay_power_gives_repair() -> void:
	_buy(&"medbay")
	assert_eq(player.level(&"repair"), 0)
	_powered(&"medbay", 1)
	assert_eq(player.level(&"repair"), 1)


func test_piloting_power_gives_autopilot_then_beacon() -> void:
	_buy_n(&"piloting", 2)
	assert_eq(player.level(&"autopilot"), 0)
	assert_eq(player.level(&"beacon"), 0)
	_powered(&"piloting", 1)
	assert_eq(player.level(&"autopilot"), 1)
	assert_eq(player.level(&"beacon"), 0)
	_powered(&"piloting", 2)
	assert_eq(player.level(&"beacon"), 1)
	player._simulate(0.016)
	assert_true(player.beacon, "replicated beacon follows")
	player.drain_power(&"piloting")
	assert_eq(player.level(&"autopilot"), 0)
	player._simulate(0.016)
	assert_false(player.beacon)


func test_remote_ships_use_the_replicated_beacon() -> void:
	var other := _ship(42, Vector2(100, 600))
	other.beacon = true
	assert_eq(other.level(&"beacon"), 1)


# --- Guns -----------------------------------------------------------------------------

func test_arm_pulls_bars_into_weapons_from_the_reactor() -> void:
	_buy_n(&"weapons", 2)  # capacity 3
	_buy(&"reactor")  # spare 2
	_buy(&"missile")
	assert_true(player.arm(&"missile"))
	assert_true(player.is_armed(&"missile"))
	assert_eq(player.power_of(&"weapons"), 3, "lasers 1 + missile 2")
	assert_eq(player.weapons_used(), 3)
	assert_eq(player.power_spare(), 0)


func test_arm_uses_free_weapons_bars_first() -> void:
	_powered(&"weapons", 2)
	var spare: int = player.power_spare()
	_buy(&"auto")
	assert_true(player.arm(&"auto"))
	assert_eq(player.power_of(&"weapons"), 2, "the free bar was enough")
	assert_eq(player.power_spare(), spare)


func test_arm_rolls_back_if_it_cannot_power_the_gun() -> void:
	_buy_n(&"weapons", 2)  # capacity 3, but only 1 spare bar
	_buy(&"missile")
	assert_false(player.arm(&"missile"))
	assert_false(player.is_armed(&"missile"))
	assert_eq(player.power_of(&"weapons"), 1, "left as it was")
	assert_eq(player.power_spare(), 1)
	assert_true(player.is_armed(&"lasers"))


func test_arm_rolls_back_when_capacity_runs_out() -> void:
	_buy(&"reactor")
	_buy(&"reactor")
	_buy(&"weapons")  # capacity 2: lasers 1 + beam 3 won't fit
	_buy(&"beam")
	assert_false(player.arm(&"beam"))
	assert_eq(player.power_of(&"weapons"), 1)
	assert_eq(player.power_spare(), 3)


func test_arm_needs_a_bought_gun_and_a_live_ship() -> void:
	_powered(&"weapons", 3)
	assert_false(player.arm(&"missile"), "not bought")
	assert_false(player.arm(&"engines"), "not a gun")
	assert_false(player.arm(&"lasers"), "already armed")
	_buy(&"missile")
	_die()
	assert_false(player.arm(&"missile"), "dead")


func test_disarm_frees_weapons_bars() -> void:
	_powered(&"weapons", 3)
	_buy(&"missile")
	assert_true(player.arm(&"missile"))
	player.disarm(&"missile")
	assert_false(player.is_armed(&"missile"))
	assert_eq(player.weapons_used(), 1)
	assert_eq(player.power_of(&"weapons"), 3, "WEAPONS stays powered")
	assert_true(player.arm(&"missile"), "re-arms on the free bars")


func test_toggle_gun_switches_on_and_off() -> void:
	_buy(&"auto")
	player.toggle_gun(&"auto")
	assert_false(player.is_armed(&"auto"), "no WEAPONS capacity for it")
	_buy(&"weapons")
	player.toggle_gun(&"auto")
	assert_true(player.is_armed(&"auto"))
	assert_eq(player.power_of(&"weapons"), 2)
	player.toggle_gun(&"auto")
	assert_false(player.is_armed(&"auto"))


func test_reducing_weapons_power_disarms_the_last_guns() -> void:
	_powered(&"weapons", 4)
	_buy(&"missile")
	_buy(&"auto")
	assert_true(player.arm(&"missile"))
	assert_true(player.arm(&"auto"))
	assert_eq(player.weapons_used(), 4)
	player._set_power(&"weapons", 3)
	assert_true(player.is_armed(&"lasers"))
	assert_true(player.is_armed(&"missile"))
	assert_false(player.is_armed(&"auto"), "the last gun goes")
	player._set_power(&"weapons", 1)
	assert_true(player.is_armed(&"lasers"))
	assert_false(player.is_armed(&"missile"))
	player.drain_power(&"weapons")
	assert_eq(player.armed.size(), 0, "nothing left armed")
	assert_eq(player.weapons_used(), 0)


# --- Shields --------------------------------------------------------------------------

func test_unpowered_shields_give_no_shield() -> void:
	_buy(&"shields")
	player._simulate(PlayerScript.SHIELD_REGEN * 3)
	assert_eq(player.shield, 0)
	assert_eq(player.level(&"shield"), 0)


func test_powered_shields_recharge_the_front() -> void:
	_powered(&"shields", 1)
	player._simulate(PlayerScript.SHIELD_REGEN - 0.1)
	assert_eq(player.shield, 0, "not yet")
	player._simulate(0.2)
	assert_eq(player.shield, 1)
	assert_eq(player.level(&"shield"), 1)
	for i in PlayerScript.SHIELD_HITS + 2:
		player._simulate(PlayerScript.SHIELD_REGEN + 0.01)
	assert_eq(player.shield, PlayerScript.SHIELD_HITS, "caps")
	assert_eq(player.rear_shield, 0, "no rear at SHIELDS 1")


func test_shields_two_recharge_the_rear_after_the_front() -> void:
	_powered(&"shields", 2)
	player.shield = PlayerScript.SHIELD_HITS - 1
	player._simulate(PlayerScript.SHIELD_REGEN + 0.01)
	assert_eq(player.shield, PlayerScript.SHIELD_HITS, "front first")
	assert_eq(player.rear_shield, 0)
	player._simulate(PlayerScript.SHIELD_REGEN + 0.01)
	assert_eq(player.rear_shield, 1)
	assert_eq(player.level(&"shield"), 2)


func test_shields_three_recharge_twice_as_fast() -> void:
	_powered(&"shields", 3)
	player._simulate(PlayerScript.SHIELD_REGEN / 2.0 + 0.01)
	assert_eq(player.shield, 1)


func test_shields_absorb_hits_before_hp() -> void:
	_powered(&"shields", 2)
	player.shield = PlayerScript.SHIELD_HITS
	player.rear_shield = PlayerScript.SHIELD_HITS
	player.take_damage(1)
	assert_eq(player.shield, PlayerScript.SHIELD_HITS - 1)
	player.take_damage(1, true)
	assert_eq(player.rear_shield, PlayerScript.SHIELD_HITS - 1, "hit from behind takes the rear")
	assert_eq(player.hp, PlayerScript.MAX_HP)


func test_draining_shields_drops_them() -> void:
	_powered(&"shields", 2)
	player.shield = PlayerScript.SHIELD_HITS
	player.rear_shield = PlayerScript.SHIELD_HITS
	player._set_power(&"shields", 1)
	assert_eq(player.shield, PlayerScript.SHIELD_HITS, "front still powered")
	assert_eq(player.rear_shield, 0, "rear drops below SHIELDS 2")
	player.drain_power(&"shields")
	assert_eq(player.shield, 0)
	player._simulate(PlayerScript.SHIELD_REGEN + 0.01)
	assert_eq(player.shield, 0, "no recharge while off")


# --- Medbay -------------------------------------------------------------------------

func test_remote_medbay_two_heals_ships_in_range() -> void:
	var other := _ship(42, player.position + Vector2(PlayerScript.HEAL_RANGE - 10, 0))
	other.medbay = 2
	player.hp = 10.0
	assert_true(player.near_medbay())
	player._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_almost_eq(player.hp, 10.0 + PlayerScript.HIT_HP * PlayerScript.HEAL_HITS, 0.01)


func test_remote_medbay_out_of_range_or_too_low_does_not_heal() -> void:
	var other := _ship(42, player.position + Vector2(0, -(PlayerScript.HEAL_RANGE + 10)))
	other.medbay = 2
	player.hp = 10.0
	player._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_eq(player.hp, 10.0, "out of range")
	other.position = player.position
	other.medbay = 1
	player._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_eq(player.hp, 10.0, "MEDBAY 1 doesn't heal")
	other.medbay = 2
	other.hp = 0
	player._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_eq(player.hp, 10.0, "a dead ship doesn't heal")


func test_own_medbay_two_heals_itself() -> void:
	_powered(&"medbay", 1)
	player.hp = 10.0
	player._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_eq(player.hp, 10.0, "MEDBAY 1 only repairs")
	_powered(&"medbay", 2)
	player._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_almost_eq(player.hp, 10.0 + PlayerScript.HIT_HP * PlayerScript.HEAL_HITS, 0.01)
	assert_eq(player.medbay, 2, "replicated medbay follows the power")


func test_medbay_three_halves_the_repair_kit_cooldown() -> void:
	_powered(&"medbay", 1)
	assert_true(player.drop_repair())
	assert_almost_eq(player._repair_cooldown, PlayerScript.REPAIR_COOLDOWN, 0.0001)
	player._repair_cooldown = 0.0
	_powered(&"medbay", 3)
	assert_true(player.drop_repair())
	assert_almost_eq(player._repair_cooldown, PlayerScript.REPAIR_COOLDOWN * 0.5, 0.0001)


func test_no_repair_kit_without_medbay_power() -> void:
	_buy(&"medbay")
	assert_false(player.drop_repair())


# --- Free and max upgrades ----------------------------------------------------------

func test_free_upgrade_is_free_and_never_a_ship() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var spares: int = game.spares
	var power_before: Dictionary = player.power.duplicate()
	var got := 0
	for i in 200:
		var id: StringName = player.free_upgrade(rng)
		if id == &"":
			break
		assert_ne(id, &"ship")
		got += 1
	assert_gt(got, 0)
	assert_eq(player.free_upgrade(rng), &"", "nothing left but +SHIP")
	assert_eq(player.levels.get(&"ship", 0), 0)
	assert_eq(game.spares, spares)
	assert_eq(player.exp_balance, 0, "cost nothing")
	assert_eq(player.power, power_before, "capacity comes unpowered")
	for it in Systems.ITEMS:
		if it.id != &"ship":
			assert_eq(player.levels.get(it.id, 0), it.max, String(it.id))


func test_max_upgrades_powers_everything_and_arms_every_gun() -> void:
	player.max_upgrades()
	for it in Systems.ITEMS:
		if it.id != &"ship":
			assert_eq(player.levels.get(it.id, 0), it.max if it.id != &"reactor" else player.reactor(), String(it.id))
	assert_eq(player.levels.get(&"ship", 0), 0, "spare ships are bought, never given")
	for sys in Systems.systems():
		assert_eq(player.power_of(sys.id), sys.max, "%s fully powered" % sys.id)
	for g in Systems.guns():
		assert_true(player.is_armed(g.id), "%s armed" % g.id)
	assert_gte(player.power_spare(), 0)
	assert_gte(player.reactor(), Systems.max_level(&"reactor"))
	assert_eq(player.hp, player.max_hp())


# --- Death and the escape pod ------------------------------------------------------

func test_death_resets_to_the_start_loadout() -> void:
	_powered(&"shields", 2)
	_powered(&"weapons", 3)
	_buy(&"missile")
	assert_true(player.arm(&"missile"))
	_buy(&"armor")
	player.shield = PlayerScript.SHIELD_HITS
	_die()
	_respawn()
	assert_eq(player.levels, _start_levels())
	assert_eq(player.power, Systems.START_POWER)
	assert_eq(player.armed.keys(), [&"lasers"])
	assert_eq(player.shield, 0)
	assert_eq(player.rear_shield, 0)
	assert_eq(player.hp, PlayerScript.MAX_HP)
	assert_eq(player.price(&"engines"), 1, "prices reset with the levels")


func test_unspent_exp_survives_death() -> void:
	_buy(&"engines")
	player.exp_balance = 5
	_die()
	_respawn()
	assert_eq(player.exp_balance, 5)


func test_pod_restores_levels_power_and_armed_guns() -> void:
	_powered(&"shields", 2)
	_powered(&"weapons", 3)
	_buy(&"missile")
	assert_true(player.arm(&"missile"))
	_buy(&"armor")
	var levels_before: Dictionary = player.levels.duplicate()
	var power_before: Dictionary = player.power.duplicate()
	var pod := _die()
	assert_not_null(pod)
	_respawn()
	pod.claim_from([player])
	assert_eq(player.levels, levels_before)
	for s in power_before:
		assert_eq(player.power_of(s), power_before[s], "%s powered back up" % s)
	assert_true(player.is_armed(&"lasers"))
	assert_true(player.is_armed(&"missile"))
	assert_eq(player.max_hp(), PlayerScript.MAX_HP + PlayerScript.HIT_HP)
	assert_eq(player.hp, player.max_hp(), "armor plating back too")


func test_pod_saved_while_dead_restores_at_respawn() -> void:
	_powered(&"engines", 2)
	var pod := _die()
	game.rescue_pod(String(pod.name), 2, true, 1)  # peer 2's drone got it
	_respawn()
	assert_eq(player.levels[&"engines"], 2)
	assert_eq(player.power_of(&"engines"), 2)
	assert_eq(player.level(&"speed"), 2)


func test_pod_restores_shields_it_carried() -> void:
	_powered(&"shields", 2)
	player.shield = 2
	player.rear_shield = 1
	player._lose_hp(player.hp)  # straight through, so the shields go down with it
	var pod: Node = game.get_node("Pods").get_children().back()
	_respawn()
	pod.claim_from([player])
	assert_eq(player.shield, 2)
	assert_eq(player.rear_shield, 1)


func test_upgrade_state_carries_levels_power_and_armed() -> void:
	_powered(&"engines", 2)
	var st: Dictionary = player.upgrade_state()
	assert_eq(st.levels, player.levels)
	assert_eq(st.power, player.power)
	assert_eq(st.armed, [&"lasers"])
	st.levels[&"engines"] = 99
	assert_eq(player.levels[&"engines"], 2, "a copy")
