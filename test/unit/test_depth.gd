extends GutTest
## Depth: fake-3D scale and projection, enemies fanning out from the vanishing point, depth-scaled
## players and bullets, stars streaming out of the point.

const EnemyScene := preload("res://scenes/enemy.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")
const Starfield := preload("res://scripts/starfield.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


# --- Projection -------------------------------------------------------------

func test_scale_small_at_point_one_at_player_line_bigger_below() -> void:
	assert_almost_eq(Depth.scale_at(Depth.VANISH_Y), Depth.MIN_SCALE, 0.001)
	assert_almost_eq(Depth.scale_at(Depth.VANISH_Y - 50.0), Depth.MIN_SCALE, 0.001, "never below min")
	assert_almost_eq(Depth.scale_at(Depth.REF_Y), 1.0, 0.001)
	assert_gt(Depth.scale_at(940.0), 1.0)
	assert_lt(Depth.scale_at(400.0), Depth.scale_at(600.0))


func test_near_full_size_for_most_of_the_screen() -> void:
	var quarter := lerpf(Depth.VANISH_Y, Depth.REF_Y, 0.25)
	var half := lerpf(Depth.VANISH_Y, Depth.REF_Y, 0.5)
	assert_gt(Depth.scale_at(quarter), 0.6, "grows fast out of the point")
	assert_gt(Depth.scale_at(half), 0.8)
	assert_lt(Depth.scale_at(lerpf(Depth.VANISH_Y, Depth.REF_Y, 0.02)), 0.3, "still tiny right at the point")


func test_every_enemy_starts_at_the_vanishing_point() -> void:
	for x in [20.0, 270.0, 520.0]:
		var p := Depth.project(Vector2(x, Depth.WORLD_START))
		assert_almost_eq(p, Vector2(Depth.VANISH_X, Depth.VANISH_Y), Vector2(0.001, 0.001))


func test_player_line_is_unchanged() -> void:
	for x in [20.0, 270.0, 520.0]:
		assert_almost_eq(Depth.project(Vector2(x, Depth.REF_Y)), Vector2(x, Depth.REF_Y), Vector2(0.01, 0.01))


func test_path_only_heads_down() -> void:
	var prev := Depth.screen_y(Depth.WORLD_START)
	for i in range(1, 30):
		var y := Depth.screen_y(Depth.WORLD_START + i * 35.0)
		assert_gt(y, prev)
		assert_gte(y, Depth.VANISH_Y)
		prev = y


func test_enemy_paths_are_straight_rays_from_the_point() -> void:
	var vp := Vector2(Depth.VANISH_X, Depth.VANISH_Y)
	for x in [20.0, 150.0, 520.0]:
		var dir := (Depth.project(Vector2(x, Depth.REF_Y)) - vp).normalized()
		for wy in [100.0, 300.0, 600.0, 1000.0]:
			var d := (Depth.project(Vector2(x, wy)) - vp).normalized()
			assert_almost_eq(d, dir, Vector2(0.001, 0.001), "x %s wy %s" % [x, wy])


# --- Enemies ----------------------------------------------------------------

func _spawned_enemy(x: float) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.world = Vector2(x, EnemyScript.SPAWN_Y)
	e.position = Depth.project(e.world)
	add_child_autofree(e)
	return e


func _step(e: Area2D, dt: float) -> void:
	e.simulate(dt)
	e._process(dt)


func test_enemy_starts_small_and_grows() -> void:
	var e := _spawned_enemy(270.0)
	e._process(0.0)
	var small: float = e.get_node("Shape").scale.x
	assert_almost_eq(small, Depth.MIN_SCALE, 0.01)
	for i in 100:
		_step(e, 0.1)
	assert_gt(e.get_node("Shape").scale.x, small * 4.0)


func test_enemy_fans_out_from_the_point_facing_down() -> void:
	var left := _spawned_enemy(60.0)
	var right := _spawned_enemy(480.0)
	left._process(0.0)
	right._process(0.0)
	assert_almost_eq(left.position, right.position, Vector2(0.001, 0.001), "same start point")
	assert_true(left.get_node("Body").flip_v)
	for i in 60:
		_step(left, 0.1)
		_step(right, 0.1)
		assert_true(left.get_node("Body").flip_v, "never flips")
	assert_lt(left.position.x, Depth.VANISH_X - 50.0)
	assert_gt(right.position.x, Depth.VANISH_X + 50.0)


func test_new_enemy_fades_in_as_it_moves() -> void:
	var e := _spawned_enemy(270.0)
	e._process(0.0)
	assert_eq(e.get_node("Body").modulate.a, 0.0)
	for i in 30:
		_step(e, 0.1)
	assert_eq(e.get_node("Body").modulate.a, 1.0)


func test_enemy_leaves_by_world_exit() -> void:
	var e := _spawned_enemy(270.0)
	e.world.y = EnemyScript.EXIT_Y + 1.0
	e._physics_process(0.0)
	assert_true(e.is_queued_for_deletion())


func test_wreck_is_sized_by_depth() -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.play_wreck(Vector2(270, 300), 0, 1)
	game.play_wreck(Vector2(270, Depth.REF_Y), 0, 1)
	var far: Node2D = game.get_node("Effects").get_child(0)
	var near: Node2D = game.get_node("Effects").get_child(1)
	assert_almost_eq(far._base_scale.x / near._base_scale.x, Depth.scale_at(300.0), 0.001)


# --- Players and bullets ----------------------------------------------------

func _player_in_game(y: float) -> Area2D:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	var p: Area2D = PlayerScene.instantiate()
	p.position = Vector2(270, y)
	game.get_node("Players").add_child(p)
	return p


func test_player_shrinks_flying_up_and_grows_flying_down() -> void:
	var p := _player_in_game(Depth.REF_Y)
	var body: Sprite2D = p.get_node("Body")
	var full := body.scale.y
	p.position.y = 500.0
	p._process(0.0)
	assert_almost_eq(body.scale.y, full * Depth.scale_at(500.0), 0.0001)
	assert_almost_eq(p.get_node("Shape").scale.x, Depth.scale_at(500.0), 0.0001)
	p.position.y = 930.0
	p._process(0.0)
	assert_gt(body.scale.y, full)
	assert_eq(p.get_node("Label").scale, Vector2.ONE, "name stays readable")


func test_player_cannot_fly_up_to_the_point() -> void:
	var p := _player_in_game(Depth.REF_Y)
	p.input_dir = Vector2.UP
	for i in 60:
		p._simulate(0.1)
	assert_almost_eq(p.position.y, p.TOP_Y, 0.001)
	p.input_dir = Vector2.DOWN
	for i in 60:
		p._simulate(0.1)
	assert_almost_eq(p.position.y, 940.0, 0.001)


func test_bullet_shrinks_and_vanishes_at_point() -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	var b: Area2D = BulletScene.instantiate()
	b.position = Vector2(270, Depth.REF_Y)
	game.get_node("Bullets").add_child(b)
	assert_almost_eq(b.scale.x, 1.0, 0.001)
	b.position.y = 400.0
	b._process(0.0)
	assert_almost_eq(b.scale.x, Depth.scale_at(400.0), 0.001)
	b.position.y = Depth.VANISH_Y + 1.0
	b._physics_process(0.01)
	assert_true(b.is_queued_for_deletion())


# --- Background -------------------------------------------------------------

func test_stars_stream_out_of_the_point() -> void:
	var sf: Node2D = Starfield.new()
	add_child_autofree(sf)
	var vp := Vector2(Depth.VANISH_X, Depth.VANISH_Y)
	var s := Vector3(2.0, -1.0, Starfield.FAR)
	var far := Starfield.project(s).distance_to(vp)
	s.z = 2.0
	var near := Starfield.project(s).distance_to(vp)
	assert_gt(near, far * 5.0, "moves outward as it nears")
	assert_lt(far, 10.0, "born close to the point")
	assert_almost_eq((Starfield.project(s) - vp).normalized(), Vector2(2, -1).normalized(), Vector2(0.001, 0.001), "on a ray")
	for i in 300:
		sf._process(0.05)
	for st in sf._stars:
		assert_between(st.z, Starfield.NEAR, Starfield.FAR)
		assert_true(Starfield.SCREEN.has_point(Starfield.project(st)))
