extends GutHookScript
## Before the suite: the default layout, whatever this machine has saved (the
## settings autoload loads the real settings file; nothing here saves it).


func run() -> void:
	Settings.left_handed = true
