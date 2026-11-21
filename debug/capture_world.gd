extends SceneTree

# Windowed reality check for the canonical game world: boots scenes/world/main.tscn,
# waits for the expanded world to stream in, and writes a PNG of the viewport.
#   Godot --path Terraria3D --script res://debug/capture_world.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("WORLDCAP FAIL: main.tscn did not load")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	var world = scene.get_node_or_null("VoxelWorld")
	var player = scene.get_node_or_null("Player")
	var frames := 0
	var deadline := Time.get_ticks_msec() + 60000
	while (world == null or player == null or not bool(world.is_generated) or not bool(player.spawned)) and Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
	# Wait in wall-clock time: an uncapped window can burn hundreds of frames
	# before the streaming workers finish.
	var settle_end := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < settle_end:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "user://world_capture.png"
	var error := image.save_png(path)
	var chunks: int = 0 if world == null else world.chunk_records.size()
	print("WORLDCAP project=%s scene=%s generated=%s spawned=%s chunks=%d frames=%d image=%s error=%d" % [
		ProjectSettings.get_setting("application/config/name", "?"),
		ProjectSettings.get_setting("application/run/main_scene", "?"),
		str(false if world == null else world.is_generated),
		str(false if player == null else player.spawned),
		chunks, frames, ProjectSettings.globalize_path(path), error])
	quit(0 if error == OK else 1)
