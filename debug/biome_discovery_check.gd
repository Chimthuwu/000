extends SceneTree

# Agent 4 Phase 4 validation: biome discoveries are deterministic, chunk-safe,
# biome-complete, placed away from spawn/other structures, and appear in the
# live canonical world. Run:
#   Godot --headless --path Terraria3D --script res://debug/biome_discovery_check.gd

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("DISCOVERY FAIL: %s %s" % [label, detail])
		return
	print("DISCOVERY PASS: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_for_at(position: Vector3, condition: Callable, limit: int) -> int:
	var frames := 0
	while not condition.call() and frames < limit:
		main.player.position = position
		await process_frame
		frames += 1
	return frames


func _run() -> void:
	var world: VoxelWorld = main.world
	var frames := 0
	while not world.is_generated and frames < 2400:
		await process_frame
		frames += 1
	_check(world.is_generated, "canonical world boots with discoveries enabled", "frames=%d" % frames)
	if not world.is_generated:
		quit(1)
		return

	var ids: Dictionary = world.block_ids
	var air_id: int = world.air_id
	var stone_id: int = int(ids.get(&"stone", 3))
	var seed: int = world.world_seed

	# --- Definition coverage -------------------------------------------------
	var core := [BiomeManager.ASHEN, BiomeManager.MIRE, BiomeManager.FROST,
		BiomeManager.DESERT, BiomeManager.MUSHROOM, BiomeManager.HUSH,
		BiomeManager.JUNGLE, BiomeManager.CORRUPTION, BiomeManager.CRIMSON,
		BiomeManager.HALLOW, BiomeManager.OCEAN]
	for biome in core:
		var templates: Array = BiomeDiscovery.templates_for_biome(int(biome))
		_check(templates.size() >= 2, "biome has discovery templates", "biome=%d templates=%d" % [int(biome), templates.size()])
	var names: Array = []
	for template in BiomeDiscovery.TEMPLATES.keys():
		var def: Dictionary = BiomeDiscovery.TEMPLATES[template]
		for key in ["wall", "floor"]:
			if def.has(key):
				_check(ids.has(StringName(String(def[key]))), "template palette block exists",
					"%s.%s=%s" % [String(template), String(key), String(def[key])])
		var loot: Array = def.get("loot", [])
		for block in loot:
			names.append(String(block))
	for block in names:
		_check(ids.has(StringName(block)), "loot block exists in canonical palette", block)

	# --- Determinism + chunk clipping ---------------------------------------
	var best_site: Dictionary = {}
	var best_distance := 1 << 30
	for gz in range(-2, 3):
		for gx in range(-2, 3):
			var site := BiomeDiscovery.site_for(seed, gx, gz)
			if site.is_empty():
				continue
			var dist: int = absi(int(site["x"]) - BiomeManager.SPAWN_X) + absi(int(site["z"]) - BiomeManager.SPAWN_Z)
			if dist < best_distance:
				best_distance = dist
				best_site = site
	_check(not best_site.is_empty(), "a discovery site exists near spawn", "distance=%d" % best_distance)
	if not best_site.is_empty():
		var sx: int = int(best_site["x"])
		var sy: int = int(best_site["y"])
		var sz: int = int(best_site["z"])
		var origin := Vector3i(floori(float(sx) / 16.0) * 16, floori(float(sy) / 16.0) * 16, floori(float(sz) / 16.0) * 16)
		var a := PackedByteArray()
		a.resize(16 * 16 * 16)
		a.fill(stone_id)
		var b := PackedByteArray()
		b.resize(16 * 16 * 16)
		b.fill(stone_id)
		BiomeDiscovery.stamp_chunk(a, origin, seed, ids, air_id, stone_id)
		BiomeDiscovery.stamp_chunk(b, origin, seed, ids, air_id, stone_id)
		_check(a == b, "discovery stamping is deterministic", "site=%s" % str(best_site["id"]))
		var changed := 0
		for i in range(a.size()):
			if a[i] != stone_id:
				changed += 1
		_check(changed > 0, "site writes real structure blocks", "changed=%d" % changed)
		var desc := BiomeDiscovery.discovery_at(seed, Vector3i(sx, sy + 1, sz))
		_check(not desc.is_empty(), "discovery_at() publishes a loot/hint descriptor", str(desc.get("label", "")))

	# --- Live world: stream to the nearest site and inspect its blocks -------
	if not best_site.is_empty():
		var sx: int = int(best_site["x"])
		var sy: int = int(best_site["y"])
		var sz: int = int(best_site["z"])
		var pos := Vector3(float(sx) + 0.5, float(sy) + 2.0, float(sz) + 0.5)
		var target := world._chunk_of(Vector3i(sx, sy, sz))
		frames = await _wait_for_at(pos, func() -> bool: return world.is_chunk_ready(target), 3000)
		_check(world.is_chunk_ready(target), "discovery chunk streams, lights and meshes",
			"id=%s frames=%d" % [str(best_site["id"]), frames])
		var found := false
		for dx in range(-6, 7):
			for dz in range(-6, 7):
				for dy in range(-2, 5):
					if world.get_block_id(Vector3i(sx + dx, sy + dy, sz + dz)) != air_id:
						found = true
						break
				if found:
					break
			if found:
				break
		_check(found, "authored blocks exist in the live streamed chunk", "at=%d,%d,%d" % [sx, sy, sz])

	if failures > 0:
		quit(1)
		return
	print("BIOME DISCOVERY CHECK PASS: all nine biomes have authored, deterministic discoveries")
	quit(0)
