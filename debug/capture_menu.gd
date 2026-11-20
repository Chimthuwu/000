extends SceneTree

# Windowed reality check: loads the canonical main menu, renders it, and writes
# a PNG so the launched project can be inspected rather than assumed.
#   Godot --path lumen_deepworld --script res://debug/capture_menu.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/ui/main_menu.tscn")
	if packed == null:
		print("CAPTURE FAIL: canonical main_menu.tscn did not load")
		quit(1)
		return
	root.add_child(packed.instantiate())
	for _frame in range(90):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "user://menu_capture.png"
	var error := image.save_png(path)
	print("CAPTURE project=%s scene=%s image=%s error=%d" % [
		ProjectSettings.get_setting("application/config/name", "?"),
		ProjectSettings.get_setting("application/run/main_scene", "?"),
		ProjectSettings.globalize_path(path), error])
	quit(0 if error == OK else 1)
