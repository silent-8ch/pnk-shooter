extends GutTest
## Enemy wreck effect: seeded variety, veer + depth scaling, explosion, cleanup.

const WreckScript := preload("res://scripts/wreck.gd")
const EnemyScene := preload("res://scenes/enemy.tscn")

var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func _wreck(fx_seed: int, parts: Array = []) -> Node2D:
	var w: Node2D = WreckScript.new()
	var tex := Ships.get_enemy_texture(0)
	w.setup(tex, Vector2.ONE, fx_seed, parts)
	add_child_autofree(w)
	return w


func _look(w: Node2D) -> Array:
	return [w.velocity, w.spin, w.end_scale, w.fire_ramp]


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
		assert_between(w.fire_ramp, 0, WreckScript.FIRE_RAMPS.size() - 1)
		assert_between(w.explosion_set, 0, WreckScript.SpriteEffect.EXPLOSIONS.size() - 1)


func test_explosion_set_varies_by_seed() -> void:
	var seen := {}
	for s in 30:
		seen[_wreck(s).explosion_set] = true
	assert_eq(seen.size(), WreckScript.SpriteEffect.EXPLOSIONS.size())


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


func test_explodes_after_duration() -> void:
	var w := _wreck(7)
	w._process(WreckScript.DURATION + 0.01)
	assert_true(w.exploded)


func test_explosion_size_matches_depth() -> void:
	var w := _wreck(7)
	w._process(WreckScript.DURATION + 0.01)
	assert_eq(w._boom_size, w.end_scale)


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


func test_parts_on_ship_light_mask() -> void:
	var w := _wreck(3, _parts())
	for piece in w.hull.get_children():
		assert_eq(piece.light_mask, Ships.LIGHT_MASK)
	w._process(WreckScript.DURATION + 0.01)
	for p in w.loose:
		assert_eq(p.node.light_mask, Ships.LIGHT_MASK)


func test_sprite_blast_plays_at_explosion_point_scaled_by_depth() -> void:
	var w := _wreck(3, _parts())
	w._process(WreckScript.DURATION / 2.0)
	var frames := []
	for c in w.get_children():
		if c is AnimatedSprite2D:
			frames.append(c.sprite_frames)
	assert_eq(frames, [], "no blast before exploding")
	w._process(WreckScript.DURATION)
	var blasts := w.get_children().filter(func(c): return c is AnimatedSprite2D)
	assert_eq(blasts.size(), 1)
	var boom: AnimatedSprite2D = blasts[0]
	assert_eq(boom.position, w.hull.position)
	var frames_now := WreckScript.SpriteEffect.explosion_frames(WreckScript.FIRE_RAMPS[w.fire_ramp], w.explosion_set)
	assert_same(boom.sprite_frames, frames_now)
	var h := WreckScript.SpriteEffect.frame_height(frames_now)
	assert_almost_eq(boom.scale.x, WreckScript.BLAST_HEIGHT * w.end_scale / h, 0.0001)


func test_fire_ramp_varies_by_seed() -> void:
	var seen := {}
	for s in 30:
		seen[_wreck(s).fire_ramp] = true
	assert_eq(seen.size(), WreckScript.FIRE_RAMPS.size())


func test_lethal_hit_plays_wreck() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	var e: Area2D = EnemyScene.instantiate()
	game.get_node("Enemies").add_child(e)
	e.take_damage(1)
	var fx := game.get_node("Effects")
	assert_eq(fx.get_child_count(), 1)
	assert_is(fx.get_child(0), WreckScript)


# --- Sound ------------------------------------------------------------------

func _enemy_in_game() -> Area2D:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	var e: Area2D = EnemyScene.instantiate()
	game.get_node("Enemies").add_child(e)
	return e


func test_non_lethal_hit_plays_hit_sound() -> void:
	var e := _enemy_in_game()
	e.hp = 2
	var hit: AudioStreamPlayer = e.get_parent().get_parent().get_node("HitSound")
	assert_eq(hit.stream.get_stream(0).resource_path, "res://assets/sfx/hit.wav")
	e.take_damage(1)
	assert_true(hit.playing)


func test_lethal_hit_plays_no_hit_sound() -> void:
	var e := _enemy_in_game()
	e.hp = 1
	var hit: AudioStreamPlayer = e.get_parent().get_parent().get_node("HitSound")
	e.take_damage(1)
	assert_false(hit.playing)


func test_implosion_on_death_explosion_on_blast() -> void:
	var w := _wreck(1)
	assert_eq(w.implosion_sound.stream.get_stream(0).resource_path, "res://assets/sfx/implosion.wav")
	assert_eq(w.explosion_sound.stream.get_stream(0).resource_path, "res://assets/sfx/explosion.wav")
	assert_true(w.implosion_sound.playing)
	assert_false(w.explosion_sound.playing)
	w.explode()
	assert_true(w.explosion_sound.playing)


func test_nearer_explosion_sounds_deeper_and_louder() -> void:
	var near := _wreck(1)
	var far := _wreck(2)
	near.end_scale = 1.6
	far.end_scale = 0.4
	near.explode()
	far.explode()
	assert_lt(near.explosion_sound.pitch_scale, far.explosion_sound.pitch_scale)
	assert_gt(near.explosion_sound.volume_db, far.explosion_sound.volume_db)


func test_sounds_vary_pitch_and_volume() -> void:
	for name in ["shoot", "hit", "implosion", "explosion"]:
		var r: AudioStreamRandomizer = load("res://assets/sfx/%s.tres" % name)
		assert_gt(r.random_pitch, 1.0, name)
		assert_gt(r.random_volume_offset_db, 0.0, name)
