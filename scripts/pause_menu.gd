extends CanvasLayer
## In-game overlay: Resume, Leave game, Quit. The simulation keeps running
## (it is networked), only local input is suppressed while open.

signal resume_pressed
signal leave_pressed
signal quit_pressed

@onready var resume_button: Button = %ResumeButton
@onready var leave_button: Button = %LeaveButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	resume_button.pressed.connect(resume_pressed.emit)
	leave_button.pressed.connect(leave_pressed.emit)
	quit_button.pressed.connect(quit_pressed.emit)
