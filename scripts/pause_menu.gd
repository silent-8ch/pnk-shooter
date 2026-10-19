extends CanvasLayer
## In-game overlay: a big Resume, then Save and exit (a solo run, see
## Game.can_save) and Leave game, with small Settings and Quit at the bottom.
## Settings (Music and Sound FX on/off, which side the controls sit on) opens
## in place of the main buttons. The simulation keeps running
## (it is networked), only local input is suppressed while open.

signal resume_pressed
signal leave_pressed
signal save_exit_pressed
signal quit_pressed

@onready var resume_button: Button = %ResumeButton
@onready var leave_button: Button = %LeaveButton
@onready var save_exit_button: Button = %SaveExitButton
@onready var quit_button: Button = %QuitButton
@onready var music_toggle: CheckButton = %MusicToggle
@onready var sfx_toggle: CheckButton = %SfxToggle
@onready var hand_side: Button = %HandSide
@onready var settings_button: Button = %SettingsButton
@onready var back_button: Button = %BackButton
@onready var settings_box: Control = %SettingsBox
@onready var main_buttons: Control = %MainButtons
@onready var bottom_row: Control = %BottomRow


func _ready() -> void:
	resume_button.pressed.connect(resume_pressed.emit)
	leave_button.pressed.connect(leave_pressed.emit)
	save_exit_button.pressed.connect(save_exit_pressed.emit)
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
	settings_button.pressed.connect(show_settings.bind(true))
	back_button.pressed.connect(show_settings.bind(false))
	visibility_changed.connect(show_settings.bind(false))  # always opens on its main buttons


## Settings opens in place of the main buttons; Back returns.
func show_settings(on: bool) -> void:
	settings_box.visible = on
	main_buttons.visible = not on
	bottom_row.visible = not on
