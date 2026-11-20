extends SceneTree

# Developer tool: regenerates data/world/adventure_config.tres from the defaults
# in scripts/content/adventure_config.gd. Run from the repo root:
#   Godot --headless --path lumen_deepworld --script res://debug/generate_adventure_config.gd

func _initialize() -> void:
	var config := AdventureConfig.new()
	var error := ResourceSaver.save(config, "res://data/world/adventure_config.tres")
	if error != OK:
		push_error("ADVENTURE CONFIG: save failed (%s)" % error_string(error))
		quit(1)
		return
	print("ADVENTURE CONFIG PASS: wrote res://data/world/adventure_config.tres")
	quit(0)
