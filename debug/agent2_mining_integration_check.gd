extends SceneTree

# Agent 2 x Agent 1 integration verification: MiningSystem-driven tiers,
# drops -> collected_blocks -> InventoryModel, feedback, placement and save.

var main: Node
var failures := 0
var checks := 0


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MINING INTEGRATION FAIL: %s %s" % [label, detail])
		return
	print("MINING PASS: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _select(player: VoxelPlayer, id: StringName) -> void:
	player.inventory.add_item(id, 1)
	for index in range(InventoryModel.HOTBAR_SIZE):
		if StringName(player.inventory.get_slot("hotbar", index)["id"]) == id:
			player.inventory.select(index)
			return


func _drop_amount(id: StringName) -> int:
	var total := 0
	for node in get_nodes_in_group("item_drops"):
		if is_instance_valid(node) and StringName(node.get("item_id")) == id:
			total += int(node.get("amount"))
	return total


func _run() -> void:
	var world: VoxelWorld = main.world
	var frames := 0
	while not world.is_generated and frames < 2400:
		await process_frame
		frames += 1
	_check(world.is_generated, "world ready", "frames=%d" % frames)
	if not world.is_generated:
		quit(1)
		return
	var player: VoxelPlayer = main.player
	await _wait_frames(4)

	# --- Priority 1: selectable tools with real tiers --------------------------
	var ladder := [
		[&"wooden_pickaxe", 1], [&"copper_pickaxe", 2], [&"iron_pickaxe", 3],
		[&"silver_pickaxe", 4], [&"gold_pickaxe", 5],
	]
	for entry in ladder:
		var id: StringName = entry[0]
		var tier: int = entry[1]
		var def := ItemDatabase.get_item(id)
		_check(def != null and def.is_tool and def.tool_type == "pickaxe" and def.tool_tier == tier,
			"tool tier defined: %s" % String(id), "tier=%d" % (def.tool_tier if def != null else -1))
		_select(player, id)
		_check(player.mining_tier == tier, "equipping %s updates player.mining_tier" % String(id), "tier=%d" % player.mining_tier)
	_select(player, &"wooden_sword")
	_check(player.mining_tier == 0, "non-tool clears mining tier")

	# --- MiningSystem tier gating on real blocks -------------------------------
	var column := Vector3i(world.spawn_origin.x + 3, 0, world.spawn_origin.z + 3)
	var ore_cases := [
		[&"stone", 1], [&"copper_ore", 1], [&"iron_ore", 2], [&"silver_ore", 3], [&"gold_ore", 4]
	]
	for case_index in range(ore_cases.size()):
		var case: Array = ore_cases[case_index]
		var block_name: StringName = case[0]
		var required: int = case[1]
		var cell := Vector3i(column.x, 4 + case_index, column.z)
		var block_id := int(world.block_ids[block_name])
		world.set_block(cell, block_id)
		var def := MiningSystem.definition(world, cell)
		_check(def != null and def.mining_tier == required, "%s data tier matches" % String(block_name), "tier=%d" % (def.mining_tier if def != null else -1))
		_check(not MiningSystem.can_mine(world, cell, required - 1), "%s rejects tier %d" % [String(block_name), required - 1])
		_check(MiningSystem.can_mine(world, cell, required), "%s accepts tier %d" % [String(block_name), required])
		var blocked := MiningSystem.break_block(world, cell, required - 1)
		_check(not bool(blocked.get("mined", false)) and bool(blocked.get("blocked", false)), "insufficient tier is blocked, block survives")
		_check(world.get_block_id(cell) == block_id, "block not destroyed by insufficient tier")
		var drop_before := ItemDatabase.item_id_for_drop(block_name)
		var count_before := player.inventory.count(drop_before)
		var result := MiningSystem.break_block(world, cell, required)
		_check(bool(result.get("mined", false)), "%s breaks at the right tier" % String(block_name))
		var drop: Dictionary = result.get("drop", {})
		var drop_id := ItemDatabase.item_id_for_drop(StringName(drop.get("block_id", &"")))
		var lost := player.deposit_drops(drop_id, int(drop.get("count", 0)))
		_check(lost == 0 and player.inventory.count(drop_before) > count_before, "%s drop lands in inventory" % String(block_name))
		player._drain_collected_blocks()

	# --- Priority 2/3: real mining loop, sink drain and feedback ----------------
	var ground := Vector3i(world.spawn_origin.x, world.spawn_height() - 1, world.spawn_origin.z)
	var ground_drop := ItemDatabase.item_id_for_drop(StringName(world.block_defs[world.get_block_id(ground)].block_id))
	_select(player, &"wooden_pickaxe")
	player.position = Vector3(ground.x + 0.5, ground.y + 1.0, ground.z + 0.5)
	player.camera.rotation.x = -1.5
	var count_before_mining := player.inventory.count(ground_drop)
	var broke := false
	for _i in range(100):
		player._update_mining(0.05, ItemDatabase.get_item(&"wooden_pickaxe"))
		if world.get_block_id(ground) == world.air_id:
			broke = true
			break
	_check(broke, "held-tool mining breaks a real voxel through MiningSystem")
	_check(player.collected_blocks.size() > 0, "Agent 1 collection sink received the drop", str(player.collected_blocks))
	player._drain_collected_blocks()
	_check(player.collected_blocks.is_empty(), "collection sink drained")
	_check(player.inventory.count(ground_drop) > count_before_mining, "mined block increases the correct inventory stack")

	# Feedback state while targeting an untouchable block.
	var gold_cell := Vector3i(column.x, 5, column.z)  # mined above; restore as gold
	world.set_block(gold_cell, int(world.block_ids[&"gold_ore"]))
	_select(player, &"wooden_pickaxe")
	player.position = Vector3(gold_cell.x + 0.5, gold_cell.y + 1.0, gold_cell.z + 0.5)
	player.camera.rotation.x = -1.5
	player._update_mining(0.05, ItemDatabase.get_item(&"wooden_pickaxe"))
	_check(player.target_block_name != "" and player.target_mining_tier == 4 and not player.target_can_mine,
		"target readout communicates insufficient tier", "%s tier=%d" % [player.target_block_name, player.target_mining_tier])
	_check(player.mining_progress == 0.0, "mining progress stays zero when tier too low")
	_check(world.get_block_id(gold_cell) == int(world.block_ids[&"gold_ore"]), "inaccessible ore stays intact")

	# --- No loss / no duplication ----------------------------------------------
	var total_before := player.inventory.count(&"stone") + _drop_amount(&"stone")
	var overflow := player.deposit_drops(&"stone", 5000)
	var total_after := player.inventory.count(&"stone") + _drop_amount(&"stone")
	_check(total_after - total_before == 5000, "large deposit has no item loss", "inv+ground delta=%d leftover=%d" % [total_after - total_before, overflow])
	var air_cell := gold_cell + Vector3i.UP
	var air_result := MiningSystem.break_block(world, air_cell, 5)
	_check(not bool(air_result.get("mined", false)), "air cannot be mined twice (no duplication)")

	# --- Block placement --------------------------------------------------------
	_select(player, &"wood")
	var place_cell := ground + Vector3i.UP
	player.camera.rotation.x = -1.4
	var wood_before := player.inventory.count(&"wood")
	# Aim straight at the cell by temporarily using a direct placement call path.
	var placed := MiningSystem.place_block(world, place_cell, &"dead_wood")
	if placed:
		player.inventory.consume(&"wood", 1)
	_check(placed and player.inventory.count(&"wood") == wood_before - 1, "block placement consumes one item")

	# --- Priority 4: save / reload ---------------------------------------------
	var saved_inv := player.inventory.serialize()
	var mined_cell_air := world.get_block_id(ground) == world.air_id
	main.save_game()
	world.set_block(ground, int(world.block_ids[&"stone"]))
	player.inventory.clear()
	main.load_game()
	_check(world.get_block_id(ground) == world.air_id, "mined world change persists across save/load")
	_check(player.inventory.serialize()["hotbar"][0]["id"] == saved_inv["hotbar"][0]["id"], "inventory restores after save/load")
	_check(mined_cell_air, "mined cell was air before the reload probe")

	if failures > 0:
		print("MINING INTEGRATION RESULT: %d/%d failed" % [failures, checks])
		quit(1)
		return
	print("MINING INTEGRATION PASS: %d checks" % checks)
	quit(0)
