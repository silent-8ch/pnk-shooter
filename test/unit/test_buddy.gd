extends GutTest
## AI buddy: the host can fly with an AI wingman. The host simulates it, its
## shots count as its own (friendly fire), it stays beside you, hunts enemies
## above, holds fire when a player is in the way, dodges danger, and leaves
## pickups, kits and pods for the players.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")

var game: Node2D
var me: Area2D
var buddy: Area2D
var _saved_peer: MultiplayerPeer
var _saved_buddy: bool


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	_saved_buddy = Net.ai_buddy
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	game = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	game._add_player(1, "Me", Ships.selected, 0)  # the buddy picks a ship other than the selected one
	game._add_buddy()
	me = game.get_node("Players/1")
	buddy = game.get_node("Players/" + str(game.BUDDY_ID))
	me.position = Vector2(270, 800)
	buddy.position = Vector2(350, 800)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer
	Net.ai_buddy = _saved_buddy
	game.active = false


func _enemy(pos: Vector2) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.position = pos
	game.get_node("Enemies").add_child(e)
	return e


func _think_and_fly(frames: int) -> void:
	for i in frames:
		buddy._think()
		buddy._simulate(1.0 / 60.0)


func _bullets() -> Array:
	return game.get_node("Bullets").get_children()


func test_buddy_is_an_ai_player_flown_by_the_host() -> void:
	assert_true(buddy.ai)
	assert_eq(buddy.player_name, "Buddy")
	assert_true(buddy.is_local(), "the host flies it")
	assert_eq(buddy.get_multiplayer_authority(), 1)
	assert_eq(game.local_player(), me, "it isn't the host's own ship")
	assert_true(game.controls(game.BUDDY_ID))
	assert_ne(buddy.ship, me.ship, "a different ship")


func test_game_start_adds_buddy_only_when_toggled() -> void:
	var g2: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(g2)
	Net.ai_buddy = true
	g2.start()
	assert_not_null(g2.get_node_or_null("Players/" + str(g2.BUDDY_ID)))
	g2.stop()
	var g3: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(g3)
	Net.ai_buddy = false
	g3.start()
	assert_null(g3.get_node_or_null("Players/" + str(g3.BUDDY_ID)))
	g3.stop()


func test_flies_beside_its_leader() -> void:
	buddy.position = Vector2(270, 500)
	_think_and_fly(120)
	assert_almost_eq(absf(buddy.position.x - me.position.x), PlayerScript.AI_WINGMAN_GAP, 12.0)
	assert_almost_eq(buddy.position.y, me.position.y, 12.0)


func test_hunts_and_shoots_an_enemy_above() -> void:
	var e := _enemy(Vector2(390, 300))
	e.set_physics_process(false)
	_think_and_fly(90)
	assert_almost_eq(buddy.position.x, 390.0, PlayerScript.AI_AIM)
	assert_gt(_bullets().size(), 0, "fired")
	var b: Area2D = _bullets()[0]
	assert_eq(b.shooter, game.BUDDY_ID, "its own shots")
	assert_true(b.is_mine(), "the host reports its hits")


func test_holds_fire_with_a_player_in_the_way() -> void:
	var e := _enemy(Vector2(350, 300))
	e.set_physics_process(false)
	me.position = Vector2(352, 600)
	buddy._think()
	assert_true(buddy.ai_friend_in_line(game))
	assert_false(buddy._fire_requested)


func test_dodges_an_enemy_coming_at_it() -> void:
	var e := _enemy(buddy.position + Vector2(10, -30))
	e.set_physics_process(false)
	var push: Vector2 = buddy.ai_avoidance(game)
	assert_gt(push.y, 0.0, "pushed away from it (down)")
	assert_gt(push.length(), 0.1)


func test_dodges_obstacles() -> void:
	game._obstacle_count += 1
	game.spawn_obstacle({"name": "Obstacle1", "piece": "asteroid_l", "x": buddy.position.x, "y": buddy.position.y - 90,
		"count": 1, "dir": 1})
	assert_gt(buddy.ai_avoidance(game).length(), 0.1)


func test_its_shots_hurt_players_but_not_itself() -> void:
	var b: Area2D = BulletScene.instantiate()
	b.shooter = game.BUDDY_ID
	game.get_node("Bullets").add_child(b)
	buddy._on_area_entered(b)
	assert_eq(buddy.hp, PlayerScript.MAX_HP, "own shots pass through")
	me._on_area_entered(b)
	assert_lt(me.hp, PlayerScript.MAX_HP, "friendly fire")


func test_only_the_flier_may_fire_as_the_buddy() -> void:
	game.fire_bullet(Vector2(10, 10), Color.RED, Vector2.UP, 0, game.BUDDY_ID)
	assert_eq(_bullets()[0].shooter, game.BUDDY_ID, "host fires for its buddy")
	game.fire_bullet(Vector2(10, 10), Color.RED, Vector2.UP, 0, 12345)
	assert_eq(_bullets()[1].shooter, 1, "not someone else's ship")


func test_leaves_pickups_and_pods_for_players() -> void:
	game.spawn_pickup(buddy.position, "Pickup1")
	var pickup: Area2D = game.get_node("Pickups/Pickup1")
	pickup._on_area_entered(buddy)
	assert_false(pickup.collected)
	assert_eq(me.exp_total, 0)


func test_drops_no_pod_and_respawns() -> void:
	buddy.take_damage(99)
	assert_false(buddy.is_alive())
	assert_eq(game.get_node("Pods").get_child_count(), 0)
	buddy._simulate(PlayerScript.RESPAWN_TIME + 0.1)
	assert_true(buddy.is_alive())


func test_late_joiner_gets_the_buddy_with_its_owner() -> void:
	assert_true(buddy.spawn_data.get("ai", false))
	assert_eq(buddy.spawn_data.get("owner"), 1)


func test_lobby_toggle_sets_the_option() -> void:
	var lobby: CanvasLayer = load("res://scenes/lobby.tscn").instantiate()
	add_child_autofree(lobby)
	lobby.buddy_toggle.button_pressed = true
	assert_true(Net.ai_buddy)
	lobby.buddy_toggle.button_pressed = false
	assert_false(Net.ai_buddy)
