extends GutTest
## Fun time: a palindrome or counting-up clock (12-hour) brings out a droid
## per living ship that orbits it; at the end of the minute (or shot down, or
## its ship lost) it bursts into an exp pickup per 20 s alive, 3 at most.

const PlayerScene := preload("res://scenes/player.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")
const BulletScript := preload("res://scripts/bullet.gd")

var game: Node2D
var fun: FunTime
var now := {"hour": 13, "minute": 21}  # 1:21, a fun time
var secs := 0.0
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	now = {"hour": 13, "minute": 21}
	secs = 0.0
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	fun = game.fun_time
	fun.clock = func() -> Dictionary: return now
	fun.seconds = func() -> float: return secs
	_ship(1, Vector2(200, 700))


func after_each() -> void:
	await wait_frames(1)  # burst droids, out of the tree, go at the end of the frame
	multiplayer.multiplayer_peer = _saved_peer


func _ship(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _at(h: int, m: int) -> void:
	now = {"hour": h, "minute": m}


func _pickups() -> int:
	var n := 0
	for p in game.get_node("Pickups").get_children():
		if not p.is_queued_for_deletion():
			n += 1
	return n


# --- The clock ---------------------------------------------------------------

func test_palindromes_are_fun() -> void:
	for t in [[1, 21], [2, 22], [10, 1], [11, 11], [12, 21], [1, 1], [3, 43], [5, 55]]:
		assert_true(FunTime.is_fun_time(t[0], t[1]), "%d:%02d" % t)


func test_counting_up_is_fun() -> void:
	for t in [[1, 23], [2, 34], [3, 45], [4, 56], [12, 34]]:
		assert_true(FunTime.is_fun_time(t[0], t[1]), "%d:%02d" % t)


func test_counting_down_and_others_are_not() -> void:
	for t in [[3, 21], [5, 43], [4, 32], [12, 10], [1, 24], [1, 22], [12, 0], [12, 12], [10, 12], [1, 0], [12, 59], [9, 1]]:
		assert_false(FunTime.is_fun_time(t[0], t[1]), "%d:%02d" % t)


func test_twelve_hour_clock() -> void:
	assert_eq(FunTime.clock_digits(13, 21), "121")
	assert_eq(FunTime.clock_digits(0, 12), "1212")
	assert_eq(FunTime.clock_digits(12, 21), "1221")
	assert_eq(FunTime.clock_digits(9, 5), "905")
	assert_true(FunTime.is_fun_time(13, 21), "13:21 is 1:21")
	assert_true(FunTime.is_fun_time(0, 21), "0:21 is 12:21")
	assert_true(FunTime.is_fun_time(23, 11), "23:11 is 11:11")
	assert_true(FunTime.is_fun_time(15, 45), "15:45 is 3:45")
	assert_false(FunTime.is_fun_time(0, 12), "0:12 is 12:12, not a palindrome")
	assert_false(FunTime.is_fun_time(13, 0), "13:00 is 1:00")


func test_real_clock_is_off_in_tests() -> void:
	var f := FunTime.new()
	var t: Dictionary = f.clock.call()
	assert_false(FunTime.is_fun_time(t.hour, t.minute))


# --- Droids ------------------------------------------------------------------

func test_one_droid_per_living_ship() -> void:
	_ship(5, Vector2(400, 700))
	var dead := _ship(6, Vector2(300, 700))
	dead.hp = 0
	fun.update(game)
	var by := {}
	for d in game.droids():
		by[d.peer] = by.get(d.peer, 0) + 1
	assert_eq(by, {1: 1, 5: 1})


func test_no_droid_when_not_fun() -> void:
	_at(13, 22)
	fun.update(game)
	assert_eq(game.droids().size(), 0)


func test_no_double_spawn_in_the_same_minute() -> void:
	fun.update(game)
	fun.update(game)
	assert_eq(game.droids().size(), 1)
	game.spawn_droid(1, game.droids()[0].name)  # the same name again: already here
	assert_eq(game.droids().size(), 1)


func test_respawned_ship_gets_no_second_droid() -> void:
	fun.update(game)
	var ship: Area2D = game.get_node("Players/1")
	ship.hp = 0
	fun.update(game)
	assert_eq(game.droids().size(), 0, "burst with its ship")
	ship.hp = ship.max_hp()
	fun.update(game)
	assert_eq(game.droids().size(), 0, "one per ship per fun minute")


func test_ship_joining_mid_minute_gets_one() -> void:
	fun.update(game)
	_ship(7, Vector2(100, 700))
	secs = 30.0
	fun.update(game)
	assert_eq(game.droids().size(), 2)


func test_orbits_its_ship() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	var ship: Area2D = game.get_node("Players/1")
	d._process(0.1)
	var a := d.position - ship.position
	assert_almost_eq(a.length(), Droid.ORBIT_RADIUS, 0.01)
	d._process(0.5)
	var b := d.position - ship.position
	assert_almost_eq(b.length(), Droid.ORBIT_RADIUS, 0.01)
	assert_almost_eq(absf(a.angle_to(b)), Droid.ORBIT_SPEED * 0.5, 0.01, "goes round")
	ship.position += Vector2(50, -20)
	d._process(0.1)
	assert_almost_eq(d.position.distance_to(ship.position), Droid.ORBIT_RADIUS, 0.01, "follows the ship")


func test_fun_time_text_for_its_pilot() -> void:
	fun.update(game)
	var texts := game.get_node("Effects").get_children().filter(func(n): return n is FloatText)
	assert_eq(texts.size(), 1)
	assert_eq(texts[0].text, "FUN TIME!")


func test_droids_of_a_new_run() -> void:
	fun.update(game)
	fun.reset()
	for d in game.droids():
		game.burst_droid(d.name)
	fun.update(game)
	assert_eq(game.droids().size(), 1, "a run started mid-minute brings them out")


# --- Rewards -----------------------------------------------------------------

func test_reward_per_twenty_seconds() -> void:
	assert_eq(FunTime.reward_for(0.0), 0)
	assert_eq(FunTime.reward_for(19.0), 0)
	assert_eq(FunTime.reward_for(20.0), 1)
	assert_eq(FunTime.reward_for(39.0), 1)
	assert_eq(FunTime.reward_for(40.0), 2)
	assert_eq(FunTime.reward_for(59.8), 3, "the whole minute, give or take a frame")
	assert_eq(FunTime.reward_for(600.0), 3, "3 at most")


func _survive(seconds: float) -> int:
	fun.update(game)
	secs = seconds
	_at(13, 22)  # the minute is over
	fun.update(game)
	return _pickups()


func test_bursts_at_end_of_minute_0() -> void:
	assert_eq(_survive(10.0), 0)
	assert_eq(game.droids().size(), 0)


func test_bursts_at_end_of_minute_1() -> void:
	assert_eq(_survive(25.0), 1)


func test_bursts_at_end_of_minute_2() -> void:
	assert_eq(_survive(45.0), 2)


func test_bursts_at_end_of_minute_3() -> void:
	assert_eq(_survive(59.9), 3)
	assert_eq(fun.minute, -1)


func test_minute_rollover_ends_it() -> void:
	_at(12, 34)
	fun.update(game)
	secs = 60.0
	_at(12, 35)
	fun.update(game)
	assert_eq(game.droids().size(), 0)
	assert_eq(_pickups(), 3)


func test_bursts_where_it_is() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	d.position = Vector2(123, 456)
	secs = 25.0
	_at(13, 22)
	fun.update(game)
	assert_eq(game.get_node("Pickups").get_child(0).position, Vector2(123, 456))


func test_shot_down_early_drops_what_it_earned() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	for i in Droid.HP:
		secs = 41.0 + i
		game.report_droid_hit(d.name)
	assert_eq(game.droids().size(), 0, "destroyed")
	assert_eq(_pickups(), 2)


func test_shot_down_at_once_drops_nothing() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	for i in Droid.HP:
		secs = 1.0 + i
		game.report_droid_hit(d.name)
	assert_eq(game.droids().size(), 0)
	assert_eq(_pickups(), 0)


func test_ship_lost_drops_what_it_earned() -> void:
	fun.update(game)
	secs = 21.0
	game.get_node("Players/1").hp = 0
	fun.update(game)
	assert_eq(game.droids().size(), 0)
	assert_eq(_pickups(), 1)


func test_ship_gone_drops_what_it_earned() -> void:
	fun.update(game)
	secs = 50.0
	var ship := game.get_node("Players/1")
	game.get_node("Players").remove_child(ship)
	ship.free()
	fun.update(game)
	assert_eq(_pickups(), 2)


# --- Getting hit -------------------------------------------------------------

func test_hits_wear_it_down() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	game.report_droid_hit(d.name)
	assert_eq(d.hp, Droid.HP - 1)
	game.report_droid_hit(d.name)
	assert_eq(d.hp, Droid.HP - 1, "a touch is one hit")
	secs = 1.0
	game.report_droid_hit(d.name)
	assert_eq(d.hp, Droid.HP - 2)


func test_nothing_hurts_it_between_levels() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	game.refit = true
	game.report_droid_hit(d.name)
	assert_eq(d.hp, Droid.HP)


func test_only_its_pilot_reports_hits() -> void:
	var other := _ship(9, Vector2(400, 700))
	other.set_multiplayer_authority(9)
	fun.update(game)
	for d in game.droids():
		if d.peer == 9:
			game.report_droid_hit(d.name)  # from us (peer 1), not 9
			assert_eq(d.hp, Droid.HP)


func test_enemy_shots_hit_it_and_ours_pass() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	var ours: Area2D = BulletScene.instantiate()
	ours.shooter = 1
	ours.position = Vector2(300, 300)
	game.get_node("Bullets").add_child(ours)
	assert_false(d.touched(game, Vector2(300, 300)), "its own side's shots pass through")
	var theirs: Area2D = BulletScene.instantiate()
	theirs.shooter = BulletScript.ENEMY_SHOOTER
	theirs.position = Vector2(300, 300)
	game.get_node("Bullets").add_child(theirs)
	assert_true(d.touched(game, Vector2(300, 300)))
	assert_true(theirs.is_queued_for_deletion(), "the shot is used up")
	assert_false(ours.is_queued_for_deletion())


func test_reports_a_touch_to_the_host() -> void:
	fun.update(game)
	var d: Droid = game.droids()[0]
	d._process(0.01)
	var theirs: Area2D = BulletScene.instantiate()
	theirs.shooter = BulletScript.ENEMY_SHOOTER
	game.get_node("Bullets").add_child(theirs)
	theirs.position = game.get_node("Players/1").position + d.orbit_offset(0.02)
	d._process(0.01)
	assert_eq(d.hp, Droid.HP - 1)


func test_host_left_keeps_the_droid() -> void:
	game.get_node("Players/1").name = "50"
	game.get_node("Players/50").peer_id = 50
	game.spawn_droid(50, "Droid4")
	game.continue_solo(50)
	assert_eq(game.droids()[0].peer, multiplayer.get_unique_id())
	assert_eq(fun.count, 4, "new names don't collide")
