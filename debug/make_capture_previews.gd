extends SceneTree

# Downscales the large windowed captures so they can be reviewed inline.

func _initialize() -> void:
	for name in ["phase1_world", "phase1_underworld", "phase1_menu"]:
		var source := "res://debug/evidence/%s.png" % name
		var image := Image.load_from_file(ProjectSettings.globalize_path(source))
		if image == null or image.is_empty():
			print("PREVIEW missing: " + source)
			continue
		image.resize(1024, 576, Image.INTERPOLATE_BILINEAR)
		var target := "res://debug/evidence/%s_preview.png" % name
		var error := image.save_png(ProjectSettings.globalize_path(target))
		print("PREVIEW %s -> %s error=%d" % [source, target, error])
	quit(0)
