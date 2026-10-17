extends CanvasLayer
## In-game overlay: Resume, Leave game, Music on/off, Quit. The simulation keeps running
## (it is networked), only local input is suppressed while open.

signal resume_pressed
signal leave_pressed
signal quit_pressed

@onready var resume_button: Button = %ResumeButton
@onready var leave_button: Button = %LeaveButton
@onready var quit_button: Button = %QuitButton
@onready var music_toggle: CheckButton = %MusicToggle


func _ready() -> void:
	resume_button.pressed.connect(resume_pressed.emit)
	leave_button.pressed.connect(leave_pressed.emit)
	quit_button.pressed.connect(quit_pressed.emit)
	music_toggle.set_pressed_no_signal(Music.enabled)
	music_toggle.toggled.connect(Music.set_enabled)
	Music.enabled_changed.connect(music_toggle.set_pressed_no_signal)
