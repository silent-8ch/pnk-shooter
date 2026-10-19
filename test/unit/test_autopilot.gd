extends GutTest
## AUTOPILOT (PILOTING 1): while you're not steering, the ship holds the spot you
## last moved it to, dodging enemies, obstacles and incoming shots, and comes
## back after.

const PlayerScene := preload("res://scenes/player.tscn")
const PlayerScript := preload("res://scripts/player.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")

var game: Node2D
var me: Area2D
var pointer: Control
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	pointer = game.get_node("PointerControls/Control")
	me = PlayerScene.instantiate()
	me.name = "1"
	me.peer_id = 1
	me.position = Vector2(270, 700)
	me.spawn_position = me.position
	game.get_node("Players").add_child(me)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _fly(seconds: float) -> void:
	for i in int(seconds * 60.0):
		me._gather_input()
		me._simulate(1.0 / 60.0)


## PILOTING bought and powered: the autopilot is on.
func _autopilot() -> void:
	me.levels[&"piloting"] = 1
	assert_true(me.add_power(&"piloting"))


func test_it_comes_with_piloting_power() -> void:
	assert_eq(me.level(&"autopilot"), 0)
	me.exp_balance = 10
	assert_true(me.buy_upgrade(&"piloting"))
	assert_eq(me.level(&"autopilot"), 0, "bought, not yet powered")
	assert_true(me.add_power(&"piloting"))
	assert_eq(me.level(&"autopilot"), 1)
	me.drain_power(&"piloting")
	assert_eq(me.level(&"autopilot"), 0)


func test_without_it_the_ship_sits_still() -> void:
	game.fire_enemy_bullet(Vector2(270, 600), Vector2.DOWN)
	_fly(0.3)
	assert_eq(me.position, Vector2(270, 700))


func test_holds_the_spot_you_last_moved_to() -> void:
	_autopilot()
	pointer.target = Vector2(150, 600)
	pointer.has_target = true
	_fly(2.0)
	assert_almost_eq(me.autopilot_anchor, Vector2(150, 600), Vector2(1, 1))
	assert_almost_eq(me.position, Vector2(150, 600), Vector2(6, 6), "flew there and stays")
	me.position = Vector2(250, 650)  # knocked away
	_fly(2.0)
	assert_almost_eq(me.position, Vector2(150, 600), Vector2(6, 6), "comes back")


func test_sidesteps_a_shot_coming_at_it() -> void:
	_autopilot()
	game.fire_enemy_bullet(Vector2(270, 560), Vector2.DOWN)
	var b: Area2D = game.get_node("Bullets").get_children().back()
	var hit := false
	for i in 60:
		me._gather_input()
		me._simulate(1.0 / 60.0)
		b._physics_process(1.0 / 60.0)
		if b.position.distance_to(me.position) < 12.0:
			hit = true
	assert_false(hit, "dodged")
	assert_gt(absf(me.position.x - 270.0), 5.0, "stepped aside")


func test_ignores_its_own_shots() -> void:
	_autopilot()
	game.fire_bullet(Vector2(270, 680), Color.WHITE, Vector2.UP)
	_fly(0.2)
	assert_almost_eq(me.position, Vector2(270, 700), Vector2(0.5, 0.5))


func test_slides_away_from_an_enemy_and_back() -> void:
	_autopilot()
	var e: Area2D = EnemyScene.instantiate()
	e.position = Vector2(280, 680)
	game.get_node("Enemies").add_child(e)
	_fly(0.3)
	assert_gt(me.position.distance_to(e.position), Vector2(270, 700).distance_to(e.position))
	e.free()
	_fly(2.0)
	assert_almost_eq(me.position, Vector2(270, 700), Vector2(6, 6))


func test_steering_overrides_it() -> void:
	_autopilot()
	pointer.target = Vector2(400, 700)
	pointer.has_target = true
	me._gather_input()
	assert_gt(me.input_dir.x, 0.0)
