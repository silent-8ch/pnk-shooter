extends GutTest
## Player ship visuals: ship + palette texture, no tint, dead-state fade.

const PlayerScene := preload("res://scenes/player.tscn")

var player: Area2D


func _spawn(ship: int, palette: int) -> Area2D:
	var p: Area2D = PlayerScene.instantiate()
	p.ship = ship
	p.palette = palette
	p.color = Color("ff7ad9")
	add_child_autofree(p)
	return p


func before_each() -> void:
	player = _spawn(0, 0)


func test_body_uses_ship_and_palette_texture() -> void:
	var body := player.get_node("Body")
	assert_is(body, Sprite2D)
	assert_same(body.texture, Ships.get_texture(0, 0))


func test_ship_and_palette_pick_texture() -> void:
	var p := _spawn(1, 2)
	assert_same(p.get_node("Body").texture, Ships.get_texture(1, 2))
	assert_not_same(p.get_node("Body").texture, Ships.get_texture(1, 0))


func test_invalid_indices_fall_back_to_first() -> void:
	var p := _spawn(99, 99)
	assert_same(p.get_node("Body").texture, Ships.get_texture(0, 0))


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
