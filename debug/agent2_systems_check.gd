extends SceneTree

# Agent 2 systems verification that does not depend on Agent 3's HUD script.
# Boots the real main scene tree with main.gd detached, so VoxelWorld, Player
# and all Agent 2 gameplay systems run against the canonical 160-block world.

var failures := 0
var checks := 0


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("AGENT2 FAIL: %s %s" % [label, detail])
		return
	print("AGENT2 PASS: %s %s" % [label, detail])


func _initialize() -> void:
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	main.set_script(null)  # HUD script is mid-edit by Agent 3; bypass orchestration only.
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	var world: VoxelWorld = main.get_node("VoxelWorld") as VoxelWorld
	var player: VoxelPlayer = main.get_node("Player") as VoxelPlayer
	var frames := 0
	while not world.is_generated and frames < 6000:
		await process_frame
		frames += 1
	_check(world.is_generated, "world streaming ready", "frames=%d" % frames)
	if not world.is_generated:
		quit(1)
		return
	await process_frame
	_check(player.inventory != null and player.statuses != null and player.progression != null and player.weapons != null,
		"Agent 2 systems initialised on the real Player")

	# --- items / crafting data -------------------------------------------------
	var required := [&"wood", &"stone", &"copper_ore", &"iron_ore", &"silver_ore", &"gold_ore",
		&"coal", &"copper_bar", &"iron_bar", &"silver_bar", &"gold_bar", &"wooden_pickaxe",
		&"copper_pickaxe", &"iron_pickaxe", &"silver_pickaxe", &"gold_pickaxe", &"wooden_axe",
		&"wooden_sword", &"wooden_bow", &"apprentice_staff", &"torch", &"healing_salve",
		&"copper_helmet", &"copper_chestplate", &"copper_leggings"]
	for id in required:
		_check(ItemDatabase.has(id), "item defined: %s" % String(id))
	_check(RecipeDatabase.all().size() >= 26, "recipes loaded", "count=%d" % RecipeDatabase.all().size())
	var recipes_valid := true
	for recipe in RecipeDatabase.all():
		for id in recipe.ingredients.keys():
			if not ItemDatabase.has(StringName(id)):
				recipes_valid = false
		for id in recipe.outputs.keys():
			if not ItemDatabase.has(StringName(id)):
				recipes_valid = false
	_check(recipes_valid, "every recipe ingredient/output resolves to an item")

	# Every mineable block drop must resolve to a real item (no nameless drops).
	var unmapped: Array[String] = []
	for def in world.block_defs:
		var drop_id: StringName = def.drop_block_id if def.drop_block_id != &"" else def.block_id
		var item_id := ItemDatabase.item_id_for_drop(drop_id)
		if item_id == &"air" or item_id == &"water" or item_id == &"lava" or item_id == &"":
			continue
		if not ItemDatabase.has(item_id):
			unmapped.append(String(drop_id))
	_check(unmapped.is_empty(), "all block drops map to item definitions", "unmapped=%s" % str(unmapped))

	# --- tool tiers ------------------------------------------------------------
	var ladder := [[&"wooden_pickaxe", 1], [&"copper_pickaxe", 2], [&"iron_pickaxe", 3],
		[&"silver_pickaxe", 4], [&"gold_pickaxe", 5]]
	for entry in ladder:
		var id: StringName = entry[0]
		var tier: int = entry[1]
		player.inventory.add_item(id, 1)
		for index in range(InventoryModel.HOTBAR_SIZE):
			if StringName(player.inventory.get_slot("hotbar", index)["id"]) == id:
				player.inventory.select(index)
				break
		_check(player.mining_tier == tier, "equipping %s sets mining_tier" % String(id), "tier=%d" % player.mining_tier)

	# --- mining rules against canonical block data -----------------------------
	var column := Vector3i(world.spawn_origin.x + 3, 0, world.spawn_origin.z + 3)
	var surface := world.spawn_height()
	var cases := [[&"stone", 1], [&"copper_ore", 1], [&"iron_ore", 2], [&"silver_ore", 3], [&"gold_ore", 4]]
	for index in range(cases.size()):
		var name: StringName = cases[index][0]
		var needed: int = cases[index][1]
		var cell := Vector3i(column.x, surface - 2 - index * 3, column.z)
		var id := int(world.block_ids[name])
		world.set_block(cell, id)
		var def := MiningSystem.definition(world, cell)
		_check(def != null and def.mining_tier == needed, "%s mining tier" % String(name))
		_check(not MiningSystem.can_mine(world, cell, needed - 1), "%s rejects lower tier" % String(name))
		var blocked := MiningSystem.break_block(world, cell, needed - 1)
		_check(not bool(blocked.get("mined", false)) and world.get_block_id(cell) == id, "low tier cannot break %s" % String(name))
		var drop := MiningSystem.drop_for(world, cell)
		var item_id := ItemDatabase.item_id_for_drop(StringName(drop.get("block_id", &"")))
		var before := player.inventory.count(item_id)
		var result := MiningSystem.break_block(world, cell, needed)
		player.deposit_drops(StringName(drop.get("block_id", &"")), int(drop.get("count", 0)))
		player._drain_collected_blocks()
		_check(bool(result.get("mined", false)) and player.inventory.count(item_id) > before,
			"%s mined and deposited as %s" % [String(name), String(item_id)])

	# --- inventory stacking / hotbar / equipment --------------------------------
	var inv := InventoryModel.new()
	var limit := ItemDatabase.stack_limit(&"stone")
	var added := inv.add_item(&"stone", limit + 17)
	_check(added == 0 and inv.get_slot("hotbar", 0)["amount"] == limit and inv.get_slot("hotbar", 1)["amount"] == 17,
		"stacking respects the item limit")
	_check(inv.split_stack("hotbar", 0, "main", 0, 25) and inv.get_slot("main", 0)["amount"] == 25, "stack splitting")
	inv.add_item(&"copper_chestplate", 1)
	var slot := -1
	for index in range(InventoryModel.HOTBAR_SIZE):
		if StringName(inv.get_slot("hotbar", index)["id"]) == &"copper_chestplate":
			slot = index
	_check(slot >= 0 and inv.equip("chest", "hotbar", slot) and inv.total_armor() == 3, "equipment changes defence statistic")
	var saved_inv := inv.serialize()
	var restored := InventoryModel.new()
	_check(restored.deserialize(saved_inv) and restored.count(&"stone") == inv.count(&"stone"), "inventory save round-trip")
	var total_before := player.inventory.count(&"stone") + _drop_total(&"stone")
	var leftover := player.deposit_drops(&"stone", 4000)
	var total_after := player.inventory.count(&"stone") + _drop_total(&"stone")
	_check(total_after - total_before == 4000, "overflow is dropped, never lost", "leftover=%d" % leftover)

	# --- crafting ---------------------------------------------------------------
	var craft := CraftingSystem.new(inv, ProgressionSystem.new(), WorldGateway.new(world))
	var torch_recipe := RecipeDatabase.get_recipe(&"craft_torch")
	inv.add_item(&"wood", 4)
	inv.add_item(&"coal", 4)
	var torches := inv.count(&"torch")
	_check(craft.can_craft(torch_recipe) and craft.craft(torch_recipe) and inv.count(&"torch") == torches + 4,
		"torch recipe crafts from data")

	# --- combat distinctness ----------------------------------------------------
	var sword := ItemDatabase.get_item(&"wooden_sword")
	var bow := ItemDatabase.get_item(&"wooden_bow")
	var staff := ItemDatabase.get_item(&"apprentice_staff")
	_check(sword.attack.kind == "melee" and bow.attack.kind == "ranged" and staff.attack.kind == "magic" and staff.attack.pierce > 0,
		"weapon categories are behaviourally distinct")

	# --- save contract ----------------------------------------------------------
	var state := player.serialize_gameplay_state()
	var stone_count := player.inventory.count(&"stone")
	player.inventory.clear()
	player.deserialize_gameplay_state(state)
	_check(player.inventory.count(&"stone") == stone_count, "player gameplay state round-trips")
	var saved_inventory: Dictionary = state.get("inventory", {})
	_check(state.has("inventory") and saved_inventory.has("equipment") and saved_inventory.has("hotbar")
		and state.has("progression") and state.has("camera_mode"),
		"save contract includes every gameplay section")

	if failures > 0:
		print("AGENT2 SYSTEMS RESULT: %d/%d failed" % [failures, checks])
		quit(1)
		return
	print("AGENT2 SYSTEMS PASS: %d checks" % checks)
	quit(0)


func _drop_total(id: StringName) -> int:
	var total := 0
	for node in get_nodes_in_group("item_drops"):
		if is_instance_valid(node) and StringName(node.get("item_id")) == id:
			total += int(node.get("amount"))
	return total
