extends GutTest
## Friendly beacon: PILOTING 2 powered. A ship showing it is skipped
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


## PILOTING 2 bought and powered on our ship (the one we fly), so the beacon is on.
func _beacon() -> void:
	me.levels[&"reactor"] = 4
	me.levels[&"piloting"] = 2
	assert_true(me.add_power(&"piloting"))
	assert_true(me.add_power(&"piloting"))
	me._simulate(0.016)


func test_beacon_is_piloting_2() -> void:
	assert_eq(Systems.max_level(&"piloting"), 2)
	me.levels[&"reactor"] = 4
	me.levels[&"piloting"] = 2
	me.add_power(&"piloting")
	me._simulate(0.016)
	assert_false(me.beacon, "PILOTING 1 is only the autopilot")
	me.add_power(&"piloting")
	me._simulate(0.016)
	assert_true(me.beacon)


func test_powering_it_turns_the_beacon_on_and_it_replicates() -> void:
	assert_false(me.beacon)
	_beacon()
	assert_true(me.beacon)
	var cfg: SceneReplicationConfig = me.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:beacon")))


func test_beacon_goes_off_with_its_power() -> void:
	_beacon()
	me.drain_power(&"piloting")
	me._simulate(0.016)
	assert_false(me.beacon)


func test_beacon_is_lost_with_the_ship() -> void:
	_beacon()
	me._lose_upgrades()
	me._simulate(0.016)
	assert_false(me.beacon)


func test_autocannon_never_targets_a_teammate() -> void:
	assert_null(me.auto_target(), "point defence: enemy shots only")
	mate.beacon = true
	assert_null(me.auto_target())


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


func test_missiles_and_rounds_fly_through_a_beacon() -> void:
	_beacon()
	var hp: float = me.hp
	for kind in [BulletScript.MISSILE, BulletScript.VULCAN]:
		game.fire_bullet(me.position, Color.WHITE, Vector2.UP, kind)
		var b: Area2D = game.get_node("Bullets").get_children().back()
		b.shooter = 7  # the mate's
		me._on_area_entered(b)
		assert_false(b.is_queued_for_deletion(), "kind %d passes through" % kind)
	assert_eq(me.hp, hp)


func test_lasers_still_hit_a_beacon() -> void:
	_beacon()
	game.fire_bullet(me.position, Color.WHITE, Vector2.UP, BulletScript.LASER)
	var b: Area2D = game.get_node("Bullets").get_children().back()
	b.shooter = 7  # the mate's
	me._on_area_entered(b)
	assert_true(b.is_queued_for_deletion(), "only the auto-aimed weapons skip it")
