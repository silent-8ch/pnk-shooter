extends GutTest
## Ruined Starbase scenery: hull plating behind the action, blast doors that
## slam shut on a band of the screen (except a gap), and a boss with sweeping
## turret fire.

const PlayerScene := preload("res://scenes/player.tscn")
const StarbaseScript := preload("res://scripts/scenery/starbase.gd")

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
	p.shield = 0
	p.rear_shield = 0
	return p


func _starbase() -> Node2D:
	game.kind = "starbase"
	game._process(0.0)
	return game.scenery


func test_starbase_kind_installs_its_scenery() -> void:
	var s := _starbase()
	assert_true(s.get_script().resource_path.ends_with("scripts/scenery/starbase.gd"))


func test_level_file_loads() -> void:
	var l = LevelKinds.load_level("starbase")
	assert_not_null(l)
	assert_eq(l.kind, "starbase")
	assert_true(l.repeat)


func test_door_schedule_is_deterministic() -> void:
	var a = StarbaseScript.new()
	var b = StarbaseScript.new()
	var c = StarbaseScript.new()
	a.run_seed = 42
	b.run_seed = 42
	c.run_seed = 43
	var differs := false
	for i in 6:
		assert_eq(a.door_band(i), b.door_band(i))
		assert_eq(a.door_gap(i), b.door_gap(i))
		differs = differs or a.door_gap(i) != c.door_gap(i) or a.door_band(i) != c.door_band(i)
	assert_true(differs, "another seed gives other doors")
	for x in [a, b, c]:
		x.free()


func test_doors_stay_on_screen() -> void:
	var a = StarbaseScript.new()
	for seed in 20:
		a.run_seed = seed
		var band: Vector2 = a.door_band(0)
		var gap: Vector2 = a.door_gap(0)
		assert_true(band.x >= 0.0 and band.y <= 960.0)
		assert_true(gap.x >= a.DOOR_EDGE - 0.01 and gap.y <= 540.0 - a.DOOR_EDGE + 0.01)
		assert_almost_eq(gap.y - gap.x, a.DOOR_GAP, 0.01)
	a.free()


func test_door_timing() -> void:
	var s := _starbase()
	assert_eq(s.door_index(0.0), -1)
	assert_eq(s.door_index(s.DOOR_FIRST), 0)
	assert_eq(s.door_index(s.DOOR_FIRST + s.DOOR_INTERVAL + 1.0), 1)


func test_closing_door_hurts_only_ships_in_the_sealed_part() -> void:
	var s := _starbase()
	var band: Vector2 = s.door_band(0)
	var gap: Vector2 = s.door_gap(0)
	var y := (band.x + band.y) / 2.0
	var sealed_x := gap.x / 2.0 if gap.x > 60.0 else (gap.y + 540.0) / 2.0
	var caught := _ship(2, Vector2(sealed_x, y))
	var safe := _ship(3, Vector2((gap.x + gap.y) / 2.0, y))
	var away := _ship(4, Vector2(sealed_x, band.y + 120.0 if band.y < 800.0 else band.x - 120.0))
	var full: float = caught.hp
	s.time = s.DOOR_FIRST + s.DOOR_WARN - 0.05
	s._process(0.0)
	assert_eq(caught.hp, full, "no hit during the warning")
	s._process(0.1)
	assert_lt(caught.hp, full, "caught in the sealed part")
	assert_eq(safe.hp, full, "in the gap")
	assert_eq(away.hp, full, "outside the band")
	var after: float = caught.hp
	s._process(0.1)
	assert_eq(caught.hp, after, "one hit per door")


func test_boss_attack_fires_a_sweeping_fan() -> void:
	var s := _starbase()
	var boss := Node2D.new()
	boss.position = Vector2(270, 200)
	add_child_autofree(boss)
	var target := _ship(2, Vector2(270, 800))
	var bullets := game.get_node("Bullets")
	var before := bullets.get_child_count()
	assert_true(s.boss_attack(boss, target, 5))
	assert_eq(bullets.get_child_count() - before, 5)
	var first: Vector2 = bullets.get_child(before + 2).direction
	s.boss_attack(boss, target, 5)
	var second: Vector2 = bullets.get_child(before + 7).direction
	assert_gt(absf(first.angle_to(second)), 0.05, "the fan's aim moves each volley")
