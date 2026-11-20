extends SceneTree

# Agent 2 boss / NPC / spawning verification, independent of HUD orchestration.

var failures := 0
var checks := 0


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("AGENT2 BOSS/NPC FAIL: %s %s" % [label, detail])
		return
	print("AGENT2 PASS: %s %s" % [label, detail])


func _initialize() -> void:
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	main.set_script(null)
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	var world: VoxelWorld = main.get_node("VoxelWorld") as VoxelWorld
	var player: VoxelPlayer = main.get_node("Player") as VoxelPlayer
	var director: EnemyDirector = main.get_node("EnemyDirector") as EnemyDirector
	var frames := 0
	while not world.is_generated and frames < 6000:
		await process_frame
		frames += 1
	_check(world.is_generated, "world ready", "frames=%d" % frames)
	if not world.is_generated:
		quit(1)
		return
	await process_frame

	# --- Enemy definitions and loot --------------------------------------------
	for kind in [EnemyConfig.KIND_GLOOMLING, EnemyConfig.KIND_LAMP_EATER, EnemyConfig.KIND_HOLLOW,
		EnemyConfig.KIND_FROST_STALKER, EnemyConfig.KIND_BOG_CRAWLER, director.KIND_WARDEN]:
		var enemy: GloomEnemy = director._make_enemy(kind)
		_check(enemy != null and enemy.loot_table != null, "enemy kind %d has loot" % kind)
		if kind == director.KIND_WARDEN:
			_check(enemy is HollowWarden, "kind 99 is the Hollow Warden boss")
		enemy.free()

	# --- Boss phases -----------------------------------------------------------
	var boss: Node = director.spawn_boss("sanctum")
	_check(boss != null and boss is HollowWarden, "boss spawns through the encounter API")
	if boss == null:
		quit(1)
		return
	var warden: HollowWarden = boss as HollowWarden
	_check(director.spawn_boss("sanctum") == null, "duplicate boss spawn is rejected")
	warden.apply_damage(320.0, 0.0, warden.position + Vector3.FORWARD)
	_check(warden.phase == 2, "boss enters phase 2 at 66% health", "phase=%d" % warden.phase)
	warden.apply_damage(350.0, 0.0, warden.position + Vector3.FORWARD)
	_check(warden.phase == 3, "boss enters phase 3 at 33% health", "phase=%d" % warden.phase)
	warden.apply_damage(9999.0, 0.0, warden.position + Vector3.FORWARD)
	var seeds_dropped := 0
	for node in get_nodes_in_group("item_drops"):
		if is_instance_valid(node) and StringName(node.get("item_id")) == &"hushwood_seed_core":
			seeds_dropped += 1
	_check(player.progression.has_flag(&"hushwood_seed_granted"), "boss defeat grants the unlock flag")
	_check(seeds_dropped > 0, "boss drops hushwood_seed_core into the world", "drops=%d" % seeds_dropped)
	_check(director.boss_director.boss_is_defeated(&"hollow_warden"), "boss defeat is recorded")
	var second_seed := player.inventory.count(&"hushwood_seed_core")
	director.boss_director.on_boss_defeated(preload("res://data/bosses/hollow_warden.tres"), main, player.position)
	_check(player.inventory.count(&"hushwood_seed_core") == second_seed, "reward cannot be duplicated")

	# --- Boss state persistence -------------------------------------------------
	var state := player.serialize_gameplay_state()
	var fresh := ProgressionSystem.new()
	fresh.deserialize(state["progression"])
	_check(fresh.has_flag(&"hushwood_seed_granted"), "boss reward flag persists in player save")
	_check(director.boss_director.serialize()["defeated"].has("hollow_warden"), "boss defeat persists")

	# --- NPC shop and quest -----------------------------------------------------
	var service: NpcService = player.npc_service
	var npc: Node3D = preload("res://scripts/npcs/npc_base.gd").new()
	main.add_child(npc)
	npc.set("shop_items", [&"healing_salve", &"torch"])
	npc.set("quest_id", &"ore_delivery")
	var coins := 200
	player.inventory.add_item(&"coin", coins)
	var salves := player.inventory.count(&"healing_salve")
	_check(service.can_buy(npc, &"healing_salve", 1), "merchant allows a purchase with currency")
	_check(service.buy(npc, &"healing_salve", 1) and player.inventory.count(&"healing_salve") == salves + 1,
		"merchant purchase transfers the item")
	service.sell(&"stone", 1)
	_check(not service.can_buy(npc, &"iron_sword", 1), "merchant refuses items outside the shop list")
	player.inventory.add_item(&"copper_ore", 6)
	_check(service.can_complete(npc) and service.complete_quest(npc), "quest completes when ingredients are present")
	_check(player.progression.has_flag(&"ore_delivery") and player.progression.has_flag(&"watch_friend"),
		"quest flags unlock progression")
	_check(not service.complete_quest(npc), "quest reward cannot be claimed twice")

	# --- Building placement -----------------------------------------------------
	var block_id := int(world.block_ids[&"stone"])
	var target: Vector3i = Vector3i(floori(player.position.x), world.spawn_height() + 3, floori(player.position.z))
	world.set_block(target, world.air_id)
	_check(MiningSystem.place_block(world, target, &"stone") and world.get_block_id(target) == block_id,
		"block placement through MiningSystem works")

	if failures > 0:
		print("AGENT2 BOSS/NPC RESULT: %d/%d failed" % [failures, checks])
		quit(1)
		return
	print("AGENT2 BOSS/NPC PASS: %d checks" % checks)
	quit(0)
