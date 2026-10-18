extends GutTest
## Autocannons: a meter slot in both tiers that adds an AUTO on/off button for
## a vulcan cannon; while on, it hoses whatever is closest within a short range
## (friendlies included) with lots of small, fast, low-damage rounds.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const BulletScript := preload("res://scripts/bullet.gd")

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
	player = PlayerScene.instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 600)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _buy_auto() -> void:
	for i in PowerMeter.slot_index(&"auto", player.tier) + 1:
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade())


func _enemy(pos: Vector2) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.position = pos
	game.get_node("Enemies").add_child(e)
	return e


func _friend(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "42"
	p.peer_id = 42
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _bullets() -> Array:
	return game.get_node("Bullets").get_children()


func test_slot_in_both_tiers() -> void:
	assert_eq(PowerMeter.max_level(&"auto", 1), 1)
	assert_eq(PowerMeter.max_level(&"auto", 2), 2)
	assert_eq(PowerMeter.SLOTS[PowerMeter.slot_index(&"auto")].label, "AUTOCAN")
	assert_gte(PowerMeter.slot_index(&"auto", 2), 0)


func test_button_appears_and_toggles() -> void:
	player._gather_input()
	assert_false(bar.is_shown(&"auto"))
	_buy_auto()
	player._gather_input()
	assert_true(bar.is_shown(&"auto"))
	assert_true(bar.press(&"auto"))
	player._gather_input()
	assert_true(player.autocannon_on, "must be switched on")
	bar._process(1.0)
	bar.press(&"auto")
	player._gather_input()
	assert_false(player.autocannon_on, "and off again")


func test_off_by_default_even_when_bought() -> void:
	_buy_auto()
	_enemy(player.position + Vector2(0, -60))
	player._simulate(0.5)
	assert_eq(_bullets().size(), 0)


func test_shoots_at_the_closest_thing_in_range() -> void:
	_buy_auto()
	player.autocannon_on = true
	_enemy(player.position + Vector2(100, 0))
	_enemy(player.position + Vector2(-50, 0))
	player._simulate(0.016)
	var shots := _bullets()
	assert_eq(shots.size(), 1)
	assert_lt(shots[0].direction.angle_to(Vector2.LEFT), PlayerScript.AUTO_SPREAD + 0.001, "aimed at the closer one")
	assert_eq(shots[0].kind, BulletScript.VULCAN)


func test_ignores_things_out_of_range() -> void:
	_buy_auto()
	player.autocannon_on = true
	_enemy(player.position + Vector2(0, -PlayerScript.AUTO_RANGE - 10))
	player._simulate(0.016)
	assert_eq(_bullets().size(), 0)


func test_targets_friendlies() -> void:
	_buy_auto()
	player.autocannon_on = true
	_friend(player.position + Vector2(0, 80))
	player._simulate(0.016)
	assert_eq(_bullets().size(), 1)
	assert_lt(absf(_bullets()[0].direction.angle_to(Vector2.DOWN)), PlayerScript.AUTO_SPREAD + 0.001)


func test_skips_dead_friendlies() -> void:
	_buy_auto()
	player.autocannon_on = true
	_friend(player.position + Vector2(0, 80)).hp = 0
	player._simulate(0.016)
	assert_eq(_bullets().size(), 0)


func test_hoses_lots_of_rounds() -> void:
	_buy_auto()
	player.autocannon_on = true
	_enemy(player.position + Vector2(0, -60))
	for i in 60:
		player._simulate(1.0 / 60.0)
	assert_gte(_bullets().size(), 12, "a dozen-plus rounds a second")
	var n := _bullets().size()
	player.tier = 2
	_buy_auto()
	assert_eq(player.level(&"auto"), 2)
	for i in 60:
		player._simulate(1.0 / 60.0)
	assert_gt(_bullets().size() - n, n, "level 2 fires faster")


func test_vulcan_rounds_are_small_fast_weak_and_short_range() -> void:
	var laser: Dictionary = BulletScript.KINDS[BulletScript.LASER]
	var vulcan: Dictionary = BulletScript.KINDS[BulletScript.VULCAN]
	assert_lt(vulcan.scale, laser.scale)
	assert_gt(vulcan.speed, laser.speed * 1.5)
	assert_lt(vulcan.damage, laser.damage)
	assert_lt(vulcan.range, 300.0)
	game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.RIGHT, BulletScript.VULCAN)
	var b: Area2D = _bullets()[0]
	assert_almost_eq(b.rotation, PI / 2.0, 0.001, "points where it flies")
	b._physics_process(0.1)
	assert_almost_eq(b.position, Vector2(270 + vulcan.speed * 0.1, 500), Vector2(0.01, 0.01))
	b._physics_process(0.2)
	assert_true(b.is_queued_for_deletion(), "fizzles")


func test_vulcan_makes_no_shoot_sound() -> void:
	game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.RIGHT, BulletScript.VULCAN)
	assert_false(game.get_node("ShootSound").playing)


func test_rounds_add_up_to_a_kill() -> void:
	var e := _enemy(Vector2(270, 300))
	var per: float = BulletScript.KINDS[BulletScript.VULCAN].damage
	var needed := int(ceil(1.0 / per))
	for i in needed - 1:
		game.report_hit(String(e.name), per)
	assert_false(e.is_queued_for_deletion(), "weak alone")
	game.report_hit(String(e.name), per)
	assert_true(e.is_queued_for_deletion() or e.hp <= 0)


func test_rounds_add_up_on_friendlies_too() -> void:
	var per: float = BulletScript.KINDS[BulletScript.VULCAN].damage
	for i in int(ceil(1.0 / per)) - 1:
		player.take_damage(per)
	assert_eq(player.hp, PlayerScript.MAX_HP)
	player.take_damage(per)
	assert_eq(player.hp, PlayerScript.MAX_HP - 1)


func test_lasers_still_go_straight_up() -> void:
	game.fire_bullet(Vector2(270, 500), Color.RED)
	var b: Area2D = _bullets()[0]
	b._physics_process(0.1)
	assert_almost_eq(b.position, Vector2(270, 458), Vector2(0.01, 0.01))
	assert_eq(b.rotation, 0.0)


func test_switched_off_when_ship_is_lost() -> void:
	_buy_auto()
	player.autocannon_on = true
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_false(player.autocannon_on)
	assert_eq(player.level(&"auto"), 0)
