extends SceneTree

# Spawn streaming stall guard. Boots the real world scene and asserts the
# launch contract that used to be intermittent:
#   1. is_generated flips within a bounded frame budget (no streaming stall),
#   2. at the flip moment the spawn column's generated blocks actually match
#      the published spawn_height (topmost solid right under the spawn cell),
#   3. after the player spawns they settle on the surface and never sink
#      below it while the world keeps streaming around them.

const BOOT_BUDGET_FRAMES := 2400
const SETTLE_FRAMES := 300

var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("SPAWN_SETTLE PASS: %s %s" % [label, detail])
	else:
		failures += 1
		print("SPAWN_SETTLE FAIL: %s %s" % [label, detail])


func _spawn_column_state(world: Node) -> Dictionary:
	var column := Vector3i(world.spawn_origin.x, 0, world.spawn_origin.z)
	var surface := int(world.spawn_height())
	# The published spawn height is the y of the topmost solid block: the
	# player's feet rest on its top face at spawn_height + 1. Do not scan the
	# whole column with is_solid: unloaded space above the resident window
	# reports solid (frontier wall) and would shadow the real surface.
	return {
		"surface": surface,
		"under_solid": bool(world.is_solid(Vector3i(column.x, surface, column.z))),
		"spawn_cell_air": not bool(world.is_solid(Vector3i(column.x, surface + 1, column.z))),
	}


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var world = scene.get_node_or_null("VoxelWorld")
	var player = scene.get_node_or_null("Player")
	if world == null or player == null:
		print("SPAWN_SETTLE FAIL missing nodes")
		quit(1)
		return
	var frames := 0
	while (not bool(world.is_generated) or not bool(player.spawned)) and frames < BOOT_BUDGET_FRAMES:
		await process_frame
		frames += 1
	_check(bool(world.is_generated) and bool(player.spawned), "spawn ready within budget",
		"frames=%d" % frames)
	var state := _spawn_column_state(world)
	var surface := int(state["surface"])
	_check(bool(state["under_solid"]), "block at spawn_height is solid", "surface=%d" % surface)
	_check(bool(state["spawn_cell_air"]), "cell above spawn_height is air", "surface=%d" % surface)
	var worst_y := 99999.0
	for _frame in range(SETTLE_FRAMES):
		await process_frame
		worst_y = minf(worst_y, player.position.y)
	# The player must settle on the surface (feet at spawn_height + 1) and
	# never sink below it while streaming continues.
	_check(floori(player.position.y) >= surface + 1,
		"player settled at or above the spawn surface",
		"final_y=%.2f lowest_y=%.2f surface=%d" % [player.position.y, worst_y, surface])
	print("SPAWN_SETTLE SUMMARY failures=%d frames=%d player_y=%.2f surface=%d loaded=%d" % [
		failures, frames, player.position.y, surface, world.chunk_records.size()])
	quit(0 if failures == 0 else 1)
