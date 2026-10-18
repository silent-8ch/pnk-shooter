extends GutTest
## Enemy types built from ships 03-05: striker, tank, orbiter.

const EnemyScene := preload("res://scenes/enemy.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const LevelScript := preload("res://scripts/level.gd")


func _enemy(type: int, pos: Vector2, group_x := -1.0, dir := 1.0) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.type = type
	e.position = pos
	e.group_x = group_x
	e.zig_dir = dir
	add_child_autofree(e)
	return e


func test_every_ship_has_an_enemy_type() -> void:
	var ships := []
	for i in EnemyScript.WAVE_TYPES:
		ships.append(EnemyScript.TYPES[i].ship)
	assert_eq(ships, range(Ships.count()), "one wave type per ship, in order")


func test_new_types_use_their_ships() -> void:
	for pair in [[EnemyScript.STRIKER, 2], [EnemyScript.TANK, 3], [EnemyScript.ORBITER, 4]]:
		var e := _enemy(pair[0], Vector2(270, 100))
		assert_same(e.get_node("Body").texture, Ships.get_lit_enemy_texture(pair[1]))


func test_group_defaults_match_old_constants() -> void:
	assert_eq(EnemyScript.TYPES[EnemyScript.WEAVER].group, [EnemyScript.WEAVER_GROUP_MIN, EnemyScript.WEAVER_GROUP_MAX])
	assert_eq(EnemyScript.TYPES[EnemyScript.DIVER].group, [EnemyScript.DIVER_GROUP, EnemyScript.DIVER_GROUP])


func test_tank_is_tough_bigger_and_worth_more() -> void:
	var tank := _enemy(EnemyScript.TANK, Vector2(270, 100))
	var weaver := _enemy(EnemyScript.WEAVER, Vector2(270, 100))
	assert_gt(tank.hp, 1)
	assert_gt(tank.points(), weaver.points())
	var body: Sprite2D = tank.get_node("Body")
	var h := body.texture.get_size().y * body.scale.y
	assert_gt(h, EnemyScript.HEIGHT)
	assert_lt(h, Ships.SHIP_HEIGHT, "still smaller than players")


func test_tank_sways_and_drifts_slowly() -> void:
	var e := _enemy(EnemyScript.TANK, Vector2(270, -40))
	var xs := []
	for i in 60:
		e.simulate(0.1)
		xs.append(e.position.x)
	assert_gt(xs.max() - 270.0, EnemyScript.TANK_SWAY * 0.9)
	assert_lt(xs.min() - 270.0, -EnemyScript.TANK_SWAY * 0.9)
	assert_lt(e.position.y + 40.0, EnemyScript.TYPES[EnemyScript.WEAVER].speed * 6.0)


func test_strikers_creep_then_lunge_front_first() -> void:
	var pts := EnemyScript.group_layout(EnemyScript.STRIKER, 3, 270.0)
	var front := _enemy(EnemyScript.STRIKER, pts[0], 270.0)
	var back := _enemy(EnemyScript.STRIKER, pts[2], 270.0)
	assert_almost_eq(back.lunge_time() - front.lunge_time(), 2.0 * EnemyScript.LUNGE_STAGGER, 0.001)
	front.simulate(EnemyScript.LUNGE_TIME - 0.1)
	var y0 := front.position.y
	front.simulate(0.1)
	var creep := front.position.y - y0
	y0 = front.position.y
	front.simulate(0.1)
	assert_gt(front.position.y - y0, creep * 3.0, "lunges much faster than it creeps")
	assert_almost_eq(front.position.y - y0, EnemyScript.LUNGE_SPEED * 0.1, 0.01)
	assert_eq(front.position.x, pts[0].x, "lunges straight down")


func test_striker_layout_is_a_slanted_line() -> void:
	var pts := EnemyScript.group_layout(EnemyScript.STRIKER, 3, 270.0)
	assert_eq(pts[1], Vector2(270, EnemyScript.SPAWN_Y - EnemyScript.STRIKER_GAP.y))
	assert_eq(pts[2] - pts[1], Vector2(EnemyScript.STRIKER_GAP.x, -EnemyScript.STRIKER_GAP.y))


func test_orbiters_circle_a_falling_center() -> void:
	var pts := EnemyScript.group_layout(EnemyScript.ORBITER, 4, 270.0)
	var center := Vector2(270, EnemyScript.ORBIT_CENTER_Y)
	for p in pts:
		assert_almost_eq(p.distance_to(center), EnemyScript.ORBIT_RADIUS, 0.001)
	var es := []
	for p in pts:
		es.append(_enemy(EnemyScript.ORBITER, p, 270.0, 1.0))
	assert_almost_eq(es[0].position, pts[0], Vector2(0.01, 0.01), "starts where it spawned")
	for i in 20:
		for e in es:
			e.simulate(0.1)
	var fallen := EnemyScript.fall_distance(EnemyScript.ORBITER, 2.0)
	var c := center + Vector2(0, fallen)
	var sum := Vector2.ZERO
	for e in es:
		assert_almost_eq(e.position.distance_to(c), EnemyScript.ORBIT_RADIUS, 0.01, "stays on the ring")
		sum += e.position
	assert_almost_eq(sum / es.size(), c, Vector2(0.01, 0.01), "ring stays even")
	var a0: float = (pts[0] - center).angle()
	var a1: float = (es[0].position - c).angle()
	assert_almost_eq(wrapf(a1 - a0, -PI, PI), wrapf(EnemyScript.ORBIT_SPEED * 2.0, -PI, PI), 0.01, "turns at ORBIT_SPEED")


func test_orbit_direction_follows_dir() -> void:
	var p := EnemyScript.group_layout(EnemyScript.ORBITER, 4, 270.0)[0]  # top of the ring
	var cw := _enemy(EnemyScript.ORBITER, p, 270.0, 1.0)
	var ccw := _enemy(EnemyScript.ORBITER, p, 270.0, -1.0)
	cw.simulate(0.1)
	ccw.simulate(0.1)
	assert_gt(cw.position.x, 270.0)
	assert_lt(ccw.position.x, 270.0)


func test_fall_distance_matches_stepped_motion() -> void:
	var e := _enemy(EnemyScript.TANK, Vector2(270, -40))
	for i in 300:
		e.simulate(0.01)
	assert_almost_eq(e.position.y + 40.0, EnemyScript.fall_distance(EnemyScript.TANK, 3.0), 0.5)


func test_restore_resumes_closed_form_paths() -> void:
	var p := EnemyScript.group_layout(EnemyScript.ORBITER, 4, 270.0)[1]
	var a := _enemy(EnemyScript.ORBITER, p, 270.0)
	for i in 15:
		a.simulate(0.1)
	var b := _enemy(EnemyScript.ORBITER, p, 270.0)
	b.restore(a._time, a.position)
	a.simulate(0.1)
	b.simulate(0.1)
	assert_almost_eq(b.position, a.position, Vector2(0.001, 0.001))


func test_groups_fit_in_arena() -> void:
	for type in [EnemyScript.STRIKER, EnemyScript.TANK, EnemyScript.ORBITER]:
		var g: Array = EnemyScript.TYPES[type].group
		var half := EnemyScript.group_half_width(type, g[1])
		assert_lt(2.0 * (half + 20.0), EnemyScript.ARENA_WIDTH, "type %d" % type)
		for p in EnemyScript.group_layout(type, g[1], EnemyScript.ARENA_WIDTH / 2.0):
			assert_lt(absf(p.x - EnemyScript.ARENA_WIDTH / 2.0), half + 0.001)


func test_levels_name_the_new_types() -> void:
	assert_eq(LevelScript.TYPES.striker, EnemyScript.STRIKER)
	assert_eq(LevelScript.TYPES.tank, EnemyScript.TANK)
	assert_eq(LevelScript.TYPES.orbiter, EnemyScript.ORBITER)
