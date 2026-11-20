extends SceneTree

# Agent 2 foundation verification. Boots the real main scene, waits for the
# streaming world, then exercises items, inventory, crafting, mining, combat,
# loot, progression, survival and save/load with direct calls (no window).

var main: Node
var failures := 0
var checks := 0
var died_count := 0


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("AGENT2 CHECK FAIL: %s %s" % [label, detail])
		return
	print("AGENT2 PASS: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


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

	# --- 1. Item and recipe databases -----------------------------------------
	var required := [
		&"wood", &"stone", &"copper_ore", &"iron_ore", &"coal", &"copper_bar",
		&"iron_bar", &"wooden_pickaxe", &"wooden_axe", &"wooden_sword", &"torch",
		&"healing_salve", &"copper_helmet", &"copper_chestplate", &"copper_leggings",
		&"wooden_bow", &"apprentice_staff"
	]
	for id in required:
		_check(ItemDatabase.has(id), "item defined: %s" % String(id))
	var all_items := ItemDatabase.all()
	_check(all_items.size() >= 30, "item database populated", "count=%d" % all_items.size())
	var recipes := RecipeDatabase.all()
	_check(recipes.size() >= 20, "recipe database populated", "count=%d" % recipes.size())
	var recipes_valid := true
	for recipe in recipes:
		for id in recipe.ingredients.keys():
			if not ItemDatabase.has(StringName(id)):
				recipes_valid = false
				push_error("recipe %s has unknown ingredient %s" % [String(recipe.recipe_id), String(id)])
		for id in recipe.outputs.keys():
			if not ItemDatabase.has(StringName(id)):
				recipes_valid = false
	_check(recipes_valid, "every recipe ingredient/output resolves")
	var weapon: ItemDef = ItemDatabase.get_item(&"wooden_sword")
	_check(weapon != null and weapon.attack != null and weapon.attack.kind == "melee", "sword has a melee AttackDef")
	var staff: ItemDef = ItemDatabase.get_item(&"apprentice_staff")
	_check(staff.attack.kind == "magic" and staff.attack.pierce > 0 and staff.attack.mana_cost > 0.0, "staff is a distinct magic weapon")

	# --- 2. Inventory model ----------------------------------------------------
	var inv := InventoryModel.new()
	var stone_limit := ItemDatabase.stack_limit(&"stone")
	var added := stone_limit + 201
	var leftover := inv.add_item(&"stone", added)
	_check(leftover == 0 and inv.count(&"stone") == added, "stacking across slots", "count=%d" % inv.count(&"stone"))
	_check(inv.get_slot("hotbar", 0)["amount"] == stone_limit and inv.get_slot("hotbar", 1)["amount"] == 201, "stack limit respected")
	_check(inv.consume(&"stone", 50) and inv.count(&"stone") == added - 50, "consume removes quantity")
	_check(inv.split_stack("hotbar", 0, "main", 0, 30) and inv.get_slot("main", 0)["amount"] == 30, "stack splitting")
	_check(inv.swap_slots("hotbar", 0, "main", 1), "slot swapping")
	inv.add_item(&"wooden_pickaxe", 1)
	inv.select(0)
	_check(inv.held_item() == &"wooden_pickaxe", "hotbar selection exposes held item")
	inv.add_item(&"copper_helmet", 1)
	var helmet_slot := -1
	for index in range(InventoryModel.HOTBAR_SIZE):
		if StringName(inv.get_slot("hotbar", index)["id"]) == &"copper_helmet":
			helmet_slot = index
	_check(helmet_slot >= 0 and inv.equip("head", "hotbar", helmet_slot), "equipment slot accepts matching armour")
	_check(inv.total_armor() == 2 and inv.count(&"copper_helmet") == 0, "armour contributes and leaves inventory")
	inv.unequip("head")
	_check(inv.count(&"copper_helmet") == 1, "unequip returns the item")
	var saved_inv := inv.serialize()
	var inv2 := InventoryModel.new()
	_check(inv2.deserialize(saved_inv) and inv2.count(&"stone") == inv.count(&"stone"), "inventory serializes and restores")

	# --- 3. Crafting -----------------------------------------------------------
	var prog := ProgressionSystem.new()
	var gw := WorldGateway.new(world)
	var craft := CraftingSystem.new(inv2, prog, gw)
	var torch_recipe := RecipeDatabase.get_recipe(&"craft_torch")
	_check(torch_recipe != null, "torch recipe exists")
	inv2.add_item(&"wood", 4)
	inv2.add_item(&"coal", 4)
	var torches_before := inv2.count(&"torch")
	_check(craft.can_craft(torch_recipe), "torch recipe is craftable without a station")
	_check(craft.craft(torch_recipe), "craft succeeds")
	_check(inv2.count(&"torch") == torches_before + 4 and inv2.count(&"wood") == 3, "craft consumes ingredients and yields output")
	var pick_recipe := RecipeDatabase.get_recipe(&"craft_wooden_pickaxe")
	_check(craft.can_craft(pick_recipe), "workbench baseline available for test")
	var staff_recipe := RecipeDatabase.get_recipe(&"craft_apprentice_staff")
	_check(not craft.can_craft(staff_recipe) and craft.reason(staff_recipe) == "LOCKED", "flag-gated recipe is locked")
	prog.set_flag(&"unlocked_magic")
	_check(craft.reason(staff_recipe) != "LOCKED", "flag unlocks recipe")

	# --- 4. Progression --------------------------------------------------------
	prog.discover(&"iron_ore")
	prog.add_stat(&"blocks_mined", 7.0)
	var p2 := ProgressionSystem.new()
	p2.deserialize(prog.serialize())
	_check(p2.has_flag(&"unlocked_magic") and p2.has_discovered(&"iron_ore") and p2.stats["blocks_mined"] == 7.0, "progression serializes")

	# --- 5. Mining with a real tool -------------------------------------------
	var spawn_height := world.spawn_height()
	var ground := Vector3i(world.spawn_origin.x, spawn_height - 1, world.spawn_origin.z)
	var info := gw.mining_info(ground)
	_check(info.has("hardness") and info.has("drop"), "world mining info available", "block=%s" % String(gw.get_block_name(ground)))
	player.inventory.add_item(&"wooden_pickaxe", 1)
	var pick_slot := 0
	for index in range(InventoryModel.HOTBAR_SIZE):
		if StringName(player.inventory.get_slot("hotbar", index)["id"]) == &"wooden_pickaxe":
			pick_slot = index
	player.inventory.select(pick_slot)
	player.position = Vector3(ground.x + 0.5, ground.y + 1.0, ground.z + 0.5)
	player.camera.rotation.x = -1.5
	var block_before := gw.get_block_id(ground)
	var mined := false
	for _i in range(80):
		player._update_mining(0.05, ItemDatabase.get_item(&"wooden_pickaxe"))
		if gw.get_block_id(ground) == gw.get_air_id():
			mined = true
			break
	_check(mined and block_before != gw.get_air_id(), "tool mining breaks a real voxel")
	var drops: Array = get_nodes_in_group("item_drops")
	_check(drops.size() > 0, "mining spawns an item entity", "drops=%d" % drops.size())

	# --- 6. Melee combat, knockback, loot -------------------------------------
	player.camera.rotation.x = 0.0
	player.inventory.add_item(&"wooden_sword", 1)
	var sword_slot := 0
	for index in range(InventoryModel.HOTBAR_SIZE):
		if StringName(player.inventory.get_slot("hotbar", index)["id"]) == &"wooden_sword":
			sword_slot = index
	player.inventory.select(sword_slot)
	var enemy: GloomEnemy = preload("res://scripts/enemies/gloomling.gd").new()
	main.add_child(enemy)
	enemy.position = player.position + Vector3(0.0, 0.0, -1.6)
	enemy.health = 60.0
	await _wait_frames(3)
	player.weapons.cooldown = 0.0
	_check(player.weapons.try_attack(), "melee attack fires")
	_check(enemy.health < 60.0, "melee damages the enemy", "hp=%.1f" % enemy.health)
	_check(enemy.knockback_velocity.length() > 0.0, "melee applies knockback")
	died_count = 0
	enemy.died.connect(_on_test_enemy_died)
	enemy.apply_damage(1000.0, 5.0, player.position)
	_check(died_count == 1, "death signal emitted")
	_check(not get_nodes_in_group("item_drops").is_empty(), "enemy drops loot")
	var kills_before := float(player.progression.stats["enemies_defeated"])
	main.enemy_director._on_enemy_died(enemy, enemy.position)
	_check(float(player.progression.stats["enemies_defeated"]) == kills_before + 1.0, "kill recorded in progression")

	# --- 7. Ranged projectile and mana ----------------------------------------
	player.inventory.add_item(&"wooden_bow", 1)
	var bow_slot := 0
	for index in range(InventoryModel.HOTBAR_SIZE):
		if StringName(player.inventory.get_slot("hotbar", index)["id"]) == &"wooden_bow":
			bow_slot = index
	player.inventory.select(bow_slot)
	player.weapons.cooldown = 0.0
	_check(player.weapons.try_attack(), "bow fires")
	_check(_projectile_exists(), "bow spawns a projectile")
	player.inventory.add_item(&"apprentice_staff", 1)
	var staff_slot := 0
	for index in range(InventoryModel.HOTBAR_SIZE):
		if StringName(player.inventory.get_slot("hotbar", index)["id"]) == &"apprentice_staff":
			staff_slot = index
	player.inventory.select(staff_slot)
	var mana_before := player.weapons.mana
	player.weapons.cooldown = 0.0
	_check(player.weapons.try_attack() and player.weapons.mana < mana_before, "staff consumes mana")
	player.weapons.mana = 0.0
	player.weapons.cooldown = 0.0
	_check(not player.weapons.try_attack(), "staff cannot fire without mana")

	# --- 8. Survival: fall damage, healing, statuses ---------------------------
	var hp_before := player.health
	player._apply_fall_damage(9.0)
	_check(player.health < hp_before, "fall damage applies")
	var hp_pre_heal := player.health
	player.inventory.add_item(&"healing_salve", 1)
	player._use_consumable(ItemDatabase.get_item(&"healing_salve"))
	_check(player.health > hp_pre_heal, "healing consumable restores health", "%.1f -> %.1f" % [hp_pre_heal, player.health])
	player.apply_slow(2.0)
	_check(player.statuses.has(&"slow"), "status effect applies")

	# --- 9. Third-person camera -----------------------------------------------
	player._toggle_camera_mode()
	_check(player.camera_mode == 1, "third-person camera toggles")
	player._toggle_camera_mode()
	_check(player.camera_mode == 0, "first-person camera restored")

	# --- 10. Player save contract ---------------------------------------------
	var state := player.serialize_gameplay_state()
	var saved_stone := player.inventory.count(&"stone")
	player.inventory.clear()
	player.deserialize_gameplay_state(state)
	_check(player.inventory.count(&"stone") == saved_stone, "player save round-trips inventory")
	_check(state.has("progression") and state.has("camera_mode"), "player save contains all gameplay keys")

	if failures > 0:
		print("AGENT2 CHECK RESULT: %d/%d failed" % [failures, checks])
		quit(1)
		return
	print("AGENT2 GAMEPLAY CHECK PASS: %d checks" % checks)
	quit(0)


func _on_test_enemy_died(_enemy: Node, _position: Vector3) -> void:
	died_count += 1


func _projectile_exists() -> bool:
	return not get_nodes_in_group("projectiles").is_empty()
