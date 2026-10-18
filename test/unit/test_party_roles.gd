extends GutTest
## Tier III and party roles: TIER III takes three more charges in tier II, then
## each ship picks one role for good: DPS, TANK, HEALER or MODIFIER.

const PlayerScene := preload("res://scenes/player.tscn")
const PlayerScript := preload("res://scripts/player.gd")

var game: Node2D
var me: Area2D
var mate: Area2D
var meter: Control
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	meter = game.get_node("PointerControls/PowerMeter")
	me = _ship(1, Vector2(270, 700))
	mate = _ship(7, Vector2(330, 700))


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _ship(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _buy(id: StringName) -> void:
	me.exp_balance += me.price(id)
	assert_true(me.buy_upgrade(id), "bought %s" % id)


func _tier3() -> void:
	for i in PowerMeter.TIER_CHARGES * 2:
		_buy(&"tier")


func _give_role(p: Area2D, r: StringName) -> void:
	p.tier = 3
	p.levels[r] = 1
	p.party_role = String(r)


# --- Tier III ----------------------------------------------------------------

func test_tier_iii_takes_three_more_charges() -> void:
	for i in PowerMeter.TIER_CHARGES:
		_buy(&"tier")
	assert_eq(me.tier, 2)
	for i in PowerMeter.TIER_CHARGES - 1:
		_buy(&"tier")
	assert_eq(me.tier, 2)
	_buy(&"tier")
	assert_eq(me.tier, 3)
	assert_false(me.can_upgrade(&"tier"), "the slot is gone in tier III")


func test_tier_iii_offers_the_four_roles() -> void:
	var ids := PowerMeter.slots_for(3).map(func(s): return s.id)
	for r in PowerMeter.ROLES:
		assert_has(ids, r)
	assert_does_not_have(ids, &"tier")
	for r in PowerMeter.ROLES:
		assert_eq(PowerMeter.max_level(r, 2), 0, "not before tier III")


func test_picking_a_role_hides_the_others() -> void:
	_tier3()
	_buy(&"healer")
	assert_eq(me.role(), &"healer")
	for r in [&"dps", &"tank", &"modifier"]:
		assert_false(me.can_upgrade(r), String(r))
	var ids := PowerMeter.slots_for(3, &"healer").map(func(s): return s.id)
	assert_has(ids, &"healer")
	assert_does_not_have(ids, &"dps")


func test_role_replicates_and_tags_the_name() -> void:
	_tier3()
	_buy(&"tank")
	me._simulate(0.016)
	assert_eq(me.party_role, "tank")
	var cfg: SceneReplicationConfig = me.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:party_role")))
	me._process(0.0)
	assert_string_contains(me.label.text, "[TANK]")


func test_remote_ships_use_the_replicated_role() -> void:
	mate.party_role = "modifier"
	assert_eq(mate.role(), &"modifier")


func test_role_is_lost_with_the_ship() -> void:
	_tier3()
	_buy(&"dps")
	me._lose_upgrades()
	assert_eq(me.role(), &"")
	assert_eq(me.party_role, "")


func test_meter_fits_all_tier_iii_slots_on_screen() -> void:
	_tier3()
	var n := PowerMeter.slots_for(3).size()
	assert_gte(meter.meter_rect().position.y, 0.0, "header on screen")
	assert_lt(meter.slot_rect(n - 1).end.y, meter.get_viewport_rect().size.y - ActionBar.BAR_HEIGHT, "above the buttons")
	for i in n - 1:
		assert_lte(meter.slot_rect(i).end.y, meter.slot_rect(i + 1).position.y, "no overlap")


# --- DPS -----------------------------------------------------------------------

func test_dps_guns_go_further() -> void:
	assert_eq(PowerMeter.max_level(&"rapid", 3, &"dps"), 9)
	assert_eq(PowerMeter.max_level(&"missile", 3, &"dps"), 9)
	assert_eq(PowerMeter.max_level(&"beam", 3, &"dps"), 5)
	assert_eq(PowerMeter.max_level(&"double", 3, &"dps"), 3)
	assert_eq(PowerMeter.max_level(&"rapid", 3, &"tank"), 6, "others stay at tier II caps")


func test_dps_spread_fires_five() -> void:
	_give_role(me, &"dps")
	me.levels[&"double"] = 3
	me._fire_requested = true
	me._simulate(0.016)
	assert_eq(game.get_node("Bullets").get_child_count(), 5)
	assert_eq(PowerMeter.label_for(PowerMeter.SLOTS[PowerMeter.slot_index(&"double")], 3, 2), "SPREAD")


# --- Tank ----------------------------------------------------------------------

func test_tank_takes_half_of_a_nearby_shipmates_hit() -> void:
	_give_role(mate, &"tank")
	mate.ai = true  # flown here, so the cover RPC lands on this peer
	var me_hp: float = me.hp
	var tank_hp: float = mate.hp
	me.take_damage(1.0)
	assert_almost_eq(me.hp, me_hp - PlayerScript.HIT_HP * (1.0 - PlayerScript.COVER_SHARE), 0.01)
	assert_almost_eq(mate.hp, tank_hp - PlayerScript.HIT_HP * PlayerScript.COVER_SHARE, 0.01)


func test_no_cover_out_of_range_or_for_the_tank_itself() -> void:
	_give_role(mate, &"tank")
	mate.position = me.position + Vector2(PlayerScript.COVER_RANGE + 10, 0)
	assert_null(me.covering_tank())
	assert_null(mate.covering_tank())


func test_tank_front_shield_recharges() -> void:
	_give_role(me, &"tank")
	me.shield = 0
	me._simulate(PlayerScript.SHIELD_REGEN + 0.01)
	assert_eq(me.shield, 1)


func test_tank_armor_goes_further() -> void:
	assert_eq(PowerMeter.max_level(&"armor", 3, &"tank"), 4)


# --- Healer --------------------------------------------------------------------

func test_healer_heals_shipmates_in_range() -> void:
	_give_role(mate, &"healer")
	me.hp = 10.0
	me._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_almost_eq(me.hp, 10.0 + PlayerScript.HIT_HP * PlayerScript.HEAL_HITS, 0.01)


func test_no_heal_out_of_range() -> void:
	_give_role(mate, &"healer")
	mate.position = me.position + Vector2(0, -(PlayerScript.HEAL_RANGE + 10))
	me.hp = 10.0
	me._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_eq(me.hp, 10.0)


func test_healer_heals_itself_and_repairs_faster_and_hauls_more() -> void:
	_give_role(me, &"healer")
	me.hp = 10.0
	me._simulate(PlayerScript.HEAL_INTERVAL + 0.01)
	assert_gt(me.hp, 10.0)
	assert_eq(me.drone_capacity(), PlayerScript.DRONE_CAPACITY * 2)
	me.levels[&"repair"] = 1
	me._repair_cooldown = 0.0
	assert_true(me.drop_repair())
	assert_eq(me._repair_cooldown, PlayerScript.REPAIR_COOLDOWN * 0.5)


# --- Modifier ------------------------------------------------------------------

func test_modifier_hastes_shipmates_in_range() -> void:
	var base_fire: float = me.fire_cooldown()
	var base_speed: float = me.move_speed()
	var base_missile: float = me.missile_cooldown()
	_give_role(mate, &"modifier")
	assert_almost_eq(me.fire_cooldown(), base_fire * PlayerScript.MOD_HASTE, 0.0001)
	assert_almost_eq(me.move_speed(), base_speed * PlayerScript.MOD_SPEED, 0.0001)
	assert_almost_eq(me.missile_cooldown(), base_missile * PlayerScript.MOD_HASTE, 0.0001)
	mate.position = me.position + Vector2(PlayerScript.MOD_RANGE + 10, 0)
	assert_eq(me.fire_cooldown(), base_fire, "out of range")


func test_dead_role_ships_give_nothing() -> void:
	_give_role(mate, &"modifier")
	mate.hp = 0
	assert_false(me.near_role(&"modifier", PlayerScript.MOD_RANGE))


func test_modifier_speed_and_options_go_further() -> void:
	assert_eq(PowerMeter.max_level(&"speed", 3, &"modifier"), 8)
	assert_eq(PowerMeter.max_level(&"option", 3, &"modifier"), 4)
