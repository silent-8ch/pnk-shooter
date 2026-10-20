extends GutTest
## Crystal Crevices: resonance beams warn then cut ships on the line, breaking
## crystal debris bursts, and the three part Crystal boss fires harder for every
## arm the party breaks off.

const PlayerScene := preload("res://scenes/player.tscn")
const CrystalScript := preload("res://scripts/scenery/crystal_crevices.gd")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.kind = "crystal_crevices"
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


func _scenery(seed_v: int) -> Node2D:
	var s: Node2D = CrystalScript.new()
	s.run_seed = seed_v
	autofree(s)
	return s


func test_kind_installs_its_scenery() -> void:
	assert_true(game.scenery.get_script().resource_path.ends_with("scripts/scenery/crystal_crevices.gd"))


func test_level_loads() -> void:
	var l = LevelKinds.load_level("crystal_crevices")
	assert_not_null(l)
	assert_eq(l.kind, "crystal_crevices")
	assert_true(l.repeat)


## --kind=<id> (Main._handle_cmdline -> Net.start_kind) drops a run straight
## into one kind of level instead of flying the forks to reach it.
func test_dev_flag_starts_a_run_in_this_kind() -> void:
	var was := Net.start_kind
	Net.start_kind = "crystal_crevices"
	game.start()
	assert_eq(game.kind, "crystal_crevices")
	assert_not_null(game.level)
	assert_eq(game.level.kind, "crystal_crevices")
	Net.start_kind = "not_a_level"
	game.start()
	assert_eq(game.kind, LevelKinds.FIRST, "a name that isn't a kind is ignored")
	Net.start_kind = ""
	game.start()
	assert_eq(game.kind, LevelKinds.FIRST, "unset: the usual Deep Space")
	Net.start_kind = was


func test_beams_come_every_few_seconds_wall_to_wall() -> void:
	var s := _scenery(7)
	var beams: Array = s.beams_between(0.0, 60.0)
	assert_between(beams.size(), 11, 19)
	for i in range(1, beams.size()):
		var gap: float = beams[i].time - beams[i - 1].time
		assert_between(gap, 3.09, 4.91)
	for b in beams:
		assert_eq(b.a.x, 0.0, "starts on the left wall")
		assert_eq(b.b.x, CrystalScript.ARENA.x, "ends on the right wall")
		for y in [b.a.y, b.b.y]:
			assert_between(y, CrystalScript.BEAM_BAND.x, CrystalScript.BEAM_BAND.y)


func test_beam_schedule_is_deterministic() -> void:
	var a: Array = _scenery(42).beams_between(0.0, 100.0)
	var b: Array = _scenery(42).beams_between(0.0, 100.0)
	assert_eq(a, b)
	assert_ne(a, _scenery(43).beams_between(0.0, 100.0), "another seed, another seam")


func test_beams_between_splits_cleanly() -> void:
	var s := _scenery(5)
	var whole: Array = s.beams_between(0.0, 30.0)
	var parts: Array = s.beams_between(0.0, 13.0) + s.beams_between(13.0, 30.0)
	assert_eq(whole, parts)


func test_beams_slant_so_no_row_is_safe() -> void:
	var s := _scenery(11)
	var slanted := false
	for b in s.beams_between(0.0, 200.0):
		if absf(b.a.y - b.b.y) > 40.0:
			slanted = true
	assert_true(slanted, "beams run at an angle, not just straight across")


func test_beam_cuts_a_ship_on_the_line_not_one_off_it() -> void:
	var s: Node2D = game.scenery
	var hit: Dictionary = s.beams_between(0.0, 10.0)[0]
	var mid: Vector2 = (hit.a + hit.b) / 2.0
	var on := _ship(1, mid)
	var off_y: float = mid.y + 300.0 if mid.y < 500.0 else mid.y - 300.0
	var off := _ship(2, Vector2(mid.x, off_y))
	off.ai = true
	var on_hp := _health(on)
	var off_hp := _health(off)
	s.time = hit.time
	s.step(0.0)
	assert_lt(_health(on), on_hp, "cut")
	assert_eq(_health(off), off_hp, "clear of the line")


func test_no_beam_before_its_time() -> void:
	var s: Node2D = game.scenery
	var hit: Dictionary = s.beams_between(0.0, 10.0)[0]
	var p := _ship(1, (hit.a + hit.b) / 2.0)
	var hp := _health(p)
	s.time = hit.time - 0.5
	s.step(0.0)
	assert_eq(_health(p), hp, "still only a warning")


func test_beams_draw_on_top() -> void:
	var o: Node2D = game.scenery.get_node("CrystalOverlay")
	assert_eq(o.z_index, 50)


func test_breaking_crystal_debris_bursts_and_hurts_close_by() -> void:
	var s: Node2D = game.scenery
	var at := Vector2(270, 500)
	var near := _ship(1, at + Vector2(20, 0))
	var far := _ship(2, at + Vector2(260, 0))
	far.ai = true
	var near_hp := _health(near)
	var far_hp := _health(far)
	s.on_obstacle_destroyed(CrystalScript.BURST_PIECE, at)
	assert_lt(_health(near), near_hp, "caught in the burst")
	assert_eq(_health(far), far_hp, "out of reach")


func test_other_pieces_dont_burst() -> void:
	var s: Node2D = game.scenery
	var at := Vector2(270, 500)
	var p := _ship(1, at)
	var hp := _health(p)
	s.on_obstacle_destroyed("girder", at)
	assert_eq(_health(p), hp, "only the crystal debris goes off")


# --- Crystal rain -----------------------------------------------------------------

func test_shards_rain_the_whole_level_through() -> void:
	var s: Node2D = game.scenery
	var obstacles := game.get_node("Obstacles")
	var before := obstacles.get_child_count()
	s.time = 0.0
	s.step(0.0)
	assert_eq(obstacles.get_child_count(), before, "none before RAIN_FIRST")
	s.time = CrystalScript.RAIN_FIRST + CrystalScript.RAIN_INTERVAL * 5.0
	s.step(0.0)
	var fallen := obstacles.get_child_count() - before
	assert_between(fallen, 5, 8, "a steady drip, not a burst")
	for o in obstacles.get_children():
		assert_eq(o.piece_id, CrystalScript.RAIN_PIECE)
		assert_true(o.destructible(), "you can shoot a lane clear")


func test_rain_comes_down_inside_the_walls_and_above_the_screen() -> void:
	var s := _scenery(5)
	var lanes := {}
	for k in 40:
		var at: Vector2 = s.rain_at(k)
		assert_between(at.x, 0.0, CrystalScript.ARENA.x)
		assert_lt(at.y, 0.0, "starts off the top")
		lanes[snappedf(at.x, 1.0)] = true
	assert_gt(lanes.size(), 3, "it spreads across the seam")


func test_rain_schedule_is_deterministic_and_steady() -> void:
	var a := _scenery(9)
	var b := _scenery(9)
	for k in 20:
		assert_eq(a.rain_at(k), b.rain_at(k), "same on every peer")
		assert_almost_eq(a.rain_time(k + 1) - a.rain_time(k), CrystalScript.RAIN_INTERVAL, 0.001)


func test_it_rains_harder_while_the_cloud_is_overhead() -> void:
	var s: Node2D = game.scenery
	var calm: float = s.rain_gap()
	game.spawn_boss()
	assert_true(game.boss_alive())
	assert_lt(s.rain_gap(), calm, "the storm is the boss")


func test_boss_fires_a_spread_and_lances_a_beam() -> void:
	var s: Node2D = game.scenery
	var target := _ship(1, Vector2(270, 700))
	var boss := Node2D.new()
	boss.position = Vector2(270, 150)
	autofree(boss)
	var bullets := game.get_node("Bullets")
	s.time = 0.0
	var fired := 0
	var lanced := 0
	for i in CrystalScript.BOSS_BEAM_EVERY:
		var before := bullets.get_child_count()
		assert_true(s.boss_attack(boss, target, 4))
		fired += bullets.get_child_count() - before
		lanced += s.pending_beams()
	assert_eq(fired, 4 * CrystalScript.BOSS_BEAM_EVERY, "a spread every volley")
	assert_gt(lanced, 0, "a beam strung through the target")


func test_boss_beam_passes_through_its_target() -> void:
	var s := _scenery(3)
	var at := Vector2(200, 600)
	var line: Array = s.boss_beam(at, 1)
	var c := Geometry2D.get_closest_point_to_segment(at, line[0], line[1])
	assert_lt(at.distance_to(c), 1.0, "the line runs through the target")
	assert_eq(s.boss_beam(at, 1), line, "deterministic")
