extends SceneTree

# Windowed visual check for the generated Underworld: boots the world, drops the
# player to a solid ash ledge near the lava sea and captures the viewport.
#   Godot --path lumen_deepworld --script res://debug/capture_underworld.gd

const BiomeManager_UNDERWORLD_OFFSET := 178

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("UNDERWORLDCAP FAIL: main.tscn did not load")
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
	if world == null or player == null:
		print("UNDERWORLDCAP FAIL: world/player missing")
		quit(1)
		return
	player.god_mode = true
	player.camera_mode = 1
	# Stream the deep rows first, then find an open column directly above lava.
	player.position = Vector3(68.5, 23.0, 68.5)
	player.velocity = Vector3.ZERO
	world.player_tracking = true
	var deep_deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deep_deadline:
		await process_frame
	var lava_id := int(world.block_ids.get(&"lava", -1))
	var target_x := 68
	var target_z := 68
	var target_y := 21
	var found := false
	for radius in range(0, 26, 2):
		for ox in range(-radius, radius + 1, 2):
			for oz in range(-radius, radius + 1, 2):
				var x := 68 + ox
				var z := 68 + oz
				for y in range(23, 18, -1):
					if int(world.get_block_id(Vector3i(x, y, z))) != lava_id:
						continue
					if bool(world.is_solid(Vector3i(x, y + 1, z))) or bool(world.is_solid(Vector3i(x, y + 2, z))):
						continue
					target_x = x
					target_z = z
					target_y = y + 1
					found = true
					break
				if found:
					break
			if found:
				break
		if found:
			break
	player.position = Vector3(float(target_x) + 0.5, float(target_y) + 0.02, float(target_z) + 0.5)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.8
	player.camera.rotation.x = -1.35
	var settle_deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < settle_deadline:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "user://underworld_capture.png"
	var error := image.save_png(path)
	print("UNDERWORLDCAP x=%d y=%d z=%d lava=%s generated=%s frames=%d image=%s error=%d" % [
		target_x, target_y, target_z, str(found), str(world.is_generated), frames, ProjectSettings.globalize_path(path), error])
	quit(0 if error == OK else 1)
