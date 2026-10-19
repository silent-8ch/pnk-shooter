extends GutHookScript
## Before the suite: the default layout, whatever this machine has saved, and
## a copy of the real settings file (post_run.gd puts it back, so no test can
## leave its choices, name or volume in it). The real clock never reads a fun
## time (FunTime.real_clock), so no test gets droids it didn't ask for.

const SETTINGS := "user://settings.cfg"
const BACKUP := "user://settings.cfg.testbackup"


func run() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SETTINGS), ProjectSettings.globalize_path(BACKUP))
	Settings.left_handed = true
	FunTime.real_clock = false
