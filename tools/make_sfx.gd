extends SceneTree
## Generates the game's 8-bit sound effects from the descriptions below. Run from the project root:
##   Godot --headless -s tools/make_sfx.gd
## Writes assets/sfx/<name>.wav (16-bit mono, 22050 Hz). Deterministic: same recipe, same bytes.
## Sounds in VARIANTS also get <name>_1.wav ... takes, and their AudioStreamRandomizer
## (<name>.tres) is rewritten to pick among all takes, keeping its random pitch/volume settings.
##
## A sound is a list of layers mixed together. Each layer is one chip voice:
##   wave    pulse12 | pulse25 | square | triangle | saw | noise  (triangle/saw are 4-bit stepped)
##   at      start time (s)               dur   length (s)
##   f0, f1  pitch at start/end (Hz), exponential glide; for noise it sets the hiss brightness
##   v0, v1  volume at start/end (0-1), stepped to 16 levels like the old chips
##   curve   volume shape: 1 linear, <1 drops fast (punchy), >1 holds then drops
##   vib     [rate Hz, depth semitones]   vibrato
##   arp     [semitones...] stepped through every `arp_step` s (chip-style chords and jingles)
##   gate    [rate Hz, duty 0-1]          chops the voice on and off (rapid fire, rattles)

const RATE := 22050
const DIR := "res://assets/sfx/"
const GAIN := 0.7
const EDGE := 0.002  # fade at each layer's ends so nothing clicks

const SOUNDS := {
	# Player blaster, "pe-cheer":
	#   "pe"   a short thin pluck that dips in pitch,
	#   "ch"   a bright hiss burst as the consonant,
	#   "eer"  a tone flying away (Doppler): pitch keeps falling, it fades and dulls as the
	#          bright pulse dies first, leaving the soft triangle under it.
	"shoot": [
		{wave = "pulse12", dur = 0.06, f0 = 750.0, f1 = 500.0, v0 = 0.5, v1 = 0.2},
		{wave = "noise", at = 0.05, dur = 0.1, f0 = 7000.0, f1 = 3500.0, v0 = 0.4, v1 = 0.0, curve = 0.6},
		{wave = "pulse25", at = 0.07, dur = 0.36, f0 = 1100.0, f1 = 560.0, v0 = 0.38, v1 = 0.0, curve = 0.2},
		{wave = "triangle", at = 0.07, dur = 0.36, f0 = 1100.0, f1 = 560.0, v0 = 0.3, v1 = 0.0, curve = 0.3},
	],
	# Enemy shot: lower, buzzier saw drop so it reads as hostile.
	"enemy_shoot": [
		{wave = "saw", dur = 0.14, f0 = 620.0, f1 = 220.0, v0 = 0.5, v1 = 0.0, curve = 0.8},
	],
	# Bullet hits an enemy: tiny noise crack over a square tick.
	"hit": [
		{wave = "noise", dur = 0.07, f0 = 4000.0, f1 = 1200.0, v0 = 0.6, v1 = 0.0, curve = 0.5},
		{wave = "square", dur = 0.04, f0 = 320.0, f1 = 140.0, v0 = 0.35, v1 = 0.0},
	],
	# Vulcan cannon burst, "buuuuuuurt": a thump as it spins up ("b"), then ~28 rounds a second
	# chopping a low buzz and a crackle together ("uuuu"), ending as the barrels spin down
	# with a last falling rattle ("rt").
	"vulcan": [
		{wave = "triangle", dur = 0.06, f0 = 180.0, f1 = 60.0, v0 = 0.6, v1 = 0.0, curve = 0.5},
		{wave = "square", dur = 0.8, f0 = 110.0, f1 = 95.0, v0 = 0.45, v1 = 0.35, gate = [28.0, 0.5]},
		{wave = "noise", dur = 0.8, f0 = 2200.0, f1 = 1500.0, v0 = 0.5, v1 = 0.4, gate = [28.0, 0.45]},
		{wave = "square", at = 0.8, dur = 0.15, f0 = 95.0, f1 = 50.0, v0 = 0.35, v1 = 0.0, curve = 0.7, gate = [20.0, 0.5]},
		{wave = "noise", at = 0.8, dur = 0.12, f0 = 1500.0, f1 = 400.0, v0 = 0.4, v1 = 0.0, curve = 0.5},
	],
	# Enemy health hits zero, just before the explosion: a low thud (falling triangle with a
	# dull noise body), then a dark rush sucked inward that swells and cuts off.
	"implosion": [
		{wave = "triangle", dur = 0.2, f0 = 140.0, f1 = 45.0, v0 = 0.75, v1 = 0.0, curve = 0.5},
		{wave = "noise", dur = 0.1, f0 = 400.0, f1 = 150.0, v0 = 0.35, v1 = 0.0, curve = 0.5},
		{wave = "noise", at = 0.06, dur = 0.24, f0 = 150.0, f1 = 900.0, v0 = 0.0, v1 = 0.35, curve = 2.0},
	],
	# Enemy destroyed: a dark, rumbly noise burst darkening as it fades, over a soft
	# triangle thump (no bright hiss or square buzz, so it isn't harsh).
	"explosion": [
		{wave = "noise", dur = 0.65, f0 = 1300.0, f1 = 60.0, v0 = 0.65, v1 = 0.0, curve = 0.6},
		{wave = "triangle", dur = 0.25, f0 = 110.0, f1 = 35.0, v0 = 0.6, v1 = 0.0, curve = 0.7},
	],
	# Player takes damage: harsh square drop with a noise grit layer.
	"player_hit": [
		{wave = "square", dur = 0.25, f0 = 480.0, f1 = 110.0, v0 = 0.55, v1 = 0.0, curve = 0.8},
		{wave = "noise", dur = 0.12, f0 = 1800.0, f1 = 600.0, v0 = 0.4, v1 = 0.0, curve = 0.6},
	],
	# Player destroyed: long rumbling blast plus a wobbling tone falling away.
	"player_death": [
		{wave = "noise", dur = 1.1, f0 = 1800.0, f1 = 50.0, v0 = 0.9, v1 = 0.0, curve = 0.6},
		{wave = "square", dur = 0.9, f0 = 700.0, f1 = 55.0, v0 = 0.45, v1 = 0.0, curve = 1.2, vib = [9.0, 0.8]},
	],
	# Respawn: triangle sweep rising with a shimmer.
	"respawn": [
		{wave = "triangle", dur = 0.45, f0 = 220.0, f1 = 1320.0, v0 = 0.6, v1 = 0.2, vib = [14.0, 0.3]},
	],
	# New wave: quick major arpeggio C5 E5 G5 C6, the top note held with vibrato.
	"wave_start": [
		{wave = "pulse25", dur = 0.24, f0 = 523.25, f1 = 523.25, v0 = 0.45, v1 = 0.45, arp = [0, 4, 7], arp_step = 0.08},
		{wave = "pulse25", at = 0.24, dur = 0.36, f0 = 1046.5, f1 = 1046.5, v0 = 0.45, v1 = 0.0, curve = 1.5, vib = [6.0, 0.25]},
	],
	# Game over: slow sad chromatic descent G4 F#4 F4 E4, the last note wobbling out.
	"game_over": [
		{wave = "square", dur = 0.66, f0 = 392.0, f1 = 392.0, v0 = 0.4, v1 = 0.4, arp = [0, -1, -2], arp_step = 0.22},
		{wave = "square", at = 0.66, dur = 0.9, f0 = 329.63, f1 = 329.63, v0 = 0.4, v1 = 0.0, curve = 1.6, vib = [5.0, 0.35]},
		{wave = "triangle", dur = 1.56, f0 = 98.0, f1 = 82.41, v0 = 0.35, v1 = 0.0, curve = 1.6},
	],
	# Experience point collected: coin-like but its own tune. A quick A5 to E6 leap (a fifth,
	# not the coin's fourth), the E6 ringing on a soft triangle, and a faint shimmering A6 on top.
	"xp": [
		{wave = "pulse25", dur = 0.045, f0 = 880.0, f1 = 880.0, v0 = 0.4, v1 = 0.35},
		{wave = "pulse25", at = 0.045, dur = 0.07, f0 = 1318.5, f1 = 1318.5, v0 = 0.4, v1 = 0.0, curve = 1.2},
		{wave = "triangle", at = 0.045, dur = 0.18, f0 = 1318.5, f1 = 1318.5, v0 = 0.3, v1 = 0.0, curve = 0.6},
		{wave = "pulse12", at = 0.09, dur = 0.14, f0 = 1760.0, f1 = 1760.0, v0 = 0.18, v1 = 0.0, curve = 0.5, vib = [30.0, 0.15]},
	],
	# A ship heals: a soft rising triangle sparkle C6 E6 G6, the top note shimmering out.
	"heal": [
		{wave = "triangle", dur = 0.15, f0 = 1046.5, f1 = 1046.5, v0 = 0.5, v1 = 0.5, arp = [0, 4, 7], arp_step = 0.05},
		{wave = "triangle", at = 0.15, dur = 0.25, f0 = 1568.0, f1 = 1568.0, v0 = 0.5, v1 = 0.0, curve = 0.8, vib = [12.0, 0.3]},
		{wave = "pulse12", at = 0.05, dur = 0.3, f0 = 2093.0, f1 = 2093.0, v0 = 0.12, v1 = 0.0, curve = 0.6, vib = [24.0, 0.2]},
	],
	# A rescue drone grabs someone: a quick "boop-bip" up an octave, G5 then G6.
	"rescue": [
		{wave = "pulse25", dur = 0.06, f0 = 784.0, f1 = 784.0, v0 = 0.4, v1 = 0.35},
		{wave = "pulse25", at = 0.06, dur = 0.12, f0 = 1568.0, f1 = 1568.0, v0 = 0.4, v1 = 0.0, curve = 1.2},
		{wave = "triangle", at = 0.06, dur = 0.16, f0 = 1568.0, f1 = 1568.0, v0 = 0.25, v1 = 0.0, curve = 0.6},
	],
	# Rescued handed over at a station: a bright "ta-da" chime, E5 G5 C6 then a ringing E6.
	"dock": [
		{wave = "pulse25", dur = 0.21, f0 = 659.25, f1 = 659.25, v0 = 0.4, v1 = 0.4, arp = [0, 3, 8], arp_step = 0.07},
		{wave = "pulse25", at = 0.21, dur = 0.4, f0 = 1318.5, f1 = 1318.5, v0 = 0.4, v1 = 0.0, curve = 1.4, vib = [6.0, 0.2]},
		{wave = "triangle", at = 0.21, dur = 0.45, f0 = 659.25, f1 = 659.25, v0 = 0.35, v1 = 0.0, curve = 1.2},
	],
	# Rescue drones launch: a "wee-woo" emergency siren, B5 down to F#5 and back, twice,
	# each note bending a little as it holds.
	"siren": [
		{wave = "pulse25", dur = 0.96, f0 = 987.77, f1 = 960.0, v0 = 0.35, v1 = 0.25, arp = [0, -5, 0, -5], arp_step = 0.24, vib = [7.0, 0.15]},
		{wave = "triangle", dur = 0.96, f0 = 987.77, f1 = 960.0, v0 = 0.3, v1 = 0.2, arp = [0, -5, 0, -5], arp_step = 0.24},
	],
	# Heal beam stream: a low, wet burble. A deep triangle wobbling fast in pitch (the
	# bubbles), a soft square an octave up chopped into blips, and a dull noise
	# underneath, all easing in and out so back-to-back bursts run together.
	"healbeam": [
		{wave = "triangle", dur = 0.6, f0 = 98.0, f1 = 92.0, v0 = 0.55, v1 = 0.45, curve = 1.5, vib = [16.0, 3.0]},
		{wave = "square", dur = 0.6, f0 = 196.0, f1 = 175.0, v0 = 0.18, v1 = 0.1, vib = [11.0, 2.0], gate = [13.0, 0.4]},
		{wave = "noise", dur = 0.6, f0 = 260.0, f1 = 200.0, v0 = 0.12, v1 = 0.08, gate = [9.0, 0.5]},
	],
	# Menu button tap: very short thin blip.
	"ui_click": [
		{wave = "pulse12", dur = 0.035, f0 = 1760.0, f1 = 1760.0, v0 = 0.4, v1 = 0.0},
	],
	# Menu confirm / start: two rising triangle notes, A5 then E6.
	"ui_confirm": [
		{wave = "triangle", dur = 0.16, f0 = 880.0, f1 = 880.0, v0 = 0.6, v1 = 0.6, arp = [0, 7], arp_step = 0.07},
		{wave = "triangle", at = 0.16, dur = 0.1, f0 = 1318.5, f1 = 1318.5, v0 = 0.6, v1 = 0.0},
	],
}


## Extra takes of a sound: the same recipe randomly nudged (seeded, so files are reproducible).
##   count        takes including the original
##   pitch        whole-sound shift, +- semitones
##   layer_pitch  extra per-layer shift, +- semitones (changes the blend, not just the pitch)
##   length       +- fraction of every duration
##   curve        +- fraction of every volume curve
const VARIANTS := {
	"shoot": {count = 3, pitch = 0.5, layer_pitch = 0.0, length = 0.04, curve = 0.0},
	"hit": {count = 4, pitch = 2.0, layer_pitch = 3.0, length = 0.2, curve = 0.3},
	"implosion": {count = 3, pitch = 2.0, layer_pitch = 2.0, length = 0.15, curve = 0.3},
	"explosion": {count = 4, pitch = 2.0, layer_pitch = 3.0, length = 0.2, curve = 0.3},
	"vulcan": {count = 3, pitch = 1.0, layer_pitch = 1.5, length = 0.15, curve = 0.2},
	"xp": {count = 3, pitch = 0.7, layer_pitch = 0.0, length = 0.05, curve = 0.1},
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var all := outputs()
	for stem in all:
		var bytes := wav_bytes(mix(all[stem]))
		var f := FileAccess.open(DIR + stem + ".wav", FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		print("%s%s.wav (%.2fs)" % [DIR, stem, float(bytes.size() - 44) / 2.0 / RATE])
	for name in VARIANTS:
		var path: String = DIR + name + ".tres"
		var old := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(randomizer_text(name, old))
		f.close()
		print(path)
	quit()


## Every file to write: stem (no extension) -> layers.
static func outputs() -> Dictionary:
	var out := {}
	for name in SOUNDS:
		out[name] = SOUNDS[name]
		for k in range(1, VARIANTS.get(name, {count = 1}).count):
			out["%s_%d" % [name, k]] = variant(name, k)
	return out


static func takes(name: String) -> PackedStringArray:
	var out := PackedStringArray([name])
	for k in range(1, VARIANTS.get(name, {count = 1}).count):
		out.append("%s_%d" % [name, k])
	return out


static func variant(name: String, k: int) -> Array:
	var s: Dictionary = VARIANTS[name]
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s#%d" % [name, k]).hash()
	var shift := rng.randf_range(-s.pitch, s.pitch)
	var stretch := 1.0 + rng.randf_range(-s.length, s.length)
	var out := []
	for layer: Dictionary in SOUNDS[name]:
		var l := layer.duplicate()
		var m := pow(2.0, (shift + rng.randf_range(-s.layer_pitch, s.layer_pitch)) / 12.0)
		l.f0 *= m
		l.f1 *= m
		l.dur *= stretch
		l.at = l.get("at", 0.0) * stretch
		if l.has("arp_step"):
			l.arp_step *= stretch
		l.curve = l.get("curve", 1.0) * (1.0 + rng.randf_range(-s.curve, s.curve))
		out.append(l)
	return out


## <name>.tres: an AudioStreamRandomizer over every take, keeping the random_* lines of `old`.
static func randomizer_text(name: String, old: String) -> String:
	var settings := PackedStringArray()
	for line in old.split("\n"):
		if line.begins_with("random_"):
			settings.append(line)
	var stems := takes(name)
	var t := "[gd_resource type=\"AudioStreamRandomizer\" load_steps=%d format=3]\n\n" % (stems.size() + 1)
	for i in stems.size():
		t += "[ext_resource type=\"AudioStream\" path=\"%s%s.wav\" id=\"%d\"]\n" % [DIR, stems[i], i + 1]
	t += "\n[resource]\n"
	for line in settings:
		t += line + "\n"
	t += "streams_count = %d\n" % stems.size()
	for i in stems.size():
		t += "stream_%d/stream = ExtResource(\"%d\")\nstream_%d/weight = 1.0\n" % [i, i + 1, i]
	return t


static func render(stem: String) -> PackedFloat32Array:
	return mix(outputs()[stem])


static func mix(layers: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for layer in layers:
		var start := roundi(layer.get("at", 0.0) * RATE)
		var v := voice(layer)
		if out.size() < start + v.size():
			out.resize(start + v.size())
		for i in v.size():
			out[start + i] += v[i]
	for i in out.size():
		out[i] = clampf(out[i] * GAIN, -1.0, 1.0)
	return out


static func voice(l: Dictionary) -> PackedFloat32Array:
	var n := roundi(l.dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var vib: Array = l.get("vib", [0.0, 0.0])
	var arp: Array = l.get("arp", [0])
	var arp_step: float = l.get("arp_step", l.dur)
	var curve: float = l.get("curve", 1.0)
	var gate: Array = l.get("gate", [0.0, 1.0])
	var edge := maxi(1, roundi(EDGE * RATE))
	var phase := 0.0
	var noise_phase := 0.0
	var lfsr := 1
	for i in n:
		var t := float(i) / n
		var sec := float(i) / RATE
		var semis: float = arp[mini(int(sec / arp_step), arp.size() - 1)] + vib[1] * sin(TAU * vib[0] * sec)
		var f: float = l.f0 * pow(l.f1 / l.f0, t) * pow(2.0, semis / 12.0)
		var vol: float = lerpf(l.v0, l.v1, pow(t, curve))
		vol = roundf(vol * 15.0) / 15.0
		if gate[0] > 0.0 and fposmod(sec * gate[0], 1.0) >= gate[1]:
			vol = 0.0
		vol *= minf(1.0, minf(float(i) / edge, float(n - 1 - i) / edge))
		phase = fposmod(phase + f / RATE, 1.0)
		var x := 0.0
		match l.wave:
			"pulse12": x = 1.0 if phase < 0.125 else -1.0
			"pulse25": x = 1.0 if phase < 0.25 else -1.0
			"square": x = 1.0 if phase < 0.5 else -1.0
			"triangle": x = _steps16(4.0 * phase - 1.0 if phase < 0.5 else 3.0 - 4.0 * phase)
			"saw": x = _steps16(2.0 * phase - 1.0)
			"noise":
				# 15-bit shift register like the NES noise channel, clocked at f.
				noise_phase += f / RATE
				var clocks := mini(int(noise_phase), 64)
				noise_phase -= int(noise_phase)
				for c in clocks:
					lfsr = (lfsr >> 1) | (((lfsr ^ (lfsr >> 1)) & 1) << 14)
				x = 1.0 if lfsr & 1 else -1.0
			_:
				assert(false, "unknown wave " + str(l.wave))
		out[i] = x * vol
	return out


static func _steps16(x: float) -> float:
	return minf(15.0, floorf((x + 1.0) * 8.0)) / 7.5 - 1.0


## 16-bit PCM mono WAV file bytes.
static func wav_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(44 + samples.size() * 2)
	b.encode_u32(0, 0x46464952)  # "RIFF"
	b.encode_u32(4, 36 + samples.size() * 2)
	b.encode_u32(8, 0x45564157)  # "WAVE"
	b.encode_u32(12, 0x20746d66)  # "fmt "
	b.encode_u32(16, 16)
	b.encode_u16(20, 1)  # PCM
	b.encode_u16(22, 1)  # mono
	b.encode_u32(24, RATE)
	b.encode_u32(28, RATE * 2)
	b.encode_u16(32, 2)
	b.encode_u16(34, 16)
	b.encode_u32(36, 0x61746164)  # "data"
	b.encode_u32(40, samples.size() * 2)
	for i in samples.size():
		b.encode_s16(44 + i * 2, roundi(samples[i] * 32767.0))
	return b
