extends GutHookScript
## After the suite: the real settings file exactly as it was (see pre_run.gd).

const SETTINGS := "user://settings.cfg"
const BACKUP := "user://settings.cfg.testbackup"


func run() -> void:
	if FileAccess.file_exists(BACKUP):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(BACKUP), ProjectSettings.globalize_path(SETTINGS))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP))
