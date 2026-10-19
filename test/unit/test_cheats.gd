extends GutTest
## All-weapons cheat: naming yourself "p4u1 " (trailing space) spawns your ship
## with every upgrade at its max, every system fully powered and every gun
## armed, again after every respawn.

const PlayerScene := preload("res://scenes/player.tscn")
const LobbyScene := preload("res://scenes/lobby.tscn")

var _saved_peer: MultiplayerPeer
var _saved_flag: bool


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	_saved_flag = Net.all_weapons


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer
	Net.all_weapons = _saved_flag


func _player() -> Area2D:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	var p: Area2D = PlayerScene.instantiate()
	p.position = Vector2(270, 800)
	game.get_node("Players").add_child(p)
	return p


## Everything bought and powered; guns (armed, and their levels, which only
## count while armed) unless `guns` is false.
func _assert_maxed(p: Area2D, guns := true) -> void:
	for s in Systems.ITEMS:
		if not guns and Systems.is_gun(s.id):
			continue
		if s.id == &"ship":
			assert_eq(p.level(s.id), 0, "spare ships are never given")
			continue
		if s.id == &"reactor":
			assert_gte(p.reactor(), Systems.max_level(s.id), "a reactor big enough")
		else:
			assert_eq(p.level(s.id), Systems.max_level(s.id), String(s.id))
		assert_false(p.can_upgrade(s.id), String(s.id) + " maxed")
	for s in Systems.systems():
		assert_eq(p.power_of(s.id), Systems.max_level(s.id), String(s.id) + " fully powered")
	assert_gte(p.power_spare(), 0)
	if not guns:
		return
	for g in Systems.guns():
		assert_true(p.is_armed(g.id), String(g.id) + " armed")


func test_lobby_name_turns_the_cheat_on_only_when_exact() -> void:
	var lobby: CanvasLayer = LobbyScene.instantiate()
	add_child_autofree(lobby)
	for name in ["p4u1", " p4u1 ", "p4u1  ", "P4U1 ", "paul "]:
		lobby.name_edit.text = name
		lobby._player_name()
		assert_false(Net.all_weapons, "'%s'" % name)
	lobby.name_edit.text = "p4u1 "
	assert_eq(lobby._player_name(), "p4u1", "shown without the space")
	assert_true(Net.all_weapons)


func test_cheat_spawns_with_every_upgrade_maxed() -> void:
	Net.all_weapons = true
	var p := _player()
	_assert_maxed(p)


func test_cheat_spawns_with_shields_up() -> void:
	Net.all_weapons = true
	var p := _player()
	assert_eq(p.shield, p.SHIELD_HITS)
	assert_eq(p.rear_shield, p.SHIELD_HITS)


func _respawned() -> Area2D:
	Net.all_weapons = true
	var p := _player()
	p.hp = 0
	p._respawn_timer = 0.01
	p._simulate(0.1)
	return p


func test_cheat_comes_back_after_respawn() -> void:
	var p := _respawned()
	assert_true(p.is_alive())
	_assert_maxed(p, false)


func test_cheat_guns_come_back_armed_after_respawn() -> void:
	var p := _respawned()
	for g in Systems.guns():
		assert_true(p.is_armed(g.id), String(g.id))
	_assert_maxed(p)


func test_no_cheat_no_upgrades() -> void:
	Net.all_weapons = false
	var p := _player()
	for s in Systems.ITEMS:
		assert_eq(p.level(s.id), Systems.start_level(s.id), String(s.id))
	for s in Systems.systems():
		assert_eq(p.power_of(s.id), Systems.START_POWER.get(s.id, 0), String(s.id))
	for g in Systems.guns():
		assert_eq(p.is_armed(g.id), g.id in Systems.START_ARMED, String(g.id))
