extends GutTest
## Autocannons: a WEAPONS gun that adds an AUTO on/off button for a vulcan
## cannon, point defence only: while armed (on), it hoses the nearest enemy
## shot within a short range, and never enemies or other ships.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const BulletScript := preload("res://scripts/bullet.gd")

var game: Node2D
var player: Area2D
var bar: ActionBar
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.get_node("PointerControls").visible = true
	bar = game.get_node("PointerControls/ActionBar")
	player = PlayerScene.instantiate()
	player.name = "1"
	player.peer_id = 1
	player.position = Vector2(270, 600)
	game.get_node("Players").add_child(player)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _buy_auto() -> void:
	for i in player.price(&"auto"):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(&"auto"))


## Room in WEAPONS (and the reactor) for every gun.
func _give_power() -> void:
	player.levels[&"reactor"] = Systems.max_level(&"reactor")
	player.levels[&"weapons"] = Systems.max_level(&"weapons")


func _arm_auto() -> void:
	_give_power()
	assert_true(player.arm(&"auto"))


func _enemy(pos: Vector2) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.position = pos
	game.get_node("Enemies").add_child(e)
	return e


func _friend(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "42"
	p.peer_id = 42
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _bullets() -> Array:
	return game.get_node("Bullets").get_children()


func test_a_weapons_gun() -> void:
	assert_true(Systems.is_gun(&"auto"))
	assert_eq(Systems.max_level(&"auto"), 2)
	assert_eq(Systems.item(&"auto").label, "AUTOCAN")
	assert_eq(Systems.gun_power(&"auto"), 1)
	assert_eq(Systems.gun_action(&"auto"), &"auto")


func test_button_appears_and_toggles() -> void:
	player._gather_input()
	assert_false(bar.is_shown(&"auto"))
	_buy_auto()
	player._gather_input()
	assert_true(bar.is_shown(&"auto"))
	assert_false(bar._lit.get(&"auto", false), "shows OFF until armed")
	_give_power()
	assert_true(bar.press(&"auto"))
	player._gather_input()
	assert_true(player.is_armed(&"auto"), "must be switched on")
	assert_true(bar._lit.get(&"auto", false))
	bar._process(1.0)
	bar.press(&"auto")
	player._gather_input()
	assert_false(player.is_armed(&"auto"), "and off again")


func test_off_by_default_even_when_bought() -> void:
	_buy_auto()
	assert_false(player.is_armed(&"auto"))
	assert_eq(player.level(&"auto"), 0, "does nothing until armed")
	_enemy(player.position + Vector2(0, -60))
	player._simulate(0.5)
	assert_eq(_bullets().size(), 0)


func test_needs_a_spare_weapons_bar_to_arm() -> void:
	_buy_auto()
	assert_false(player.arm(&"auto"), "the lasers take the only WEAPONS bar")
	player.levels[&"weapons"] = 2
	assert_true(player.arm(&"auto"), "powered up from the reactor")
	assert_eq(player.power_of(&"weapons"), 2)
	assert_eq(player.level(&"auto"), 1)


func test_shoots_at_the_closest_enemy_shot_in_range() -> void:
	_buy_auto()
	_arm_auto()
	_enemy_shot(player.position + Vector2(100, 0), Vector2.ZERO)
	_enemy_shot(player.position + Vector2(-50, 0), Vector2.ZERO)
	player._simulate(0.016)
	var shots := _bullets().filter(func(b): return not b.is_hostile())
	assert_eq(shots.size(), 1)
	assert_lt(shots[0].direction.angle_to(Vector2.LEFT), PlayerScript.AUTO_SPREAD + 0.001, "aimed at the closer one")
	assert_eq(shots[0].kind, BulletScript.VULCAN)


func test_ignores_shots_out_of_range() -> void:
	_buy_auto()
	_arm_auto()
	_enemy_shot(player.position + Vector2(0, -PlayerScript.AUTO_RANGE - 10), Vector2.ZERO)
	player._simulate(0.016)
	assert_eq(_bullets().filter(func(b): return not b.is_hostile()).size(), 0)


func test_never_targets_enemies_or_ships() -> void:
	_buy_auto()
	_arm_auto()
	_enemy(player.position + Vector2(0, -40))
	_friend(player.position + Vector2(0, 60))
	assert_null(player.auto_target(), "only enemy shots")
	player._simulate(0.016)
	assert_eq(_bullets().size(), 0)


func test_fires_a_steady_stream_of_rounds() -> void:
	_buy_auto()
	_arm_auto()
	var shot := _enemy_shot(player.position + Vector2(0, -60), Vector2.ZERO)
	shot.toughness = 100000
	for i in 60:
		player._simulate(1.0 / 60.0)
	var rounds := func(): return _bullets().filter(func(b): return not b.is_hostile()).size()
	assert_almost_eq(rounds.call(), int(1.0 / PlayerScript.AUTO_COOLDOWN) + 1, 1, "a round every AUTO_COOLDOWN")
	var n: int = rounds.call()
	_buy_auto()
	assert_eq(player.level(&"auto"), 2)
	for i in 60:
		player._simulate(1.0 / 60.0)
	assert_gt(rounds.call() - n, n, "level 2 fires faster")


func test_vulcan_rounds_are_small_slow_weak_and_long_lived() -> void:
	var laser: Dictionary = BulletScript.KINDS[BulletScript.LASER]
	var vulcan: Dictionary = BulletScript.KINDS[BulletScript.VULCAN]
	assert_lt(vulcan.scale, laser.scale)
	assert_lt(vulcan.speed, laser.speed, "slow enough to see the strand")
	assert_lt(vulcan.damage, laser.damage)
	assert_gt(vulcan.range, 400.0, "a long strand")
	game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.RIGHT, BulletScript.VULCAN)
	var b: Area2D = _bullets()[0]
	assert_almost_eq(b.rotation, PI / 2.0, 0.001, "points where it flies")
	b._physics_process(0.1)
	assert_almost_eq(b.position, Vector2(270 + vulcan.speed * 0.1, 500), Vector2(0.01, 0.01))
	b._physics_process(vulcan.range / vulcan.speed)
	assert_true(b.is_queued_for_deletion(), "fizzles in the end")


func test_rounds_join_into_one_strand_per_gun() -> void:
	game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.UP, BulletScript.VULCAN)
	var first: Area2D = _bullets().back()
	game.fire_bullet(Vector2(272, 510), Color.RED, Vector2.UP, BulletScript.VULCAN)
	var second: Area2D = _bullets().back()
	assert_eq(second.link, first, "joined to the round before it")
	game.fire_bullet(Vector2(100, 500), Color.RED, Vector2.UP, BulletScript.VULCAN)
	assert_null(_bullets().back().link, "another gun's round starts its own strand")
	assert_null(first.link)


func test_a_dense_stream_of_light_rounds() -> void:
	assert_eq(BulletScript.KINDS[BulletScript.VULCAN].damage, 0.125)
	assert_eq(PlayerScript.AUTO_COOLDOWN, 0.035)
	var per_second := BulletScript.KINDS[BulletScript.VULCAN].damage / PlayerScript.AUTO_COOLDOWN
	assert_almost_eq(per_second, 0.5 / 0.14, 0.01, "same damage per second as before")


## An enemy shot at `pos` flying `dir` (Vector2.ZERO: hanging still, for aim checks).
func _enemy_shot(pos: Vector2, dir: Vector2) -> Area2D:
	game.fire_enemy_bullet(pos, dir)
	var shot: Area2D = _bullets().filter(func(b): return b.is_hostile()).back()
	if dir == Vector2.ZERO:
		shot.direction = Vector2.ZERO
	return shot


func test_aims_at_enemy_shots_before_enemies() -> void:
	_buy_auto()
	_arm_auto()
	_enemy(player.position + Vector2(-40, 0))
	_enemy_shot(player.position + Vector2(100, 0), Vector2.DOWN)
	assert_true(player.auto_target().is_in_group("bullet"), "the shot, though the enemy is closer")
	player._simulate(0.016)
	var round: Area2D = _bullets().filter(func(b): return not b.is_hostile())[0]
	assert_lt(absf(round.direction.angle_to(Vector2.RIGHT)), 1.0, "toward the shot (well ahead of it: rounds are slow)")
	assert_gt(round.direction.y, 0.0, "leading it: the shot is falling")


func test_ignores_enemy_shots_out_of_range() -> void:
	_enemy_shot(player.position + Vector2(0, -PlayerScript.AUTO_RANGE - 10), Vector2.DOWN)
	assert_null(player.auto_target())


func test_ignores_player_shots() -> void:
	game.fire_bullet(player.position + Vector2(0, -50), Color.RED)
	assert_null(player.auto_target())


func test_a_round_shoots_down_an_enemy_shot() -> void:
	var shot := _enemy_shot(Vector2(270, 300), Vector2.DOWN)
	game.fire_bullet(Vector2(270, 400), Color.RED, Vector2.UP, BulletScript.VULCAN)
	var round: Area2D = _bullets().filter(func(b): return b.kind == BulletScript.VULCAN)[0]
	round._on_area_entered(shot)
	assert_true(round.is_queued_for_deletion(), "the round is spent")
	assert_false(shot.is_queued_for_deletion(), "one round isn't enough")
	for i in BulletScript.SHOT_TOUGHNESS - 1:
		game.fire_bullet(Vector2(270, 400), Color.RED, Vector2.UP, BulletScript.VULCAN)
		var more: Area2D = _bullets().filter(func(b): return b.kind == BulletScript.VULCAN and not b.is_queued_for_deletion()).back()
		more._on_area_entered(shot)
	assert_true(shot.is_queued_for_deletion(), "shot down after %d rounds" % BulletScript.SHOT_TOUGHNESS)


func test_a_round_passes_other_player_shots() -> void:
	game.fire_bullet(Vector2(270, 300), Color.BLUE)
	var laser: Area2D = _bullets()[0]
	game.fire_bullet(Vector2(270, 400), Color.RED, Vector2.UP, BulletScript.VULCAN)
	var round: Area2D = _bullets().filter(func(b): return b.kind == BulletScript.VULCAN)[0]
	round._on_area_entered(laser)
	assert_false(laser.is_queued_for_deletion())
	assert_false(round.is_queued_for_deletion())


func test_shoots_down_a_shot_coming_at_it() -> void:
	_buy_auto()
	_arm_auto()
	var shot := _enemy_shot(player.position + Vector2(0, -PlayerScript.AUTO_RANGE + 5), Vector2.DOWN)
	for i in 30:
		player._simulate(1.0 / 60.0)
		await wait_physics_frames(1)
		if not is_instance_valid(shot) or shot.is_queued_for_deletion():
			break
	assert_true(not is_instance_valid(shot) or shot.is_queued_for_deletion(), "gone before it reached the ship")


func test_vulcan_makes_no_shoot_sound() -> void:
	game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.RIGHT, BulletScript.VULCAN)
	assert_false(game.get_node("ShootSound").playing)


func test_rounds_add_up_to_a_kill() -> void:
	var e := _enemy(Vector2(270, 300))
	var per: float = BulletScript.KINDS[BulletScript.VULCAN].damage
	var needed := int(ceil(1.0 / per))
	for i in needed - 1:
		game.report_hit(String(e.name), per)
	assert_false(e.is_queued_for_deletion(), "weak alone")
	game.report_hit(String(e.name), per)
	assert_true(e.is_queued_for_deletion() or e.hp <= 0)


func test_rounds_chip_at_friendlies_too() -> void:
	var per: float = BulletScript.KINDS[BulletScript.VULCAN].damage
	player.take_damage(per)
	assert_almost_eq(player.hp, PlayerScript.MAX_HP - per * PlayerScript.HIT_HP, 0.001, "each round shows")
	for i in int(ceil(1.0 / per)) - 1:
		player.take_damage(per)
	assert_almost_eq(player.hp, PlayerScript.MAX_HP - PlayerScript.HIT_HP, 0.001, "a laser's worth")


func test_lasers_still_go_straight_up() -> void:
	game.fire_bullet(Vector2(270, 500), Color.RED)
	var b: Area2D = _bullets()[0]
	b._physics_process(0.1)
	assert_almost_eq(b.position, Vector2(270, 458), Vector2(0.01, 0.01))
	assert_eq(b.rotation, 0.0)


func test_switched_off_when_ship_is_lost() -> void:
	_buy_auto()
	_arm_auto()
	player.take_damage(PlayerScript.MAX_HP)
	player._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_false(player.is_armed(&"auto"))
	assert_eq(player.level(&"auto"), 0)


func test_a_stream_of_rounds_plays_one_vulcan_burst() -> void:
	var sound: AudioStreamPlayer = game.get_node("VulcanSound")
	assert_eq(sound.stream, load("res://assets/sfx/vulcan.tres"))
	game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.UP, BulletScript.VULCAN)
	var until: float = game._vulcan_until[1]
	for i in 5:
		game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.UP, BulletScript.VULCAN)
	assert_eq(game._vulcan_until[1], until, "no new burst while one is playing")
	game._vulcan_until[1] = 0.0  # that burst ran out
	game.fire_bullet(Vector2(270, 500), Color.RED, Vector2.UP, BulletScript.VULCAN)
	assert_gt(game._vulcan_until[1], until - 0.001, "next burst")



func test_options_fire_vulcans_at_the_shots_nearest_them() -> void:
	_buy_auto()
	_arm_auto()
	player.levels[&"option"] = 1
	player.levels[&"drones"] = 1
	player.levels[&"reactor"] = 8
	player.add_power(&"option")
	player._simulate(0.016)
	player._trail.assign([Vector2(100, 600), Vector2(100, 600), Vector2(100, 600)])
	_enemy_shot(Vector2(100, 520), Vector2.ZERO)  # near where the option is
	_enemy_shot(player.position + Vector2(0, -60), Vector2.ZERO)
	player._auto_cooldown = 0.0
	player._run_autocannon(1.0 / 60.0)
	var from := _bullets().filter(func(b): return not b.is_hostile() and not b.is_queued_for_deletion()).map(func(b): return b.position.x)
	assert_gt(from.size(), 1, "the ship and its option")
	assert_true(from.any(func(x): return x < 200.0), "one from the option's side")
