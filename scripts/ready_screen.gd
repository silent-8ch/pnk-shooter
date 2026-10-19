extends CanvasLayer
## Between runs: the last run's results and who's ready for the next one. Each
## player taps Ready; when everyone connected is ready the host starts the next
## run (Game.set_ready). Leave goes back to the main menu.

signal ready_toggled(on: bool)
signal leave_pressed

@onready var results_label: Label = %ResultsLabel
@onready var players_label: Label = %PlayersLabel
@onready var ready_button: Button = %ReadyButton
@onready var leave_button: Button = %LeaveButton


func _ready() -> void:
	ready_button.toggled.connect(func(on: bool) -> void:
		ready_button.text = "Ready!" if on else "Ready"
		ready_toggled.emit(on))
	leave_button.pressed.connect(leave_pressed.emit)


func open(results: String) -> void:
	results_label.text = results if results != "" else "Waiting for the next run"
	players_label.text = ""
	ready_button.set_pressed_no_signal(false)
	ready_button.text = "Ready"
	visible = true


## [{name, ready}], from Game.ready_changed.
func show_players(list: Array) -> void:
	var lines := PackedStringArray()
	for p in list:
		lines.append("%s   %s" % [p.get("name", "Player"), "READY" if p.get("ready", false) else "..."])
	players_label.text = "\n".join(lines)
