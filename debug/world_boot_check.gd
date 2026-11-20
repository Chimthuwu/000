extends SceneTree

# Loads the real world scene, waits for the streaming/light/mesh handshake and
# reports whether the lifted-surface spawn and vertical chunk window settle.

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var world = scene.get_node_or_null("VoxelWorld")
	var player = scene.get_node_or_null("Player")
	if world == null or player == null:
		print("BOOT_CHECK FAIL missing nodes")
		quit(1)
		return
	var frames := 0
	while (not bool(world.is_generated) or not bool(player.spawned)) and frames < 900:
		await process_frame
		frames += 1
	for _settle in range(8):
		await process_frame
	var ok: bool = bool(world.is_generated) and bool(player.spawned) and world.chunk_records.size() > 0
	print("BOOT_CHECK ready=%s spawned=%s frames=%d player_y=%.1f surface=%d loaded_chunks=%d generated=%d lit=%d meshed=%d" % [
		str(world.is_generated), str(player.spawned), frames, player.position.y,
		world.spawn_height(), world.chunk_records.size(),
		world.generated_chunk_count, world.initialized_light_chunks, world.meshed_chunk_count])
	quit(0 if ok else 1)
