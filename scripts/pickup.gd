extends Area2D
## Pickup dropped where an enemy is shot down; local on every peer (like Wreck).
## Uses the william animation, whose frames run backwards: william_03 is the
## first frame and william_00 the last. While waiting it holds the first frame
## while its painted color slots cycle through STAR_COLORS (a Mario-star
## palette cycle: each step shifts every slot to the next color). When
## the host says a player took it, it plays through to the last frame (each frame
## drawn fainter than the one before), holds there shrinking away as it fades
## out, with an xp sound. It doesn't spin: it lands at a random angle, and each frame of the
## collect animation shows at its own random angle (seeded from its name, so
## every peer sees the same). It pulses a little in size and wanders a little
## around its spot. Uncollected, it blinks out after LIFETIME.
##
## Each palette step is the painted frames re-rendered by PaletteFrames (cached).
## Every slot cycles, outline included.

const FRAMES := preload("res://assets/effects/william.tres")
const DISPLAY_SCALE := 0.25  # 456 x 272 sheet-scale frames -> on-screen size
const RENDER_SCALE := 0.5  # SVG -> texture; 2x the display size for high-DPI phones
const SLOTS := 8  # most color slots any william frame uses
const RADIUS := 22.0  # pickup reach, screen px
const STAR_COLORS: Array[Color] = [
	Color("ffffff"), Color("ffd45a"), Color("ff6b1a"), Color("ff7ad9"), Color("5ad1ff"), Color("8dff7a"),
]
const CYCLE_RATE := 15.0  # palette steps per second
const COLLECT_ALPHAS: Array[float] = [1.0, 0.8, 0.6, 0.45]  # opacity per frame: each fainter than the last
const COLLECT_SOUND := preload("res://assets/sfx/xp.tres")  # random pick of the xp variants
const COLLECT_FPS := 4.0  # slow enough to see every frame
const HOLD_TIME := 0.6  # on the last frame before fading
const FADE_TIME := 0.3
const LIFETIME := 8.0
const BLINK_TIME := 2.0  # blinks during the last this-many seconds
const PULSE := 0.08  # it grows and shrinks this much either way
const PULSE_RATE := 2.2  # pulses per second
const DRIFT := Vector2(3.0, 2.5)  # px it wanders either way around its spot
const DRIFT_RATE := Vector2(0.9, 1.3)  # wander cycles per second, x and y

static var _frames: SpriteFrames

var collected := false
var sprite: AnimatedSprite2D
var sound := AudioStreamPlayer.new()
var _age := 0.0
var _collect_age := 0.0
var _step := -1  # current palette step
var _shown_frame := -1  # collect animation frame last given its own angle
var _rng := RandomNumberGenerator.new()  # seeded from the name: every peer sees the same angles
var _drift_phase := Vector2.ZERO


## The william frames in play order (reversed from their file numbering).
static func play_frames() -> SpriteFrames:
	if _frames == null:
		_frames = SpriteFrames.new()
		_frames.set_animation_loop(&"default", false)
		_frames.set_animation_speed(&"default", COLLECT_FPS)
		var n := FRAMES.get_frame_count(&"default")
		for i in n:
			_frames.add_frame(&"default", FRAMES.get_frame_texture(&"default", n - 1 - i))
	return _frames


## Palette for cycle step `step`: slot k gets the star color `step + k` along, so
## the colors march across the slots.
static func star_palette(step: int) -> Array[Color]:
	var out: Array[Color] = []
	for k in range(1, SLOTS + 1):
		out.append(STAR_COLORS[(step + k) % STAR_COLORS.size()])
	return out


## The painted frames recolored for cycle step `step` (cached by PaletteFrames).
static func frames_for_step(step: int) -> SpriteFrames:
	return PaletteFrames.recolor(play_frames(), star_palette(step % STAR_COLORS.size()), RENDER_SCALE)


## Renders every cycle step up front so the first pickup doesn't hitch.
static func warm() -> void:
	for i in STAR_COLORS.size():
		frames_for_step(i)


func _init() -> void:
	collision_layer = 0
	collision_mask = 1  # players
	monitorable = false
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)

	sprite = AnimatedSprite2D.new()
	sprite.scale = Vector2.ONE * (DISPLAY_SCALE / RENDER_SCALE)
	sprite.light_mask = 0  # not dimmed like ships
	add_child(sprite)
	sound.stream = COLLECT_SOUND
	add_child(sound)
	area_entered.connect(_on_area_entered)
	_apply_color()


func _ready() -> void:
	_rng.seed = hash([String(name), "pickup"])
	sprite.rotation = _rng.randf() * TAU  # each one lands at its own angle
	_drift_phase = Vector2(_rng.randf(), _rng.randf()) * TAU


func palette_step() -> int:
	return _step


## Swaps in the frames for the current cycle step, keeping the animation's place.
func _apply_color() -> void:
	var step := int(_age * CYCLE_RATE) % STAR_COLORS.size()
	if step == _step:
		return
	_step = step
	var frame := sprite.frame
	var progress := sprite.frame_progress
	var playing := sprite.is_playing()
	sprite.sprite_frames = frames_for_step(step)
	sprite.set_frame_and_progress(frame, progress)
	if playing:
		sprite.play(&"default")


## Plays the collect animation (every peer, from Game.collect_pickup).
func collect() -> void:
	if collected:
		return
	collected = true
	set_deferred("monitoring", false)
	sprite.play(&"default")
	if sound.is_inside_tree():
		sound.play()


## 1, down to 0 as the collect animation's last frame is shown (held, then faded).
func shrink() -> float:
	if not collected or sprite.is_playing():
		return 1.0
	return 1.0 - clampf(_collect_age / (HOLD_TIME + FADE_TIME), 0.0, 1.0)


## Pulses a little in size and wanders a little around its spot (the
## pickup's reach stays put).
func _wobble() -> void:
	sprite.scale = Vector2.ONE * (DISPLAY_SCALE / RENDER_SCALE) * (1.0 + PULSE * sin(_age * TAU * PULSE_RATE)) * shrink()
	sprite.position = Vector2(sin(_age * TAU * DRIFT_RATE.x + _drift_phase.x) * DRIFT.x,
		sin(_age * TAU * DRIFT_RATE.y + _drift_phase.y) * DRIFT.y)


func _process(delta: float) -> void:
	_age += delta
	_apply_color()
	_wobble()
	if collected and sprite.frame != _shown_frame:
		_shown_frame = sprite.frame
		if _shown_frame > 0:
			sprite.rotation = _rng.randf() * TAU  # every frame of the collect animation at its own angle
	if not collected:
		var left := LIFETIME - _age
		if left <= 0.0:
			queue_free()
		elif left < BLINK_TIME:
			visible = fmod(left, 0.2) > 0.1
		return
	visible = true
	var f := clampi(sprite.frame, 0, COLLECT_ALPHAS.size() - 1)
	modulate.a = COLLECT_ALPHAS[f]
	if sprite.is_playing():
		return
	_collect_age += delta  # counts from the last frame
	modulate.a *= 1.0 - clampf((_collect_age - HOLD_TIME) / FADE_TIME, 0.0, 1.0)
	if _collect_age >= HOLD_TIME + FADE_TIME:
		queue_free()


## The touching ship's owner claims it; the host gives it to the first claim.
func _on_area_entered(area: Area2D) -> void:
	if collected or multiplayer.multiplayer_peer == null:
		return
	if not area.is_in_group("player") or not area.is_local() or area.ai or not area.is_alive():
		return
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.request_pickup.rpc_id(1, String(name))
