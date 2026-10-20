extends GutTest
## The ship's systems in small console popups: only a SHIP button shows in play;
## it opens the systems popup, a row opens that system's popup (power - and +,
## UPGRADE, its items), BACK goes up, and SHIP or a tap outside closes it.

const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var panel: ShipPanel
var player: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	panel = game.get_node("PointerControls/ShipPanel")
	player = PlayerScene.instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 600)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _exp(n: int) -> void:
	for i in n:
		game.collect_pickup("none", 1)


## The button doing `action` (for `id`, if given).
func _button(action: StringName, id := &"") -> Dictionary:
	for b in panel.buttons():
		if b.action == action and (id == &"" or b.id == id):
			return b
	return {}


func _press(action: StringName, id := &"") -> void:
	var b := _button(action, id)
	assert_false(b.is_empty(), "%s %s is on screen" % [action, id])
	if not b.is_empty():
		panel.tap(b.rect.get_center())


func _touch(pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = pos
	panel._input(ev)


# --- In play ---------------------------------------------------------------------

func test_only_the_ship_button_shows_in_play() -> void:
	assert_false(panel.is_open())
	assert_eq(panel.buttons().size(), 1)
	var tab := panel.tab_rect()
	var screen := panel.get_viewport_rect().size
	assert_gt(tab.position.x, screen.x / 2.0, "bottom right, away from the action buttons")
	assert_lte(tab.end.y, screen.y - ActionBar.BAR_HEIGHT, "above the action bar")
	assert_lt(tab.size.x * tab.size.y, screen.x * screen.y * 0.02, "small")


## The misfire this fixes: the tab used to sit 20 px above PHOTONS in the same
## corner, so a thumb reaching for the gun opened the systems popup instead.
## It now goes to the far corner, so the guns a thumb lives on (the first three
## buttons) share no x with it, whichever hand the controls are set up for.
const THUMB_BUTTONS := 3


func test_ship_button_is_clear_of_the_gun_buttons() -> void:
	var bar: ActionBar = game.get_node("PointerControls/ActionBar")
	for a in ActionBar.ACTIONS:
		bar.set_shown(a.id, true)  # a fully upgraded bar: the widest it ever gets
	var was := Settings.left_handed
	for handed in [true, false]:
		Settings.left_handed = handed
		var tab := panel.tab_rect()
		for slot in THUMB_BUTTONS:
			var b := bar.button_rect(bar.shown_actions()[slot])
			var label: String = ActionBar.ACTIONS[bar.shown_actions()[slot]].label
			assert_true(tab.end.x <= b.position.x or b.end.x <= tab.position.x,
				"SHIP shares no x with %s (left_handed %s)" % [label, handed])
	Settings.left_handed = was


func test_closed_only_the_button_blocks_steering() -> void:
	assert_true(panel.contains(panel.tab_rect().get_center()))
	assert_false(panel.contains(Vector2(270, 300)))


# --- Systems popup ---------------------------------------------------------------

func test_ship_opens_the_systems_popup() -> void:
	_press(&"tab")
	assert_eq(panel.page, ShipPanel.SYSTEMS_PAGE)
	for id in ShipPanel.ROWS:
		assert_false(_button(&"open", id).is_empty(), String(id))


func test_popup_is_small_and_sits_above_the_button() -> void:
	_press(&"tab")
	var r := panel.popup_rect()
	var screen := panel.get_viewport_rect().size
	assert_lte(r.end.y, panel.tab_rect().position.y)
	assert_gte(r.position.y, 0.0)
	assert_lt(r.size.x, screen.x * 0.6, "a popup, not a screen")
	for b in panel.buttons():
		if b.action == &"open":
			assert_true(r.encloses(b.rect), String(b.id))


func test_rows_dont_overlap() -> void:
	_press(&"tab")
	var rects: Array = panel.buttons().map(func(b): return b.rect)
	for i in rects.size():
		for k in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[k]), "%d and %d" % [i, k])


func test_ship_again_closes_it() -> void:
	_press(&"tab")
	_press(&"tab")
	assert_false(panel.is_open())


func test_tap_outside_closes_it_without_steering() -> void:
	_press(&"tab")
	var outside := Vector2(450, 200)
	assert_true(panel.contains(outside), "a tap anywhere is the popup's while it's open")
	_touch(outside)
	assert_false(panel.is_open())
	assert_false(panel.contains(outside), "steering again once closed")


func test_open_popup_leaves_the_action_bar_alone() -> void:
	_press(&"tab")
	var screen := panel.get_viewport_rect().size
	assert_false(panel.contains(Vector2(270, screen.y - ActionBar.BAR_HEIGHT / 2.0)))


# --- One system ------------------------------------------------------------------

func test_a_row_opens_its_system_and_back_returns() -> void:
	_press(&"tab")
	_press(&"open", &"engines")
	assert_eq(panel.page, &"engines")
	assert_false(_button(&"power_up", &"engines").is_empty())
	assert_false(_button(&"power_down", &"engines").is_empty())
	assert_false(_button(&"buy", &"engines").is_empty(), "UPGRADE")
	_press(&"back")
	assert_eq(panel.page, ShipPanel.SYSTEMS_PAGE)


func test_plus_and_minus_move_power() -> void:
	_exp(10)
	player.buy_upgrade(&"engines")
	panel.page = &"engines"
	assert_eq(player.power_of(&"engines"), 1)
	_press(&"power_up", &"engines")
	assert_eq(player.power_of(&"engines"), 2)
	_press(&"power_down", &"engines")
	_press(&"power_down", &"engines")
	assert_eq(player.power_of(&"engines"), 0)
	_press(&"power_down", &"engines")
	assert_eq(player.power_of(&"engines"), 0, "no lower than off")


func test_plus_needs_a_spare_bar() -> void:
	_exp(10)
	player.buy_upgrade(&"engines")
	player.add_power(&"engines")  # the reactor's last bar
	assert_eq(player.power_spare(), 0)
	_exp(20)
	player.buy_upgrade(&"engines")
	panel.page = &"engines"
	_press(&"power_up", &"engines")
	assert_eq(player.power_of(&"engines"), 2)


func test_upgrade_buys_capacity() -> void:
	_exp(10)
	panel.page = &"engines"
	_press(&"buy", &"engines")
	assert_eq(player.levels[&"engines"], 2)
	assert_eq(player.power_of(&"engines"), 1, "comes unpowered")


func test_uninstalled_system_can_be_installed() -> void:
	_exp(10)
	panel.page = &"shields"
	_press(&"buy", &"shields")
	assert_eq(player.levels.get(&"shields", 0), 1)


func test_nothing_bought_without_exp() -> void:
	panel.page = &"engines"
	_press(&"buy", &"engines")
	assert_eq(player.levels[&"engines"], 1)


func test_weapons_lists_the_guns() -> void:
	panel.page = &"weapons"
	for id in [&"lasers", &"double", &"rapid", &"missile", &"auto", &"beam", &"healbeam"]:
		assert_false(_button(&"buy", id).is_empty(), String(id))
	_exp(20)
	_press(&"buy", &"missile")
	assert_eq(player.levels.get(&"missile", 0), 1)


func test_drones_and_hull_list_their_items() -> void:
	panel.page = &"drones"
	assert_false(_button(&"buy", &"option").is_empty())
	assert_false(_button(&"buy", &"rescue").is_empty())
	panel.page = &"hull"
	assert_false(_button(&"buy", &"armor").is_empty())
	assert_false(_button(&"buy", &"ship").is_empty())
	assert_true(_button(&"power_up").is_empty(), "the hull isn't powered")


func test_reactor_page_buys_bars() -> void:
	_exp(10)
	panel.page = &"reactor"
	_press(&"buy", &"reactor")
	assert_eq(player.reactor(), 4)
	assert_true(_button(&"power_up").is_empty())


func test_every_system_popup_fits_on_screen() -> void:
	for id in ShipPanel.ROWS:
		panel.page = id
		var r := panel.popup_rect()
		assert_gte(r.position.y, 0.0, String(id))
		for b in panel.buttons():
			if b.action != &"tab":
				assert_true(r.encloses(b.rect), "%s %s" % [id, b.action])


func test_taps_ignored_while_game_input_is_off() -> void:
	_exp(10)
	panel.page = &"engines"
	game.input_enabled = false
	_press(&"buy", &"engines")
	assert_eq(player.levels[&"engines"], 1)
	game.input_enabled = true


func test_pointer_controls_dont_steer_on_the_popup() -> void:
	_press(&"tab")
	var pointer: Node = game.get_node("PointerControls/Control")
	assert_true(pointer._on_action_bar(Vector2(450, 200)))
	panel.close()
	assert_false(pointer._on_action_bar(Vector2(450, 200)))


# --- Exp on the button ---------------------------------------------------------------

func test_ship_button_knows_when_exp_can_buy_something() -> void:
	var p: Node = player
	p.exp_balance = 0
	assert_false(ShipPanel.can_buy_something(p))
	p.exp_balance = 100
	assert_true(ShipPanel.can_buy_something(p))


# --- Pools: drones and piloting ----------------------------------------------------

func _tap_button(action: StringName, id: StringName) -> void:
	for b in panel.buttons():
		if b.action == action and b.id == id:
			panel.tap(b.rect.get_center())
			return
	fail_test("no %s button for %s" % [action, id])


func test_drones_popup_has_power_for_each_drone_kind() -> void:
	player.levels[&"reactor"] = 8
	player.levels[&"drones"] = 3
	player.levels[&"option"] = 2
	player.levels[&"rescue"] = 2
	panel.page = &"drones"
	var acts := panel.buttons().map(func(b): return [b.action, b.id])
	assert_has(acts, [&"power_up", &"option"])
	assert_has(acts, [&"power_up", &"rescue"])
	assert_has(acts, [&"power_down", &"rescue"])
	assert_does_not_have(acts, [&"power_up", &"drones"], "no power row for the pool itself")
	_tap_button(&"power_up", &"rescue")
	assert_eq(player.level(&"rescue"), 1, "rescue first, if you want")
	assert_eq(player.level(&"option"), 0)
	_tap_button(&"power_up", &"option")
	_tap_button(&"power_down", &"rescue")
	assert_eq(player.level(&"option"), 1)
	assert_eq(player.level(&"rescue"), 0)


func test_piloting_popup_powers_autopilot_and_beacon_apart() -> void:
	player.levels[&"reactor"] = 6
	player.levels[&"piloting"] = 1
	panel.page = &"piloting"
	var acts := panel.buttons().map(func(b): return [b.action, b.id])
	assert_has(acts, [&"power_up", &"beacon"])
	assert_does_not_have(acts, [&"buy", &"beacon"], "comes with PILOTING")
	_tap_button(&"power_up", &"beacon")
	assert_eq(player.level(&"beacon"), 1)
	assert_eq(player.level(&"autopilot"), 0)
