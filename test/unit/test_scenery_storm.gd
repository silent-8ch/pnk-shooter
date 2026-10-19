extends GutTest
## Ion Storm: lightning strikes warn then hurt ships at their spot, gusts push
## ships sideways, and the boss calls down chain lightning plus a spread.

const PlayerScene := preload("res://scenes/player.tscn")
const StormScript := preload("res://scripts/scenery/storm.gd")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.kind = "storm"
	game._process(0.0)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _ship(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _health(p: Node) -> float:
	return p.hp + p.shield


func _storm(seed_v: int) -> Node2D:
	var s: Node2D = StormScript.new()
	s.run_seed = seed_v
	autofree(s)
	return s


func test_storm_kind_installs_its_scenery() -> void:
	assert_true(game.scenery.get_script().resource_path.ends_with("scripts/scenery/storm.gd"))


func test_level_loads() -> void:
	var l = LevelKinds.load_level("storm")
	assert_not_null(l)
	assert_eq(l.kind, "storm")
	assert_true(l.repeat)


func test_strikes_come_every_few_seconds() -> void:
	var s := _storm(7)
	var hits: Array = s.strikes_between(0.0, 60.0)
	assert_between(hits.size(), 14, 24)
	for i in range(1, hits.size()):
		var gap: float = hits[i].time - hits[i - 1].time
		assert_between(gap, 2.49, 4.01)
	for h in hits:
		assert_true(s.STRIKE_AREA.has_point(h.pos) or s.STRIKE_AREA.end.is_equal_approx(h.pos))


func test_strike_schedule_is_deterministic() -> void:
	var a: Array = _storm(42).strikes_between(0.0, 100.0)
	var b: Array = _storm(42).strikes_between(0.0, 100.0)
	assert_eq(a, b)
	assert_ne(a, _storm(43).strikes_between(0.0, 100.0), "another seed, another storm")


func test_strikes_between_splits_cleanly() -> void:
	var s := _storm(5)
	var whole: Array = s.strikes_between(0.0, 30.0)
	var parts: Array = s.strikes_between(0.0, 13.0) + s.strikes_between(13.0, 30.0)
	assert_eq(whole, parts)


func test_strike_hurts_ship_at_its_spot_not_far_one() -> void:
	var s: Node2D = game.scenery
	var hit: Dictionary = s.strikes_between(0.0, 10.0)[0]
	var near := _ship(1, hit.pos)
	var far_pos: Vector2 = hit.pos + Vector2(0, 300) if hit.pos.y < 500 else hit.pos - Vector2(0, 300)
	var far := _ship(2, far_pos)
	far.ai = true
	var near_hp := _health(near)
	var far_hp := _health(far)
	s.time = hit.time
	s.step(0.0)
	assert_lt(_health(near), near_hp, "struck")
	assert_eq(_health(far), far_hp, "out of reach")


func test_no_strike_before_its_time() -> void:
	var s: Node2D = game.scenery
	var hit: Dictionary = s.strikes_between(0.0, 10.0)[0]
	var p := _ship(1, hit.pos)
	var hp := _health(p)
	s.time = hit.time - 0.5
	s.step(0.0)
	assert_eq(_health(p), hp, "still only a warning")


func test_wind_is_sideways_bounded_and_shared() -> void:
	var a := _storm(9)
	var b := _storm(9)
	var moved := false
	for i in 200:
		a.time = i * 0.37
		b.time = a.time
		var w: Vector2 = a.push_at(Vector2(100, 400))
		assert_eq(w.y, 0.0)
		assert_lte(absf(w.x), a.WIND_MAX + 0.001)
		assert_eq(w, b.push_at(Vector2(400, 800)), "same everywhere and on every peer")
		if absf(w.x) > 20.0:
			moved = true
	assert_true(moved, "gusts actually push")


func test_wind_changes_over_time() -> void:
	var s := _storm(3)
	var signs := {}
	for i in 100:
		signs[signf(s.wind(i * 1.5))] = true
	assert_true(signs.has(1.0) and signs.has(-1.0), "gusts blow both ways")


func test_darkness_overlay_draws_on_top() -> void:
	var o: Node2D = game.scenery.get_node("StormOverlay")
	assert_eq(o.z_index, 50)


func test_boss_chain_lightning_and_spread() -> void:
	var s: Node2D = game.scenery
	var target := _ship(1, Vector2(270, 700))
	var boss := Node2D.new()
	boss.position = Vector2(270, 150)
	autofree(boss)
	var bullets := game.get_node("Bullets")
	var before := bullets.get_child_count()
	s.time = 0.0
	assert_true(s.boss_attack(boss, target, 4))
	assert_eq(bullets.get_child_count() - before, 4, "aimed spread fired")
	assert_eq(s.chain_pending(), 3, "three strikes warning")
	var hp := _health(target)
	s.step(0.5)
	assert_eq(_health(target), hp, "still warning")
	s.step(0.6)
	assert_eq(s.chain_pending(), 0)
	assert_lt(_health(target), hp, "chain lightning hit the target")


func test_chain_spots_are_deterministic_and_near_target() -> void:
	var a: PackedVector2Array = _storm(1).chain_spots(Vector2(270, 600), 3)
	var b: PackedVector2Array = _storm(1).chain_spots(Vector2(270, 600), 3)
	assert_eq(a, b)
	assert_eq(a.size(), 3)
	assert_eq(a[0], Vector2(270, 600))
	for p in a:
		assert_lte(p.distance_to(Vector2(270, 600)), 96.0)
