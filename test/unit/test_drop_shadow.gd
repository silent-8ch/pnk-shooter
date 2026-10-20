extends GutTest
## DropShadow: one global light, every shadow falls the same way on screen.

const EnemyScene := preload("res://scenes/enemy.tscn")
const ObstacleScript := preload("res://scripts/obstacle.gd")


func _sprite() -> Sprite2D:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var s := Sprite2D.new()
	s.texture = Ships.get_enemy_texture(0)
	holder.add_child(s)
	return s


func _screen_offset(shadow: DropShadow) -> Vector2:
	return shadow.global_position - shadow.get_parent().global_position


func test_falls_away_from_the_light() -> void:
	var s := _sprite()
	var sh := DropShadow.attach(s)
	assert_almost_eq(_screen_offset(sh), DropShadow.LIGHT_DIR * DropShadow.OFFSET, Vector2(0.01, 0.01))
	assert_gt(DropShadow.LIGHT_DIR.x, 0.0, "light from the left")
	assert_gt(DropShadow.LIGHT_DIR.y, 0.0, "light from the top")


func test_offset_holds_however_the_sprite_turns_scales_and_flips() -> void:
	var s := _sprite()
	var sh := DropShadow.attach(s, DropShadow.OBSTACLE_HEIGHT)
	var want := DropShadow.LIGHT_DIR * DropShadow.OFFSET * DropShadow.OBSTACLE_HEIGHT
	for setup in [[0.0, Vector2.ONE], [1.3, Vector2(0.4, 0.4)], [-2.5, Vector2(2.0, 1.5)], [PI, Vector2(1, -1)]]:
		s.rotation = setup[0]
		s.scale = setup[1]
		s.get_parent().rotation = 0.7
		s.flip_v = not s.flip_v
		sh._process(0.0)
		assert_almost_eq(_screen_offset(sh), want, Vector2(0.01, 0.01), str(setup))
		assert_eq(sh.flip_v, s.flip_v, "follows the flip")


func test_a_flat_unlit_copy_behind_its_sprite() -> void:
	var s := _sprite()
	var sh := DropShadow.attach(s)
	assert_true(sh.show_behind_parent)
	assert_eq(sh.light_mask, 0, "no light touches it")
	assert_eq(sh.modulate, DropShadow.COLOR)
	assert_eq(sh.modulate.r + sh.modulate.g + sh.modulate.b, 0.0, "dark")
	s.texture = Ships.get_enemy_texture(1)
	sh._process(0.0)
	assert_same(sh.texture, s.texture, "follows a texture change")


func test_ships_enemies_and_obstacles_cast_shadows() -> void:
	var e: Node2D = EnemyScene.instantiate()
	e.set_physics_process(false)
	add_child_autofree(e)
	assert_not_null(e.body.get_node_or_null("Shadow"), "enemy")
	var o: Area2D = ObstacleScript.new()
	o.piece_id = "asteroid_m"
	add_child_autofree(o)
	var sprites := o.find_children("*", "Sprite2D", false, false)
	assert_eq(sprites.size(), 1)
	var sh: DropShadow = sprites[0].get_node("Shadow")
	assert_eq(sh.height, DropShadow.OBSTACLE_HEIGHT, "rocks sit lower than ships")
	var player: Node2D = load("res://scenes/player.tscn").instantiate()
	add_child_autofree(player)
	assert_not_null(player.body.get_node_or_null("Shadow"), "player")
