extends SceneTree

# Vertical streaming check: teleports the player far below and far above the
# spawn surface, then waits for the vertical window to deliver a lit, meshed
# chunk and a solid floor under the target cell.
#   Godot --headless --path Terraria3D --script res://debug/vertical_travel_check.gd

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var world = scene.get_node_or_null("VoxelWorld")
	var player = scene.get_node_or_null("Player")
	if world == null or player == null:
		print("VERTICAL_CHECK FAIL missing nodes")
		quit(1)
		return
	var frames := 0
	while (not bool(world.is_generated) or not bool(player.spawned)) and frames < 900:
		await process_frame
		frames += 1
	# Let the initial spawn burst settle, then freeze physics so gravity cannot
	# drag the probe out of the window it is testing.
	for _settle in range(30):
		await process_frame
	player.set_physics_process(false)
	var failures := 0
	# Descent, abyss and ascent: each jump moves the resident window, which is
	# the expensive part under headless timing.
	for target in [150, 60, 150]:
		var pos: Vector3 = player.global_position
		var cell := Vector3i(floori(pos.x), int(target) - 2, floori(pos.z))
		var chunk: Vector3i = world._chunk_of(cell)
		var waited := 0
		var ready: bool = world.is_chunk_ready(chunk)
		player.global_position = Vector3(pos.x, float(target), pos.z)
		while not ready and waited < 1200:
			await process_frame
			waited += 1
			ready = world.is_chunk_ready(chunk)
		var loaded: bool = world.is_chunk_loaded_at(cell)
		var floor_found := false
		for dy in range(1, 7):
			if world.is_solid(cell + Vector3i(0, -dy, 0)):
				floor_found = true
				break
		var record: Dictionary = world.chunk_records.get(chunk, {})
		var lit: bool = bool(record.get("light_ready", false))
		var meshed: bool = bool(record.get("mesh_installed", false))
		var ok: bool = ready and loaded and floor_found
		if not ready:
			print("VERTDIAG y=%d queue=%s set=%s waiting=%s meshed_flags=%s queue_size=%d meshed=%d tasks=%s" % [
				int(target), str(world.mesh_queue.has(chunk)), str(world.mesh_set.has(chunk)),
				str(world.mesh_waiting.has(chunk)), str(bool(record.get("mesh_installed", false))),
				world.mesh_queue.size(), world.meshed_chunk_count, str(world.mesh_task_chunks)])
		if not ok:
			failures += 1
		print("VERTICAL y=%d chunk=%s ready=%s lit=%s meshed=%s loaded=%s floor=%s frames=%d" % [
			int(target), str(chunk), str(ready), str(lit), str(meshed), str(loaded), str(floor_found), waited])
	print("VERTICAL_CHECK %s failures=%d" % ["FAIL" if failures > 0 else "PASS", failures])
	quit(1 if failures > 0 else 0)
