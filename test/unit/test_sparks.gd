extends GutTest
## Sparks: a burst of short bright streaks wherever something hits something
## (shots on ships, pods, obstacles and Tetran's arms, rams, scrapes, and
## vulcan rounds meeting enemy shots). Local only; they fly out and fade.

const BulletScene := preload("res://scenes/bullet.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _sparks() -> Array:
	return game.get_node("Effects").get_children().filter(func(n): return n is Sparks)


func _shot(at: Vector2, shooter := 5) -> Area2D:
	var b: Area2D = BulletScene.instantiate()
	b.shooter = shooter
	b.position = at
	game.get_node("Bullets").add_child(b)
	return b


func test_they_fly_out_and_fade() -> void:
	var s := Sparks.spawn(game.get_node("Effects"), Vector2(100, 100), Vector2.UP)
	assert_eq(s.spark_count(), 7)
	for sp in s._sparks:
		assert_gt(sp.vel.y, 0.0, "back the way the hit came from")
	s._process(Sparks.LIFE + 0.01)
	assert_true(s.is_queued_for_deletion())


func test_shots_on_enemies_spark() -> void:
	game.spawn_group(preload("res://scripts/enemy.gd").WEAVER, 270.0, 1)
	var e: Area2D = game.get_node("Enemies").get_children().back()
	e._on_area_entered(_shot(e.position))
	assert_eq(_sparks().size(), 1)


func test_shots_on_players_spark() -> void:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = Vector2(270, 700)
	game.get_node("Players").add_child(p)
	p._on_area_entered(_shot(p.position))
	assert_eq(_sparks().size(), 1)


func test_shots_on_obstacles_spark() -> void:
	game.spawn_obstacle({"name": "Obstacle1", "piece": "asteroid_l", "x": 270.0, "y": 300.0, "count": 1, "dir": 1.0})
	var o: Area2D = game.get_node("Obstacles/Obstacle1")
	o._on_area_entered(_shot(o.position))
	assert_eq(_sparks().size(), 1)


func test_vulcan_rounds_meeting_shots_spark() -> void:
	game.fire_enemy_bullet(Vector2(270, 300), Vector2.DOWN)
	var shot: Area2D = game.get_node("Bullets").get_children().back()
	game.fire_bullet(Vector2(270, 310), Color.RED, Vector2.UP, preload("res://scripts/bullet.gd").VULCAN)
	var round: Area2D = game.get_node("Bullets").get_children().back()
	round._on_area_entered(shot)
	assert_eq(_sparks().size(), 1)


func test_heal_shots_dont_spark() -> void:
	game.spawn_group(preload("res://scripts/enemy.gd").WEAVER, 270.0, 1)
	var e: Area2D = game.get_node("Enemies").get_children().back()
	var b := _shot(e.position)
	b.kind = preload("res://scripts/bullet.gd").HEAL
	e._on_area_entered(b)
	assert_eq(_sparks().size(), 0)


# --- Damage numbers ------------------------------------------------------------------

func _numbers() -> Array:
	return game.get_node("Effects").get_children().filter(func(n): return n is DamageNumber)


func test_your_hits_show_damage_numbers_x100() -> void:
	game.spawn_group(preload("res://scripts/enemy.gd").WEAVER, 270.0, 1)
	var e: Area2D = game.get_node("Enemies").get_children().back()
	e._on_area_entered(_shot(e.position, multiplayer.get_unique_id()))
	assert_eq(_numbers().size(), 1)
	assert_eq(_numbers()[0].text(), "100", "a photon hit")


func test_other_players_hits_dont_show() -> void:
	game.spawn_group(preload("res://scripts/enemy.gd").WEAVER, 270.0, 1)
	var e: Area2D = game.get_node("Enemies").get_children().back()
	e._on_area_entered(_shot(e.position, 77))
	assert_eq(_numbers().size(), 0)


func test_a_stream_on_one_target_rolls_into_one_number() -> void:
	var target := Node2D.new()
	game.get_node("Effects").add_child(target)
	for i in 8:
		DamageNumber.add(game.get_node("Effects"), target, 0.125)
	assert_eq(_numbers().size(), 1)
	assert_eq(_numbers()[0].text(), "100")
	var n: DamageNumber = _numbers()[0]
	n._process(DamageNumber.MERGE_TIME + 0.01)
	DamageNumber.add(game.get_node("Effects"), target, 0.125)
	assert_eq(_numbers().size(), 2, "after a pause, a new number")
	n._process(DamageNumber.FLOAT_TIME + 0.01)
	assert_true(n.is_queued_for_deletion(), "floated away")


func test_heals_read_plus_in_green_and_damage_taken_in_red() -> void:
	var target := Node2D.new()
	game.get_node("Effects").add_child(target)
	var h := DamageNumber.add(game.get_node("Effects"), target, 0.1, DamageNumber.HEAL, true)
	assert_eq(h.text(), "+10")
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = Vector2(270, 700)
	game.get_node("Players").add_child(p)
	p.take_damage(1.0)
	var taken := _numbers().filter(func(n): return n.color == DamageNumber.TAKE)
	assert_eq(taken.size(), 1)
	assert_eq(taken[0].text(), "100")
