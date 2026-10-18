extends GutTest
## Bosses: after boss_kills_needed() kills the host sends one in; the level
## holds its place and only small groups come while it's up.
## It hovers, fires aimed spreads of hostile bullets, and shows an hp bar.
## Beating it raises the stage: every enemy sent in after is tougher.

const EnemyScene := preload("res://scenes/enemy.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
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


func _player(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _boss() -> Area2D:
	game.spawn_boss()
	return game.get_node("Enemies").get_children().back()


func _enemies() -> Array:
	return game.get_node("Enemies").get_children().filter(func(e): return not e.is_queued_for_deletion())


# --- Arrival -------------------------------------------------------------------

func _kill_weaver() -> void:
	game.spawn_group(EnemyScript.WEAVER, 270.0, 1)
	game.destroy_enemy(_enemies().back(), true)


func test_kills_bring_in_the_boss() -> void:
	game.active = true
	game.level = null
	_player(Vector2(270, 800))
	for i in game.boss_kills_needed() - 1:
		_kill_weaver()
	game._physics_process(0.016)
	assert_false(game.boss_alive())
	_kill_weaver()
	game._physics_process(0.016)
	assert_true(game.boss_alive())
	assert_eq(game.kills, 0, "the count starts over")


func test_later_stages_need_more_kills() -> void:
	var first: int = game.boss_kills_needed()
	game.stage = 2
	assert_eq(game.boss_kills_needed(), first + 2 * game.BOSS_KILLS_STEP)


func test_small_groups_keep_coming_during_the_boss_and_the_level_waits() -> void:
	game.active = true
	game.level = null
	_player(Vector2(270, 800))
	_boss()
	var t: float = game.level_time
	for i in int(game.BOSS_ADD_INTERVAL * 10) + 2:
		game._physics_process(0.1)
	assert_eq(game.level_time, t, "level clock paused")
	var adds := _enemies().filter(func(e): return not e.is_boss())
	assert_gt(adds.size(), 0)
	for e in adds:
		assert_has(game.BOSS_ADD_TYPES, e.type)
	game.destroy_enemy(adds[0], true)
	assert_eq(game.kills, 0, "escort kills don't count toward the next boss")


func test_waves_and_levels_never_send_a_boss() -> void:
	assert_eq(EnemyScript.WAVE_TYPES, EnemyScript.BOSS)
	assert_false(LevelScript().TYPES.values().has(EnemyScript.BOSS))


func LevelScript() -> GDScript:
	return preload("res://scripts/level.gd")


func test_boss_is_big_tough_and_worth_a_lot() -> void:
	var b := _boss()
	assert_true(b.is_boss())
	assert_gte(b.hp, 40)
	var body: Sprite2D = b.get_node("Body")
	assert_gt(body.texture.get_size().y * body.scale.y, Ships.SHIP_HEIGHT * 2.0)
	assert_gt(b.points(), 10 * EnemyScript.TYPES[EnemyScript.WEAVER].points)


func test_boss_glides_in_then_weaves_without_leaving() -> void:
	var b := _boss()
	for i in 600:  # 60 s
		b.simulate(0.1)
		assert_lte(b.position.y, EnemyScript.BOSS_Y + EnemyScript.BOSS_BOB + 0.01)
	assert_almost_eq(b.position.y, EnemyScript.BOSS_Y, EnemyScript.BOSS_BOB + 0.01)
	var xs := []
	for i in 120:
		b.simulate(0.1)
		xs.append(b.position.x)
	assert_gt(xs.max() - xs.min(), EnemyScript.BOSS_SWAY)


# --- Attacks -------------------------------------------------------------------

func test_settled_boss_fires_an_aimed_spread_at_the_player() -> void:
	var p := _player(Vector2(270, 800))
	var b := _boss()
	b.position = Vector2(270, EnemyScript.BOSS_Y)
	b._boss_fire(b.fire_interval() + 0.01)
	var shots: Array = game.get_node("Bullets").get_children()
	assert_eq(shots.size(), 3)
	for s in shots:
		assert_true(s.is_hostile())
		assert_eq(s.kind, BulletScript.ENEMY_SHOT)
		assert_gt(s.direction.y, 0.8, "toward the player below")
	assert_almost_eq(shots[1].direction, (p.position - b.position).normalized().rotated(0.0), Vector2(0.01, 0.01))


func test_hostile_shots_hurt_players_but_pass_through_enemies() -> void:
	var p := _player(Vector2(270, 800))
	var b := _boss()
	game.fire_enemy_bullet(Vector2(270, 600), Vector2.DOWN)
	var shot: Area2D = game.get_node("Bullets").get_children().back()
	var boss_hp: int = b.hp
	b._on_area_entered(shot)
	assert_false(shot.is_queued_for_deletion(), "enemies ignore it")
	assert_eq(b.hp, boss_hp)
	var hp: float = p.hp
	p._on_area_entered(shot)
	assert_lt(p.hp, hp)


func test_later_stages_fire_more_often_and_wider() -> void:
	var b := _boss()
	var first: float = b.fire_interval()
	b.stage = 3
	assert_lt(b.fire_interval(), first)
	_player(Vector2(270, 800))
	b.position = Vector2(270, EnemyScript.BOSS_Y)
	b._boss_fire(b.fire_interval() + 0.01)
	assert_eq(game.get_node("Bullets").get_child_count(), 6)


# --- Hits and death -------------------------------------------------------------

func test_hp_bar_follows_the_host() -> void:
	var b := _boss()
	b.take_damage(1.0)
	assert_eq(b.shown_hp, b.hp)
	assert_lt(b.shown_hp, b.max_hp)


func test_ramming_only_chips_the_boss() -> void:
	var b := _boss()
	var hp: int = b.hp
	b.ram()
	assert_eq(b.hp, hp - EnemyScript.BOSS_RAM_DAMAGE)
	assert_false(b.is_queued_for_deletion())


func test_beating_the_boss_raises_the_stage_and_drops_loot() -> void:
	var b := _boss()
	b.take_damage(9999.0)
	assert_eq(game.stage, 1)
	assert_eq(game.get_node("Pickups").get_child_count(), game.BOSS_PICKUPS)
	assert_gt(game.score, 0)
	assert_eq(get_tree().get_nodes_in_group("banner").size(), 2, "warning, then the new stage")


func test_stage_replicates() -> void:
	var cfg: SceneReplicationConfig = game.get_node("ScoreSync").replication_config
	assert_true(cfg.has_property(NodePath(".:stage")))


# --- Stronger enemies ------------------------------------------------------------

func test_later_stages_send_tougher_faster_richer_enemies() -> void:
	game.stage = 2
	game.spawn_group(EnemyScript.WEAVER, 270.0, 1)
	var e: Area2D = _enemies().back()
	assert_eq(e.stage, 2)
	assert_eq(e.hp, ceili(1 * (1.0 + EnemyScript.STAGE_HP * 2)))
	assert_gt(e.hp, 1)
	assert_gt(e.speed_now(), EnemyScript.TYPES[EnemyScript.WEAVER].speed * EnemyScript.RAMP_START)
	assert_eq(e.points(), EnemyScript.TYPES[EnemyScript.WEAVER].points * 3)


func test_speed_boost_is_capped() -> void:
	var e: Area2D = EnemyScene.instantiate()
	e.stage = 100
	assert_eq(e.speed_mult(), EnemyScript.STAGE_SPEED_MAX)
	e.free()


func test_stage_travels_with_a_late_joiner_snapshot() -> void:
	game.stage = 1
	game.spawn_group(EnemyScript.TANK, 270.0, 1)
	assert_eq(_enemies().back().snapshot().stage, 1)


func test_stop_resets_the_stage() -> void:
	game.stage = 3
	game.stop()
	assert_eq(game.stage, 0)
