extends SceneTree

# Trees are meshes, not voxels, so their hit test and felling are separate from
# block mining. This checks the whole path: aim at a trunk and it is picked,
# a non-axe is refused, an axe fells the tree and pays wood, the tree does not
# come back when the streaming region rebuilds, and the stump block is left in
# place so felling never digs a pit.

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("TREE PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("TREE FAIL: %s %s" % [label, detail])


func _init() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var world: VoxelWorld = main.world
	var frames := 0
	while not world.is_generated and frames < 1800:
		await process_frame
		frames += 1
	_check(world.is_generated, "world generated", "frames=%d" % frames)
	if not world.is_generated:
		quit(1)
		return
	var vegetation: WorldVegetation = world.vegetation
	_check(vegetation != null and vegetation.site_slots.size() > 0, "trees exist around spawn",
		"sites=%d" % (vegetation.site_slots.size() if vegetation != null else -1))
	if vegetation == null or vegetation.site_slots.is_empty():
		quit(1)
		return

	# Only sites in loaded chunks can have their base block inspected.
	var cell := Vector3i(1 << 30, 0, 1 << 30)
	for attempt in range(600):
		for site_variant in vegetation.site_slots.keys():
			var site: Vector3i = site_variant
			if world.is_chunk_ready(world._chunk_of(site)):
				cell = site
				break
		if cell.x != 1 << 30:
			break
		await process_frame
	_check(cell.x != 1 << 30, "found a tree in a loaded chunk", "cell=%s" % str(cell))
	if cell.x == 1 << 30:
		quit(1)
		return
	var centre := Vector3(float(cell.x) + 0.5, float(cell.y) + 1.2, float(cell.z) + 0.5)
	var origin := centre + Vector3(3.0, 0.0, 0.0)
	var aimed := vegetation.raycast_tree(origin, Vector3(-1.0, 0.0, 0.0), 6.0)
	_check(not aimed.is_empty() and Vector3i(aimed.get("cell", Vector3i.ZERO)) == cell,
		"aiming at a trunk picks that tree", "cell=%s hit=%s" % [str(cell), str(aimed.get("cell", "none"))])

	# Looking well above the canopy must not pick the tree.
	var high := vegetation.raycast_tree(origin + Vector3(0.0, 40.0, 0.0), Vector3(-1.0, 0.0, 0.0), 6.0)
	_check(high.is_empty(), "aiming over the canopy is not a trunk hit")

	var base_before := world.get_block_id(cell)
	var base_name := String(world.block_defs[base_before].block_id) if base_before >= 0 else "?"
	_check(base_before > 0, "the tree base block is readable", "id=%d name=%s" % [base_before, base_name])

	var player = main.player
	var axe := ItemDatabase.get_item(&"wooden_axe")
	var sword := ItemDatabase.get_item(&"wooden_sword")
	player.mining_progress = 0.0
	player._chop_tree(0.1, sword, aimed)
	_check(not player.target_can_mine, "a sword cannot fell a tree")
	player.mining_progress = 0.0
	player._chop_tree(0.1, axe, aimed)
	_check(player.target_can_mine, "an axe can fell a tree")
	_check(player.target_block_name == "Tree", "the target readout names the tree",
		"name=%s" % player.target_block_name)

	# Hold the axe on it until the swing finishes.
	var swings := 0
	player.mining_progress = 0.0
	while player.mining_progress > 0.0 or swings == 0:
		player._chop_tree(0.25, axe, aimed)
		swings += 1
		if swings > 40:
			break
	var felled: bool = vegetation.felled_sites.has(cell)
	_check(felled, "the tree is recorded as felled", "swings=%d" % swings)
	_check(not vegetation.site_slots.has(cell), "the felled tree leaves the live site table")
	var owed := int(player._pending_tree_loot.get(cell, 0))
	_check(owed > 0, "the felled tree still owes its wood until it lands", "wood=%d" % owed)
	_check(int(player.collected_blocks.get(&"wood", 0)) == 0,
		"nothing is added to the inventory while the trunk is still falling")

	# Land the trunk and check the wood arrives as real drops on the ground.
	var landed := 0
	while not vegetation.tree_falls.is_empty() and landed < 400:
		vegetation._process(1.0 / 60.0)
		landed += 1
	var drops: Array = []
	var drop_total := 0
	for node in main.get_children():
		if node is ItemEntity and (node as ItemEntity).item_id == &"wood":
			drops.append(node)
			drop_total += (node as ItemEntity).amount
	_check(not drops.is_empty(), "the landing tree drops wood pickups", "stacks=%d frames=%d" % [drops.size(), landed])
	_check(drop_total == owed, "every owed log is dropped", "dropped=%d owed=%d" % [drop_total, owed])
	_check(not player._pending_tree_loot.has(cell), "the owed wood is cleared once it drops")

	# Walking over the logs must collect them, which is the whole point of real drops.
	var carried_before := int(player.inventory.count(&"wood"))
	if not drops.is_empty():
		player.global_position = (drops[0] as ItemEntity).global_position
	# Headless frames are far faster than real time, and a drop has a pickup delay.
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		# Stand on a log every frame: the drop drifts, and the player has physics.
		for node in drops:
			if is_instance_valid(node):
				player.global_position = (node as ItemEntity).global_position
				break
		await process_frame
	var carried_after := int(player.inventory.count(&"wood"))
	_check(carried_after > carried_before, "standing on the dropped logs picks them up",
		"wood %d -> %d" % [carried_before, carried_after])
	_check(world.get_block_id(cell) == base_before,
		"the base block is untouched so there is no pit", "before=%d after=%d" % [base_before, world.get_block_id(cell)])

	# A streaming rebuild must not resurrect it.
	vegetation.region_center = Vector2i(1 << 30, 1 << 30)
	vegetation.update_region(world.world_seed, Vector2i(cell.x, cell.z), 96)
	_check(not vegetation.site_slots.has(cell), "a streaming rebuild keeps the tree felled")

	if failures > 0:
		printerr("TREE FELLING CHECK FAIL: %d failure(s)" % failures)
		quit(1)
		return
	print("TREE FELLING CHECK PASS: trunk picking, axe gate, felling and wood drops verified")
	quit(0)
