extends SceneTree

# Checks that building works the plain Terraria/Minecraft way: pick a block in the
# hotbar, look at a surface, right click, and one block appears on the face you are
# looking at. No projector, no rectangle drag, no depth setting.

var _failures: Array[String] = []

func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s (%s)" % [name, detail])
	else:
		_failures.append(name)
		print("FAIL %s (%s)" % [name, detail])


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var world = scene.get_node_or_null("VoxelWorld")
	var player = scene.get_node_or_null("Player")
	if world == null or player == null:
		print("BLOCK PLACEMENT CHECK FAIL: missing world or player")
		quit(1)
		return
	var camera: Camera3D = player.get_node("Camera3D")
	var frames := 0
	while (not bool(world.is_generated) or not bool(player.spawned)) and frames < 900:
		await process_frame
		frames += 1
	for _settle in range(6):
		await process_frame

	var inventory = player.inventory
	# Find a hotbar slot that holds a placeable block.
	var slot := -1
	var block_item := ""
	for index in range(inventory.HOTBAR_SIZE):
		var stack: Dictionary = inventory.get_slot("hotbar", index)
		if inventory.is_empty(stack):
			continue
		var def = ItemDatabase.get_item(stack["id"])
		if def != null and String(def.place_block) != "":
			slot = index
			block_item = String(stack["id"])
			break
	if slot < 0:
		print("BLOCK PLACEMENT CHECK FAIL: no placeable block in the hotbar")
		quit(1)
		return
	inventory.select(slot)
	await process_frame

	# Look straight down at the ground under the player.
	camera.rotation = Vector3(-0.85, 0.0, 0.0)
	await process_frame
	var hit: Dictionary = player._voxel_raycast(player.REACH)
	if hit.is_empty():
		print("BLOCK PLACEMENT CHECK FAIL: no surface under the player")
		quit(1)
		return
	var target: Vector3i = hit["previous_air"]
	_check("looking down finds an empty cell on the surface",
		world.get_block_id(target) == world.air_id, "cell=%s" % str(target))

	var before: int = int(inventory.count(StringName(block_item)))

	var before_snapshot := {}
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			for dz in range(-3, 4):
				var cell := target + Vector3i(dx, dy, dz)
				before_snapshot[cell] = world.get_block_id(cell)

	Input.action_press("place_block")
	await process_frame
	await process_frame
	Input.action_release("place_block")
	for _settle in range(4):
		await process_frame

	var placed_id: int = world.get_block_id(target)
	var placed_name := ""
	if placed_id >= 0 and placed_id < world.block_defs.size():
		placed_name = String(world.block_defs[placed_id].block_id)
	_check("right click puts the held block on the aimed face",
		placed_id != world.air_id, "cell=%s -> %s" % [str(target), placed_name])

	var after: int = int(inventory.count(StringName(block_item)))
	_check("placing spends exactly one block", before - after == 1, "%d -> %d" % [before, after])

	# Only the aimed cell may change: no rectangle, no extrusion depth.
	var changed := 0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			for dz in range(-3, 4):
				var cell := target + Vector3i(dx, dy, dz)
				if world.get_block_id(cell) == before_snapshot.get(cell, world.air_id):
					continue
				changed += 1
				if cell != target:
					_check("only the aimed cell changed", false, "extra cell %s" % str(cell))
					changed = -999
					break
			if changed < 0:
				break
		if changed < 0:
			break
	_check("only the aimed cell changed", changed == 1, "changed cells=%d" % changed)

	# The cell the player stands in stays free.
	var feet := Vector3i(floori(player.position.x), floori(player.position.y + 0.1), floori(player.position.z))
	_check("the player's own cell is never filled", world.get_block_id(feet) == world.air_id, "cell=%s" % str(feet))

	if _failures.is_empty():
		print("BLOCK PLACEMENT CHECK PASS")
		quit(0)
	else:
		print("BLOCK PLACEMENT CHECK FAIL: %s" % ", ".join(_failures))
		quit(1)
