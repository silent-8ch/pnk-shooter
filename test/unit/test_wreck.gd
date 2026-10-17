extends GutTest
## Enemy wreck effect: seeded variety, veer + depth scaling, explosion, cleanup.

const WreckScript := preload("res://scripts/wreck.gd")


func _wreck(fx_seed: int, parts: Array = []) -> Node2D:
	var w: Node2D = WreckScript.new()
	var tex := Ships.get_enemy_texture(0)
	w.setup(tex, Vector2.ONE, fx_seed, parts)
	add_child_autofree(w)
	return w


func _look(w: Node2D) -> Array:
	return [w.velocity, w.spin, w.end_scale, w.spark_amount, w.spark_speed,
		w.spark_ramp, w.flash_radius, w.rings.size(), w.pops.size(), w.smoke_shade]


func test_same_seed_same_look() -> void:
	assert_eq(_look(_wreck(42)), _look(_wreck(42)))


func test_different_seeds_look_different() -> void:
	var looks := {}
	for s in 20:
		looks[str(_look(_wreck(s)))] = true
	assert_eq(looks.size(), 20)


func test_rolls_within_ranges() -> void:
	for s in 50:
		var w := _wreck(s)
		assert_almost_eq(w.velocity.length(), WreckScript.VEER_SPEED, WreckScript.FALL_SPEED + 0.01)
		assert_between(absf(w.spin), WreckScript.SPIN_MIN, WreckScript.SPIN_MAX)
		var grows: bool = w.end_scale >= WreckScript.GROW_RANGE.x
		var r: Vector2 = WreckScript.GROW_RANGE if grows else WreckScript.SHRINK_RANGE
		assert_between(w.end_scale, r.x, r.y)
		assert_between(w.rings.size(), 1, 2)
		assert_between(w.pops.size(), 0, 3)


func test_both_grow_and_shrink_happen() -> void:
	var grow := 0
	var shrink := 0
	for s in 40:
		if _wreck(s).end_scale > 1.0:
			grow += 1
		else:
			shrink += 1
	assert_gt(grow, 0)
	assert_gt(shrink, 0)


func test_veers_spins_and_changes_depth() -> void:
	var w := _wreck(7)
	w._process(WreckScript.DURATION / 2.0)
	assert_ne(w.hull.position, Vector2.ZERO)
	assert_eq(w.position, Vector2.ZERO, "node stays put; the hull moves")
	assert_ne(w.hull.rotation, 0.0)
	assert_almost_eq(w.hull.scale.x, w.depth_scale(0.5), 0.001)
	assert_lt(w.hull.scale.y, 0.0, "flipped to face down")
	assert_false(w.exploded)


func test_smoke_trails_in_world_space_and_scales_with_depth() -> void:
	var w := _wreck(7)
	assert_false(w.smoke.local_coords)
	assert_true(w.smoke.emitting)
	w._process(WreckScript.DURATION * 0.75)
	assert_almost_eq(w.smoke.scale_amount_max, WreckScript.SMOKE_SCALE.y * w.depth_scale(0.75), 0.001)


func test_explodes_after_duration() -> void:
	var w := _wreck(7)
	w._process(WreckScript.DURATION + 0.01)
	assert_true(w.exploded)
	assert_false(w.smoke.emitting)
	assert_eq(w._sparks.size(), 1)


func test_explosion_size_matches_depth() -> void:
	var w := _wreck(7)
	w._process(WreckScript.DURATION + 0.01)
	assert_eq(w._boom_size, w.end_scale)


func test_secondary_pops_fire() -> void:
	for s in 50:
		var w := _wreck(s)
		if w.pops.is_empty():
			continue
		w._process(WreckScript.DURATION + 0.01)
		w._process(0.3)
		assert_eq(w._sparks.size(), 1 + w.pops.size())
		return
	fail_test("no seed produced secondary pops")


func test_freed_after_linger() -> void:
	var w := _wreck(1)
	w._process(WreckScript.DURATION + 0.01)
	w._process(WreckScript.LINGER + 0.01)
	assert_true(w.is_queued_for_deletion())


# --- Parts ------------------------------------------------------------------

func _parts() -> Array:
	return Ships.get_enemy_parts(0, 1)


func test_one_sprite_per_part() -> void:
	var parts := _parts()
	var w := _wreck(3, parts)
	assert_eq(w.hull.get_child_count(), parts.size())
	for i in parts.size():
		assert_eq(w.hull.get_child(i).position, parts[i].offset)


func test_without_parts_uses_whole_texture() -> void:
	var w := _wreck(3)
	assert_eq(w.hull.get_child_count(), 1)
	assert_same(w.hull.get_child(0).texture, Ships.get_enemy_texture(0))
	assert_eq(w.breakoffs.size(), 0, "nothing to shed from a single piece")


func test_sheds_small_parts_during_veer() -> void:
	var parts := _parts()
	var w := _wreck(3, parts)
	assert_between(w.breakoffs.size(), 1, 2)
	var largest := 0
	for i in parts.size():
		if parts[i].area > parts[largest].area:
			largest = i
	for b in w.breakoffs:
		assert_ne(b.piece, largest)
		assert_lt(b.time, WreckScript.DURATION)
	w._process(WreckScript.DURATION - 0.01)
	assert_false(w.exploded)
	assert_eq(w.loose.size(), w.breakoffs.size())
	for b in w.breakoffs:
		assert_false(w.hull.get_child(b.piece).visible)


func test_all_parts_fly_apart_on_explosion() -> void:
	var parts := _parts()
	var w := _wreck(3, parts)
	w._process(WreckScript.DURATION + 0.01)
	assert_eq(w.loose.size(), parts.size())
	for piece in w.hull.get_children():
		assert_false(piece.visible)
	var before: Array = w.loose.map(func(p): return p.node.position)
	w._process(0.1)
	for i in w.loose.size():
		assert_ne(w.loose[i].node.position, before[i])


func test_loose_parts_fade_out() -> void:
	var w := _wreck(3, _parts())
	w._process(WreckScript.DURATION + 0.01)
	w._process(WreckScript.PIECE_LIFE / 2.0)
	assert_almost_eq(w.loose[-1].node.modulate.a, 0.5, 0.05)


func test_detached_part_keeps_world_transform() -> void:
	var w := _wreck(3, _parts())
	w._process(0.3)
	var piece: Sprite2D = w.hull.get_child(0)
	var xf := piece.global_transform
	w._detach(piece, 0.0, Vector2.ZERO)
	var loose_node: Sprite2D = w.loose[-1].node
	assert_almost_eq(loose_node.global_position, xf.origin, Vector2(0.01, 0.01))
	assert_almost_eq(loose_node.global_transform.get_scale().x, xf.get_scale().x, 0.001)


func test_freed_loose_parts_are_skipped() -> void:
	var w := _wreck(3, _parts())
	w.set_process(false)  # drive time manually only
	w._process(WreckScript.DURATION + 0.01)
	w._process(WreckScript.PIECE_LIFE + 0.01)
	await wait_process_frames(1)  # loose parts are now freed
	w._process(0.01)
	assert_engine_error_count(0)
	assert_push_error_count(0)
