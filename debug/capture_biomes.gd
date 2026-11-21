extends SceneTree

# Windowed visual evidence pass: teleports a free camera through the core
# surface identities and one underground cave, then writes one PNG per shot.
# Run with: Godot --fixed-fps 60 --path . --script res://debug/capture_biomes.gd

var main: Node
var world: VoxelWorld
var player: VoxelPlayer
var camera: Camera3D


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("BIOMECAP FAIL: main.tscn did not load")
		quit(1)
		return
	main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _capture(shot_name: String, detail := "") -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://debug/evidence/biome_%s.png" % shot_name
	var error := image.save_png(path)
	print("BIOMECAP %s %s error=%d image=%s" % [shot_name, detail, error, path])


func _frame_column(x: int, z: int, rise: float, style := "default") -> void:
	var surface := world.get_surface_height(x, z)
	world.set_generation_focus(Vector3i(x, surface, z))
	player.position = Vector3(float(x) + 0.5, float(surface) + rise, float(z) + 0.5)
	player.velocity = Vector3.ZERO
	if style == "jungle":
		# Understory view: clear of the high canopy and sky-island layer.
		camera.global_position = Vector3(float(x) - 16.0, float(surface) + 10.0, float(z) - 16.0)
		camera.look_at(Vector3(float(x) + 20.0, float(surface) + 7.0, float(z) + 20.0), Vector3.UP)
	else:
		# Three-quarter surface vista below the 24-52 block sky-island band.
		camera.global_position = Vector3(float(x) - 26.0, float(surface) + rise + 2.0, float(z) - 26.0)
		camera.look_at(Vector3(float(x) + 20.0, float(surface) + 4.0, float(z) + 20.0), Vector3.UP)
	camera.far = 360.0


# Finds an interior column, not a border sliver, by requiring the four sides
# and the centre to share the requested dominant biome.
func _find_clear_center(biome: int) -> Vector2i:
	var best := Vector2i(64, 64)
	var best_score := -1.0
	for gz in range(-30, 31):
		for gx in range(-30, 31):
			var p := Vector2i(64 + gx * 64, 64 + gz * 64)
			if BiomeManager.dominant_biome(p.x, p.y) != biome:
				continue
			var weight := BiomeManager.get_weights(p.x, p.y)[biome]
			if weight < 0.68:
				continue
			var clear := true
			for radius in [96, 160]:
				for offset: Vector2i in [Vector2i(-radius, 0), Vector2i(radius, 0), Vector2i(0, -radius), Vector2i(0, radius)]:
					var neighbour: Vector2i = p + offset
					if BiomeManager.dominant_biome(neighbour.x, neighbour.y) != biome:
						clear = false
						break
				if not clear:
					break
			if not clear:
				continue
			var score := weight - Vector2(p).distance_to(Vector2(64, 64)) * 0.00001
			if score > best_score:
				best_score = score
				best = p
	if best_score < 0.0:
		return BiomeManager.find_biome_center(biome, world.world_seed, 64, 64)
	return best


func _capture_sky_island() -> void:
	var dirt_id := int(world.block_ids.get(&"dirt", -1))
	var stone_id := int(world.block_ids.get(&"stone", -1))
	var deep_id := int(world.block_ids.get(&"deepstone", stone_id))
	if dirt_id < 0:
		return
	world.set_generation_focus(Vector3i(64, 228, 64))
	player.position = Vector3(64.5, 228.0, 64.5)
	player.velocity = Vector3.ZERO
	main.cycle.restore_time(DayNightCycle.CONFIG.day_seconds * 0.5)
	await _wait(7.0)
	var cap := Vector3i.ZERO
	var found := false
	for y in range(204, 250):
		for x in range(0, 160, 2):
			for z in range(0, 160, 2):
				var cell := Vector3i(x, y, z)
				if int(world.get_block_id(cell)) != dirt_id:
					continue
				var below := int(world.get_block_id(cell + Vector3i.DOWN))
				if below != stone_id and below != deep_id and below != dirt_id:
					continue
				cap = cell
				found = true
				break
			if found:
				break
		if found:
			break
	if not found:
		print("BIOMECAP sky_island SKIPPED: no island cap found")
		return
	world.set_generation_focus(cap)
	player.position = Vector3(float(cap.x) + 0.5, float(cap.y) + 0.5, float(cap.z) + 0.5)
	player.velocity = Vector3.ZERO
	await _wait(2.0)
	camera.global_position = Vector3(float(cap.x) - 16.0, float(cap.y) + 10.0, float(cap.z) - 16.0)
	camera.look_at(Vector3(float(cap.x), float(cap.y) - 4.0, float(cap.z)), Vector3.UP)
	await _capture("sky_island", "cap=%d,%d,%d" % [cap.x, cap.y, cap.z])
	# Deliberately look up from just below the cap to verify the layered underside.
	camera.global_position = Vector3(float(cap.x) - 18.0, float(cap.y) - 10.0, float(cap.z) - 18.0)
	camera.look_at(Vector3(float(cap.x), float(cap.y) - 8.0, float(cap.z)), Vector3.UP)
	await _wait(1.0)
	await _capture("sky_island_below", "cap=%d,%d,%d" % [cap.x, cap.y, cap.z])


func _run() -> void:
	var started := Time.get_ticks_msec()
	var next_report := 15000
	while (not main.world.is_generated or not main.player.spawned) and Time.get_ticks_msec() - started < 180000:
		if Time.get_ticks_msec() - started >= next_report:
			print("BIOMECAP waiting %ds generated=%s spawned=%s chunks=%d meshed=%d" % [next_report / 1000, str(main.world.is_generated), str(main.player.spawned), main.world.chunk_records.size(), main.world.meshed_chunk_count])
			next_report += 15000
		await process_frame
	world = main.world
	player = main.player
	if world == null or player == null or not world.is_generated or not player.spawned:
		print("BIOMECAP FAIL: world or player never became ready")
		quit(1)
		return
	camera = player.get_node("Camera3D") as Camera3D
	player.god_mode = true
	player.set_physics_process(false)
	main.get_node("HUD/DebugReadout").visible = false
	# set_time_hours() maps 12:00 onto the middle of the whole 24-minute cycle,
	# which is night here. Set the middle of the actual configured day phase.
	main.cycle.restore_time(DayNightCycle.CONFIG.day_seconds * 0.5)
	await _wait(1.5)

	var shots := [
		["forest", BiomeManager.MIRE],
		["desert", BiomeManager.DESERT],
		["jungle", BiomeManager.HUSH],
		["snow", BiomeManager.FROST],
		["mushroom", BiomeManager.MUSHROOM],
	]
	var evil := BiomeManager.CRIMSON if BiomeManager.evil_mode() == "crimson" else BiomeManager.CORRUPTION
	shots.append(["evil", evil])

	for shot in shots:
		var shot_name: String = shot[0]
		var biome: int = shot[1]
		var center := _find_clear_center(biome)
		var style := "jungle" if biome == BiomeManager.HUSH else "default"
		_frame_column(center.x, center.y, 18.0, style)
		main.cycle.restore_time(DayNightCycle.CONFIG.day_seconds * 0.5)
		await _wait(6.0)
		await _capture(shot_name, "biome=%d center=%d,%d name=%s" % [biome, center.x, center.y, BiomeManager.biome_name(biome)])

	# Enable the gated Hallow only after the base surface shots so it cannot
	# recolor Snow/Crimson border trees during their captures.
	BiomeManager.set_hallow_enabled(true)
	var hallow_center := _find_clear_center(BiomeManager.HALLOW)
	_frame_column(hallow_center.x, hallow_center.y, 18.0, "default")
	main.cycle.restore_time(DayNightCycle.CONFIG.day_seconds * 0.5)
	await _wait(6.0)
	await _capture("hallow", "center=%d,%d" % [hallow_center.x, hallow_center.y])

	await _capture_sky_island()

	# One cave shot: find a 3-high air pocket with a solid floor near spawn.
	var cave := Vector3i.ZERO
	var found := false
	var air := world.air_id
	for y in range(150, 70, -4):
		for radius in range(0, 33, 4):
			for dx in range(-radius, radius + 1, 4):
				for dz in range(-radius, radius + 1, 4):
					var cell := Vector3i(64 + dx, y, 64 + dz)
					if int(world.get_block_id(cell)) != air or int(world.get_block_id(cell + Vector3i.UP)) != air:
						continue
					if int(world.get_block_id(cell + Vector3i.UP * 2)) != air:
						continue
					if not world.is_solid(cell + Vector3i.DOWN):
						continue
					cave = cell
					found = true
					break
				if found:
					break
			if found:
				break
		if found:
			break
	if found:
		world.set_generation_focus(cave)
		player.position = Vector3(float(cave.x) + 0.5, float(cave.y) + 0.1, float(cave.z) + 0.5)
		player.velocity = Vector3.ZERO
		camera.global_position = Vector3(float(cave.x) + 0.5, float(cave.y) + 1.2, float(cave.z) + 0.5)
		camera.rotation = Vector3(-0.05, 0.7, 0.0)
		world.set_flashlight_enabled(true)
		await _wait(12.0)
		await _capture("underground", "cell=%d,%d,%d" % [cave.x, cave.y, cave.z])
	else:
		print("BIOMECAP underground SKIPPED: no cave pocket found")

	# Deep layer: place the camera in the open Underworld air above the lava sea.
	world.set_generation_focus(Vector3i(64, 22, 64))
	player.position = Vector3(64.5, 22.0, 64.5)
	player.velocity = Vector3.ZERO
	camera.global_position = Vector3(64.5, 23.2, 64.5)
	camera.rotation = Vector3(-0.04, 0.6, 0.0)
	world.set_flashlight_enabled(true)
	await _wait(12.0)
	await _capture("underworld", "cell=64,22,64")

	quit(0)
