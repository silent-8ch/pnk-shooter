extends GutTest
## Planet Surface: a canyon over scrolling ground. The walls narrow and widen
## along the course but always leave a 300 px channel; they shove ships back
## and scrape them. The boss bombards the ground around its target.

const PlayerScene := preload("res://scenes/player.tscn")
const SurfaceScript := preload("res://scripts/scenery/surface.gd")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.level = null
	game.kind = "surface"
	game._process(0.0)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _ship(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	if id != 1:
		p.ai = true  # flown on this peer
	game.get_node("Players").add_child(p)
	return p


func _surface(seed: int) -> Node2D:
	var s: Node2D = SurfaceScript.new()
	s.run_seed = seed
	autofree(s)
	return s


func test_the_kind_installs_its_scenery_and_level() -> void:
	assert_string_ends_with(game.scenery.get_script().resource_path, "scenery/surface.gd")
	var lvl = LevelKinds.load_level("surface")
	assert_not_null(lvl)
	assert_eq(lvl.kind, "surface")
	assert_true(lvl.repeat)


func test_walls_always_leave_the_channel() -> void:
	var s := _surface(42)
	for t in 200:
		s.time = t * 0.7
		for y in range(0, 961, 40):
			var left: float = s.wall_width(0, y)
			var right: float = s.wall_width(1, y)
			assert_gt(left, 0.0)
			assert_true(540.0 - left - right >= 300.0, "channel at t=%s y=%s" % [s.time, y])


func test_walls_vary_and_are_deterministic() -> void:
	var a := _surface(7)
	var b := _surface(7)
	var c := _surface(8)
	var widths := {}
	var differs := false
	for t in 60:
		a.time = t * 1.3
		b.time = a.time
		c.time = a.time
		assert_eq(a.wall_width(0, 300.0), b.wall_width(0, 300.0))
		assert_eq(a.wall_width(1, 700.0), b.wall_width(1, 700.0))
		widths[snappedf(a.wall_width(0, 300.0), 1.0)] = true
		differs = differs or a.wall_width(0, 300.0) != c.wall_width(0, 300.0)
	assert_gt(widths.size(), 10, "the width changes over time")
	assert_true(differs, "another seed, another canyon")


func test_walls_scroll_with_the_ground() -> void:
	var s := _surface(3)
	s.time = 10.0
	var w: float = s.wall_width(0, 200.0)
	s.time = 11.0
	assert_almost_eq(s.wall_width(0, 260.0), w, 0.001, "a row moves down 60 px/s")


func test_walls_push_ships_back_into_the_channel() -> void:
	var s: Node2D = game.scenery
	assert_eq(s.push_at(Vector2(270, 400)), Vector2.ZERO, "clear in the middle")
	var left: Vector2 = s.push_at(Vector2(s.wall_width(0, 400.0) - 5.0, 400))
	assert_gt(left.x, 400.0, "strongly right out of the left wall")
	assert_eq(left.y, 0.0)
	var right: Vector2 = s.push_at(Vector2(540.0 - s.wall_width(1, 400.0) + 5.0, 400))
	assert_lt(right.x, -400.0, "left out of the right wall")


func test_scraping_a_wall_hurts_with_a_cooldown() -> void:
	var s: Node2D = game.scenery
	var p := _ship(7, Vector2(s.wall_width(0, 500.0), 500))
	var safe := _ship(8, Vector2(270, 500))
	var hp: float = p.hp
	s.step(0.0)
	var once: float = p.hp
	assert_lt(once, hp, "scraped")
	s.step(0.3)
	assert_eq(p.hp, once, "cooling down")
	p.position.x = s.wall_width(0, 500.0)  # walls moved a bit
	s.step(0.35)
	assert_lt(p.hp, once, "scraped again after the cooldown")
	assert_eq(safe.hp, safe.max_hp(), "ships in the channel are fine")


func test_boss_bombards_around_the_target() -> void:
	var s: Node2D = game.scenery
	var target := _ship(7, Vector2(270, 500))
	var far := _ship(8, Vector2(270, 850))
	var boss := Node2D.new()
	boss.position = Vector2(270, 150)
	add_child_autofree(boss)
	var bullets: int = game.get_node("Bullets").get_child_count()
	assert_true(s.boss_attack(boss, target, 4))
	assert_gt(game.get_node("Bullets").get_child_count(), bullets, "plus an aimed shot")
	assert_eq(s.strikes.size(), 3)
	assert_eq(s.strikes[0].pos, target.position, "one right on the target")
	var hp: float = target.hp
	s.step(0.5)
	assert_eq(target.hp, hp, "just a warning so far")
	var effects_before: int = game.get_node("Effects").get_child_count()
	s.step(0.6)
	assert_lt(target.hp, hp, "it blew up")
	var booms := game.get_node("Effects").get_children().filter(func(n): return n is AnimatedSprite2D)
	assert_gte(booms.size(), 3, "the painted explosions, not circles")
	assert_gt(game.get_node("Effects").get_child_count(), effects_before)
	assert_eq(far.hp, far.max_hp(), "far away is safe")
	s.step(0.5)
	assert_eq(s.strikes.size(), 0, "blasts fade")


func test_bomb_spots_are_deterministic_and_near() -> void:
	var a := _surface(5)
	var b := _surface(5)
	var at := Vector2(270, 500)
	for i in 10:
		var sa: PackedVector2Array = a.bomb_spots(i, at, 5)
		assert_eq(sa, b.bomb_spots(i, at, 5))
		for p in sa:
			assert_lt(p.distance_to(at), 91.0)
