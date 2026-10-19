extends GutTest
## Heal beam: a WEAPONS gun that adds a HEAL on/off button; while armed (on),
## the ship streams fast heal shots straight up. They heal other ships they hit, and
## make enemies they hit stronger and bigger.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")
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


func _buy_healbeam() -> void:
	for i in player.price(&"healbeam"):
		game.collect_pickup("none", 1)
	assert_true(player.buy_upgrade(&"healbeam"))


## Room in the reactor and WEAPONS for every gun.
func _give_power() -> void:
	player.levels[&"reactor"] = Systems.max_level(&"reactor")
	player.levels[&"weapons"] = Systems.max_level(&"weapons")


## Armed, with the HEAL button held down.
func _arm_healbeam() -> void:
	_give_power()
	assert_true(player.arm(&"healbeam"))
	player._heal_held = true


func _heal_shot(shooter: int, at: Vector2) -> Area2D:
	var b: Area2D = BulletScene.instantiate()
	b.kind = BulletScript.HEAL
	b.shooter = shooter
	b.position = at
	game.get_node("Bullets").add_child(b)
	return b


func _enemy(pos: Vector2, type := EnemyScript.WEAVER) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.type = type
	e.position = pos
	game.get_node("Enemies").add_child(e)
	return e


func _heal_bullets() -> Array:
	return game.get_node("Bullets").get_children().filter(func(b): return b.kind == BulletScript.HEAL)


func test_a_weapons_gun() -> void:
	assert_true(Systems.is_gun(&"healbeam"))
	assert_eq(Systems.max_level(&"healbeam"), 2)
	assert_eq(Systems.gun_power(&"healbeam"), 1)
	assert_eq(Systems.gun_action(&"healbeam"), &"heal")
	assert_eq(Systems.gun_for_action(&"heal"), &"healbeam")


func test_adds_a_heal_button_the_first_press_arms_it() -> void:
	player._gather_input()
	assert_false(bar.is_shown(&"heal"))
	_buy_healbeam()
	player._gather_input()
	assert_true(bar.is_shown(&"heal"))
	assert_false(bar._lit.get(&"heal", false), "shows OFF until armed")
	_give_power()
	assert_true(bar.press(&"heal"))
	player._gather_input()
	assert_true(player.is_armed(&"healbeam"))
	assert_true(bar._lit.get(&"heal", false), "lit while armed")
	bar._process(1.0)
	assert_true(bar.press(&"heal"))
	player._gather_input()
	assert_true(player.is_armed(&"healbeam"), "not a toggle: pressing again doesn't switch it off")


func test_fires_only_while_held() -> void:
	_buy_healbeam()
	_arm_healbeam()
	player._heal_held = false
	for i in 30:
		player._simulate(1.0 / 60.0)
	assert_eq(_heal_bullets().size(), 0, "armed but not held")
	player._heal_held = true
	player._simulate(1.0 / 60.0)
	assert_gt(_heal_bullets().size(), 0)


func test_holding_the_button_holds_the_trigger() -> void:
	_buy_healbeam()
	_give_power()
	game.get_node("PointerControls").visible = true
	player._gather_input()
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.index = 3
	ev.position = bar.button_rect(ActionBar.ACTIONS.map(func(a): return a.id).find(&"heal")).get_center()
	bar._input(ev)
	player._gather_input()
	assert_true(player.is_armed(&"healbeam"))
	assert_true(player._heal_held, "finger down")
	ev = ev.duplicate()
	ev.pressed = false
	bar._input(ev)
	player._gather_input()
	assert_false(player._heal_held, "let go")


func test_streams_very_fast_shots_straight_up_while_held() -> void:
	_buy_healbeam()
	_arm_healbeam()
	for i in 60:
		player._simulate(1.0 / 60.0)
	var shots := _heal_bullets()
	assert_almost_eq(shots.size(), int(1.0 / PlayerScript.HEALBEAM_INTERVAL), 1, "a dense stream")
	assert_lt(PlayerScript.HEALBEAM_INTERVAL, 0.1, "faster than it was")
	for b in shots:
		assert_eq(b.direction, Vector2.UP)
	assert_gt(BulletScript.KINDS[BulletScript.HEAL].speed, BulletScript.KINDS[BulletScript.LASER].speed, "fast")


func test_level_two_fires_twice_as_fast() -> void:
	player.levels[&"healbeam"] = 2
	_arm_healbeam()
	for i in 60:
		player._simulate(1.0 / 60.0)
	assert_almost_eq(_heal_bullets().size(), int(2.0 / PlayerScript.HEALBEAM_INTERVAL), 2)


func test_off_or_unbought_fires_nothing() -> void:
	_give_power()
	assert_false(player.arm(&"healbeam"), "can't arm what isn't bought")
	player._simulate(0.5)
	assert_eq(_heal_bullets().size(), 0, "not bought")
	_buy_healbeam()
	player._simulate(0.5)
	assert_eq(_heal_bullets().size(), 0, "switched off")


func test_lost_with_the_ship() -> void:
	_buy_healbeam()
	_arm_healbeam()
	player._lose_upgrades()
	assert_false(player.is_armed(&"healbeam"))
	assert_eq(player.level(&"healbeam"), 0)


func test_heal_shots_heal_other_ships() -> void:
	player.hp = 10.0
	var b := _heal_shot(42, player.position)
	player._on_area_entered(b)
	assert_true(b.is_queued_for_deletion())
	assert_almost_eq(player.hp, 10.0 + 0.1 * PlayerScript.HIT_HP, 0.0001)


func test_own_heal_shots_pass_through() -> void:
	player.hp = 10.0
	var b := _heal_shot(1, player.position)
	player._on_area_entered(b)
	assert_false(b.is_queued_for_deletion())
	assert_eq(player.hp, 10.0)


func test_heal_shots_make_enemies_stronger_and_bigger() -> void:
	var e := _enemy(Vector2(270, 300))
	var hp_before: int = e.hp
	for i in 10:
		e._on_area_entered(_heal_shot(1, e.position))
	await wait_frames(1)  # hit reports reach the host at the end of the frame
	assert_eq(e.hp, hp_before + 1, "ten shots, a hit point")
	assert_eq(e.max_hp, hp_before + 1)
	assert_almost_eq(e.scale.x, 1.0 + EnemyScript.GROW_STEP, 0.0001, "and a bit bigger")


func test_enemy_growth_is_capped() -> void:
	var e := _enemy(Vector2(270, 300))
	e.grow(100)
	assert_almost_eq(e.scale.x, EnemyScript.GROW_MAX, 0.0001)


func test_heal_shots_never_hurt_enemies() -> void:
	var e := _enemy(Vector2(270, 300))
	for i in 25:
		e._on_area_entered(_heal_shot(1, e.position))
	await wait_frames(1)  # hit reports reach the host at the end of the frame
	assert_false(e.is_queued_for_deletion())
	assert_gt(e.hp, EnemyScript.TYPES[EnemyScript.WEAVER].hp)


func test_heal_shots_pass_through_pods() -> void:
	game.spawn_pod(Vector2(200, 300), 0, "Pod1")
	var pod: Area2D = game.get_node("Pods/Pod1")
	var b := _heal_shot(1, pod.position)
	pod._on_area_entered(b)
	assert_false(b.is_queued_for_deletion())
	assert_true(game.get_node("Pods").has_node("Pod1"))


func test_a_stream_of_heals_chimes_now_and_then() -> void:
	var heal: AudioStreamPlayer = game.get_node("HealSound")
	player.hp = 5.0
	player.heal(0.1)
	assert_true(heal.playing)
	heal.stop()
	player.heal(0.1)
	assert_false(heal.playing, "not again so soon")


func test_stream_burbles_once_per_burst() -> void:
	_buy_healbeam()
	_arm_healbeam()
	var burble: AudioStreamPlayer = game.get_node("HealBeamSound")
	player._simulate(1.0 / 60.0)
	assert_true(burble.playing)
	var until: float = game._healbeam_until[1]
	burble.stop()
	for i in 6:
		player._simulate(1.0 / 60.0)
	assert_eq(game._healbeam_until[1], until, "no new burble mid-burst")
	assert_false(burble.playing)
	assert_false(game.get_node("ShootSound").playing, "not the laser sound")
