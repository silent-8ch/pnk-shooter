extends GutTest
## Party health bars in the HUD (every player's health as a green bar, yours
## first) and granular health (HIT_HP per hit out of MAX_HP).

const PlayerScript := preload("res://scripts/player.gd")
const PartyBars := preload("res://scripts/party_bars.gd")

var game: Node2D
var player: Area2D
var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	player = _add(1, Vector2(270, 700))


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _add(id: int, pos: Vector2) -> Area2D:
	var p: Area2D = preload("res://scenes/player.tscn").instantiate()
	p.name = str(id)
	p.peer_id = id
	p.position = pos
	game.get_node("Players").add_child(p)
	return p


func test_hud_has_party_bars_not_an_hp_number() -> void:
	assert_not_null(game.get_node_or_null("HUD/PartyBars"))
	assert_null(game.get_node_or_null("HUD/HPLabel"))


func test_one_row_per_player_local_first() -> void:
	var other := _add(2, Vector2(100, 700))
	game.get_node("Players").move_child(other, 0)
	var rows: Array = game.get_node("HUD/PartyBars").rows()
	assert_eq(rows, [player, other])


func test_bar_shows_health_fraction() -> void:
	assert_eq(PartyBars.fill_of(player), 1.0)
	player.take_damage(1)
	assert_almost_eq(PartyBars.fill_of(player), 1.0 - PlayerScript.HIT_HP / PlayerScript.MAX_HP, 0.001)
	player.take_damage(99)
	assert_eq(PartyBars.fill_of(player), 0.0)


func test_bar_uses_the_replicated_max_for_armor() -> void:
	var other := _add(2, Vector2(100, 700))
	other.max_health = PlayerScript.MAX_HP + PlayerScript.HIT_HP
	other.hp = PlayerScript.MAX_HP
	assert_lt(PartyBars.fill_of(other), 1.0)
	var cfg: SceneReplicationConfig = player.get_node("Sync").replication_config
	assert_true(cfg.has_property(NodePath(".:max_health")))
	assert_true(cfg.has_property(NodePath(".:hp")))


func test_owner_publishes_its_max_health() -> void:
	player.levels[&"armor"] = 1
	player._physics_process(0.01)
	assert_eq(player.max_health, player.max_hp())


func test_health_is_granular() -> void:
	player.take_damage(0.25)
	assert_almost_eq(player.hp, PlayerScript.MAX_HP - 0.25 * PlayerScript.HIT_HP, 0.001)
	assert_true(player.is_alive())


func test_three_hits_still_kill_from_full() -> void:
	player.take_damage(1)
	player.take_damage(1)
	assert_true(player.is_alive())
	player.take_damage(1)
	assert_false(player.is_alive())
	assert_eq(player.hp, 0.0)


func test_shield_still_soaks_whole_hits() -> void:
	player.shield = 1
	player.take_damage(0.5)
	assert_eq(player.hp, PlayerScript.MAX_HP, "fraction banked against the shield")
	player.take_damage(0.5)
	assert_eq(player.shield, 0)
	assert_eq(player.hp, PlayerScript.MAX_HP)


func test_draws_without_errors() -> void:
	_add(2, Vector2(100, 700)).hp = 0
	var bars: Control = game.get_node("HUD/PartyBars")
	bars.queue_redraw()
	await wait_frames(2)
	assert_eq(bars.rows().size(), 2)
