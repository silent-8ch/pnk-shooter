extends GutTest
## Pickup: william frames reversed, idle star-palette cycle (no spin), drop on shoot-down,
## server-decided collection, collect animation holding the last frame.

const PickupScript := preload("res://scripts/pickup.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const WILLIAM := preload("res://assets/effects/william.tres")

var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _pickup() -> Area2D:
	var p: Area2D = PickupScript.new()
	add_child_autofree(p)
	return p


func _game() -> Node2D:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	return game


func test_frames_play_backwards_from_william_03() -> void:
	var f := PickupScript.play_frames()
	assert_eq(f.get_frame_count(&"default"), 4)
	for i in 4:
		assert_same(f.get_frame_texture(&"default", i), WILLIAM.get_frame_texture(&"default", 3 - i))
	assert_false(f.get_animation_loop(&"default"), "holds the last frame")


func test_idle_holds_first_frame_and_cycles_palette_without_spinning() -> void:
	var p := _pickup()
	var steps := {}
	for i in 30:
		p._process(1.0 / 60.0)
		steps[p.palette_step()] = true
		assert_same(p.sprite.sprite_frames, PickupScript.frames_for_step(p.palette_step()))
	assert_eq(p.sprite.frame, 0)
	assert_false(p.sprite.is_playing())
	assert_eq(p.rotation, 0.0, "no spin")
	var angle: float = p.sprite.rotation
	p._process(0.5)
	assert_eq(p.sprite.rotation, angle, "the art doesn't spin either")
	assert_gte(steps.size(), 4, "rapid palette cycle")


func test_star_palettes_cycle_every_slot_including_outline() -> void:
	var outline := {}
	for step in PickupScript.STAR_COLORS.size():
		var pal := PickupScript.star_palette(step)
		assert_eq(pal.size(), PickupScript.SLOTS)
		outline[pal[0]] = true
		var next := PickupScript.star_palette(step + 1)
		for k in range(0, pal.size() - 1):
			assert_eq(next[k], pal[k + 1], "colors march across slots")
	assert_eq(outline.size(), PickupScript.STAR_COLORS.size(), "slot 1 (main outline) cycles too")


func test_uses_the_painted_colors() -> void:
	# Every william frame is painted with color slots, and the cycle re-renders them.
	for i in 4:
		var svg := FileAccess.get_file_as_string("res://assets/effects/william_%02d.svg" % i)
		assert_true(svg.contains("data-slot=\"2\""), "william_%02d is painted" % i)
	var f := PickupScript.frames_for_step(0)
	var tex := f.get_frame_texture(&"default", 0)
	assert_ne(tex, WILLIAM.get_frame_texture(&"default", 3), "re-rendered, not the preview")
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var colored := false
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and c.s > 0.3:
				colored = true
				break
		if colored:
			break
	assert_true(colored, "has colored (not black/white) pixels")


func test_collect_frames_are_held_long_and_do_not_spin() -> void:
	assert_gte(1.0 / PickupScript.COLLECT_FPS, 0.2, "each frame on screen at least 0.2 s")
	var p := _pickup()
	p.collect()
	for f in 4:
		p.sprite.frame = f
		p._process(0.05)
	assert_eq(p.rotation, 0.0)


func test_each_collect_frame_is_fainter() -> void:
	var p := _pickup()
	p.collect()
	var last := 1.01
	for f in 4:
		p.sprite.frame = f
		p._process(0.0)
		assert_lt(p.modulate.a, last, "frame %d fainter" % f)
		last = p.modulate.a


func test_collect_plays_xp_sound_once() -> void:
	var p := _pickup()
	assert_is(p.sound.stream, AudioStreamRandomizer)
	var paths := []
	for i in p.sound.stream.streams_count:
		paths.append(p.sound.stream.get_stream(i).resource_path)
	assert_eq(paths, ["res://assets/sfx/xp.wav", "res://assets/sfx/xp_1.wav", "res://assets/sfx/xp_2.wav"])
	assert_false(p.sound.playing)
	p.collect()
	assert_true(p.sound.playing)


func test_palette_swap_keeps_collect_animation_going() -> void:
	var p := _pickup()
	p.collect()
	p.sprite.frame = 2
	p._age += 1.0 / PickupScript.CYCLE_RATE
	p._apply_color()
	assert_eq(p.sprite.frame, 2)
	assert_true(p.sprite.is_playing())


func test_uncollected_blinks_then_expires() -> void:
	var p := _pickup()
	p._process(PickupScript.LIFETIME - PickupScript.BLINK_TIME + 0.05)
	var seen_hidden := false
	for i in 40:
		p._process(0.025)
		if not p.visible:
			seen_hidden = true
	assert_true(seen_hidden, "blinks near the end")
	p._process(PickupScript.LIFETIME)
	assert_true(p.is_queued_for_deletion())


func test_collect_plays_to_last_frame_holds_then_fades() -> void:
	var p := _pickup()
	p.collect()
	assert_true(p.collected)
	assert_true(p.sprite.is_playing())
	await wait_seconds(4.0 / PickupScript.COLLECT_FPS + 0.15)
	assert_eq(p.sprite.frame, 3, "on the last frame")
	assert_false(p.sprite.is_playing(), "holds it")
	p._process(0.1)
	assert_eq(p.rotation, 0.0, "not spinning")
	p._process(PickupScript.HOLD_TIME + PickupScript.FADE_TIME)
	assert_true(p.is_queued_for_deletion())


func test_shot_down_enemy_drops_pickup_where_it_died() -> void:
	var game := _game()
	var e: Area2D = EnemyScene.instantiate()
	e.position = Vector2(210, 330)
	game.get_node("Enemies").add_child(e)
	e.take_damage(99)
	var pickups := game.get_node("Pickups")
	assert_eq(pickups.get_child_count(), 1)
	assert_eq(pickups.get_child(0).position, Vector2(210, 330))


func test_rammed_enemy_drops_nothing() -> void:
	var game := _game()
	var e: Area2D = EnemyScene.instantiate()
	game.get_node("Enemies").add_child(e)
	e.ram()
	assert_eq(game.get_node("Pickups").get_child_count(), 0)


func test_player_touching_it_collects_once() -> void:
	var game := _game()
	game.spawn_pickup(Vector2(100, 100), "Pickup1")
	var p: Area2D = game.get_node("Pickups/Pickup1")
	var player: Area2D = PlayerScene.instantiate()
	game.get_node("Players").add_child(player)
	p._on_area_entered(player)
	assert_true(p.collected)
	p._on_area_entered(player)  # second touch is ignored
	assert_true(p.collected)


func test_dead_player_or_non_player_cannot_collect() -> void:
	var game := _game()
	game.spawn_pickup(Vector2(100, 100), "Pickup1")
	var p: Area2D = game.get_node("Pickups/Pickup1")
	var player: Area2D = PlayerScene.instantiate()
	game.get_node("Players").add_child(player)
	player.hp = 0
	p._on_area_entered(player)
	var e: Area2D = EnemyScene.instantiate()
	game.get_node("Enemies").add_child(e)
	p._on_area_entered(e)
	assert_false(p.collected)


func test_only_players_are_detected() -> void:
	var p := _pickup()
	assert_eq(p.collision_mask, 1, "player layer")
	assert_eq(p.collision_layer, 0, "nothing else reacts to it")


func test_stop_clears_pickups() -> void:
	var game := _game()
	game.spawn_pickup(Vector2(100, 100), "Pickup1")
	game.stop()
	assert_false(game.has_node("Pickups/Pickup1"))



func _named(n: String) -> Area2D:
	var p: Area2D = PickupScript.new()
	p.name = n
	add_child_autofree(p)
	return p


func test_lands_at_a_random_angle_the_same_on_every_peer() -> void:
	var angles := {}
	for i in 12:
		angles[snappedf(_named("Pickup%d" % i).sprite.rotation, 0.001)] = true
	assert_gt(angles.size(), 8, "angles vary")
	var first := _named("Pickup77")
	var angle: float = first.sprite.rotation
	remove_child(first)
	first.free()
	assert_eq(_named("Pickup77").sprite.rotation, angle, "same from the same name")


func test_each_collect_frame_gets_its_own_angle() -> void:
	var p := _named("Pickup5")
	p.collect()
	var distinct := {}
	for f in 4:
		p.sprite.frame = f
		p._process(0.0)
		distinct[snappedf(p.sprite.rotation, 0.001)] = true
	assert_eq(distinct.size(), 4, "a new angle each frame")


func test_pulses_and_wanders_around_its_spot() -> void:
	var p := _named("Pickup3")
	p.position = Vector2(200, 300)
	var sizes := {}
	var far := 0.0
	for i in 120:
		p._process(1.0 / 60.0)
		sizes[snappedf(p.sprite.scale.x, 0.0001)] = true
		far = maxf(far, p.sprite.position.length())
		assert_lte(absf(p.sprite.position.x), PickupScript.DRIFT.x + 0.001)
		assert_lte(absf(p.sprite.position.y), PickupScript.DRIFT.y + 0.001)
	var base := PickupScript.DISPLAY_SCALE / PickupScript.RENDER_SCALE
	assert_gt(sizes.size(), 10, "pulses")
	for sz in sizes:
		assert_between(sz, base * (1.0 - PickupScript.PULSE) - 0.0001, base * (1.0 + PickupScript.PULSE) + 0.0001)
	assert_gt(far, 1.0, "wanders")
	assert_eq(p.position, Vector2(200, 300), "its reach stays put")



func test_last_frame_shrinks_away_as_it_is_shown() -> void:
	var p := _named("Pickup9")
	p.collect()
	p.sprite.stop()
	p.sprite.frame = 3
	var base := PickupScript.DISPLAY_SCALE / PickupScript.RENDER_SCALE * (1.0 + PickupScript.PULSE)
	var last := INF
	var t := 0.0
	while t < PickupScript.HOLD_TIME + PickupScript.FADE_TIME - 0.05:
		var before: float = p.shrink()
		p._process(0.05)
		t += 0.05
		assert_lt(p.shrink(), last, "smaller every step")
		last = p.shrink()
		assert_lte(p.sprite.scale.x, base * before + 0.0001, "drawn at its shrunken size")
	assert_lt(last, 0.15, "almost gone by the end")
