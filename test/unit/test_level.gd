extends GutTest
## Levels (levels/*.json from tools/level-designer): parsing, timeline timing,
## repeats, lane placement, and the game spawning groups from the timeline.

const LevelScript := preload("res://scripts/level.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

const SCORE := {
	"name": "Test", "length": 4, "repeat": true,
	"events": [
		{"time": 2, "type": "diver", "lane": 8, "count": 3, "dir": -1},
		{"time": 0, "type": "weaver", "lane": 0, "count": 4, "dir": 1},
		{"time": 3.25, "type": "weaver", "lane": 4, "count": 1, "dir": 1},
	],
}

var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _level(over := {}) -> RefCounted:
	return LevelScript.parse(JSON.stringify(SCORE.merged(over, true)))


func test_parses_and_sorts_events() -> void:
	var l: RefCounted = _level()
	assert_eq(l.name, "Test")
	assert_eq(l.length, 4.0)
	assert_eq(l.events.map(func(e): return e.time), [0.0, 2.0, 3.25])
	assert_eq(l.events[0].type, EnemyScript.WEAVER)
	assert_eq(l.events[1].type, EnemyScript.DIVER)
	assert_eq(l.events[1].dir, -1.0)


func test_rejects_non_levels() -> void:
	assert_null(LevelScript.parse("not json"))
	assert_null(LevelScript.parse("[1, 2]"))
	assert_null(LevelScript.parse("{\"name\": \"x\"}"))
	assert_null(LevelScript.parse(JSON.stringify({"name": "old", "bpm": 120, "bars": 4, "events": []})), "old score format")


func test_skips_bad_events_and_clamps_numbers() -> void:
	var l: RefCounted = _level({"length": 99999, "events": [
		{"time": 1, "type": "boss", "lane": 0, "count": 1},
		{"time": -1, "type": "weaver", "lane": 0, "count": 1},
		{"time": 9999, "type": "weaver", "lane": 0, "count": 1},
		{"time": 2, "type": "weaver", "lane": 40, "count": 50},
		"junk",
	]})
	assert_eq(l.length, 1800.0)
	assert_eq(l.events.size(), 1)
	assert_eq(l.events[0].lane, LevelScript.LANES - 1)
	assert_eq(l.events[0].count, LevelScript.MAX_COUNT)


func test_events_between_is_half_open() -> void:
	var l: RefCounted = _level()
	assert_eq(l.events_between(0.0, 0.01).size(), 1, "0 s plays at once")
	assert_eq(l.events_between(0.01, 2.0).size(), 0, "2 s not yet")
	assert_eq(l.events_between(2.0, 3.25).size(), 1)


func test_repeating_score_loops() -> void:
	var l: RefCounted = _level()
	var due: Array = l.events_between(3.9, 4.1)
	assert_eq(due.size(), 1, "0 s again on the second pass")
	assert_eq(due[0].time, 0.0)
	assert_eq(l.events_between(0.0, 12.0).size(), 9, "three passes")
	assert_false(l.finished(100.0))


func test_one_shot_score_finishes() -> void:
	var l: RefCounted = _level({"repeat": false})
	assert_eq(l.events_between(3.9, 4.1).size(), 0)
	assert_false(l.finished(3.9))
	assert_true(l.finished(4.0))


func test_lanes_spread_left_to_right_and_keep_groups_on_screen() -> void:
	var w := 540.0
	var last := -1.0
	for lane in LevelScript.LANES:
		var e := {"type": EnemyScript.WEAVER, "lane": lane, "count": 3}
		var x := LevelScript.center_x(e, w)
		assert_gt(x, last, "lane %d right of the last" % lane)
		last = x
		var half := EnemyScript.group_half_width(e.type, e.count)
		assert_gte(x - half, 0.0)
		assert_lte(x + half, w)
	var wide := {"type": EnemyScript.WEAVER, "lane": 0, "count": 7}
	assert_eq(LevelScript.center_x(wide, 200.0), 100.0, "too wide: centered")


func test_level_files_in_the_repo_parse() -> void:
	var files := DirAccess.get_files_at(LevelScript.DIR) if DirAccess.dir_exists_absolute(LevelScript.DIR) else PackedStringArray()
	for f in files:
		if f.ends_with(".json"):
			var l: RefCounted = LevelScript.load_file(LevelScript.DIR + "/" + f)
			assert_not_null(l, f)
			assert_gt(l.events.size(), 0, f)
	var first := LevelScript.first_level_path()
	assert_true(first == "" or first.ends_with(".json"))
	assert_null(LevelScript.load_file(""))
	assert_null(LevelScript.load_file("res://levels/missing.json"))


func test_game_spawns_groups_from_the_score() -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.rival_chance = 0.0  # counts the level's own enemies
	game.active = true
	game.stage_time = game.PACE_RAMP * 2.0  # full pace
	game.level = _level({"repeat": false})
	game._physics_process(0.01)
	var enemies := game.get_node("Enemies")
	assert_eq(enemies.get_child_count(), 4, "weaver line of 4 at 0 s")
	var center: float = LevelScript.center_x(game.level.events[0], game.ARENA.size.x)
	assert_eq(enemies.get_child(0).group_x, center)
	game._physics_process(1.0)  # up to 1 s
	assert_eq(enemies.get_child_count(), 4)
	game._physics_process(1.0)  # 2 s: diver V of 3, heading left
	assert_eq(enemies.get_child_count(), 7)
	assert_eq(enemies.get_child(6).zig_dir, -1.0)
	assert_almost_eq(game.level_time, 2.01, 0.0001)
	game.active = false


func test_game_falls_back_to_random_waves_after_a_one_shot_score() -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.rival_chance = 0.0  # counts the level's own enemies
	game.active = true
	game.stage_time = game.PACE_RAMP * 2.0  # full pace
	game.level = _level({"repeat": false, "events": []})
	game.level_time = 4.0  # past the end
	game._physics_process(game.GROUP_INTERVAL)
	assert_gt(game.get_node("Enemies").get_child_count(), 0)
	game.active = false


func test_joiner_gets_the_level_clock() -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.rival_chance = 0.0  # counts the level's own enemies
	game.set_level_time(12.5)
	assert_eq(game.level_time, 12.5)
