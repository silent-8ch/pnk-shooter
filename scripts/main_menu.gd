extends CanvasLayer
## Title screen: Play or Quit.

signal play_pressed
signal quit_pressed

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	play_button.pressed.connect(play_pressed.emit)
	quit_button.pressed.connect(quit_pressed.emit)
