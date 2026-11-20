extends SceneTree

# Proves which project.godot a launcher actually opened.
func _initialize() -> void:
	print("LAUNCH IDENTITY name=", ProjectSettings.get_setting("application/config/name"),
		" main_scene=", ProjectSettings.get_setting("application/run/main_scene"),
		" project_root=", ProjectSettings.globalize_path("res://"))
	quit(0)
