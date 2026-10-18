extends GutTest
## Enemies change color as the stage goes up (Ships.enemy_colors): a ramp of
## looks after stage 1's reds, looping at the end with a pulse.

const EnemyScene := preload("res://scenes/enemy.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")


func _enemy(stage: int) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.type = EnemyScript.WEAVER
	e.stage = stage
	add_child_autofree(e)
	return e


func test_each_stage_on_the_ramp_has_its_own_colors() -> void:
	var seen := []
	for stage in Ships.ENEMY_STAGE_NAMES.size() + 1:
		var c: Array[Color] = Ships.enemy_colors(0, stage)
		assert_false(seen.has(c), "stage %d" % stage)
		seen.append(c)
	assert_eq(Ships.enemy_colors(0, 0), Array(Ships.ENEMY_PALETTES[0].colors), "stage 1 keeps the reds")


func test_enemies_spawn_in_their_stage_colors() -> void:
	var a := _enemy(0)
	var b := _enemy(1)
	assert_same(a.get_node("Body").texture, Ships.get_lit_enemy_texture(0, 0))
	assert_same(b.get_node("Body").texture, Ships.get_lit_enemy_texture(0, 1))
	assert_not_same(a.get_node("Body").texture, b.get_node("Body").texture)


func test_the_ramp_loops_and_then_pulses() -> void:
	var n := Ships.ENEMY_STAGE_NAMES.size() + 1
	assert_eq(Ships.enemy_colors(1, n), Ships.enemy_colors(1, 0))
	assert_same(Ships.get_enemy_texture(1, n), Ships.get_enemy_texture(1, 0), "shared cache")
	assert_false(Ships.enemy_glows(n - 1))
	assert_true(Ships.enemy_glows(n))
	var e := _enemy(n)
	e._process(0.0)
	assert_ne(e.get_node("Body").self_modulate, Color.WHITE)


func test_wreck_parts_match_the_stage_colors() -> void:
	var a := Ships.get_enemy_parts(0, 0, 0)
	var b := Ships.get_enemy_parts(0, 0, 2)
	assert_not_same(a, b)
	assert_same(Ships.get_enemy_parts(0, 0, 2), b, "cached per stage")
	assert_ne(a.size(), 0)
	assert_ne(b.size(), 0)


func test_wreck_uses_the_enemy_stage() -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.play_wreck(Vector2(100, 100), EnemyScript.WEAVER, 1, "Wreck1", "", 2)
	var w := game.get_node("Effects/Wreck1")
	assert_same(w.hull.get_child(0).texture, Ships.get_enemy_parts(0, 1, 2)[0].texture)
