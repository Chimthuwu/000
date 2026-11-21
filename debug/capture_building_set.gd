extends SceneTree

# Visual evidence for the crafting-station building set. Builds a real little
# house out of the new blocks beside the player, then photographs it from two
# angles so the furniture silhouettes, glass, bricks, platforms and door can be
# judged in the running game.
#   Godot --fixed-fps 60 --path . --script res://debug/capture_building_set.gd

const SHOT_DIR := "res://debug/evidence"

var main: Node
var world: VoxelWorld
var player: VoxelPlayer
var camera: Camera3D


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
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
	var path := "%s/build_%s.png" % [SHOT_DIR, shot_name]
	var error := image.save_png(path)
	print("BUILDCAP %s %s error=%d image=%s" % [shot_name, detail, error, path])


func _put(cell: Vector3i, id: StringName) -> void:
	var block_id := int(world.block_ids[id])
	world.set_block(cell, block_id)


func _run() -> void:
	world = main.get_node("VoxelWorld")
	player = main.get_node("Player")
	camera = player.get_node("Camera3D")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 3000:
		await process_frame
		frames += 1
	await _wait(1.5)
	player.set_process(false)

	# --- Build site on flat, tree-free ground ahead of the player. ---
	var px := floori(player.global_position.x)
	var pz := floori(player.global_position.z)
	var origin := Vector3i(px + 8, 0, pz + 8)
	for dz in range(-8, 13):
		for dx in range(-8, 13):
			var cx := px + dx
			var cz := pz + dz
			var clear := true
			var sites := WorldGenerator.collect_tree_sites_region(world.world_seed, cx - 4, cz - 4, cx + 4, cz + 4)
			for site in sites:
				if Vector2(float(site["x"]) - float(cx), float(site["z"]) - float(cz)).length() < 5.0:
					clear = false
					break
			if not clear:
				continue
			origin = Vector3i(cx, world.get_surface_height(cx, cz), cz)
			break
		if origin.x != px + 8:
			break
	origin.y = world.get_surface_height(origin.x, origin.z)
	world.set_generation_focus(origin)
	await _wait(1.0)
	origin.y = world.get_surface_height(origin.x, origin.z)
	print("BUILDCAP site origin=%s surface=%d" % [str(origin), origin.y])

	# Flatten a 9x9 pad so the house sits level.
	for dx in range(-1, 8):
		for dz in range(-1, 7):
			var h := world.get_surface_height(origin.x + dx, origin.z + dz)
			for y in range(origin.y, h + 1):
				_put(Vector3i(origin.x + dx, y, origin.z + dz), &"air")
			_put(Vector3i(origin.x + dx, origin.y - 1, origin.z + dz), &"stone_brick")
			_put(Vector3i(origin.x + dx, origin.y - 2, origin.z + dz), &"stone_brick")

	# Brick floor and back wall with a glass window.
	for x in range(0, 6):
		for z in range(0, 4):
			_put(origin + Vector3i(x, 0, z), &"stone_brick")
	for x in range(0, 6):
		for y in range(1, 5):
			_put(origin + Vector3i(x, y, 0), &"stone_brick")
	_put(origin + Vector3i(2, 2, 0), &"glass")
	_put(origin + Vector3i(3, 2, 0), &"glass")
	# Side wall with a doorway gap.
	for z in range(1, 4):
		for y in range(1, 5):
			_put(origin + Vector3i(0, y, z), &"stone_brick")
	_put(origin + Vector3i(0, 1, 2), &"air")
	_put(origin + Vector3i(0, 2, 2), &"air")
	_put(origin + Vector3i(0, 1, 2), &"wood_door")
	_put(origin + Vector3i(0, 2, 2), &"wood_door")
	# Platform deck along the open front.
	for x in range(0, 6):
		_put(origin + Vector3i(x, 1, 4), &"wood_platform")
	# Stations lined up inside.
	_put(origin + Vector3i(1, 1, 1), &"workbench")
	_put(origin + Vector3i(3, 1, 1), &"furnace")
	_put(origin + Vector3i(4, 1, 3), &"anvil")
	_put(origin + Vector3i(5, 1, 1), &"chest")
	# A torch so the interior is readable at any time of day.
	_put(origin + Vector3i(2, 3, 1), &"torch")
	await _wait(1.2)

	# --- Exterior three-quarter shot. ---
	camera.global_position = Vector3(origin.x + 8.8, origin.y + 4.6, origin.z - 6.4)
	camera.look_at(Vector3(origin.x + 2.6, origin.y + 1.6, origin.z + 2.2), Vector3.UP)
	camera.far = 120.0
	await _wait(0.8)
	await _capture("house", "brick house, glass window, door and platform deck")

	# --- Stand in the doorway and open the crafting panel, which must now show
	# the stations that are physically in reach. ---
	var hud: GameHUD = main.get_node("HUD")
	player.set_process(true)
	player.global_position = Vector3(origin.x + 2.5, origin.y + 1.0, origin.z + 2.0)
	await _wait(0.6)
	player.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud._toggle_crafting()
	await _wait(0.6)
	print("BUILDCAP crafting_stations=%s" % ("" if hud.craft_station_label == null else hud.craft_station_label.text))
	await _capture("crafting", "crafting panel with physical stations in reach")
	hud._toggle_crafting()

	# --- Interior close-up of the stations. ---
	camera.global_position = Vector3(origin.x + 2.6, origin.y + 2.5, origin.z + 5.2)
	camera.look_at(Vector3(origin.x + 2.8, origin.y + 1.05, origin.z + 1.0), Vector3.UP)
	await _wait(0.8)
	await _capture("stations", "workbench, furnace, anvil and chest")

	quit(0)
