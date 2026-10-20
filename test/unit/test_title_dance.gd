extends GutTest
## The title screen: "Paul and Krystal Hlusko's Shooter", with ships 01 and
## 02 dancing behind it: circling, swooping together, a kiss with hearts, an
## embrace, drifting apart, round and round.

const MainScene := preload("res://scenes/main.tscn")


func test_title_reads_paul_and_krystals() -> void:
	var main: Node = MainScene.instantiate()
	add_child_autofree(main)
	assert_eq(main.main_menu.get_node("Margin/VBox/Title").text, "Paul and Krystal Hlusko's Shooter")
	assert_true(main.main_menu.has_node("TitleDance"))
	var stars: Node = main.main_menu.get_node("Starfield")
	assert_lt(stars.get_index(), main.main_menu.get_node("TitleDance").get_index(), "stars behind the dancers")
	assert_gt(stars.get_index(), main.main_menu.get_node("Background").get_index(), "in front of the backdrop")
	Net.stop_browsing()


func test_they_circle_wide_then_meet_for_a_kiss() -> void:
	var circling := TitleDance.pose_at(1.0)
	assert_almost_eq((circling.a - circling.b).length(), TitleDance.WIDE * 2.0, 0.5)
	var kiss := TitleDance.pose_at((TitleDance.SWOOP_END + TitleDance.KISS_END) / 2.0)
	assert_eq(kiss.kiss, 1.0)
	assert_almost_eq((kiss.a - kiss.b).length(), TitleDance.KISS * 2.0, 0.5, "nose to nose")
	var face_a := Vector2.UP.rotated(kiss.a_rot)
	assert_gt(face_a.dot((kiss.b - kiss.a).normalized()), 0.95, "facing each other")


func test_they_embrace_then_drift_apart_and_loop() -> void:
	var hold := TitleDance.pose_at((TitleDance.KISS_END + TitleDance.EMBRACE_END) / 2.0 + 0.5)
	assert_eq(hold.embrace, 1.0)
	assert_lt((hold.a - hold.b).length(), TitleDance.CLOSE * 2.0 + 1.0)
	var end := TitleDance.pose_at(TitleDance.LOOP - 0.001)
	var start := TitleDance.pose_at(TitleDance.LOOP)
	assert_almost_eq(end.a.distance_to(start.a), 0.0, 1.0, "the loop joins up")


func test_the_dance_is_smooth() -> void:
	var t := 0.0
	var last: Dictionary = TitleDance.pose_at(0.0)
	while t < TitleDance.LOOP * 2.0:
		t += 1.0 / 60.0
		var pose := TitleDance.pose_at(t)
		assert_lt(pose.a.distance_to(last.a), 12.0, "no jumps at %.2f" % t)
		last = pose



func test_the_dancers_have_thrusters() -> void:
	var dance := TitleDance.new()
	add_child_autofree(dance)
	var jets := dance.get_children().filter(func(n): return n is Sprite2D and n.has_node("Thrusters"))
	assert_eq(jets.size(), 2)


func test_the_dancers_are_lit_like_the_game() -> void:
	var dance := TitleDance.new()
	add_child_autofree(dance)
	var shade: PointLight2D = dance.get_node("ShipShade")
	assert_eq(shade.blend_mode, Light2D.BLEND_MODE_SUB)
	assert_almost_eq(shade.energy, Sun.SHADE_ENERGY, 0.001, "as spooky as the game")
	var sun: PointLight2D = dance.get_node("Sun")
	assert_true(sun.shadow_enabled, "they shadow each other")
	assert_lt(sun.position.x, 0.0, "off the top-left corner")
	assert_lt(sun.position.y, 0.0)
	var screen := dance.get_viewport_rect()
	for light in [shade, sun]:
		var half: Vector2 = light.texture.get_size() * light.texture_scale / 2.0
		assert_true(Rect2(light.position - half, half * 2.0).encloses(screen), light.name + " covers the screen")
	var ships := dance.find_children("*", "Sprite2D", false, false)
	assert_eq(ships.size(), 2)
	for s in ships:
		assert_is(s.texture, CanvasTexture, "normal-mapped")
		assert_eq(s.light_mask, Ships.LIGHT_MASK)
		assert_gt(s.find_children("*", "LightOccluder2D", false, false).size(), 0, "blocks the light")

