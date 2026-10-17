extends CanvasLayer
## Title screen: Play, Music on/off, or Quit.

signal play_pressed
signal quit_pressed

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton
@onready var music_toggle: CheckButton = %MusicToggle


func _ready() -> void:
	play_button.pressed.connect(play_pressed.emit)
	quit_button.pressed.connect(quit_pressed.emit)
	music_toggle.set_pressed_no_signal(Music.enabled)
	music_toggle.toggled.connect(Music.set_enabled)
	Music.enabled_changed.connect(music_toggle.set_pressed_no_signal)
