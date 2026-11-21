extends SceneTree

## Verifies the second building pass end to end: chest storage (panel moves,
## persistence and contents spilling on break), the chair plus NPC housing
## validation, and Minecraft-style stairs with placement facing.

const COMPLETE := "BUILDING EXTRA CHECK PASS: chests, housing and stairs"

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("EXTRA PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("EXTRA FAIL: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _block_name(world: VoxelWorld, cell: Vector3i) -> StringName:
	var id := world.get_block_id(cell)
	if id < 0 or id >= world.block_defs.size():
		return &""
	return StringName(world.block_defs[id].block_id)


func _click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func _run() -> void:
	var frames := 0
	while not main.world.is_generated and frames < 1800:
		await process_frame
		frames += 1
	_check(main.world.is_generated, "world generated", "frames=%d" % frames)

	var world: VoxelWorld = main.world
	var player: VoxelPlayer = main.player
	var hud: GameHUD = main.hud
	var inv: InventoryModel = player.inventory

	# --- 1. Data: chair, stairs, items, recipes ---------------------------------
	for id in [&"chair", &"wood_stairs_n", &"wood_stairs_e", &"wood_stairs_s", &"wood_stairs_w",
			&"stone_stairs_n", &"stone_stairs_e", &"stone_stairs_s", &"stone_stairs_w"]:
		_check(world.block_ids.has(id), "block registered", String(id))
	var chair_def: BlockLightDef = world.block_defs[int(world.block_ids[&"chair"])]
	_check(chair_def.seating, "chair declares seating")
	_check(chair_def.passable, "chair is walk-through")
	_check(chair_def.station == "none", "chair is not a crafting station")
	for facing in ["n", "e", "s", "w"]:
		var stair_name := StringName("wood_stairs_%s" % facing)
		_check(world.fixture_ids.has(int(world.block_ids[stair_name])), "stair fixture mapped", String(stair_name))
		_check(StringName(world.fixture_ids[int(world.block_ids[stair_name])]) == StringName("stairs_%s" % facing),
			"stair fixture names its facing", String(stair_name))
	for item_id in [&"chair", &"wood_stairs", &"stone_stairs"]:
		_check(ItemDatabase.get_item(item_id) != null, "item exists", String(item_id))
	for recipe_id in [&"craft_chair", &"craft_wood_stairs", &"craft_stone_stairs"]:
		_check(RecipeDatabase.get_recipe(recipe_id) != null, "recipe exists", String(recipe_id))
	_check(int(RecipeDatabase.get_recipe(&"craft_wood_stairs").outputs.get(&"wood_stairs", 0)) == 4, "wood stairs come four at a time")
	_check(RecipeDatabase.get_recipe(&"craft_wood_stairs").station == "workbench", "stairs need a workbench")

	# --- 2. Chest storage model -------------------------------------------------
	var store := ContainerStore.new()
	var cell := Vector3i(3, 40, 5)
	_check(store.total(cell) == 0, "new chest is empty")
	_check(store.slots(cell).size() == ContainerStore.SLOTS, "chest has 20 slots")
	_check(store.deposit(cell, &"stone", 120) == 0, "deposit fits")
	_check(store.total(cell) == 120, "deposit is counted")
	_check(store.deposit(cell, &"stone", 3000) == 0, "deposit fills more stacks")
	var stone_limit := ItemDatabase.stack_limit(&"stone")
	_check(store.total(cell) == 120 + 3000, "both deposits kept", "limit=%d" % stone_limit)
	var taken := store.take(cell, 0, 7)
	_check(StringName(taken.get("id", &"")) == &"stone" and int(taken.get("amount", 0)) == 7, "take hands back a stack")
	_check(store.total(cell) == 120 + 3000 - 7, "take reduced the chest")
	var saved := store.serialize()
	var restored := ContainerStore.new()
	_check(restored.deserialize(saved), "containers deserialize")
	_check(restored.total(cell) == store.total(cell), "container contents survive a save round trip")

	# --- 3. Build a sealed test room --------------------------------------------
	var feet := Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
	feet.x = (feet.x / 16) * 16 + 8
	feet.z = (feet.z / 16) * 16 + 8
	feet.y = world.get_surface_height(feet.x, feet.z)
	var origin := Vector3i(feet.x + 4, feet.y + 1, feet.z)
	world.set_generation_focus(origin)
	var waited := 0
	while not world.is_chunk_loaded_at(origin) and waited < 600:
		await process_frame
		waited += 1
	_check(world.is_chunk_loaded_at(origin), "room chunk loaded", "frames=%d" % waited)

	# 5 x 4 x 5 shell: floor, walls three high, roof. Interior is 3 x 2 x 3.
	var stone_brick := &"stone_brick"
	for dx in range(0, 5):
		for dz in range(0, 5):
			for dy in range(-1, 4):
				var c := origin + Vector3i(dx, dy, dz)
				var shell := dy == -1 or dy == 3 or dx == 0 or dx == 4 or dz == 0 or dz == 4
				world.set_block(c, int(world.block_ids[stone_brick]) if shell else world.air_id)
	# A door in the south wall and a torch, chair and bench inside.
	var door_cell := origin + Vector3i(2, 0, 0)
	world.set_block(door_cell, int(world.block_ids[&"wood_door"]))
	var torch_cell := origin + Vector3i(1, 1, 3)
	world.set_block(torch_cell, world.air_id)
	_check(MiningSystem.place_block(world, torch_cell, &"torch"), "torch places inside")
	var chair_cell := origin + Vector3i(1, 0, 2)
	_check(MiningSystem.place_block(world, chair_cell, &"chair"), "chair places inside")
	var bench_cell := origin + Vector3i(3, 0, 2)
	_check(MiningSystem.place_block(world, bench_cell, &"workbench"), "workbench places inside")
	var inside := origin + Vector3i(2, 0, 2)
	# The chest sits on the floor beside the bench, where the player will look.
	var chest_cell := origin + Vector3i(2, 0, 3)
	_check(MiningSystem.place_block(world, chest_cell, &"chest"), "chest places inside")
	await _wait_frames(4)

	# --- 4. Housing validation --------------------------------------------------
	var report := HouseValidator.validate(world, inside)
	_check(bool(report.get("sealed", false)), "room is sealed", "reason=%s" % report.get("reason"))
	_check(bool(report.get("door", false)), "room has a door")
	_check(bool(report.get("light", false)), "room has light")
	_check(bool(report.get("seat", false)), "room has seating")
	_check(bool(report.get("table", false)), "room has a table")
	_check(bool(report.get("valid", false)), "room qualifies as a house", HouseValidator.summary(report))
	_check(int(report.get("volume", 0)) >= HouseValidator.MIN_VOLUME, "house volume counted", "volume=%d" % int(report.get("volume", 0)))

	world.set_block(chair_cell, world.air_id)
	var no_chair := HouseValidator.validate(world, inside)
	_check(not bool(no_chair.get("valid", false)), "a house without a chair is rejected")
	_check(not bool(no_chair.get("seat", false)), "missing chair is reported")
	_check(String(no_chair.get("reason", "")) == HouseValidator.REASON_SEAT, "reason names the chair")

	MiningSystem.place_block(world, chair_cell, &"chair")
	world.set_block(bench_cell, world.air_id)
	var no_table := HouseValidator.validate(world, inside)
	_check(String(no_table.get("reason", "")) == HouseValidator.REASON_TABLE, "reason names the table")
	MiningSystem.place_block(world, bench_cell, &"workbench")

	# The house may sit in hillside terrain, so carve the approach the door
	# opens onto; otherwise "open" only exposes packed earth and stays sealed.
	for dz in range(1, 4):
		for dy in range(0, 3):
			world.set_block(door_cell + Vector3i(0, dy, -dz), world.air_id)
	world.set_block(door_cell, int(world.block_ids[&"wood_door_open"]))
	var open_door := HouseValidator.validate(world, inside)
	_check(not bool(open_door.get("valid", false)), "an open door leaves the house unsealed")
	_check(String(open_door.get("reason", "")) == HouseValidator.REASON_OPEN, "open door is reported as not sealed")
	world.set_block(door_cell, int(world.block_ids[&"wood_door"]))

	var hole := origin + Vector3i(2, 3, 2)
	world.set_block(hole, world.air_id)
	var holed := HouseValidator.validate(world, inside)
	_check(String(holed.get("reason", "")) == HouseValidator.REASON_OPEN, "a hole in the roof is reported as not sealed")
	world.set_block(hole, int(world.block_ids[stone_brick]))

	# Outdoors must never validate, no matter how much furniture stands there.
	var outside := origin + Vector3i(8, 0, 8)
	var outdoors := HouseValidator.validate(world, outside)
	_check(not bool(outdoors.get("valid", false)), "open sky is not a house")

	# --- 4b. Terraria light: an edit re-bakes, and walls block -------------------
	# A chunk that was already baked used to keep its old light forever, so a
	# torch placed in a built room never lit it, and every block attenuated by
	# one, so light walked through walls. Both are asserted here.
	var light_waited := 0
	while world.get_light_level(torch_cell) == 0 and light_waited < 600:
		await process_frame
		light_waited += 1
	_check(world.get_light_level(torch_cell) == 15, "a placed torch bakes light into the room",
		"level=%d frames=%d" % [world.get_light_level(torch_cell), light_waited])
	var lit_mid := world.get_light_level(inside + Vector3i(0, 1, 0))
	_check(lit_mid >= 8, "torchlight fills the interior", "level=%d" % lit_mid)
	var behind_wall := origin + Vector3i(5, 1, 2)
	_check(world.get_light_level(behind_wall) == 0, "solid walls stop torchlight",
		"level=%d" % world.get_light_level(behind_wall))

	world.set_block(torch_cell, world.air_id)
	# get_light_level reads 0 while a chunk is stale, so give the re-bake time to
	# finish instead of reading the invalidation itself.
	await _wait_frames(180)
	_check(world.get_light_level(inside + Vector3i(0, 1, 0)) == 0, "removing the torch bakes the room dark again",
		"level=%d" % world.get_light_level(inside + Vector3i(0, 1, 0)))
	MiningSystem.place_block(world, torch_cell, &"torch")

	# --- 5. An NPC actually moves in -------------------------------------------
	var guide: NpcBase = null
	for node in get_nodes_in_group("npc"):
		guide = node as NpcBase
		if guide != null:
			break
	_check(guide != null, "an NPC exists to house")
	var already_resident := guide != null and player.npc_service.is_resident(guide)
	player.global_position = Vector3(inside) + Vector3(0.5, 0.0, 0.5)
	await _wait_frames(2)
	main._update_housing(0.5)
	await _wait_frames(2)
	_check(hud.house_label.visible and hud.house_label.text.contains("HOUSE"), "HUD shows the house readout", hud.house_label.text)
	if guide != null and not already_resident:
		_check(player.npc_service.is_resident(guide), "the NPC became a resident")
		_check(guide.global_position.distance_to(Vector3(inside) + Vector3(0.5, 0.0, 0.5)) < 4.0, "the NPC moved into the house")
	else:
		_check(true, "NPC was already housed (progression flag set)")

	# --- 6. Chest panel and stack moves ----------------------------------------
	player.set_process(false)
	player.global_position = Vector3(chest_cell) + Vector3(0.5, 0.0, -1.8)
	player.camera.look_at_from_position(player.aim_origin(), Vector3(chest_cell) + Vector3(0.5, 0.5, 0.5), Vector3.UP)
	await _wait_frames(2)
	var target := hud._chest_under_crosshair()
	_check(target == chest_cell, "crosshair finds the chest", str(target))
	hud.open_chest(target)
	_check(hud.chest_visible, "chest panel opens")
	_check(hud.chest_panel.visible, "chest panel is visible")
	_check(hud.chest_slots.size() == ContainerStore.SLOTS, "panel shows 20 chest slots")
	_check(hud.chest_inv_slots.size() == InventoryModel.MAIN_SIZE + InventoryModel.HOTBAR_SIZE, "panel shows the player inventory")

	inv.add_item(&"stone", 25)
	var stone_area := "main"
	var stone_slot := -1
	for i in range(InventoryModel.MAIN_SIZE):
		if StringName(inv.get_slot("main", i).get("id", &"")) == &"stone":
			stone_slot = i
			break
	if stone_slot == -1:
		stone_area = "hotbar"
		for i in range(InventoryModel.HOTBAR_SIZE):
			if StringName(inv.get_slot("hotbar", i).get("id", &"")) == &"stone":
				stone_slot = i
				break
	_check(stone_slot >= 0, "a stone stack is in the bag")
	hud._on_chest_inv_slot_input(stone_area, stone_slot, _click())
	_check(player.containers.total(chest_cell) == 25, "clicking a bag stack deposits it", "total=%d" % player.containers.total(chest_cell))
	_check(int(inv.get_slot(stone_area, stone_slot).get("amount", 0)) == 0, "the deposited bag slot is empty")
	hud._refresh_chest_panel()
	_check(hud.chest_slots[0]["count"].text == "25", "panel shows the chest count")
	hud._on_chest_slot_input(0, _click())
	_check(player.containers.total(chest_cell) == 0, "clicking a chest stack withdraws it")
	_check(inv.count(&"stone") >= 25, "the stones are back in the bag")
	hud.close_chest()
	_check(not hud.chest_visible and not hud.chest_panel.visible, "chest panel closes")

	# --- 7. Breaking a chest spills its contents --------------------------------
	player.containers.deposit(chest_cell, &"torch", 4)
	_check(player.containers.total(chest_cell) == 4, "chest holds items before mining")
	player.mining_tier = 0
	player._complete_mining(chest_cell)
	await _wait_frames(1)
	_check(world.get_block_id(chest_cell) == world.air_id, "chest block is gone")
	_check(not player.containers.has_items(chest_cell), "broken chest forgets its contents")
	var drops := get_nodes_in_group("item_drops")
	_check(drops.size() >= 1, "breaking a chest drops item entities", "drops=%d" % drops.size())

	# --- 8. Stairs place with the facing you look at ----------------------------
	var stair_def := ItemDatabase.get_item(&"wood_stairs")
	_check(stair_def != null, "wood stairs item resolved")
	player.camera.look_at(player.global_position + Vector3(0, 1.6, -5), Vector3.UP)
	_check(player._placement_block(stair_def) == &"wood_stairs_n", "looking north places a north stair", String(player._placement_block(stair_def)))
	player.camera.look_at(player.global_position + Vector3(5, 1.6, 0), Vector3.UP)
	_check(player._placement_block(stair_def) == &"wood_stairs_e", "looking east places an east stair", String(player._placement_block(stair_def)))
	player.camera.look_at(player.global_position + Vector3(0, 1.6, 5), Vector3.UP)
	_check(player._placement_block(stair_def) == &"wood_stairs_s", "looking south places a south stair", String(player._placement_block(stair_def)))
	player.camera.look_at(player.global_position + Vector3(-5, 1.6, 0), Vector3.UP)
	_check(player._placement_block(stair_def) == &"wood_stairs_w", "looking west places a west stair", String(player._placement_block(stair_def)))

	var stair_cell := origin + Vector3i(0, 3, 4)
	world.set_block(stair_cell, world.air_id)
	_check(MiningSystem.place_block(world, stair_cell, &"wood_stairs_e"), "east stair places")
	_check(_block_name(world, stair_cell) == &"wood_stairs_e", "stair keeps its facing")
	_check(world.is_solid(stair_cell), "stairs collide like a block")
	var stair_drop := MiningSystem.drop_for(world, stair_cell)
	_check(StringName(stair_drop.get("block_id", &"")) == &"wood_stairs", "a stair drops the stair item")
	_check(ItemDatabase.item_id_for_drop(&"wood_stairs_e") != &"", "stair variants map to an item")

	# --- 9. Persistence through the real player payload ------------------------
	var chest_two := origin + Vector3i(1, 0, 1)
	MiningSystem.place_block(world, chest_two, &"chest")
	player.containers.deposit(chest_two, &"iron_bar", 3)
	var payload := player.serialize_gameplay_state()
	_check(payload.has("containers"), "chest data is part of the gameplay save")
	player.containers.deserialize({})
	_check(not player.containers.has_items(chest_two), "containers reset before restore")
	player.deserialize_gameplay_state(payload)
	_check(player.containers.total(chest_two) == 3, "chest contents restore from the save payload")

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
