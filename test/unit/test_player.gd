extends GutTest
## Player ship visuals: ship + palette texture, no tint, dead-state fade.

const PlayerScene := preload("res://scenes/player.tscn")

var player: Area2D
var _saved_peer: MultiplayerPeer


func _spawn(ship: int, palette: int) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.ship = ship
	p.palette = palette
	p.color = Color("ff7ad9")
	add_child_autofree(p)
	return p


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	player = _spawn(0, 0)


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func test_body_uses_ship_and_palette_texture() -> void:
	var body := player.get_node("Body")
	assert_is(body, Sprite2D)
	assert_same(body.texture, Ships.get_lit_texture(0, 0))
	assert_same(body.texture.diffuse_texture, Ships.get_texture(0, 0))


func test_ship_and_palette_pick_texture() -> void:
	var p := _spawn(1, 2)
	assert_same(p.get_node("Body").texture.diffuse_texture, Ships.get_texture(1, 2))
	assert_not_same(p.get_node("Body").texture.diffuse_texture, Ships.get_texture(1, 0))


func test_invalid_indices_fall_back_to_first() -> void:
	var p := _spawn(99, 99)
	assert_same(p.get_node("Body").texture.diffuse_texture, Ships.get_texture(0, 0))


func test_every_ship_renders_about_44px_tall() -> void:
	for i in Ships.count():
		var body: Sprite2D = _spawn(i, 0).get_node("Body")
		var rendered: Vector2 = body.texture.get_size() * body.scale
		assert_almost_eq(rendered.y, Ships.SHIP_HEIGHT, 0.5, "ship %d height" % i)


func test_player_color_no_longer_tints_ship() -> void:
	var body: Sprite2D = player.get_node("Body")
	assert_eq(body.modulate, Color.WHITE)


func test_dead_player_fades() -> void:
	var body: Sprite2D = player.get_node("Body")
	player.hp = 0
	player._process(0.0)
	assert_almost_eq(body.modulate.a, 0.25, 0.001)
	player.hp = 1
	player._process(0.0)
	assert_eq(body.modulate.a, 1.0)


# --- Firing (server side) ---------------------------------------------------

func _armed_player() -> Area2D:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	var p: Area2D = PlayerScene.instantiate()
	p.position = Vector2(270, 800)
	game.get_node("Players").add_child(p)
	return p


func _bullets(p: Area2D) -> int:
	return p.get_parent().get_parent().get_node("Bullets").get_child_count()


func test_no_shot_without_press() -> void:
	var p := _armed_player()
	for i in 30:
		p._simulate(0.1)
	assert_eq(_bullets(p), 0, "no autofire")


func test_one_press_one_shot() -> void:
	var p := _armed_player()
	p._fire_requested = true
	p._simulate(0.016)
	p._simulate(1.0)
	assert_eq(_bullets(p), 1)


func test_press_during_cooldown_is_dropped() -> void:
	var p := _armed_player()
	p._fire_requested = true
	p._simulate(0.016)
	p._fire_requested = true
	p._simulate(0.016)
	assert_eq(_bullets(p), 1, "too soon")
	p._simulate(p.FIRE_COOLDOWN)
	assert_eq(_bullets(p), 1, "dropped, not queued")
	p._fire_requested = true
	p._simulate(0.016)
	assert_eq(_bullets(p), 2)


func test_dead_player_ignores_press() -> void:
	var p := _armed_player()
	p.hp = 0
	p._respawn_timer = 10.0
	p._fire_requested = true
	p._simulate(0.016)
	p.hp = p.MAX_HP
	p._simulate(0.016)
	assert_eq(_bullets(p), 0)


func test_fire_rate_is_slow() -> void:
	assert_gte(preload("res://scripts/player.gd").FIRE_COOLDOWN, 0.4)
