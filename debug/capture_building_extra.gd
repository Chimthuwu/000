extends SceneTree

# Visual evidence for the second building pass: a sealed brick room with a
# door, torch, chair, workbench and chest (the HUD house readout should show
# HOUSE READY), an open chest panel, and a wooden staircase outside.
#   Godot --fixed-fps 60 --path . --script res://debug/capture_building_extra.gd

const SHOT_DIR := "res://debug/evidence"

var main: Node
var world: VoxelWorld
var player: VoxelPlayer
var camera: Camera3D
var hud: GameHUD
var shot_camera: Camera3D


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


## Photographs need daylight and an unpaused game: with --fixed-fps the day
## cycle races through thousands of frames, so each shot resets the clock.
func _prepare_shot() -> void:
	main.pause_due_to_focus = false
	# set_time_hours maps the full 24 h onto the whole cycle, whose night alone
	# is 900 s, so "12:00" lands at midnight. Stay inside the 420 s day segment.
	var cycle := main.get_node("DayNightCycle")
	cycle.restore_time(cycle.CONFIG.day_seconds * 0.45)
	if hud != null and hud.paused:
		hud.resume_game()
	await _wait(0.25)


func _capture(shot_name: String, detail := "") -> void:
	await _prepare_shot()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/extra_%s.png" % [SHOT_DIR, shot_name]
	var error := image.save_png(path)
	print("EXTRACAP %s %s error=%d image=%s" % [shot_name, detail, error, path])


func _put(cell: Vector3i, id: StringName) -> void:
	world.set_block(cell, int(world.block_ids[id]))


func _run() -> void:
	world = main.get_node("VoxelWorld")
	player = main.get_node("Player")
	hud = main.get_node("HUD")
	camera = player.get_node("Camera3D")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 3000:
		await process_frame
		frames += 1
	await _wait(1.5)
	player.set_process(false)

	# Anchor the build to the spawn column, which is guaranteed Forest: the
	# player's own position is not reliable this early (spawn placement happens
	# after world generation) and far biomes fog the shot out.
	var spawn := world.spawn_origin
	var origin := Vector3i(spawn.x + 9, 0, spawn.z + 6)
	var highest := world.get_surface_height(origin.x, origin.z)
	for dx in range(-2, 10):
		for dz in range(-3, 9):
			highest = maxi(highest, world.get_surface_height(origin.x + dx, origin.z + dz))
	origin.y = highest
	world.set_generation_focus(origin)
	await _wait(1.2)
	print("EXTRACAP site origin=%s" % str(origin))

	# Flatten a pad with a carved approach so the door opens onto air.
	for dx in range(-2, 10):
		for dz in range(-3, 9):
			var h := world.get_surface_height(origin.x + dx, origin.z + dz)
			for y in range(origin.y, h + 1):
				_put(Vector3i(origin.x + dx, y, origin.z + dz), &"air")
			_put(Vector3i(origin.x + dx, origin.y - 1, origin.z + dz), &"stone_brick")
			_put(Vector3i(origin.x + dx, origin.y - 2, origin.z + dz), &"stone_brick")

	# 7 x 5 shell, three interior cells tall.
	for dx in range(0, 7):
		for dz in range(0, 5):
			_put(origin + Vector3i(dx, 0, dz), &"stone_brick")
			_put(origin + Vector3i(dx, 4, dz), &"stone_brick")
	for dx in range(0, 7):
		for dy in range(1, 4):
			_put(origin + Vector3i(dx, dy, 0), &"stone_brick")
			_put(origin + Vector3i(dx, dy, 4), &"stone_brick")
	for dz in range(1, 4):
		for dy in range(1, 4):
			_put(origin + Vector3i(0, dy, dz), &"stone_brick")
			_put(origin + Vector3i(6, dy, dz), &"stone_brick")
	# Window in the back wall.
	_put(origin + Vector3i(3, 2, 0), &"glass")
	_put(origin + Vector3i(2, 2, 0), &"glass")
	# Door in the south wall, facing the camera.
	_put(origin + Vector3i(3, 1, 4), &"air")
	_put(origin + Vector3i(3, 2, 4), &"air")
	_put(origin + Vector3i(3, 1, 4), &"wood_door")
	_put(origin + Vector3i(3, 2, 4), &"wood_door")
	# Furniture and light inside.
	_put(origin + Vector3i(1, 2, 1), &"torch")
	_put(origin + Vector3i(3, 3, 1), &"torch")
	_put(origin + Vector3i(5, 2, 1), &"torch")
	_put(origin + Vector3i(1, 2, 3), &"torch")
	_put(origin + Vector3i(2, 1, 1), &"chair")
	_put(origin + Vector3i(4, 1, 1), &"workbench")
	_put(origin + Vector3i(5, 1, 1), &"chest")

	# A wooden staircase climbing east, one block up per step, on a stone
	# footing so it reads as a real flight rather than floating blocks.
	for step in range(4):
		_put(origin + Vector3i(9 + step, step, 2), &"stone_brick")
		_put(origin + Vector3i(9 + step, step + 1, 2), &"wood_stairs_e")
	for step in range(4):
		_put(origin + Vector3i(9 + step, step + 2, 2), &"air")
	await _wait(1.2)

	# --- Exterior: house plus staircase. ---
	# The player's own camera is re-lerped toward the third-person rig every
	# frame, so the shots use a standalone camera parked where needed.
	player.set_process(false)
	player.set_physics_process(false)
	player.visible = false
	shot_camera = Camera3D.new()
	shot_camera.far = 140.0
	root.add_child(shot_camera)
	shot_camera.current = true
	shot_camera.global_position = Vector3(origin.x + 11.0, origin.y + 4.4, origin.z + 10.0)
	shot_camera.look_at(Vector3(origin.x + 3.5, origin.y + 1.6, origin.z + 2.0), Vector3.UP)
	await _wait(0.9)

	await _capture("stairs", "brick house with wooden staircase climbing east")

	# --- Interior with the house readout. ---
	# The player must stand inside for the HUD house readout.
	player.set_process(true)
	player.global_position = Vector3(origin.x + 3.5, origin.y + 1.0, origin.z + 2.2)
	await _wait(1.0)
	player.set_process(false)
	# Step the Guide out of the camera line so the furniture is readable; he is
	# still the resident the housing rule just moved in.
	if main._guide != null:
		main._guide.global_position = Vector3(origin.x + 4.7, origin.y + 1.0, origin.z + 2.7)
	shot_camera.global_position = Vector3(origin.x + 3.5, origin.y + 1.9, origin.z + 3.0)
	shot_camera.look_at(Vector3(origin.x + 3.5, origin.y + 0.9, origin.z + 0.5), Vector3.UP)
	await _wait(0.8)
	var report := HouseValidator.validate(world, Vector3i(floori(player.global_position.x), floori(player.global_position.y + 0.5), floori(player.global_position.z)))
	print("EXTRACAP interior_light chair=%d mid=%d" % [world.get_light_level(origin + Vector3i(2, 1, 1)), world.get_light_level(origin + Vector3i(3, 1, 2))])
	print("EXTRACAP house_label=%s visible=%s report=%s" % [hud.house_label.text, str(hud.house_label.visible), str(report)])
	await _capture("house", "interior with chair, workbench and chest; HUD house readout")

	# --- Chest panel. ---
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.open_chest(origin + Vector3i(5, 1, 1))
	player.containers.deposit(origin + Vector3i(5, 1, 1), &"stone", 34)
	player.containers.deposit(origin + Vector3i(5, 1, 1), &"torch", 6)
	hud._refresh_chest_panel()
	await _wait(0.6)
	print("EXTRACAP chest_visible=%s total=%d" % [str(hud.chest_visible), player.containers.total(origin + Vector3i(5, 1, 1))])
	await _capture("chest", "chest panel with stored stone and torches")
	hud.close_chest()

	quit(0)
