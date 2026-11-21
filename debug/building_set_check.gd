extends SceneTree

## Verifies the crafting-station building set end to end: the block data and
## station metadata, the item/recipe chain, physical station proximity gating,
## placement of every new block, and the two-state door.

const COMPLETE := "BUILDING CHECK PASS: crafting stations and building set"

var main: Node
var failures := 0

const NEW_BLOCKS: Array[StringName] = [
	&"wood_platform", &"wood_door", &"wood_door_open", &"stone_brick",
	&"glass", &"workbench", &"furnace", &"anvil", &"chest",
]

const NEW_ITEMS: Array[StringName] = [
	&"wood_platform", &"wood_door", &"stone_brick", &"glass",
	&"workbench", &"furnace", &"anvil", &"chest",
]

const NEW_RECIPES: Array[StringName] = [
	&"craft_workbench", &"craft_furnace", &"craft_anvil", &"craft_wood_platform",
	&"craft_wood_door", &"craft_stone_brick", &"craft_glass", &"craft_chest",
]


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("BUILDING PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("BUILDING FAIL: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _run() -> void:
	var frames := 0
	while not main.world.is_generated and frames < 1800:
		await process_frame
		frames += 1
	_check(main.world.is_generated, "world generated", "frames=%d" % frames)

	var world: VoxelWorld = main.world
	var player: VoxelPlayer = main.player
	var inv: InventoryModel = player.inventory
	var cs: CraftingSystem = player.crafting

	# --- 1. Block data ---------------------------------------------------------
	for id in NEW_BLOCKS:
		_check(world.block_ids.has(id), "block registered", String(id))
	var workbench_def: BlockLightDef = world.block_defs[int(world.block_ids[&"workbench"])]
	var furnace_def: BlockLightDef = world.block_defs[int(world.block_ids[&"furnace"])]
	var anvil_def: BlockLightDef = world.block_defs[int(world.block_ids[&"anvil"])]
	_check(workbench_def.station == "workbench", "workbench declares its station")
	_check(furnace_def.station == "furnace", "furnace declares its station")
	_check(anvil_def.station == "anvil", "anvil declares its station")
	_check(workbench_def.passable and furnace_def.passable, "furniture is walk-through")
	_check(furnace_def.emitted_light > 0, "furnace emits light", "light=%d" % furnace_def.emitted_light)
	var glass_def: BlockLightDef = world.block_defs[int(world.block_ids[&"glass"])]
	_check(glass_def.attenuation == 0, "glass does not block light")

	# --- 2. Items and recipes --------------------------------------------------
	for id in NEW_ITEMS:
		var def := ItemDatabase.get_item(id)
		_check(def != null and def.place_block == id, "item places its block", String(id))
	for id in NEW_RECIPES:
		_check(RecipeDatabase.get_recipe(id) != null, "recipe exists", String(id))
	_check(RecipeDatabase.get_recipe(&"craft_furnace").station == "workbench", "furnace is crafted at a workbench")
	_check(RecipeDatabase.get_recipe(&"craft_glass").station == "furnace", "glass is smelted at a furnace")
	_check(RecipeDatabase.get_recipe(&"craft_anvil").station == "workbench", "anvil is crafted at a workbench")

	# --- 3. Station gating -----------------------------------------------------
	var pick_recipe := RecipeDatabase.get_recipe(&"craft_wooden_pickaxe")
	var iron_recipe := RecipeDatabase.get_recipe(&"smelt_iron")
	_check(not cs.station_available("workbench"), "no station before one is placed")
	_check(not cs.station_available("furnace"), "no furnace before one is placed")

	inv.add_item(&"wood", 40)
	inv.add_item(&"stone", 40)
	inv.add_item(&"coal", 10)
	inv.add_item(&"iron_ore", 9)
	inv.add_item(&"iron_bar", 6)
	inv.add_item(&"torch", 4)
	inv.add_item(&"desert_sand", 3)

	_check(cs.can_craft(RecipeDatabase.get_recipe(&"craft_workbench")), "workbench is hand-craftable")
	_check(cs.craft(RecipeDatabase.get_recipe(&"craft_workbench")), "workbench crafts")
	_check(inv.count(&"workbench") == 1, "workbench lands in the inventory")

	# Build the pad beside the player on ground we explicitly stream and clear,
	# so placement can never fail because a chunk was not loaded yet.
	# Centre the pad inside one chunk: every block this check places then lives
	# in the same streamed chunk as the pad, so streaming cannot split the test.
	var feet := Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
	feet.x = (feet.x / 16) * 16 + 8
	feet.z = (feet.z / 16) * 16 + 8
	feet.y = world.get_surface_height(feet.x, feet.z)
	var base := Vector3i(feet.x + 2, feet.y + 1, feet.z)
	world.set_generation_focus(base)
	var waited := 0
	while not world.is_chunk_loaded_at(base) and waited < 600:
		await process_frame
		waited += 1
	_check(world.is_chunk_loaded_at(base), "test pad chunk is loaded", "frames=%d" % waited)
	for dx in range(-1, 5):
		for dz in range(-1, 3):
			for dy in range(0, 3):
				var cell := base + Vector3i(dx, dy, dz)
				if world.get_block_id(cell) != world.air_id:
					world.set_block(cell, world.air_id)
				_check(world.get_block_id(cell) == world.air_id, "pad cell cleared", str(cell))
	await _wait_frames(20)
	player.global_position = Vector3(float(feet.x) + 0.5, float(feet.y) + 1.0, float(feet.z) + 0.5)
	await _wait_frames(2)


	_check(MiningSystem.place_block(world, base, &"workbench"), "workbench places into the world")
	_check(_block_name(world, base) == &"workbench", "placed cell holds the workbench")
	_check(world.has_station(&"workbench"), "placed workbench is a reachable station")
	_check(cs.can_craft(pick_recipe), "workbench unlocks tool recipes")
	_check(not cs.station_available("furnace"), "furnace still missing after a workbench")

	inv.add_item(&"wood", 4)
	_check(cs.craft(RecipeDatabase.get_recipe(&"craft_furnace")), "furnace crafts at the workbench")
	_check(MiningSystem.place_block(world, base + Vector3i(2, 0, 0), &"furnace"), "furnace places")
	_check(world.has_station(&"furnace"), "placed furnace is a reachable station")
	_check(cs.can_craft(iron_recipe), "furnace unlocks smelting")
	_check(cs.can_craft(RecipeDatabase.get_recipe(&"craft_glass")), "furnace unlocks glass")

	inv.add_item(&"iron_bar", 10)
	_check(cs.craft(RecipeDatabase.get_recipe(&"craft_anvil")), "anvil crafts at the workbench")
	_check(MiningSystem.place_block(world, base + Vector3i(0, 0, 2), &"anvil"), "anvil places")
	_check(cs.can_craft(RecipeDatabase.get_recipe(&"craft_iron_sword")), "anvil unlocks forging")

	# --- 4. The rest of the building set ---------------------------------------
	for id in [&"stone_brick", &"glass", &"wood_platform", &"chest"]:
		_check(MiningSystem.place_block(world, base + Vector3i(0, 1, 0) + _offset_for(id), id),
			"places building block", String(id))
		_check(_block_name(world, base + Vector3i(0, 1, 0) + _offset_for(id)) == id,
			"placed block keeps its identity", String(id))

	# --- 5. Doors are a two-state block ----------------------------------------
	var door_cell := base + Vector3i(1, 0, 1)
	_check(MiningSystem.place_block(world, door_cell, &"wood_door"), "door places")
	_check(world.is_solid(door_cell), "closed door blocks movement")
	_check(world.set_block(door_cell, int(world.block_ids[&"wood_door_open"])), "door opens")
	_check(not world.is_solid(door_cell), "open door is walk-through")
	var drop := MiningSystem.drop_for(world, door_cell)
	_check(StringName(drop.get("block_id", &"")) == &"wood_door", "open door still drops a door")
	_check(world.set_block(door_cell, int(world.block_ids[&"wood_door"])), "door closes")
	_check(world.is_solid(door_cell), "closed door is solid again")

	# --- 5b. The real interact path (E) opens the door you are looking at -------
	var door_cell2 := base + Vector3i(2, 0, 2)
	world.set_block(door_cell2, world.air_id)
	_check(MiningSystem.place_block(world, door_cell2, &"wood_door"), "second door places for the interact test")
	player.set_process(false)
	# Aim comes from the player's eye in third person, so move the player, not
	# just the camera, and point the view at the door.
	player.global_position = Vector3(door_cell2) + Vector3(0.5, 0.0, 2.2)
	player.camera.look_at(Vector3(door_cell2) + Vector3(0.5, 0.5, 0.5), Vector3.UP)
	await _wait_frames(2)
	_check(player._toggle_door(), "interact toggles a door in front of the player")
	_check(_block_name(world, door_cell2) == &"wood_door_open", "interact opened the door")
	await _wait_frames(20)
	_check(player._toggle_door(), "interact toggles the open door back")
	_check(_block_name(world, door_cell2) == &"wood_door", "interact closed the door")

	# --- 6. Furniture stays breakable ------------------------------------------
	var bench_drop := MiningSystem.drop_for(world, base)
	_check(StringName(bench_drop.get("block_id", &"")) == &"workbench", "workbench drops itself when broken")
	var broken := MiningSystem.break_block(world, base + Vector3i(2, 0, 0), 0)
	_check(bool(broken.get("mined", false)), "furnace is breakable")

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)


func _offset_for(id: StringName) -> Vector3i:
	match id:
		&"stone_brick":
			return Vector3i(1, 0, 0)
		&"glass":
			return Vector3i(2, 0, 0)
		&"wood_platform":
			return Vector3i(3, 0, 0)
		_:
			return Vector3i(3, 0, 1)


func _block_name(world: VoxelWorld, cell: Vector3i) -> StringName:
	var id := world.get_block_id(cell)
	if id < 0 or id >= world.block_defs.size():
		return &""
	return world.block_defs[id].block_id
