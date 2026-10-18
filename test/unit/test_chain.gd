extends GutTest
## Chain reactions: out-of-control wrecks collide with ships and pods and blow
## up early; blasts destroy enemies and pods nearby (whose wrecks can blow up
## more) and hurt players; escape pods can be shot and blow up small.

const EnemyScene := preload("res://scenes/enemy.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")
const PlayerScript := preload("res://scripts/player.gd")
const WreckScript := preload("res://scripts/wreck.gd")
const PodScript := preload("res://scripts/escape_pod.gd")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _enemy(pos: Vector2) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.position = pos
	game.get_node("Enemies").add_child(e)
	return e


func _player(pos: Vector2) -> Area2D:
	var p: Area2D = preload("res://scenes/player.tscn").instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _wreck(pos: Vector2, wreck_name := "WreckT") -> Node2D:
	game.play_wreck(pos, 0, 7, wreck_name)
	return game.get_node("Effects/" + wreck_name)


func _wrecks() -> Array:
	return game.get_node("Effects").get_children().filter(func(n): return n is WreckScript)


func test_wreck_hitting_an_enemy_destroys_it_and_blows_up() -> void:
	var w := _wreck(Vector2(270, 300))
	var e := _enemy(w.hull_position())
	w._process(0.001)
	assert_true(e.is_queued_for_deletion(), "the other ship goes too")
	assert_true(w.exploded, "blown up early")
	assert_eq(_wrecks().size(), 2, "its own wreck carries the chain on")


func test_wreck_hitting_a_player_hurts_and_blows_up() -> void:
	var w := _wreck(Vector2(270, 300))
	var p := _player(w.hull_position())
	w._process(0.001)
	assert_true(w.exploded)
	assert_lt(p.hp, PlayerScript.MAX_HP)


func test_wreck_hitting_a_pod_destroys_it() -> void:
	var w := _wreck(Vector2(270, 300))
	game.spawn_pod(w.hull_position(), 0, "PodX")
	w._process(0.001)
	assert_true(w.exploded)
	assert_false(game.get_node("Pods").has_node("PodX"))


func test_wreck_ignores_its_own_pod() -> void:
	game.play_wreck(Vector2(270, 300), 0, 7, "WreckT", "PodOwn")
	game.spawn_pod(Vector2(270, 300), 0, "PodOwn", "WreckT")
	var w: Node2D = game.get_node("Effects/WreckT")
	w._process(0.001)
	assert_false(w.exploded)
	w.explode()
	assert_true(game.get_node("Pods").has_node("PodOwn"), "its blast spares it too")


func test_blast_takes_out_nearby_ships_but_not_far_ones() -> void:
	var w := _wreck(Vector2(270, 300))
	w.explode()
	var at: Vector2 = w.hull_position()
	var near := _enemy(at + Vector2(w.blast_radius() * 0.8, 0))
	var far := _enemy(at + Vector2(w.blast_radius() + 80, 0))
	game.blast(at, w.blast_radius())
	assert_true(near.is_queued_for_deletion())
	assert_false(far.is_queued_for_deletion())


func test_blast_hurts_the_local_player() -> void:
	var p := _player(Vector2(270, 300))
	game.blast(Vector2(280, 300), WreckScript.BLAST_RADIUS)
	assert_eq(p.hp, PlayerScript.MAX_HP - 1)


func test_chain_reaction_carries_on() -> void:
	var a := _enemy(Vector2(100, 300))
	a.take_damage(1)
	var w1: Node2D = _wrecks()[0]
	var b := _enemy(w1.hull_position() + Vector2(10, 0))  # in the first blast
	w1.explode()
	assert_true(b.is_queued_for_deletion(), "set off by a")
	var w2: Node2D = _wrecks().filter(func(w): return not w.exploded)[0]
	w2._process(0.001)
	var c := _enemy(w2.hull_position() + Vector2(10, 0))  # in the second
	w2.explode()
	assert_true(c.is_queued_for_deletion(), "set off by b")
	assert_eq(game.score, a.points() * 3, "chain kills score")


func test_shot_pod_blows_up_small() -> void:
	game.spawn_pod(Vector2(200, 300), 0, "Pod1")
	var pod: Area2D = game.get_node("Pods/Pod1")
	assert_eq(pod.collision_mask & 4, 4, "bullets hit it")
	var b: Area2D = BulletScene.instantiate()
	b.shooter = 1
	b.position = pod.position
	game.get_node("Bullets").add_child(b)
	pod._on_area_entered(b)
	assert_true(b.is_queued_for_deletion())
	assert_false(game.get_node("Pods").has_node("Pod1"))
	assert_lt(PodScript.BURST_HEIGHT, WreckScript.BLAST_HEIGHT / 2.0, "very small explosion")
	assert_lt(PodScript.BLAST_RADIUS, WreckScript.BLAST_RADIUS / 2.0)


func test_pod_blast_can_chain_to_a_touching_pod() -> void:
	game.spawn_pod(Vector2(200, 300), 0, "Pod1")
	game.spawn_pod(Vector2(210, 300), 0, "Pod2")
	game.report_pod_hit("Pod1")
	assert_false(game.get_node("Pods").has_node("Pod2"))


func test_others_bullets_dont_report_pod_hits() -> void:
	game.spawn_pod(Vector2(200, 300), 0, "Pod1")
	var pod: Area2D = game.get_node("Pods/Pod1")
	var b: Area2D = BulletScene.instantiate()
	b.shooter = 42
	game.get_node("Bullets").add_child(b)
	pod._on_area_entered(b)
	assert_true(b.is_queued_for_deletion(), "removed on every peer")
	assert_true(game.get_node("Pods").has_node("Pod1"), "its shooter reports it")


func test_destroyed_enemy_wreck_carries_its_pod_name() -> void:
	var e := _enemy(Vector2(300, 300))
	e.take_damage(1)
	var w: Node2D = _wrecks()[0]
	var pod: Node = game.get_node("Pods").get_child(0)
	assert_eq(w.pod_name, String(pod.name))
	assert_eq(pod.from_wreck, String(w.name))
