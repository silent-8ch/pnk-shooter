extends GutTest
## Forks: after each boss the party votes between two kinds of level (each with
## a reward) by flying into the left or right gate. Ships in neither gate and
## ties go with the host's side.

const PlayerScene := preload("res://scenes/player.tscn")
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


func _ship(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	if id != 1:
		p.ai = true  # flown on this peer
	game.get_node("Players").add_child(p)
	return p


func _open(left := {"kind": "orbit", "reward": "spare"}, right := {"kind": "storm", "reward": "repair"}) -> void:
	game.show_fork([left, right])


const LEFT := Vector2(135, 330)
const RIGHT := Vector2(405, 330)
const OUT := Vector2(270, 800)


func test_options_are_two_other_kinds_with_different_rewards() -> void:
	var rng := RandomNumberGenerator.new()
	for i in 50:
		rng.seed = i
		var o := LevelKinds.fork_options("orbit", rng)
		assert_eq(o.size(), 2)
		assert_ne(o[0].kind, o[1].kind)
		assert_ne(o[0].kind, "orbit", "never the kind just played")
		assert_ne(o[1].kind, "orbit")
		assert_ne(o[0].reward, o[1].reward)
		assert_true(LevelKinds.REWARDS.has(o[0].reward))


func test_beating_a_boss_opens_a_fork_after_the_refit() -> void:
	_ship(1, OUT)
	game.spawn_boss()
	var boss: Node = game.get_node("Enemies").get_children().back()
	game.destroy_enemy(boss, true)
	assert_true(game.refit, "a refit first")
	assert_false(game.fork_open())
	game.set_refit_ready(true)
	assert_false(game.refit)
	assert_true(game.fork_open(), "then the paths")
	assert_eq(get_tree().get_nodes_in_group("gate").size(), 2)


func test_nothing_spawns_while_the_fork_is_open() -> void:
	_ship(1, OUT)
	game.level = null
	_open()
	var t: float = game.level_time
	for i in 50:
		game._physics_process(0.1)
		if not game.fork_open():
			break
	assert_eq(game.level_time, t)
	assert_eq(game.get_node("Enemies").get_child_count(), 0)


func test_majority_wins() -> void:
	_ship(1, LEFT)
	_ship(7, RIGHT)
	_ship(8, RIGHT + Vector2(20, 0))
	_open()
	assert_eq(game.fork_votes().votes, [1, 2])
	assert_eq(game.fork_choice(), 1)


func test_ties_and_stragglers_go_with_the_host() -> void:
	_ship(1, RIGHT)
	_ship(7, LEFT)
	_open()
	assert_eq(game.fork_choice(), 1, "tie: host's side")
	var host := game.get_node("Players/1")
	host.position = Vector2(100, 800)  # host on the left, in no gate
	_ship(8, Vector2(500, 800))  # in no gate either
	assert_eq(game.fork_choice(), 0, "1 left vote + 2 stragglers on the host's side")


func test_the_vote_closes_when_everyone_is_in_or_time_runs_out() -> void:
	var host := _ship(1, OUT)
	_open()
	game._physics_process(0.1)
	assert_true(game.fork_open(), "host still outside")
	host.position = RIGHT
	game._physics_process(0.1)
	assert_false(game.fork_open(), "everyone is in")
	assert_eq(game.kind, "storm")
	host.position = OUT
	_open()
	for i in int(game.FORK_TIME * 10) + 2:
		game._physics_process(0.1)
	assert_false(game.fork_open(), "timed out")
	assert_eq(game.kind, "orbit", "host's side (left of center)")


func test_choosing_switches_the_kind_level_and_background() -> void:
	_ship(1, OUT)
	game.level_time = 50.0
	_open()
	game.choose_fork(1)
	assert_eq(game.kind, "storm")
	assert_eq(game.level_time, 0.0)
	assert_eq(get_tree().get_nodes_in_group("gate").filter(func(g): return not g.is_queued_for_deletion()).size(), 0)
	game._process(0.0)
	assert_eq(game.get_node("Background").color, LevelKinds.info("storm").bg)
	var cfg: SceneReplicationConfig = game.get_node("ScoreSync").replication_config
	assert_true(cfg.has_property(NodePath(".:kind")))


func test_random_waves_use_the_kinds_enemies() -> void:
	_ship(1, OUT)
	game.kind = "asteroid_belt"
	game.level = null
	for i in 200:
		game._physics_process(0.1)
	var types := {}
	for e in game.get_node("Enemies").get_children():
		types[e.type] = true
	assert_gt(types.size(), 0)
	for t in types:
		assert_has(LevelKinds.wave_types("asteroid_belt"), t)


func test_reward_spare_ship() -> void:
	_ship(1, OUT)
	var before: int = game.spares
	game.apply_reward("spare")
	assert_eq(game.spares, before + 1)


func test_reward_full_repair() -> void:
	var p := _ship(1, OUT)
	p.hp = 10.0
	game.apply_reward("repair")
	assert_eq(p.hp, p.max_hp())


func test_reward_free_upgrade() -> void:
	var p := _ship(1, OUT)
	var before: Dictionary = p.levels.duplicate()
	game.apply_reward("upgrade")
	var total := 0
	for id in p.levels:
		total += p.levels[id] - before.get(id, 0)
	assert_eq(total, 1, "one level of one Systems item")
	assert_eq(p.levels.get(&"ship", 0), 0, "never a spare ship")
	assert_eq(p.exp_balance, 0, "free")


func test_reward_double_exp_and_score_last_one_stage() -> void:
	var p := _ship(1, OUT)
	game.apply_reward("exp2")
	game.collect_pickup("none", 1)
	assert_eq(p.exp_balance, 2)
	game.apply_reward("score2")
	assert_eq(game.exp_mult, 1, "next fork ends it")
	game.add_score(10)
	assert_eq(game.score, 20)


func test_a_new_run_starts_in_deep_space() -> void:
	game.kind = "storm"
	game.stop()
	assert_eq(game.kind, LevelKinds.FIRST)
	assert_false(game.fork_open())
