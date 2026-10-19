extends GutTest
## Beam: a WEAPONS gun (3 bars) with a BEAM button that, once armed, pours a
## dense stream of lasers straight up from where it was fired, for a moment;
## levels make it thicker and longer.

const PlayerScript := preload("res://scripts/player.gd")

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


func _buy_beam() -> void:
	for i in player.price(&"beam"):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(&"beam"))


## Room in WEAPONS (and the reactor) for it, then armed.
func _arm_beam() -> void:
	player.levels[&"reactor"] = Systems.max_level(&"reactor")
	player.levels[&"weapons"] = Systems.max_level(&"weapons")
	assert_true(player.arm(&"beam"))


func _bullets() -> Array:
	return game.get_node("Bullets").get_children()


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		player._simulate(1.0 / 60.0)
		t += 1.0 / 60.0


func test_a_weapons_gun() -> void:
	assert_true(Systems.is_gun(&"beam"))
	assert_eq(Systems.max_level(&"beam"), 3)
	assert_eq(Systems.gun_power(&"beam"), 3)


func test_button_appears_when_bought() -> void:
	player._gather_input()
	assert_false(bar.is_shown(&"beam"))
	_buy_beam()
	player._gather_input()
	assert_true(bar.is_shown(&"beam"))
	assert_false(bar._lit.get(&"beam", false), "shows OFF until armed")
	player.levels[&"reactor"] = 5
	player.levels[&"weapons"] = 4
	assert_true(bar.press(&"beam"))
	player._gather_input()
	player._simulate(0.016)
	assert_true(player.is_armed(&"beam"), "the first tap arms it")
	assert_false(player.beam_active(), "without firing")
	bar._process(PlayerScript.BEAM_COOLDOWN + 0.1)
	assert_true(bar.press(&"beam"))
	player._gather_input()
	player._simulate(0.016)
	assert_true(player.beam_active(), "the next one fires")


func test_dense_stream_for_a_moment() -> void:
	_buy_beam()
	_arm_beam()
	player._beam_requested = true
	_run(PlayerScript.BEAM_TIMES[0])
	var n := _bullets().size()
	assert_almost_eq(n, int(PlayerScript.BEAM_TIMES[0] / PlayerScript.BEAM_INTERVAL), 2, "a bullet every interval")
	_run(0.5)
	assert_false(player.beam_active(), "lasts a moment")
	assert_eq(_bullets().size(), n, "then stops")


func test_stream_stays_where_it_started() -> void:
	_buy_beam()
	_arm_beam()
	player._beam_requested = true
	player._simulate(0.016)
	var origin_x := player.position.x
	player.position.x += 150
	_run(0.3)
	for b in _bullets():
		assert_almost_eq(b.position.x, origin_x, 0.01)
		assert_eq(b.direction, Vector2.UP)


func test_upgrades_make_it_thicker_and_longer() -> void:
	_buy_beam()
	_arm_beam()
	assert_eq(player.beam_columns(), 1)
	var t1: float = player.beam_time()
	_buy_beam()
	_buy_beam()
	assert_eq(player.level(&"beam"), 3)
	assert_eq(player.beam_columns(), 5, "thicker")
	assert_gt(player.beam_time(), t1, "persists longer")
	player._beam_requested = true
	player._simulate(0.016)
	var xs := {}
	for b in _bullets():
		xs[snappedf(b.position.x - player.position.x, 0.01)] = true
	assert_eq(xs.size(), 5)


func test_cooldown() -> void:
	assert_eq(ActionBar.cooldown_of(&"beam"), PlayerScript.BEAM_COOLDOWN)
	_buy_beam()
	_arm_beam()
	player._beam_requested = true
	_run(1.0)
	var n := _bullets().size()
	player._beam_requested = true
	_run(0.5)
	assert_eq(_bullets().size(), n, "not again until the cooldown ends")
	_run(PlayerScript.BEAM_COOLDOWN)
	player._beam_requested = true
	_run(0.2)
	assert_gt(_bullets().size(), n)


func test_without_the_upgrade_nothing_fires() -> void:
	player._beam_requested = true
	_run(0.5)
	assert_eq(_bullets().size(), 0)


func test_bought_but_not_armed_nothing_fires() -> void:
	_buy_beam()
	assert_false(player.arm(&"beam"), "not enough WEAPONS bars")
	player._beam_requested = true
	_run(0.5)
	assert_eq(_bullets().size(), 0)


func test_stops_when_ship_is_lost() -> void:
	_buy_beam()
	_arm_beam()
	player._beam_requested = true
	player._simulate(0.016)
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(0.016)
	assert_false(player.beam_active())
