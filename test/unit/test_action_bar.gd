extends GutTest
## ActionBar: bottom button row; Lasers fires one shot per press with a short
## cooldown, works from any finger, and drives the local player's shots.

var layer: CanvasLayer
var bar: Control
var _saved_left := true


func before_each() -> void:
	_saved_left = Settings.left_handed
	Settings.left_handed = true  # the default layout, whatever this machine has saved
	layer = CanvasLayer.new()
	bar = ActionBar.new()
	layer.add_child(bar)
	add_child_autofree(layer)


func after_each() -> void:
	Settings.left_handed = _saved_left


func _touch(pressed: bool, pos: Vector2, index := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	bar._input(ev)


func _lasers_center() -> Vector2:
	return bar.button_rect(0).get_center()


func test_lasers_is_the_first_button_at_the_bottom() -> void:
	assert_eq(ActionBar.ACTIONS[0].id, &"lasers")
	var r: Rect2 = bar.button_rect(0)
	var screen := bar.get_viewport_rect().size
	assert_gt(r.position.y, screen.y - ActionBar.BAR_HEIGHT - 0.01)
	assert_lte(r.end.y, screen.y)
	assert_lt(r.position.x, screen.x / 4.0, "first slot on the left")


func test_short_cooldown_matches_server() -> void:
	assert_lte(ActionBar.cooldown_of(&"lasers"), 0.5)
	assert_eq(ActionBar.cooldown_of(&"lasers"), preload("res://scripts/player.gd").FIRE_COOLDOWN)


func test_tap_fires_once_then_cools_down() -> void:
	_touch(true, _lasers_center())
	assert_eq(bar.presses[&"lasers"], 1)
	_touch(false, _lasers_center())
	_touch(true, _lasers_center())
	assert_eq(bar.presses[&"lasers"], 1, "ignored during cooldown")
	assert_gt(bar.cooldown_left(&"lasers"), 0.0)
	bar._process(ActionBar.cooldown_of(&"lasers"))
	assert_eq(bar.cooldown_left(&"lasers"), 0.0)
	_touch(false, _lasers_center())
	_touch(true, _lasers_center())
	assert_eq(bar.presses[&"lasers"], 2)


func test_any_finger_can_press() -> void:
	_touch(true, Vector2(300, 400), 0)  # steering finger elsewhere
	_touch(true, _lasers_center(), 3)
	assert_eq(bar.presses[&"lasers"], 1)


func test_tap_outside_buttons_does_nothing() -> void:
	_touch(true, Vector2(300, 400))
	_touch(true, Vector2(500, 940))  # on the bar but not a button
	assert_eq(bar.presses[&"lasers"], 0)
	assert_true(bar.contains(Vector2(500, 940)))
	assert_false(bar.contains(Vector2(300, 400)))


func test_hidden_bar_ignores_presses() -> void:
	layer.visible = false
	_touch(true, _lasers_center())
	assert_eq(bar.presses[&"lasers"], 0)
	assert_false(bar.contains(_lasers_center()))


func test_hiding_resets_cooldown() -> void:
	_touch(true, _lasers_center())
	layer.visible = false
	layer.visible = true
	assert_eq(bar.cooldown_left(&"lasers"), 0.0)


# --- In the game -----------------------------------------------------------

func test_game_has_bar_and_lasers_press_makes_local_player_fire() -> void:
	var saved := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	var gbar: Control = game.get_node("PointerControls/ActionBar")
	assert_true(gbar.is_in_group("action_bar"))
	var p: Area2D = preload("res://scenes/player.tscn").instantiate()
	p.peer_id = multiplayer.get_unique_id()
	p.position = Vector2(270, 800)
	game.get_node("Players").add_child(p)
	p._gather_input()  # syncs the press count
	assert_false(p._fire_requested)
	gbar.press(&"lasers")
	p._gather_input()
	assert_true(p._fire_requested)
	p._simulate(0.016)
	assert_eq(game.get_node("Bullets").get_child_count(), 1)
	multiplayer.multiplayer_peer = saved


func test_ship_stays_above_the_bar() -> void:
	var saved := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	var p: Area2D = preload("res://scenes/player.tscn").instantiate()
	p.position = Vector2(270, 800)
	game.get_node("Players").add_child(p)
	p.input_dir = Vector2.DOWN
	for i in 30:
		p._simulate(0.1)
	assert_lte(p.position.y, 960.0 - ActionBar.BAR_HEIGHT - 20.0 + 0.001)
	multiplayer.multiplayer_peer = saved


func _key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	bar._input(ev)


func test_key_1_fires_lasers() -> void:
	_key(KEY_1)
	assert_eq(bar.presses[&"lasers"], 1)
	_key(KEY_KP_1)
	assert_eq(bar.presses[&"lasers"], 1, "cooldown applies to keys too")


func test_number_keys_follow_the_shown_buttons() -> void:
	assert_eq(bar.action_for_key(KEY_2), &"", "nothing on 2 yet")
	bar.set_shown(&"rescue", true)
	bar.set_shown(&"auto", true)
	assert_eq(bar.action_for_key(KEY_1), &"lasers")
	assert_eq(bar.action_for_key(KEY_2), &"rescue")
	assert_eq(bar.action_for_key(KEY_3), &"auto")
	assert_eq(bar.action_for_key(KEY_4), &"")
	_key(KEY_3)
	assert_eq(bar.presses[&"auto"], 1)


func test_held_key_does_not_repeat() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_1
	ev.pressed = true
	ev.echo = true
	bar._input(ev)
	assert_eq(bar.presses[&"lasers"], 0)


# --- Long presses ------------------------------------------------------------

func _right_click(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = pos
	bar._input(ev)


func _shift_key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.shift_pressed = true
	bar._input(ev)


func test_seven_actions() -> void:
	assert_eq(ActionBar.ACTIONS.map(func(a): return a.id),
		[&"lasers", &"missile", &"rescue", &"beam", &"auto", &"repair", &"heal"])


func test_finger_held_past_long_press_counts_one_hold() -> void:
	_touch(true, _lasers_center())
	assert_eq(bar.presses[&"lasers"], 1, "the touch is a press")
	bar._process(ActionBar.LONG_PRESS * 0.5)
	assert_eq(bar.holds[&"lasers"], 0, "not yet")
	bar._process(ActionBar.LONG_PRESS * 0.6)
	assert_eq(bar.holds[&"lasers"], 1)
	bar._process(ActionBar.LONG_PRESS * 2.0)
	assert_eq(bar.holds[&"lasers"], 1, "once per hold")
	_touch(false, _lasers_center())
	bar._process(ActionBar.LONG_PRESS * 2.0)
	assert_eq(bar.holds[&"lasers"], 1)


func test_short_tap_is_not_a_hold() -> void:
	_touch(true, _lasers_center())
	bar._process(ActionBar.LONG_PRESS * 0.5)
	_touch(false, _lasers_center())
	bar._process(ActionBar.LONG_PRESS)
	assert_eq(bar.holds[&"lasers"], 0)


func test_second_hold_counts_again() -> void:
	_touch(true, _lasers_center())
	bar._process(ActionBar.LONG_PRESS + 0.01)
	_touch(false, _lasers_center())
	_touch(true, _lasers_center())
	bar._process(ActionBar.LONG_PRESS + 0.01)
	assert_eq(bar.holds[&"lasers"], 2)


func test_hold_off_buttons_counts_nothing() -> void:
	_touch(true, Vector2(500, 940))
	bar._process(ActionBar.LONG_PRESS * 2.0)
	for a in ActionBar.ACTIONS:
		assert_eq(bar.holds[a.id], 0)


func test_hiding_drops_a_held_finger() -> void:
	_touch(true, _lasers_center())
	layer.visible = false
	layer.visible = true
	bar._process(ActionBar.LONG_PRESS * 2.0)
	assert_eq(bar.holds[&"lasers"], 0)


func test_right_click_is_a_hold_not_a_press() -> void:
	_right_click(_lasers_center())
	assert_eq(bar.holds[&"lasers"], 1)
	assert_eq(bar.presses[&"lasers"], 0)
	_right_click(Vector2(300, 400))
	assert_eq(bar.holds[&"lasers"], 1, "off the bar")


func test_shift_number_key_is_a_hold() -> void:
	bar.set_shown(&"missile", true)
	_shift_key(KEY_2)
	assert_eq(bar.holds[&"missile"], 1)
	assert_eq(bar.presses[&"missile"], 0)
	_shift_key(KEY_1)
	assert_eq(bar.holds[&"lasers"], 1)
	assert_eq(bar.presses[&"lasers"], 0)


func test_hold_needs_a_shown_button() -> void:
	assert_false(bar.hold(&"beam"))
	assert_eq(bar.holds[&"beam"], 0)
	assert_false(bar.hold(&"nope"))
	bar.set_shown(&"beam", true)
	assert_true(bar.hold(&"beam"))
	assert_eq(bar.holds[&"beam"], 1)


func test_hidden_bar_ignores_holds() -> void:
	layer.visible = false
	_right_click(_lasers_center())
	_shift_key(KEY_1)
	assert_eq(bar.holds[&"lasers"], 0)


func test_hold_ignores_cooldown() -> void:
	_touch(true, _lasers_center())
	_touch(false, _lasers_center())
	assert_gt(bar.cooldown_left(&"lasers"), 0.0)
	_right_click(_lasers_center())
	assert_eq(bar.holds[&"lasers"], 1)


func test_set_power() -> void:
	assert_eq(bar._power.get(&"missile", 0), 0)
	bar.set_power(&"missile", 2)
	assert_eq(bar._power[&"missile"], 2)
	bar.set_power(&"missile", 0)
	assert_eq(bar._power[&"missile"], 0)


func test_all_seven_buttons_fit_on_the_bar() -> void:
	for a in ActionBar.ACTIONS:
		bar.set_shown(a.id, true)
	assert_eq(bar.shown_actions().size(), 7)
	var screen := bar.get_viewport_rect().size
	var prev := Rect2()
	for slot in bar.shown_actions().size():
		var i: int = bar.shown_actions()[slot]
		var r: Rect2 = bar.button_rect(i)
		assert_gt(r.size.x, 0.0)
		assert_gte(r.position.x, 0.0)
		assert_lte(r.end.x, screen.x, "%s on screen" % ActionBar.ACTIONS[i].id)
		assert_true(bar.bar_rect().encloses(r))
		if slot > 0:
			assert_gt(r.position.x, prev.end.x, "no overlap")
		prev = r
	_touch(true, bar.button_rect(6).get_center())
	assert_eq(bar.presses[&"heal"], 1, "the last one is pressable")
	assert_eq(bar.action_for_key(KEY_7), &"heal")
