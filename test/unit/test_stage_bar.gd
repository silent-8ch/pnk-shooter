extends GutTest
## The HUD's stage progress line: the track fills with the kills toward the
## boss, with a landmark halfway for the ELITE mini boss and one at the end for
## the boss, and the count (or what's happening instead) on the right.

const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var bar: StageBar
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	bar = game.get_node("HUD/StageBar")


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func test_the_bar_is_in_the_hud() -> void:
	assert_not_null(bar)
	assert_true(bar.is_in_group("stage_bar"))
	assert_eq(bar.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never eats a tap")


func test_a_fresh_stage_starts_empty() -> void:
	game.kills = 0
	var s := bar.state()
	assert_eq(s.fill, 0.0)
	assert_eq(s.text, "0/%d" % game.boss_kills_needed())
	assert_false(s.elite_passed)


func test_the_track_fills_with_the_kills() -> void:
	var needed: int = game.boss_kills_needed()
	game.kills = needed / 4
	var quarter: float = bar.state().fill
	game.kills = needed / 2
	var half: float = bar.state().fill
	assert_almost_eq(quarter, 0.25, 0.03)
	assert_almost_eq(half, 0.5, 0.03)
	assert_gt(half, quarter, "it only goes forward")


func test_the_count_says_how_far_in_you_are() -> void:
	game.kills = 7
	assert_eq(bar.state().text, "7/%d" % game.boss_kills_needed())


func test_the_elite_landmark_lights_up_at_the_halfway_point() -> void:
	game.kills = game.mini_boss_kills() - 1
	assert_false(bar.state().elite_passed, "still coming")
	game.kills = game.mini_boss_kills()
	assert_true(bar.state().elite_passed, "behind us")
	assert_almost_eq(bar.state().fill, StageBar.ELITE_AT, 0.03, "the landmark sits where the track is half full")


func test_a_later_stage_needs_more_kills_for_the_same_fill() -> void:
	game.stage = 0
	game.kills = 15
	var early: float = bar.state().fill
	game.stage = 5  # boss_kills_needed grows every stage
	var late: float = bar.state().fill
	assert_lt(late, early, "the same kills get you less far into a longer stage")
	assert_eq(bar.state().text, "15/%d" % game.boss_kills_needed())


func test_it_never_overruns_its_track() -> void:
	game.kills = game.boss_kills_needed() * 3
	var s := bar.state()
	assert_eq(s.fill, 1.0)
	assert_eq(s.text, "%d/%d" % [game.boss_kills_needed(), game.boss_kills_needed()])


func test_a_refit_says_so_instead_of_counting() -> void:
	game.refit = true
	var s := bar.state()
	assert_eq(s.text, "REFIT")
	assert_eq(s.fill, 1.0)


func test_a_fork_says_so() -> void:
	game.show_fork([{"kind": "orbit", "reward": "spare"}, {"kind": "storm", "reward": "repair"}])
	assert_true(game.fork_open())
	assert_eq(bar.state().text, "PATH")


func test_a_boss_fills_the_track() -> void:
	game.kind = LevelKinds.FIRST
	game.spawn_boss()
	assert_true(game.boss_alive())
	var s := bar.state()
	assert_eq(s.text, "BOSS")
	assert_eq(s.fill, 1.0)


func test_the_mini_boss_holds_the_track_at_the_halfway_mark() -> void:
	game.kills = game.mini_boss_kills()
	game.spawn_elite()
	assert_true(game.elite_alive())
	var s := bar.state()
	assert_eq(s.text, "ELITE")
	assert_almost_eq(s.fill, StageBar.ELITE_AT, 0.03, "kills stop counting, so it holds its place")


func test_the_count_and_the_track_share_the_line_without_overlapping() -> void:
	bar.size = Vector2(508, StageBar.HEIGHT)
	var track := bar.track_rect()
	var label := bar.label_rect()
	assert_gt(track.size.x, label.size.x, "the track gets most of the line")
	assert_lte(track.end.x, label.position.x, "no overlap")
	assert_almost_eq(label.end.x, bar.size.x, 0.01, "the count ends the line")


func test_it_survives_a_squeezed_line() -> void:
	bar.size = Vector2(40, StageBar.HEIGHT)
	assert_gt(bar.track_rect().size.x, 0.0, "a track is still drawable")
