extends GutTest
## Generated 8-bit sound effects (tools/make_sfx.gd → assets/sfx/*.wav).

const Sfx := preload("res://tools/make_sfx.gd")


func test_every_sound_is_generated_and_up_to_date() -> void:
	for name in Sfx.outputs():
		var path: String = Sfx.DIR + name + ".wav"
		assert_true(FileAccess.file_exists(path), path)
		assert_eq(FileAccess.get_file_as_bytes(path), Sfx.wav_bytes(Sfx.render(name)), path + " matches its recipe")


func test_sounds_load_as_audio_streams() -> void:
	for name in Sfx.outputs():
		var stream := load(Sfx.DIR + name + ".wav") as AudioStreamWAV
		assert_not_null(stream, name)
		if stream:
			assert_almost_eq(stream.get_length(), Sfx.render(name).size() / float(Sfx.RATE), 0.01, name)


func test_sounds_are_audible_unclipped_and_click_free() -> void:
	for name in Sfx.outputs():
		var s := Sfx.render(name)
		var peak := 0.0
		for x in s:
			peak = maxf(peak, absf(x))
		assert_gt(peak, 0.1, name + " is audible")
		assert_lt(peak, 1.0, name + " does not clip")
		assert_almost_eq(s[0], 0.0, 0.01, name + " starts silent")
		assert_almost_eq(s[s.size() - 1], 0.0, 0.01, name + " ends silent")


func test_durations_fit_their_use() -> void:
	var len := func(n: String) -> float: return Sfx.render(n).size() / float(Sfx.RATE)
	assert_lt(len.call("shoot"), preload("res://scripts/player.gd").FIRE_COOLDOWN, "ends before the next shot")
	assert_lt(len.call("ui_click"), 0.1)
	assert_lt(len.call("xp"), 0.3, "picked up in quick runs")
	assert_gt(len.call("explosion"), len.call("hit"))
	assert_lt(len.call("implosion"), len.call("explosion"), "a quick lead-in to the explosion")
	assert_gt(len.call("player_death"), len.call("explosion"))


func test_render_is_deterministic() -> void:
	assert_eq(Sfx.render("explosion"), Sfx.render("explosion"), "noise is a shift register, not random")


func test_wav_header() -> void:
	var b := Sfx.wav_bytes(PackedFloat32Array([0.0, 1.0, -1.0]))
	assert_eq(b.slice(0, 4).get_string_from_ascii(), "RIFF")
	assert_eq(b.slice(8, 16).get_string_from_ascii(), "WAVEfmt ")
	assert_eq(b.decode_u32(24), Sfx.RATE)
	assert_eq(b.decode_u16(34), 16)
	assert_eq(b.decode_u32(40), 6)
	assert_eq(b.decode_s16(46), 32767)
	assert_eq(b.decode_s16(48), -32767)


func test_variants_are_distinct_takes() -> void:
	for name in Sfx.VARIANTS:
		var takes := Sfx.takes(name)
		assert_eq(takes.size(), Sfx.VARIANTS[name].count, name)
		assert_eq(Sfx.outputs()[name], Sfx.SOUNDS[name], name + " take 0 is the recipe itself")
		for i in range(1, takes.size()):
			assert_ne(Sfx.render(takes[i]), Sfx.render(name), takes[i] + " differs")


func test_shoot_takes_barely_vary() -> void:
	var base := Sfx.render("shoot").size()
	for stem in Sfx.takes("shoot"):
		assert_almost_eq(float(Sfx.render(stem).size()) / base, 1.0, 0.05, stem + " length")
		for i in Sfx.SOUNDS.shoot.size():
			var ratio: float = Sfx.outputs()[stem][i].f0 / Sfx.SOUNDS.shoot[i].f0
			assert_almost_eq(ratio, 1.0, 0.03, stem + " pitch")


func test_randomizers_pick_among_all_takes() -> void:
	for name in Sfx.VARIANTS:
		var r: AudioStreamRandomizer = load(Sfx.DIR + name + ".tres")
		assert_eq(r.streams_count, Sfx.VARIANTS[name].count, name)
		for i in r.streams_count:
			assert_eq(r.get_stream(i).resource_path, Sfx.DIR + Sfx.takes(name)[i] + ".wav")


func test_randomizer_text_keeps_random_settings() -> void:
	var t := Sfx.randomizer_text("hit", "[resource]\nrandom_pitch = 1.2\nrandom_volume_offset_db = 2.0\nstreams_count = 1\n")
	assert_string_contains(t, "random_pitch = 1.2\n")
	assert_string_contains(t, "random_volume_offset_db = 2.0\n")
	assert_string_contains(t, "streams_count = %d\n" % Sfx.VARIANTS.hit.count)
	assert_false(t.contains("streams_count = 1\n"))


func test_gate_chops_a_voice() -> void:
	var v := Sfx.voice({wave = "square", dur = 0.2, f0 = 100.0, f1 = 100.0, v0 = 1.0, v1 = 1.0, gate = [10.0, 0.5]})
	assert_ne(v[int(0.025 * Sfx.RATE)], 0.0, "on in the first half of each cycle")
	assert_eq(v[int(0.075 * Sfx.RATE)], 0.0, "off in the second half")
	assert_ne(v[int(0.125 * Sfx.RATE)], 0.0, "on again next cycle")
