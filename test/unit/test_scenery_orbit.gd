extends GutTest
## Planet Orbit scenery: a planet off one side, gravity toward it, debris rings
## every RING_INTERVAL s from the host, and the boss's orbital strike.

const PlayerScene := preload("res://scenes/player.tscn")
const OrbitScript := preload("res://scripts/scenery/orbit.gd")

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


func _orbit(seed := 1234) -> Node2D:
	var s: Node2D = OrbitScript.new()
	s.game = game
	s.run_seed = seed
	add_child_autofree(s)
	return s


func _ship(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func test_kind_installs_orbit_scenery() -> void:
	game.kind = "orbit"
	game._process(0.0)
	assert_true(game.scenery.get_script().resource_path.ends_with("scenery/orbit.gd"))


func test_level_loads() -> void:
	var l = LevelKinds.load_level("orbit")
	assert_not_null(l)
	assert_eq(l.kind, "orbit")


func test_planet_side_comes_from_seed() -> void:
	var sides := {}
	for i in 20:
		var s := _orbit(i)
		assert_eq(s.side, _orbit(i).side, "same seed, same side")
		sides[s.side] = true
		assert_true(s.center.x < 0.0 if s.side < 0.0 else s.center.x > 540.0, "center off screen on its side")
	assert_eq(sides.size(), 2, "both sides happen")


func test_gravity_pulls_toward_the_planet_gently() -> void:
	var s := _orbit()
	var near_x := 200.0 if s.side < 0.0 else 340.0
	var far_x := 520.0 if s.side < 0.0 else 20.0
	var near: Vector2 = s.push_at(Vector2(near_x, 470))
	var far: Vector2 = s.push_at(Vector2(far_x, 470))
	assert_eq(signf(near.x), s.side, "toward the planet's side")
	assert_eq(signf(far.x), s.side)
	assert_between(near.length(), 40.0, 60.0, "near the planet")
	assert_lt(far.length(), near.length(), "weaker far away")
	assert_lt(near.length(), 340.0 * 0.25, "easily out-flown")


func test_ring_schedule_is_deterministic() -> void:
	var a := _orbit(77)
	var b := _orbit(77)
	for k in 5:
		assert_eq(a.ring_time(k), b.ring_time(k))
		assert_eq(a.ring_layout(k), b.ring_layout(k))
	assert_almost_eq(a.ring_time(1) - a.ring_time(0), 15.0, 0.01)


func test_ring_has_a_gap_and_uses_debris_pieces() -> void:
	var s := _orbit()
	for k in 10:
		var ring: Array = s.ring_layout(k)
		assert_eq(ring.size(), s.RING_SLOTS - s.RING_GAP)
		for p in ring:
			assert_has(["debris", "asteroid_s"], p.piece)
			assert_lt(p.pos.y, 0.0, "starts above the screen")


func test_host_sends_rings_on_time() -> void:
	var s := _orbit()
	var obstacles := game.get_node("Obstacles")
	s.time = s.RING_FIRST - 0.1
	s.step(0.0)
	assert_eq(obstacles.get_child_count(), 0)
	s.time = s.RING_FIRST + 0.1
	s.step(0.0)
	assert_eq(obstacles.get_child_count(), s.RING_SLOTS - s.RING_GAP)
	s.step(0.0)
	assert_eq(obstacles.get_child_count(), s.RING_SLOTS - s.RING_GAP, "only once")


func test_boss_attack_fires_strikes_and_spread() -> void:
	var s := _orbit()
	var boss := Node2D.new()
	boss.position = Vector2(270, 140)
	add_child_autofree(boss)
	var target := Node2D.new()
	target.position = Vector2(270, 800)
	add_child_autofree(target)
	var bullets := game.get_node("Bullets")
	var before := bullets.get_child_count()
	assert_true(s.boss_attack(boss, target, 5))
	assert_eq(bullets.get_child_count() - before, 3 + s.SPREAD)
	var edge := 0
	for b in bullets.get_children():
		if absf(b.position.x - (s.STRIKE_INSET if s.side < 0.0 else 540.0 - s.STRIKE_INSET)) < 1.0:
			edge += 1
			assert_eq(signf(b.direction.x), -s.side, "across the screen, away from the planet")
	assert_eq(edge, 3, "strikes come from the planet's side")


func test_draws_without_errors() -> void:
	var s := _orbit()
	s.time = 12.0
	s.queue_redraw()
	await wait_process_frames(2)
	assert_true(is_instance_valid(s))
