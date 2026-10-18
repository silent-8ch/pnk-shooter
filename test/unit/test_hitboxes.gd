extends GutTest
## Hitboxes follow the ship art: outlines traced from each SVG's alpha
## (Ships.hit_polygons) replace the old one-size circle on enemies, the boss
## and players.

const EnemyScene := preload("res://scenes/enemy.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const PlayerScene := preload("res://scenes/player.tscn")


func _enemy(type: int) -> Area2D:
	var e: Area2D = EnemyScene.instantiate()
	e.type = type
	e.position = Vector2(270, 300)
	add_child_autofree(e)
	return e


func _polys(area: Node) -> Array:
	var out := []
	for c in area.get_children():
		if c is CollisionPolygon2D:
			out.append(c.polygon)
	return out


func _inside(polys: Array, p: Vector2) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _art(ship: int) -> Image:
	var img := Image.new()
	img.load_svg_from_string(Ships.get_svg(ship), Ships.RENDER_SCALE)
	return img


## A pixel whose whole 7x7 neighborhood is solid (`opaque`) or clear.
func _pixel(img: Image, opaque: bool, inside_box := Rect2i()) -> Vector2i:
	var box := inside_box if inside_box.has_area() else Rect2i(Vector2i.ZERO, img.get_size())
	for y in range(box.position.y + 3, box.end.y - 3):
		for x in range(box.position.x + 3, box.end.x - 3):
			var ok := true
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					if (img.get_pixel(x + dx, y + dy).a > 0.5) != opaque:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _local(img: Image, px: Vector2i, body: Sprite2D) -> Vector2:
	var v := (Vector2(px) + Vector2(0.5, 0.5) - Vector2(img.get_size()) / 2.0) * body.scale
	return Vector2(v.x, -v.y) if body.flip_v else v


func test_every_ship_has_an_outline() -> void:
	for i in Ships.count():
		assert_gt(Ships.hit_polygons(i).size(), 0, "ship %d" % i)
	assert_same(Ships.hit_polygons(0), Ships.hit_polygons(0), "cached")


func test_enemies_and_boss_use_the_outline_not_a_circle() -> void:
	for type in [EnemyScript.WEAVER, EnemyScript.TANK, EnemyScript.BOSS]:
		var e := _enemy(type)
		assert_false(e.has_node("Shape"), "circle gone")
		assert_gt(_polys(e).size(), 0)


func test_boss_hits_land_on_the_hull_and_miss_the_gaps() -> void:
	var e := _enemy(EnemyScript.BOSS)
	var body: Sprite2D = e.get_node("Body")
	var img := _art(EnemyScript.TYPES[EnemyScript.BOSS].ship)
	var solid := _pixel(img, true)
	assert_ne(solid, Vector2i(-1, -1))
	assert_true(_inside(_polys(e), _local(img, solid, body)), "on the hull")
	# a clear pixel inside the art's bounding box: a gap the old shape covered
	var used := img.get_used_rect()
	var gap := _pixel(img, false, used)
	if gap != Vector2i(-1, -1):
		assert_false(_inside(_polys(e), _local(img, gap, body)), "through the gap")
	var far := Vector2(used.end.x + 4, used.end.y + 4) * body.scale.x  # well outside the art
	assert_false(_inside(_polys(e), far))


func test_outline_scales_with_the_boss() -> void:
	var small := _enemy(EnemyScript.WEAVER)
	var big := _enemy(EnemyScript.BOSS)
	var size := func(a: Area2D) -> float:
		var r := Rect2()
		for poly in _polys(a):
			for v in poly:
				r = r.expand(v)
		return r.size.y
	assert_gt(size.call(big), size.call(small) * 2.5)
	assert_almost_eq(size.call(big), EnemyScript.TYPES[EnemyScript.BOSS].height, EnemyScript.TYPES[EnemyScript.BOSS].height * 0.1)


func test_enemy_outline_is_flipped_like_its_sprite() -> void:
	var e := _enemy(EnemyScript.DIVER)
	var body: Sprite2D = e.get_node("Body")
	var img := _art(EnemyScript.TYPES[EnemyScript.DIVER].ship)
	var solid := _pixel(img, true)
	assert_true(_inside(_polys(e), _local(img, solid, body)))


func test_players_use_their_ship_outline() -> void:
	var p: Area2D = PlayerScene.instantiate()
	p.ship = 2
	add_child_autofree(p)
	assert_false(p.has_node("Shape"))
	var img := _art(2)
	var solid := _pixel(img, true)
	assert_true(_inside(_polys(p), _local(img, solid, p.get_node("Body"))))
