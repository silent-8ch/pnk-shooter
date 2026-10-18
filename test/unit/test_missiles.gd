extends GutTest
## Seeking missiles: a meter slot that adds a MISSILE button; each press fires a
## smaller, darker (player-colored) laser from the ship and each option that
## turns toward the nearest enemy. Same damage as a laser, twice its cooldown at
## level 1. Levels, salvos and smoke trails: test_missile_tiers.gd.

const PlayerScript := preload("res://scripts/player.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")

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
	player.color = Color("ff7ad9")
	player.position = Vector2(270, 700)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _buy(id: StringName) -> void:
	for i in player.price(id):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(id), "bought %s" % id)


func _bullets() -> Array:
	return game.get_node("Bullets").get_children()


func _fire() -> void:
	player._missile_requested = true
	player._simulate(0.016)


func test_slot_and_its_own_button() -> void:
	assert_gte(PowerMeter.slot_index(&"missile", 1), 0)
	assert_gte(PowerMeter.slot_index(&"missile", 2), 0)
	player._gather_input()
	assert_false(bar.is_shown(&"missile"))
	_buy(&"missile")
	player._gather_input()
	assert_true(bar.is_shown(&"missile"))
	assert_ne(bar.button_rect(ActionBar.ACTIONS.map(func(a): return a.id).find(&"missile")), bar.button_rect(0))


func test_button_fires_a_missile() -> void:
	_buy(&"missile")
	player._gather_input()
	assert_true(bar.press(&"missile"))
	player._gather_input()
	player._simulate(0.016)
	assert_eq(_bullets().size(), 1)
	assert_true(_bullets()[0].is_seeking())


func test_cooldown_is_twice_the_laser() -> void:
	assert_eq(PlayerScript.MISSILE_COOLDOWN, PlayerScript.FIRE_COOLDOWN * 2.0)
	assert_eq(ActionBar.cooldown_of(&"missile"), PlayerScript.MISSILE_COOLDOWN)
	_buy(&"missile")
	_fire()
	player._simulate(PlayerScript.FIRE_COOLDOWN)
	_fire()
	assert_eq(_bullets().size(), 1, "still cooling down after one laser cooldown")
	player._simulate(PlayerScript.FIRE_COOLDOWN)
	_fire()
	assert_eq(_bullets().size(), 2)


func test_without_the_upgrade_nothing_fires() -> void:
	_fire()
	assert_eq(_bullets().size(), 0)


func test_smaller_and_darker_player_colored_laser() -> void:
	game.fire_bullet(Vector2(100, 500), player.color)
	game.fire_bullet(Vector2(200, 500), player.color, Vector2.UP, BulletScript.MISSILE)
	var laser: Area2D = _bullets()[0]
	var missile: Area2D = _bullets()[1]
	assert_almost_eq(missile.get_node("Body").scale.y, laser.get_node("Body").scale.y * BulletScript.KINDS[BulletScript.MISSILE].scale, 0.0001)
	var dark: Color = player.color.darkened(BulletScript.KINDS[BulletScript.MISSILE].darken)
	assert_eq(missile.get_node("Light").color, dark)
	assert_same(missile.get_node("Body").sprite_frames, BulletScript.frames_for(dark))


func test_options_fire_missiles_too() -> void:
	_buy(&"missile")
	_buy(&"option")
	player._process(0.0)
	_fire()
	assert_eq(_bullets().size(), 2)


func test_missile_turns_toward_the_nearest_enemy() -> void:
	var e: Area2D = EnemyScene.instantiate()
	e.position = Vector2(400, 500)
	game.get_node("Enemies").add_child(e)
	game.fire_bullet(Vector2(270, 700), player.color, Vector2.UP, BulletScript.MISSILE)
	var m: Area2D = _bullets()[0]
	var start_gap := m.position.distance_to(e.position)
	for i in 20:
		m._physics_process(1.0 / 60.0)
	assert_gt(m.direction.x, 0.0, "veers right toward it")
	assert_lt(m.position.distance_to(e.position), start_gap)
	assert_almost_eq(m.rotation, Vector2.UP.angle_to(m.direction), 0.0001)


func test_missile_flies_straight_with_no_enemies() -> void:
	game.fire_bullet(Vector2(270, 700), player.color, Vector2.UP, BulletScript.MISSILE)
	var m: Area2D = _bullets()[0]
	m._physics_process(0.1)
	assert_eq(m.direction, Vector2.UP)


func test_missile_does_laser_damage() -> void:
	var e: Area2D = EnemyScene.instantiate()
	game.get_node("Enemies").add_child(e)
	var hp: int = e.hp
	game.fire_bullet(e.position, player.color, Vector2.UP, BulletScript.MISSILE)
	e._on_area_entered(_bullets()[0])
	assert_true(e.hp == hp - 1 or e.is_queued_for_deletion(), "one damage, like a laser")
