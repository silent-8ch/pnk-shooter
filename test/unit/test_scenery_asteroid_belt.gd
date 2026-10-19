extends GutTest
## Asteroid Belt scenery: parallax rocks behind, medium asteroids split in two,
## rock showers on a seeded schedule, and a boss that hurls rocks.

const BeltScript := preload("res://scripts/scenery/asteroid_belt.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _belt() -> Node2D:
	game.kind = "asteroid_belt"
	game._process(0.0)
	return game.scenery


func _pieces(id: String) -> Array:
	return game.get_node("Obstacles").get_children().filter(func(o): return o.piece_id == id and not o.is_queued_for_deletion())


func test_kind_installs_its_scenery() -> void:
	var s := _belt()
	assert_not_null(s)
	assert_true(s.get_script().resource_path.ends_with("scenery/asteroid_belt.gd"))


func test_level_loads_with_its_kind() -> void:
	var level = LevelKinds.load_level("asteroid_belt")
	assert_not_null(level)
	assert_eq(level.kind, "asteroid_belt")
	assert_true(level.repeat)
	assert_between(level.length, 90.0, 120.0)
	var types := {}
	for e in level.events:
		types[e.type] = true
	assert_true(types.has(EnemyScript.WEAVER))
	assert_true(types.has(EnemyScript.TANK))
	assert_true(types.has(-1), "has obstacle events")


func test_medium_asteroid_splits_into_two_small_ones_nearby() -> void:
	var s := _belt()
	var at := Vector2(270, 400)
	s.on_obstacle_destroyed("asteroid_m", at)
	var small := _pieces("asteroid_s")
	assert_eq(small.size(), 2)
	for o in small:
		assert_almost_eq(o.position.distance_to(at), BeltScript.SPLIT_OFFSET, 0.5)


func test_other_pieces_do_not_split() -> void:
	var s := _belt()
	s.on_obstacle_destroyed("asteroid_s", Vector2(270, 400))
	s.on_obstacle_destroyed("debris", Vector2(270, 400))
	assert_eq(game.get_node("Obstacles").get_child_count(), 0)


func test_rock_shower_falls_in_on_schedule() -> void:
	var s := _belt()
	s.time = BeltScript.SHOWER_FIRST - 0.1
	s.step(0.0)
	assert_eq(_pieces("asteroid_s").size(), 0, "nothing before the first shower")
	s.time = BeltScript.SHOWER_FIRST + 0.01
	s.step(0.0)
	var n := _pieces("asteroid_s").size()
	assert_between(n, BeltScript.SHOWER_ROCKS.x, BeltScript.SHOWER_ROCKS.y)
	assert_eq(n, s.shower(0).size())
	s.step(0.0)
	assert_eq(_pieces("asteroid_s").size(), n, "each shower falls once")
	for o in _pieces("asteroid_s"):
		assert_lt(o.position.y, 0.0, "starts above the screen")


func test_shower_schedule_is_deterministic_from_the_seed() -> void:
	var a := BeltScript.new()
	var b := BeltScript.new()
	var c := BeltScript.new()
	a.run_seed = 1234
	b.run_seed = 1234
	c.run_seed = 99
	var differs := false
	for k in 5:
		assert_eq(a.shower_time(k), b.shower_time(k))
		assert_eq(a.shower(k), b.shower(k))
		if a.shower(k) != c.shower(k):
			differs = true
	assert_true(differs, "another seed gives other showers")
	a.free()
	b.free()
	c.free()


func test_shower_rocks_stay_on_screen_sideways() -> void:
	var s := BeltScript.new()
	for seed in 20:
		s.run_seed = seed
		for at in s.shower(seed):
			assert_between(at.x, 0.0, 540.0)
	s.free()


func test_boss_attack_fires_a_wide_arc() -> void:
	var s := _belt()
	var boss := Node2D.new()
	boss.position = Vector2(270, 150)
	var target := Node2D.new()
	target.position = Vector2(270, 800)
	add_child_autofree(boss)
	add_child_autofree(target)
	assert_true(s.boss_attack(boss, target, 3))
	assert_eq(game.get_node("Bullets").get_child_count(), 3 + BeltScript.BOSS_EXTRA_SHOTS)
	assert_eq(_pieces("asteroid_s").size(), 0, "no rocks on the first attack")


func test_boss_throws_rocks_every_few_attacks() -> void:
	var s := _belt()
	var boss := Node2D.new()
	boss.position = Vector2(270, 150)
	var target := Node2D.new()
	target.position = Vector2(500, 800)
	add_child_autofree(boss)
	add_child_autofree(target)
	for i in BeltScript.BOSS_ROCK_EVERY:
		s.boss_attack(boss, target, 3)
	var rocks := _pieces("asteroid_s")
	assert_between(rocks.size(), BeltScript.BOSS_ROCKS.x, BeltScript.BOSS_ROCKS.y)
	for o in rocks:
		assert_gt(o.position.y, boss.position.y, "in front of the boss")
		assert_between(o.position.x, 0.0, 540.0)


func test_draws_without_errors() -> void:
	var s := _belt()
	s.time = 37.0
	await wait_process_frames(2)
	assert_gt(s.time, 37.0)
