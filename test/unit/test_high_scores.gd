extends GutTest
## HighScores: the log of finished runs, best (furthest stage, then score) first.

const TEST_PATH := "user://test_high_scores.json"


func before_each() -> void:
	HighScores.path = TEST_PATH
	HighScores.clear()


func after_each() -> void:
	HighScores.clear()
	HighScores.path = HighScores.PATH


func _run(stage: int, score: int) -> int:
	return HighScores.add({"stage": stage, "score": score, "players": ["A", "B"], "date": "2026-10-18"})


func test_empty_without_a_file() -> void:
	assert_eq(HighScores.load_all(), [])


func test_ranks_by_stage_then_score() -> void:
	assert_eq(_run(1, 500), 1)
	assert_eq(_run(3, 100), 1, "further beats more points")
	assert_eq(_run(1, 900), 2)
	assert_eq(_run(1, 50), 4)
	var top := HighScores.top(3)
	assert_eq(top.map(func(r): return [r.stage, r.score]), [[3, 100], [1, 900], [1, 500]])


func test_round_trips_through_the_file() -> void:
	_run(2, 300)
	var r: Dictionary = HighScores.load_all()[0]
	assert_eq(r.stage, 2)
	assert_eq(r.score, 300)
	assert_eq(r.players, ["A", "B"])
	assert_eq(r.date, "2026-10-18")
	assert_false(FileAccess.file_exists(TEST_PATH + ".tmp"), "temp file renamed away")


func test_keeps_the_best_hundred() -> void:
	for i in HighScores.MAX_ENTRIES:
		_run(5, 1000 + i)
	assert_eq(_run(1, 1), 0, "didn't make the log")
	assert_eq(HighScores.load_all().size(), HighScores.MAX_ENTRIES)


func test_a_broken_file_is_an_empty_log() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	assert_eq(HighScores.load_all(), [])
	assert_eq(_run(1, 10), 1)


func test_lobby_lists_the_best_runs() -> void:
	_run(4, 1234)
	var lobby: CanvasLayer = load("res://scenes/lobby.tscn").instantiate()
	add_child_autofree(lobby)
	lobby.show_high_scores()
	assert_string_contains(lobby.high_scores_label.text, "Stage 4")
	assert_string_contains(lobby.high_scores_label.text, "1234")
	assert_string_contains(lobby.high_scores_label.text, "A, B")
