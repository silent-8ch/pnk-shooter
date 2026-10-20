extends GutTest
## The Crystal Storm, Crystal Crevices' boss: the cloud the level's rain falls
## out of, drawn from the scan. One target with no parts to break off; what
## makes it a fight is the downpour it drops on whoever it's aiming at, heavier
## the more it has been worn down.

const EnemyScript := preload("res://scripts/enemy.gd")
const CrystalBossScript := preload("res://scripts/crystal_boss.gd")
const CrystalScript := preload("res://scripts/scenery/crystal_crevices.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game.active = true
	game.kind = "crystal_crevices"
	game._process(0.0)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _boss() -> Area2D:
	game.kind = "crystal_crevices"
	game.spawn_boss()
	return game.get_node("Enemies").get_children().back()


func _cloud(e: Area2D) -> Node2D:
	return e.get_node("CrystalStorm")


func _player(pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func test_crystal_crevices_boss_is_the_storm_cloud() -> void:
	var e := _boss()
	assert_eq(e.type, EnemyScript.CRYSTAL)
	assert_true(e.is_crystal())
	assert_true(e.is_boss(), "a boss in every way: bar, music, stage, refit")
	assert_true(e.has_node("CrystalStorm"))
	assert_false(e.body.visible, "it's weather, not a ship")


func test_other_kinds_keep_their_boss() -> void:
	game.kind = "asteroid_belt"
	game.spawn_boss()
	var e: Area2D = game.get_node("Enemies").get_children().back()
	assert_eq(e.type, EnemyScript.BOSS)


func test_it_wears_the_scanned_cloud_art() -> void:
	var cloud := _cloud(_boss())
	var sprite: Sprite2D = cloud.get_node("Cloud")
	assert_eq(sprite.texture, CrystalBossScript.ART)
	assert_true(CrystalBossScript.ART.resource_path.ends_with("assets/crystal_storm.svg"))
	assert_gt(sprite.texture.get_width(), sprite.texture.get_height(), "a cloud is wider than it is tall")


func test_it_hangs_wide_with_a_box_hit_box() -> void:
	var e := _boss()
	var cloud := _cloud(e)
	assert_gt(cloud.width(), 200.0, "wider than any ship")
	var shape = e.get_node("Shape").shape
	assert_true(shape is RectangleShape2D, "a circle would miss its ends")
	assert_almost_eq(shape.size.x, cloud.width(), 1.0)


func test_no_thrusters_on_a_cloud() -> void:
	assert_false(_boss().has_node("Thrusters"))


func test_it_has_no_parts_and_takes_damage_straight_away() -> void:
	var e := _boss()
	var hp: int = e.hp
	e.take_damage(3.0)
	assert_eq(e.hp, hp - 3, "one target, nothing shielding it")


func test_it_drifts_and_swells_without_leaving_its_place() -> void:
	var cloud := _cloud(_boss())
	var xs := {}
	var widths := {}
	for i in 60:
		cloud.enemy._time = i * 0.25
		cloud._process(0.0)
		xs[snappedf(cloud.get_node("Cloud").position.x, 0.1)] = true
		widths[snappedf(cloud.width(), 0.1)] = true
		assert_lte(absf(cloud.get_node("Cloud").position.x), CrystalBossScript.DRIFT + 0.01, "stays over its spot")
	assert_gt(xs.size(), 10, "it drifts")
	assert_gt(widths.size(), 10, "and breathes")


func test_wear_tracks_how_hurt_it_is() -> void:
	var e := _boss()
	var cloud := _cloud(e)
	assert_almost_eq(cloud.wear(), 0.0, 0.001, "untouched")
	e.hp = e.max_hp / 2
	assert_almost_eq(cloud.wear(), 0.5, 0.05, "halfway")
	e.hp = 0
	assert_almost_eq(cloud.wear(), 1.0, 0.001, "done for")


# --- The downpour -----------------------------------------------------------------

func test_the_boss_rains_shards_and_fires() -> void:
	var s: Node2D = game.scenery
	var e := _boss()
	var target := _player(Vector2(270, 700))
	var bullets := game.get_node("Bullets")
	var obstacles := game.get_node("Obstacles")
	var shots := bullets.get_child_count()
	var rocks := obstacles.get_child_count()
	assert_true(s.boss_attack(e, target, 4))
	assert_gt(bullets.get_child_count() - shots, 0, "it fires too")
	assert_gt(obstacles.get_child_count() - rocks, 0, "and drops shards")
	for o in obstacles.get_children():
		assert_eq(o.piece_id, CrystalScript.RAIN_PIECE)


func test_a_downpour_lands_over_its_target_and_inside_the_walls() -> void:
	var s: Node2D = game.scenery
	var e := _boss()
	for x in [40.0, 270.0, 500.0]:
		var at := Vector2(x, 700)
		var drops: Array = s.downpour(e, at, 0.5)
		assert_gt(drops.size(), 0)
		var mid := 0.0
		for p in drops:
			assert_between(p.x, 0.0, CrystalScript.ARENA.x, "inside the walls")
			mid += p.x
		mid /= drops.size()
		assert_lt(absf(mid - clampf(x, 105.0, 435.0)), 60.0, "centred near the target")


func test_a_worn_cloud_drops_more() -> void:
	var s: Node2D = game.scenery
	var e := _boss()
	var fresh: int = s.downpour(e, Vector2(270, 700), 0.0).size()
	var worn: int = s.downpour(e, Vector2(270, 700), 1.0).size()
	assert_eq(fresh, CrystalScript.DOWNPOUR_SHARDS.x)
	assert_eq(worn, CrystalScript.DOWNPOUR_SHARDS.y)
	assert_gt(worn, fresh, "the worse it's hurt the harder it rains")


func test_downpour_shards_start_below_the_cloud() -> void:
	var s: Node2D = game.scenery
	var e := _boss()
	var cloud := _cloud(e)
	for p in s.downpour(e, Vector2(270, 700), 0.5):
		assert_gte(p.y, e.position.y + cloud.underside() - 0.01, "out of its underside, not its middle")
