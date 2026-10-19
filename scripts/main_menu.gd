extends CanvasLayer
## Title screen: Continue (when there's a saved run, SaveGame), Play, Music and Sound FX on/off, which side the controls sit on, or Quit.

signal play_pressed
signal continue_pressed
signal quit_pressed

@onready var play_button: Button = %PlayButton
@onready var continue_button: Button = %ContinueButton
@onready var quit_button: Button = %QuitButton
@onready var music_toggle: CheckButton = %MusicToggle
@onready var sfx_toggle: CheckButton = %SfxToggle
@onready var hand_side: Button = %HandSide


func _ready() -> void:
	play_button.pressed.connect(play_pressed.emit)
	continue_button.pressed.connect(continue_pressed.emit)
	refresh()
	quit_button.pressed.connect(quit_pressed.emit)
	music_toggle.set_pressed_no_signal(Music.enabled)
	music_toggle.toggled.connect(Music.set_enabled)
	Music.enabled_changed.connect(music_toggle.set_pressed_no_signal)
	sfx_toggle.set_pressed_no_signal(Settings.sfx)
	sfx_toggle.toggled.connect(Settings.set_sfx)
	Settings.sfx_changed.connect(sfx_toggle.set_pressed_no_signal)
	hand_side.text = Settings.side_text(Settings.left_handed)
	hand_side.pressed.connect(func() -> void: Settings.set_left_handed(not Settings.left_handed))
	Settings.handed_changed.connect(func(left: bool) -> void: hand_side.text = Settings.side_text(left))


## Continue shows only while there's a saved run.
func refresh() -> void:
	continue_button.visible = SaveGame.exists()
