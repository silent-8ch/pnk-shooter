extends GutTest
## The Crystal boss, Crystal Crevices': three targets in order. Two arms with
## their own hp shield the core, so the party has to break both before the body
## can be hurt at all. The arms sway and hurt any ship that touches them.

const EnemyScript := preload("res://scripts/enemy.gd")
const CrystalBossScript := preload("res://scripts/crystal_boss.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _boss() -> Area2D:
	game.kind = "crystal_crevices"
	game.spawn_boss()
	return game.get_node("Enemies").get_children().back()


func _arms(e: Area2D) -> Node2D:
	return e.get_node("CrystalArms")


func _player(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


## Breaks arm `side` outright.
func _break(e: Area2D, side: int) -> void:
	var arms := _arms(e)
	arms.hit_arm(side, arms.arm_max)


func test_crystal_crevices_boss_is_the_crystal_boss() -> void:
	var e := _boss()
	assert_eq(e.type, EnemyScript.CRYSTAL)
	assert_true(e.is_crystal())
	assert_true(e.is_boss(), "a boss in every way: bar, music, stage, refit")
	assert_true(e.has_node("CrystalArms"))
	assert_true(e.body.visible, "it keeps its ship body; only the arms are drawn in code")


func test_other_kinds_keep_their_boss() -> void:
	game.kind = "asteroid_belt"
	game.spawn_boss()
	var e: Area2D = game.get_node("Enemies").get_children().back()
	assert_eq(e.type, EnemyScript.BOSS)


func test_it_has_two_arms_with_their_own_hp_and_hit_boxes() -> void:
	var e := _boss()
	var arms := _arms(e)
	assert_eq(CrystalBossScript.ARMS, 2)
	assert_eq(arms.arm_hp.size(), 2)
	assert_eq(arms.arms_alive(), 2)
	assert_gt(arms.arm_max, 0)
	assert_eq(arms.get_child_count(), 2, "a hit box per arm")


func test_arm_hp_scales_with_the_stage() -> void:
	game.kind = "crystal_crevices"
	game.stage = 0
	game.spawn_boss()
	var weak: int = _arms(game.get_node("Enemies").get_children().back()).arm_max
	game.stage = 4
	game.spawn_boss()
	var tough: int = _arms(game.get_node("Enemies").get_children().back()).arm_max
	assert_gt(tough, weak, "a later stage's arms take more breaking")


func test_arms_reach_out_both_ways_and_sway() -> void:
	var left := CrystalBossScript.arm_segment(0.0, 0)[1] as Vector2
	var right := CrystalBossScript.arm_segment(0.0, 1)[1] as Vector2
	assert_lt(left.x, 0.0, "arm 0 reaches left")
	assert_gt(right.x, 0.0, "arm 1 reaches right")
	var angles := {}
	for i in 60:
		angles[snappedf(CrystalBossScript.arm_angle(i * 0.25, 0), 0.01)] = true
	assert_gt(angles.size(), 10, "it sways rather than holding still")
	for i in 400:  # never folds back over the core
		var a := CrystalBossScript.arm_angle(i * 0.1, 0)
		assert_lt(absf(angle_difference(a, PI)), CrystalBossScript.SWAY + 0.001)


func test_shards_shrink_toward_the_tip() -> void:
	assert_gt(CrystalBossScript.shard_radius(0), CrystalBossScript.shard_radius(CrystalBossScript.SHARDS - 1))
	var seg := CrystalBossScript.arm_segment(1.0, 1)
	var root: Vector2 = seg[0]
	var tip: Vector2 = seg[1]
	for i in CrystalBossScript.SHARDS:  # every shard sits on the arm's line
		var p := CrystalBossScript.shard_at(1.0, 1, i)
		assert_almost_eq(p.distance_to(Geometry2D.get_closest_point_to_segment(p, root, tip)), 0.0, 0.001)


# --- The core is shielded until both arms are gone --------------------------------

func test_core_takes_nothing_while_an_arm_stands() -> void:
	var e := _boss()
	assert_true(e.is_shielded())
	var hp: int = e.hp
	e.take_damage(10.0)
	assert_eq(e.hp, hp, "shots spark off the shield for nothing")
	_break(e, 0)
	assert_eq(_arms(e).arms_alive(), 1)
	assert_true(e.is_shielded(), "one arm still holds it up")
	e.take_damage(10.0)
	assert_eq(e.hp, hp, "still covered")


func test_breaking_both_arms_uncovers_the_core() -> void:
	var e := _boss()
	var hp: int = e.hp
	_break(e, 0)
	_break(e, 1)
	assert_eq(_arms(e).arms_alive(), 0)
	assert_false(e.is_shielded())
	e.take_damage(3.0)
	assert_eq(e.hp, hp - 3, "now it bleeds")


func test_ramming_a_shielded_core_does_nothing() -> void:
	var e := _boss()
	var hp: int = e.hp
	e.ram()
	assert_eq(e.hp, hp)


func test_shooting_an_arm_wears_it_down_then_breaks_it() -> void:
	var e := _boss()
	var arms := _arms(e)
	arms.hit_arm(0, 1.0)
	assert_eq(arms.arm_hp[0], arms.arm_max - 1, "one shot off")
	assert_false(arms.is_broken(0))
	assert_eq(arms.arm_hp[1], arms.arm_max, "the other arm is untouched")
	arms.hit_arm(0, arms.arm_max)
	assert_true(arms.is_broken(0))
	assert_eq(arms.arm_hp[0], 0, "never goes negative")


func test_a_broken_arm_takes_no_more_hits_and_stops_blocking() -> void:
	var e := _boss()
	var arms := _arms(e)
	_break(e, 0)
	arms.hit_arm(0, 5.0)
	assert_eq(arms.arm_hp[0], 0)
	arms._place_shapes()
	assert_true(arms.get_child(0).disabled, "its hit box is off")
	assert_false(arms.get_child(1).disabled, "the standing arm still blocks")


# --- The arms as a hazard ---------------------------------------------------------

func test_a_standing_arm_is_touchable_and_a_broken_one_is_not() -> void:
	var e := _boss()
	var arms := _arms(e)
	arms._place_shapes()
	var tip: Vector2 = e.position + (CrystalBossScript.arm_segment(arms._time(), 0)[1] as Vector2) * e.scale.x
	assert_true(arms.touches(tip, 4.0), "the arm is there")
	assert_gt(arms.danger_at(tip, 0.0), 0.0, "and the AI pilot is told so")
	_break(e, 0)
	assert_false(arms.touches(tip, 4.0), "broken off")
	assert_eq(arms.danger_at(tip, 0.0), 0.0)


func test_arms_are_a_hazard_ships_run_into() -> void:
	var e := _boss()
	var arms := _arms(e)
	assert_true(arms.is_in_group("hazard"), "Player hurts a ship that touches it")
	assert_eq(arms.collision_layer, 2)
	assert_eq(arms.collision_mask, 4, "bullets")


func test_a_shot_between_the_arms_is_left_for_the_core() -> void:
	var e := _boss()
	var arms := _arms(e)
	arms._place_shapes()
	assert_eq(arms.arm_at(e.position + Vector2(0, 220)), -1, "well below both arms")
	var on_arm: Vector2 = e.position + (CrystalBossScript.shard_at(arms._time(), 1, 2)) * e.scale.x
	assert_eq(arms.arm_at(on_arm), 1, "a shot on the right arm hits the right arm")
