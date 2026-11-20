extends SceneTree

# Verifies the green "Overworld" starting region and its trees.

var failures := 0
var checks := 0


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("OVERWORLD FAIL: %s %s" % [label, detail])
		return
	print("OVERWORLD PASS: %s %s" % [label, detail])


func _initialize() -> void:
	BiomeManager.configure(139732)
	_check(BiomeManager.dominant_biome(BiomeManager.SPAWN_X, BiomeManager.SPAWN_Z) == BiomeManager.MIRE,
		"spawn column is the green Overworld (internal MIRE id)",
		"biome=%d" % BiomeManager.dominant_biome(BiomeManager.SPAWN_X, BiomeManager.SPAWN_Z))
	_check(BiomeManager.biome_name(BiomeManager.MIRE) == "Forest", "Mire is presented as Forest")
	var h := BiomeManager.get_height(BiomeManager.SPAWN_X, BiomeManager.SPAWN_Z)
	_check(h > BiomeManager.WATER_LEVEL, "spawn height is above standing water", "height=%d water=%d" % [h, BiomeManager.WATER_LEVEL])

	var sites: Array = WorldGenerator.collect_tree_sites_region(139732, 40, 40, 88, 88)
	_check(sites.size() >= 6, "Overworld has trees near spawn", "sites=%d" % sites.size())
	var over_land := 0
	for site in sites:
		if BiomeManager.dominant_biome(int(site["x"]), int(site["z"])) == BiomeManager.MIRE:
			over_land += 1
	_check(over_land >= 4, "trees are placed in the Overworld biome", "overworld_trees=%d" % over_land)

	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	var game_world: VoxelWorld = main.get_node("VoxelWorld") as VoxelWorld
	var game_player: VoxelPlayer = main.get_node("Player") as VoxelPlayer
	var frames := 0
	while not game_world.is_generated and frames < 6000:
		await process_frame
		frames += 1
	_check(game_world.is_generated, "world boots with the new spawn biome", "frames=%d" % frames)
	for _i in range(4):
		await process_frame
	var cell := Vector3i(floori(game_player.position.x), 0, floori(game_player.position.z))
	_check(game_world.get_biome_at(cell) == BiomeManager.MIRE, "live player spawns in Overworld")
	_check(game_player.position.y > float(BiomeManager.WATER_LEVEL), "player spawns out of the water", "y=%.1f" % game_player.position.y)

	if failures > 0:
		print("OVERWORLD RESULT: %d/%d failed" % [failures, checks])
		quit(1)
		return
	print("OVERWORLD PASS: %d checks" % checks)
	quit(0)
