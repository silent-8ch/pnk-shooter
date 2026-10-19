extends GutTest
## Guns are armed from the ActionBar: a tap on a disarmed gun arms it (no shot),
## a tap on an armed one fires, and a long press disarms it. AUTO and HEAL taps
## are on/off switches.

var game: Node2D
var bar: ActionBar
var player: Area2D
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
	player.position = Vector2(270, 600)
	game.get_node("Players").add_child(player)
	player._gather_input()  # syncs the press and hold counts


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _buy(id: StringName) -> void:
	for i in player.price(id):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(id), "bought %s" % id)


func _tap(id: StringName) -> void:
	bar._process(10.0)  # off cooldown
	assert_true(bar.press(id), "pressed %s" % id)
	player._gather_input()


func _long_press(id: StringName) -> void:
	assert_true(bar.hold(id), "held %s" % id)
	player._gather_input()


func _bullets() -> int:
	return game.get_node("Bullets").get_child_count()


func test_lasers_start_armed_and_lit_with_their_power() -> void:
	assert_true(player.is_armed(&"lasers"))
	assert_true(bar._lit.get(&"lasers", false))
	assert_eq(bar._power.get(&"lasers", 0), Systems.gun_power(&"lasers"))


func test_long_press_disarms_lasers() -> void:
	_long_press(&"lasers")
	assert_false(player.is_armed(&"lasers"))
	assert_false(bar._lit.get(&"lasers", true), "shown OFF")
	assert_eq(player.weapons_used(), 0)


func test_tap_on_disarmed_laser_arms_it_without_firing() -> void:
	_long_press(&"lasers")
	_tap(&"lasers")
	assert_true(player.is_armed(&"lasers"))
	assert_false(player._fire_requested, "no shot")
	player._simulate(0.016)
	assert_eq(_bullets(), 0)
	player._gather_input()
	assert_true(bar._lit.get(&"lasers", false), "lit once armed")


func test_next_tap_fires() -> void:
	_long_press(&"lasers")
	_tap(&"lasers")
	_tap(&"lasers")
	assert_true(player._fire_requested)
	player._simulate(0.016)
	assert_eq(_bullets(), 1)


func test_right_click_disarms_through_the_bar() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = bar.button_rect(0).get_center()
	bar._input(ev)
	player._gather_input()
	assert_false(player.is_armed(&"lasers"))


func test_finger_hold_disarms_through_the_bar() -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = bar.button_rect(0).get_center()
	bar._input(ev)
	player._gather_input()  # the touch itself: a shot from the armed laser
	assert_true(player._fire_requested)
	bar._process(ActionBar.LONG_PRESS + 0.01)
	player._gather_input()
	assert_false(player.is_armed(&"lasers"), "held: disarmed")


func test_long_press_on_disarmed_gun_stays_disarmed() -> void:
	_long_press(&"lasers")
	_long_press(&"lasers")
	assert_false(player.is_armed(&"lasers"))


func test_arming_needs_a_weapons_bar() -> void:
	_long_press(&"lasers")
	player.drain_power(&"weapons")
	player.levels[&"weapons"] = 1
	player.add_power(&"engines")  # fill the reactor: engines 1 + 0 weapons
	player.levels[&"engines"] = 3
	player.add_power(&"engines")
	player.add_power(&"engines")
	assert_eq(player.power_spare(), 0)
	_tap(&"lasers")
	assert_false(player.is_armed(&"lasers"), "no bar to arm it with")
	assert_eq(player.power_of(&"weapons"), 0)


func test_arming_powers_weapons_from_the_reactor() -> void:
	_long_press(&"lasers")
	player.drain_power(&"weapons")
	_tap(&"lasers")
	assert_true(player.is_armed(&"lasers"))
	assert_eq(player.power_of(&"weapons"), 1)


func test_bar_lights_armed_gun_on_the_same_frame_it_arms() -> void:
	_long_press(&"lasers")
	_tap(&"lasers")
	assert_true(bar._lit.get(&"lasers", false))


func test_missile_tap_arms_then_fires_and_hold_disarms() -> void:
	_buy(&"missile")
	_buy(&"weapons")  # 2 bars of capacity: the missile's 2 once the laser's off
	_long_press(&"lasers")
	assert_true(bar.is_shown(&"missile"))
	assert_false(player.is_armed(&"missile"), "bought unarmed")
	assert_eq(bar._power.get(&"missile", 0), 2)
	_tap(&"missile")
	assert_true(player.is_armed(&"missile"))
	assert_false(player._missile_requested, "arming, not firing")
	_tap(&"missile")
	assert_true(player._missile_requested)
	assert_eq(player.power_of(&"weapons"), 2, "weapons powered up from the reactor to arm it")
	_long_press(&"missile")
	assert_false(player.is_armed(&"missile"))


func test_auto_tap_toggles() -> void:
	_buy(&"auto")
	_long_press(&"lasers")  # frees the only weapons bar
	_tap(&"auto")
	assert_true(player.is_armed(&"auto"))
	assert_true(bar._lit.get(&"auto", false))
	_tap(&"auto")
	assert_false(player.is_armed(&"auto"))


func test_heal_tap_toggles() -> void:
	_buy(&"healbeam")
	_long_press(&"lasers")
	_tap(&"heal")
	assert_true(player.is_armed(&"healbeam"))
	_tap(&"heal")
	assert_false(player.is_armed(&"healbeam"))
