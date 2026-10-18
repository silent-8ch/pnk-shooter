extends GutTest
## Friendly beacon: a BEACON upgrade in the meter. A ship showing it is skipped
## by other players' autocannons and missiles; without it, they can target you
## (friendly fire is on).

const BulletScript := preload("res://scripts/bullet.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var game: Node2D
var me: Area2D
var mate: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	me = _ship(1, Vector2(270, 700))
	mate = _ship(7, Vector2(330, 700))


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _ship(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func _missile_from(shooter: int, pos: Vector2) -> Area2D:
	game.fire_bullet(pos, Color.RED, Vector2.UP, BulletScript.MISSILE)
	var b: Area2D = game.get_node("Bullets").get_children().back()
	b.shooter = shooter
	return b


func test_beacon_is_an_upgrade_in_both_tiers() -> void:
	assert_eq(PowerMeter.max_level(&"beacon", 1), 1)
	assert_eq(PowerMeter.max_level(&"beacon", 2), 1)
	assert_gte(PowerMeter.slot_index(&"beacon", 1), 0)


func test_buying_it_turns_the_beacon_on_and_it_replicates() -> void:
	assert_false(mate.beacon)
	mate.levels[&"beacon"] = 1
	mate._simulate(0.016)
	assert_true(mate.beacon)
	var cfg: SceneReplicationConfig = mate.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:beacon")))


func test_beacon_is_lost_with_the_ship() -> void:
	mate.levels[&"beacon"] = 1
	mate._simulate(0.016)
	mate._lose_upgrades()
	mate._simulate(0.016)
	assert_false(mate.beacon)


func test_autocannon_targets_a_teammate_without_a_beacon() -> void:
	assert_eq(me.auto_target(), mate)


func test_autocannon_skips_a_teammate_with_a_beacon() -> void:
	mate.beacon = true
	assert_null(me.auto_target())


func test_autocannon_still_hits_enemies_near_a_beacon() -> void:
	mate.beacon = true
	var e: Area2D = preload("res://scenes/enemy.tscn").instantiate()
	e.position = Vector2(270, 620)
	game.get_node("Enemies").add_child(e)
	assert_eq(me.auto_target(), e)


func test_missile_seeks_a_teammate_without_a_beacon_but_never_its_shooter() -> void:
	var m := _missile_from(1, Vector2(270, 650))
	assert_eq(m.seek_target(), mate, "the nearest ship that isn't ours")
	var own := _missile_from(7, Vector2(330, 650))
	assert_eq(own.seek_target(), me)


func test_missile_skips_a_teammate_with_a_beacon() -> void:
	mate.beacon = true
	var m := _missile_from(1, Vector2(330, 650))
	assert_null(m.seek_target())


func test_missile_skips_dead_ships() -> void:
	mate.hp = 0
	var m := _missile_from(1, Vector2(330, 650))
	assert_null(m.seek_target())
