extends GutTest
## New effect art wired in: engine flames, hit sparks, player-hit flash, and
## the wreck's sparks, embers, smoke puffs, flash and rings.

const EnemyScene := preload("res://scenes/enemy.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
const WreckScript := preload("res://scripts/wreck.gd")
const Effect := preload("res://scripts/sprite_effect.gd")
const EngineFlames := preload("res://scripts/engine_flames.gd")

var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


# --- Thruster anchors -------------------------------------------------------

func test_every_ship_has_thrusters_in_its_lower_half() -> void:
	for ship in Ships.count():
		var t := Ships.get_thrusters(ship)
		assert_gt(t.size(), 0, "ship %d" % ship)
		var h: float = Ships.get_texture(ship, 0).get_size().y
		for a in t:
			assert_gt(a.pos.y, 0.0, "below center")
			assert_lte(a.pos.y, h / 2.0 + 1.0, "inside the texture")
			assert_gte(a.width, 3.0)


func test_thrusters_sorted_and_not_stacked() -> void:
	for ship in Ships.count():
		var t := Ships.get_thrusters(ship)
		for i in range(1, t.size()):
			assert_gt(t[i].pos.x, t[i - 1].pos.x)
		for a in t:
			for b in t:
				if a != b:
					assert_false(b.pos.y > a.pos.y and absf(b.pos.x - a.pos.x) < b.width / 2.0)


func test_thrusters_cached() -> void:
	assert_same(Ships.get_thrusters(0), Ships.get_thrusters(0))


# --- Engine flames ----------------------------------------------------------

func test_player_has_one_flame_per_thruster_behind_body() -> void:
	var p: Area2D = PlayerScene.instantiate()
	p.ship = 1
	add_child_autofree(p)
	var engines: Node2D = p.engines
	assert_eq(engines.get_child_count(), Ships.get_thrusters(1).size())
	assert_lt(engines.get_index(), p.get_node("Body").get_index(), "drawn behind the ship")
	assert_eq(engines.scale, Vector2.ONE)
	var flame: AnimatedSprite2D = engines.get_child(0)
	assert_same(flame.sprite_frames, EngineFlames.THRUST)
	assert_true(flame.is_playing())
	var body_scale: Vector2 = p.get_node("Body").scale
	assert_eq(flame.position, Ships.get_thrusters(1)[0].pos * body_scale)


func test_flame_tint_from_thruster_slot() -> void:
	var p: Area2D = PlayerScene.instantiate()
	p.ship = 0
	p.palette = 1
	add_child_autofree(p)
	var slot: Color = Ships.get_palette_colors(0, 1)[Ships.THRUSTER_SLOT - 1]
	assert_eq(p.engines.get_child(0).modulate, slot.lerp(Color.WHITE, EngineFlames.TINT_TO_WHITE))


func test_flames_not_on_ship_light_mask() -> void:
	var p: Area2D = PlayerScene.instantiate()
	add_child_autofree(p)
	for f in p.engines.get_children():
		assert_eq(f.light_mask & Ships.LIGHT_MASK, 0)


func test_dead_player_hides_flames() -> void:
	var p: Area2D = PlayerScene.instantiate()
	add_child_autofree(p)
	p.hp = 0
	p._process(0.0)
	assert_false(p.engines.visible)
	p.hp = p.MAX_HP
	p._process(0.0)
	assert_true(p.engines.visible)


func test_enemy_flames_flipped() -> void:
	var e: Area2D = EnemyScene.instantiate()
	e.type = EnemyScript.DIVER
	add_child_autofree(e)
	var engines: Node2D
	for c in e.get_children():
		if c is EngineFlames:
			engines = c
	assert_not_null(engines)
	assert_eq(engines.scale, Vector2(1, -1), "flames point up behind a downward ship")
	assert_eq(engines.get_child_count(), Ships.get_thrusters(1).size())


# --- Hits -------------------------------------------------------------------

func _game() -> Node2D:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child_autofree(game)
	return game


func test_non_lethal_hit_plays_hit_spark() -> void:
	var game := _game()
	var e: Area2D = EnemyScene.instantiate()
	e.position = Vector2(100, 200)
	game.get_node("Enemies").add_child(e)
	e.hp = 2
	e.take_damage(1)
	var fx := game.get_node("Effects")
	assert_eq(fx.get_child_count(), 1)
	assert_same(fx.get_child(0).sprite_frames, Effect.HIT)
	assert_eq(fx.get_child(0).position, Vector2(100, 200))


func test_lethal_hit_plays_wreck_not_spark() -> void:
	var game := _game()
	var e: Area2D = EnemyScene.instantiate()
	game.get_node("Enemies").add_child(e)
	e.take_damage(1)
	var fx := game.get_node("Effects")
	assert_eq(fx.get_child_count(), 1)
	assert_is(fx.get_child(0), WreckScript)


func test_player_hit_flash_follows_player() -> void:
	var game := _game()
	var p: Area2D = PlayerScene.instantiate()
	p.name = "1"
	p.peer_id = 1
	game.get_node("Players").add_child(p)
	p.take_damage(1)
	var flashes := p.get_children().filter(func(c): return c is AnimatedSprite2D and c.sprite_frames == Effect.PLAYER_HIT)
	assert_eq(flashes.size(), 1)
	assert_eq(flashes[0].position, Vector2.ZERO)


# --- Wreck art --------------------------------------------------------------

func _wreck(fx_seed: int) -> Node2D:
	var w: Node2D = WreckScript.new()
	w.setup(Ships.get_enemy_texture(0), Vector2.ONE, fx_seed)
	add_child_autofree(w)
	return w


func test_wreck_smoke_uses_puff_art() -> void:
	var w := _wreck(4)
	assert_true(WreckScript.TRAIL_PUFFS.has(w.smoke.texture))


func test_wreck_sparks_and_embers_use_art() -> void:
	var w := _wreck(4)
	w._process(WreckScript.DURATION + 0.01)
	var emitters := w.get_children().filter(func(c): return c is CPUParticles2D and c != w.smoke)
	var embers := emitters.filter(func(c): return c.texture == WreckScript.EMBER)
	var sparks := emitters.filter(func(c): return WreckScript.SPARKS.has(c.texture))
	assert_eq(sparks.size(), 1)
	assert_eq(embers.size(), 1)
	assert_true(embers[0].particle_flag_align_y)


func test_spark_art_varies_by_seed() -> void:
	var seen := {}
	for s in 30:
		seen[_wreck(s).spark_tex] = true
	assert_eq(seen.size(), WreckScript.SPARKS.size())
