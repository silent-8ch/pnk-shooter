extends GutTest
## All-weapons cheat: naming yourself "p4u1 " (trailing space) spawns your ship
## with every upgrade at its tier II max, again after every respawn.

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


func _assert_maxed(p: Area2D) -> void:
	assert_eq(p.tier, 2)
	for s in PowerMeter.slots_for(2):
		if s.id == &"ship":
			assert_eq(p.level(s.id), 0, "spare ships are never given")
			continue
		assert_eq(p.level(s.id), PowerMeter.max_level(s.id, 2), String(s.id))
		assert_false(p.can_upgrade(s.id), String(s.id) + " maxed")


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
	assert_eq(p.shield, p.SHIELD_HITS)
	assert_eq(p.rear_shield, p.SHIELD_HITS)


func test_cheat_comes_back_after_respawn() -> void:
	Net.all_weapons = true
	var p := _player()
	p.hp = 0
	p._respawn_timer = 0.01
	p._simulate(0.1)
	assert_true(p.is_alive())
	_assert_maxed(p)


func test_no_cheat_no_upgrades() -> void:
	Net.all_weapons = false
	var p := _player()
	assert_eq(p.tier, 1)
	for s in PowerMeter.SLOTS:
		assert_eq(p.level(s.id), 0, String(s.id))
