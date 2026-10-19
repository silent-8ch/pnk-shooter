extends GutTest
## Terrain obstacles: the shared piece catalog, tiled runs with caps, level
## events, scrolling, ships pushed out / bumped / crushed, bullets blocked,
## destructible pieces shot apart, and outline placeholders until art exists.

const ObstacleScript := preload("res://scripts/obstacle.gd")
const LevelScript := preload("res://scripts/level.gd")
const PlayerScript := preload("res://scripts/player.gd")
const BulletScene := preload("res://scenes/bullet.tscn")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _obstacle(piece: String, pos: Vector2, count := 1, dir := 1.0) -> Area2D:
	game._obstacle_count += 1
	var n := "Obstacle%d" % game._obstacle_count
	game.spawn_obstacle({"name": n, "piece": piece, "x": pos.x, "y": pos.y, "count": count, "dir": dir})
	return game.get_node("Obstacles/" + n)


func _player(pos: Vector2) -> Area2D:
	var p: Area2D = preload("res://scenes/player.tscn").instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func test_catalog_has_described_drawable_pieces() -> void:
	var cat := ObstacleScript.catalog()
	assert_gt(cat.size(), 5)
	for id in cat:
		var p: Dictionary = cat[id]
		assert_gt(p.size.x, 0.0, id)
		assert_gte(p.outline.size(), 3, id + " has an outline")
		assert_true(p.shape in ["circle", "rect"], id)
		for c in p.caps:
			assert_true(cat.has(c), id + " cap " + c)
			assert_true(cat[c].cap)
	var text := FileAccess.get_file_as_string(ObstacleScript.PIECES_PATH)
	var data: Dictionary = JSON.parse_string(text)
	for p in data.pieces:
		assert_gt(str(p.get("description", "")).length(), 20, p.id + " says what to draw")


func test_tile_piece_repeats_between_its_caps() -> void:
	var parts := ObstacleScript.layout("girder", 3)
	assert_eq(parts.map(func(p): return p.piece), ["girder_end_l", "girder", "girder", "girder", "girder_end_r"])
	var seg: float = ObstacleScript.piece("girder").size.x
	assert_almost_eq(parts[2].offset.x - parts[1].offset.x, seg, 0.001, "segments butt up")
	assert_almost_eq(parts[0].offset.x + parts[4].offset.x, 0.0, 0.001, "centered")


func test_caps_are_not_placeable() -> void:
	assert_true(ObstacleScript.placeable("hull"))
	assert_false(ObstacleScript.placeable("hull_end_l"))
	assert_false(ObstacleScript.placeable("nope"))


func test_level_parses_obstacle_events() -> void:
	var l: RefCounted = LevelScript.parse(JSON.stringify({"name": "o", "length": 10, "repeat": false, "events": [
		{"time": 1, "type": "obstacle", "piece": "girder", "lane": 2, "count": 4, "dir": -1},
		{"time": 2, "type": "obstacle", "piece": "girder_end_l", "lane": 2, "count": 1, "dir": 1},
		{"time": 3, "type": "obstacle", "piece": "missing", "lane": 2, "count": 1, "dir": 1},
	]}))
	assert_eq(l.events.size(), 1, "caps and unknown pieces skipped")
	assert_eq(l.events[0].piece, "girder")
	assert_eq(l.events[0].type, LevelScript.OBSTACLE)
	assert_eq(l.events[0].dir, -1.0)


func test_game_spawns_obstacles_from_the_level() -> void:
	game.active = true
	game.level = LevelScript.parse(JSON.stringify({"name": "o", "length": 10, "repeat": false, "events": [
		{"time": 0, "type": "obstacle", "piece": "hull", "lane": 4, "count": 3, "dir": 1},
		{"time": 0, "type": "obstacle", "piece": "asteroid_s", "lane": 0, "count": 3, "dir": 1},
	]}))
	game._physics_process(0.01)
	var obs := game.get_node("Obstacles").get_children()
	assert_eq(obs.size(), 4, "one hull run + a cluster of 3 rocks")
	assert_eq(obs[0].parts.size(), 5)
	assert_almost_eq(obs[0].position.x, game.ARENA.size.x / 2.0, 0.01, "lane 4 = middle")
	assert_lt(obs[0].position.y, 0.0, "enters from above")
	game.active = false


func test_random_obstacles_without_a_level() -> void:
	game.active = true
	game.stage_time = game.PACE_RAMP * 2.0  # full pace
	game.level = null
	game._physics_process(game.OBSTACLE_INTERVAL)
	assert_gt(game.get_node("Obstacles").get_child_count(), 0)
	game.active = false


func test_scrolls_down_and_leaves() -> void:
	var o := _obstacle("asteroid_l", Vector2(270, -60))
	o._process(1.0)
	assert_almost_eq(o.position.y, -60.0 + ObstacleScript.scroll_speed(), 0.01)
	o.position.y = 2000
	o._process(0.01)
	assert_true(o.is_queued_for_deletion())


func test_ship_is_pushed_out_of_a_rock() -> void:
	var o := _obstacle("asteroid_l", Vector2(270, 400))
	var res: Dictionary = game.resolve_obstacles(Vector2(280, 400), 14.0)
	assert_true(res.touching)
	assert_false(o.touches(res.pos, 14.0 - 0.1), "clear of it")
	var away: Dictionary = game.resolve_obstacles(Vector2(100, 100), 14.0)
	assert_false(away.touching)


func test_ship_is_pushed_out_of_a_girder() -> void:
	_obstacle("girder", Vector2(270, 400), 3)
	var res: Dictionary = game.resolve_obstacles(Vector2(270, 410), 14.0)
	assert_true(res.touching)
	assert_gt(res.pos.y, 400.0 + 9.0 + 13.9, "out the bottom (nearest side)")
	assert_true(res.below == false)


func test_player_bumps_and_takes_a_little_damage() -> void:
	var p := _player(Vector2(270, 600))
	_obstacle("asteroid_l", Vector2(270, 560))
	p._simulate(0.016)
	assert_false(game.overlaps_obstacle(p.position, PlayerScript.SHIP_RADIUS - 0.1))
	assert_almost_eq(p.hp, PlayerScript.MAX_HP - PlayerScript.BUMP_DAMAGE * PlayerScript.HIT_HP, 0.01)
	p._simulate(0.016)
	assert_almost_eq(p.hp, PlayerScript.MAX_HP - PlayerScript.BUMP_DAMAGE * PlayerScript.HIT_HP, 0.01, "cooldown")


func test_pinned_against_the_bottom_is_crushed() -> void:
	var p := _player(Vector2(270, 600))
	var bottom: float = p._movement_bounds().end.y
	p.position = Vector2(270, bottom)
	_obstacle("hull", Vector2(270, bottom - 20), 4)
	var before: float = p.hp
	for i in 30:
		p._simulate(1.0 / 60.0)
	assert_lt(p.hp, before - PlayerScript.BUMP_DAMAGE * PlayerScript.HIT_HP, "crushing keeps hurting")


func test_obstacles_block_bullets() -> void:
	var o := _obstacle("hull", Vector2(270, 300), 2)
	var b: Area2D = BulletScene.instantiate()
	b.shooter = 1
	game.get_node("Bullets").add_child(b)
	o._on_area_entered(b)
	assert_true(b.is_queued_for_deletion())
	assert_false(o.is_queued_for_deletion(), "indestructible")


func test_small_rocks_can_be_shot_apart() -> void:
	var o := _obstacle("asteroid_s", Vector2(270, 300))
	var n := String(o.name)
	var hits := int(ObstacleScript.piece("asteroid_s").hp)
	for i in hits - 1:
		game.report_obstacle_hit(n, 1.0)
	assert_true(game.get_node("Obstacles").has_node(n))
	game.report_obstacle_hit(n, 1.0)
	assert_false(game.get_node("Obstacles").has_node(n))
	assert_eq(game.score, hits * game.OBSTACLE_POINTS)


func test_indestructible_ignores_hit_reports() -> void:
	var o := _obstacle("asteroid_l", Vector2(270, 300))
	for i in 50:
		game.report_obstacle_hit(String(o.name), 1.0)
	assert_true(game.get_node("Obstacles").has_node(String(o.name)))


func test_outline_placeholder_until_art_exists() -> void:
	assert_null(ObstacleScript.art("girder"), "no art drawn yet")
	var o := _obstacle("girder", Vector2(270, 300), 2)
	assert_eq(o.find_children("*", "Sprite2D", false, false).size(), 0)
	o.queue_redraw()
	await wait_frames(2)
	pass_test("drew outlines without errors")


func test_spawn_rejects_bad_data() -> void:
	game.spawn_obstacle({"name": "Bogus", "piece": "girder", "x": 0, "y": 0})
	game.spawn_obstacle({"name": "Obstacle99", "piece": "girder_end_l", "x": 0, "y": 0})
	assert_eq(game.get_node("Obstacles").get_child_count(), 0)


func test_stop_clears_obstacles() -> void:
	var o := _obstacle("asteroid_m", Vector2(100, 100))
	game.stop()
	assert_true(o.is_queued_for_deletion())


# --- Exp inside -----------------------------------------------------------------------

## The next obstacle name that does (or doesn't) carry exp.
func _loot_obstacle(piece: String, pos: Vector2, want: bool) -> Area2D:
	while ObstacleScript.carries_loot("Obstacle%d" % (game._obstacle_count + 1)) != want:
		game._obstacle_count += 1
	return _obstacle(piece, pos)


func test_about_one_breakable_piece_in_six_carries_exp() -> void:
	var n := 0
	for i in 600:
		if ObstacleScript.carries_loot("Obstacle%d" % i):
			n += 1
	assert_between(n, 70, 130)
	assert_true(_loot_obstacle("asteroid_m", Vector2(270, 300), true).loot)
	assert_false(_loot_obstacle("asteroid_m", Vector2(270, 300), false).loot)


func test_any_breakable_piece_can_carry_it_but_not_solid_ones() -> void:
	var solid := ""
	var breakable: Array = []
	for id in ObstacleScript.catalog():
		if not ObstacleScript.placeable(id):
			continue
		if ObstacleScript.piece(id).get("hp", 0.0) > 0.0:
			breakable.append(id)
		else:
			solid = id
	assert_gt(breakable.size(), 1)
	for id in breakable:
		assert_true(_loot_obstacle(id, Vector2(270, 300), true).loot, id)
	if solid != "":
		assert_false(_loot_obstacle(solid, Vector2(270, 300), true).loot, "can't be broken open")


func test_every_peer_agrees_which_carry_it() -> void:
	for i in 50:
		var n := "Obstacle%d" % i
		assert_eq(ObstacleScript.carries_loot(n), ObstacleScript.carries_loot(n))


func test_it_flashes_through_the_exp_colors() -> void:
	var o := _loot_obstacle("asteroid_m", Vector2(270, 300), true)
	var seen := {}
	for i in 30:
		o._process(1.0 / 30.0)
		seen[o.modulate] = true
	assert_gt(seen.size(), 2, "cycles")
	var plain := _loot_obstacle("asteroid_m", Vector2(100, 300), false)
	plain._process(0.1)
	assert_eq(plain.modulate, Color.WHITE)


func test_breaking_it_drops_an_exp_where_it_was() -> void:
	var o := _loot_obstacle("asteroid_s", Vector2(200, 300), true)
	var n := String(o.name)
	var before := game.get_node("Pickups").get_child_count()
	for i in 20:
		if o.is_queued_for_deletion():
			break
		game.report_obstacle_hit(n, 1.0)
	assert_true(o.is_queued_for_deletion(), "broken")
	var pickups := game.get_node("Pickups").get_children()
	assert_eq(pickups.size(), before + 1)
	assert_true(pickups.back().position.distance_to(Vector2(200, 300)) < 40.0)


func test_a_plain_one_drops_nothing() -> void:
	var o := _loot_obstacle("asteroid_s", Vector2(200, 300), false)
	var n := String(o.name)
	for i in 20:
		if o.is_queued_for_deletion():
			break
		game.report_obstacle_hit(n, 1.0)
	assert_true(o.is_queued_for_deletion(), "broken")
	assert_eq(game.get_node("Pickups").get_child_count(), 0)
