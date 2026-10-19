extends GutTest
## Rivals: enemies that fly and fight like players, facing down. The host
## flies them (Rival): they hold the top of the screen, line up over a player
## and fire down, dodge players' shots, and other peers follow the host.

const EnemyScript := preload("res://scripts/enemy.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.level = null


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _player(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _rival(pos := Vector2(270, 150)) -> Area2D:
	game.spawn_rival()
	var e: Area2D = game.get_node("Enemies").get_children().back()
	e.position = pos
	return e


func _fly(e: Area2D, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		e._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0


func _hostile() -> Array:
	return game.get_node("Bullets").get_children().filter(func(b): return b.is_hostile())


func test_a_rival_is_a_player_ship_facing_down() -> void:
	var e := _rival()
	assert_true(e.is_rival())
	assert_eq(e.type, EnemyScript.RIVAL)
	assert_true(e.ship_override >= 0 and e.ship_override < Ships.count(), "a random player ship")
	assert_true(e.body.flip_v, "facing down")
	assert_eq(e.hp, 4)


func test_it_lines_up_over_the_player_and_fires_down() -> void:
	_player(Vector2(400, 750))
	var e := _rival(Vector2(150, 160))
	_fly(e, 3.0)
	assert_almost_eq(e.position.x, 400.0, Rival.AIM * 2.0, "over the player")
	assert_lte(e.position.y, Rival.BOTTOM_Y + 0.1, "keeps to the top")
	var shots := _hostile()
	assert_gt(shots.size(), 0)
	for b in shots:
		assert_eq(b.direction, Vector2.DOWN)


func test_more_shots_at_later_stages() -> void:
	assert_eq(Rival.shots_for(0), 1)
	assert_eq(Rival.shots_for(Rival.DOUBLE_AT), 2)
	assert_eq(Rival.shots_for(Rival.TRIPLE_AT), 3)
	assert_eq(Rival.volley(Vector2(100, 100), 3).size(), 3)


func test_it_dodges_a_shot_coming_up_at_it() -> void:
	_player(Vector2(270, 750))
	var e := _rival(Vector2(270, 170))
	game.fire_bullet(Vector2(270, 300), Color.RED)  # a player's photon, flying up at it
	var shot: Area2D = game.get_node("Bullets").get_children().back()
	var closest := INF
	for i in 30:
		e._physics_process(1.0 / 60.0)
		shot.position += shot.velocity() / 60.0
		closest = minf(closest, e.position.distance_to(shot.position))
	assert_gt(closest, Rival.RADIUS + 4.0, "out of the way")


func test_other_peers_follow_the_hosts_positions() -> void:
	var e := _rival(Vector2(100, 150))
	e.rival_at(Vector2(300, 200))
	assert_eq(e._rival_target, Vector2(300, 200))


func test_now_and_then_a_wave_brings_one_never_more_than_two() -> void:
	seed(4)
	for i in 200:
		game._maybe_rival()
	assert_eq(game.rivals_alive(), game.RIVAL_MAX)


func test_no_rivals_during_a_boss() -> void:
	game.spawn_boss()
	seed(1)
	for i in 100:
		game._maybe_rival()
	assert_eq(game.rivals_alive(), 0)
