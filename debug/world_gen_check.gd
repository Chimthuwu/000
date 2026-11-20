extends SceneTree

# Headless world verification for the 256-block, six-biome world:
# layers, vertical window, generation, caves/liquids, underground biomes,
# biome ores, determinism, border continuity, mining/placement, save round-trip.
#   Godot --headless --path lumen_deepworld --script res://debug/world_gen_check.gd

const SEED := 139732

var _failed := false


func _initialize() -> void:
	var ids := _ids()
	_check_layers()
	_check_vertical_window()
	_check_generator(ids)
	_check_determinism(ids)
	_check_boundaries(ids)
	_check_biomes(ids)
	_check_underground_biomes(ids)
	_check_cave_connectivity(ids)
	_check_cave_cache(ids)
	_check_sky(ids)
	_check_liquid_sim(ids)
	_check_mining(ids)
	_check_save(ids)
	_check_performance(ids)
	print("WORLD_CHECK %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _ids() -> Dictionary:
	var keys := [
		"air", "stone", "dirt", "ashen_soil", "canyon_gravel", "mycelium",
		"rotted_ashen_soil", "frost_snow", "frost_ice", "mire_mud", "toxic_silt",
		"lumen_crystal", "iron_ore", "torch", "deepstone", "cavern_stone",
		"coal_ore", "copper_ore", "silver_ore", "gold_ore", "dead_wood",
		"pale_wood", "water", "lava", "magma_stone", "frost_stone",
		"mycelium_stone", "ancient_ore", "frost_crystal_ore", "fungal_ore",
		"volcanic_crystal_ore", "desert_sand", "sandstone", "mushroom_soil",
		"cactus", "mushroom_stem", "mushroom_cap", "crystal_stone",
	]
	var d := {}
	for i in range(keys.size()):
		d[StringName(keys[i])] = i
	return d


func _check_layers() -> void:
	var surface := BiomeManager.get_height(64, 64)
	var checks := {
		WorldLayers.Layer.SURFACE: WorldLayers.layer_at(surface, surface),
		WorldLayers.Layer.UPPER_UNDERGROUND: WorldLayers.layer_at(surface - 5, surface),
		WorldLayers.Layer.UNDERGROUND: WorldLayers.layer_at(surface - 30, surface),
		WorldLayers.Layer.DEEP: WorldLayers.layer_at(surface - 80, surface),
		WorldLayers.Layer.CAVERN: WorldLayers.layer_at(surface - 120, surface),
		WorldLayers.Layer.ABYSS: WorldLayers.layer_at(surface - 170, surface),
		WorldLayers.Layer.SKY: WorldLayers.layer_at(surface + 3, surface),
	}
	var ok := true
	for expected in checks.keys():
		if int(checks[expected]) != int(expected):
			ok = false
	if WorldLayers.WORLD_Y != 256 or WorldLayers.CHUNKS_Y != 16:
		ok = false
	if not ok:
		_failed = true
	print("LAYERS surface=%d world_y=%d chunks_y=%d -> %s" % [surface, WorldLayers.WORLD_Y, WorldLayers.CHUNKS_Y, "PASS" if ok else "FAIL"])


func _check_vertical_window() -> void:
	var world := VoxelWorld.new()
	var surface_window := world._vertical_window(Vector3(0, float(world.spawn_height()) + 2.0, 0))
	var deep_window := world._vertical_window(Vector3(0, 24.0, 0))
	var span := surface_window.y - surface_window.x + 1
	var ok := span == world.VERTICAL_ABOVE + world.VERTICAL_BELOW + 1 \
		and surface_window.y < world.CHUNKS_Y and surface_window.x >= 0 \
		and deep_window.x < surface_window.x and deep_window.y >= 0
	world.free()
	if not ok:
		_failed = true
	print("VERTICAL surface_window=%s deep_window=%s -> %s" % [str(surface_window), str(deep_window), "PASS" if ok else "FAIL"])


func _check_generator(ids: Dictionary) -> void:
	var air_id: int = int(ids[&"air"])
	var water_id: int = int(ids[&"water"])
	var lava_id: int = int(ids[&"lava"])
	var deep_id: int = int(ids[&"deepstone"])
	var cav_id: int = int(ids[&"cavern_stone"])
	var ore_ids := [
		int(ids[&"coal_ore"]), int(ids[&"copper_ore"]), int(ids[&"iron_ore"]),
		int(ids[&"silver_ore"]), int(ids[&"gold_ore"]), int(ids[&"ancient_ore"]),
		int(ids[&"frost_crystal_ore"]), int(ids[&"fungal_ore"]),
		int(ids[&"volcanic_crystal_ore"]),
	]
	var air := 0
	var water := 0
	var lava := 0
	var ore := 0
	var deep := 0
	var cavern := 0
	var chunks := 0
	for cz in range(3, 6):
		for cx in range(3, 6):
			for cy in [0, 2, 4, 6, 8, 10, 12]:
				var blocks := WorldGenerator.generate_chunk(Vector3i(cx, cy, cz), SEED, ids)
				chunks += 1
				for i in range(blocks.size()):
					var id := int(blocks[i])
					if id == air_id:
						air += 1
					elif id == water_id:
						water += 1
					elif id == lava_id:
						lava += 1
					elif id == deep_id:
						deep += 1
					elif id == cav_id:
						cavern += 1
					if ore_ids.has(id):
						ore += 1
	var ok := air > 2000 and water > 50 and lava > 5 and ore > 60 and deep > 100 and cavern > 100
	if not ok:
		_failed = true
	print("GEN chunks=%d air=%d water=%d lava=%d ore=%d deep=%d cavern=%d -> %s" % [chunks, air, water, lava, ore, deep, cavern, "PASS" if ok else "FAIL"])


func _check_determinism(ids: Dictionary) -> void:
	var a := WorldGenerator.generate_chunk(Vector3i(4, 1, 4), SEED, ids)
	var b := WorldGenerator.generate_chunk(Vector3i(4, 1, 4), SEED, ids)
	var ok := a == b and a.size() == 4096
	if not ok:
		_failed = true
	print("DETERMINISM equal=%s size=%d -> %s" % [str(a == b), a.size(), "PASS" if ok else "FAIL"])


func _check_boundaries(ids: Dictionary) -> void:
	# Adjacent chunks share no cells; verify surface continuity and that
	# structure/prop stamping is reproducible for the same chunk.
	var max_step := 0
	for z in range(16):
		max_step = maxi(max_step, absi(BiomeManager.get_height(15, z) - BiomeManager.get_height(16, z)))
	var a := PackedByteArray()
	a.resize(4096)
	a.fill(int(ids[&"stone"]))
	var b := PackedByteArray()
	b.resize(4096)
	b.fill(int(ids[&"stone"]))
	WorldStructures.stamp_chunk(a, Vector3i(0, 6, 0), SEED, ids, int(ids[&"air"]), int(ids[&"stone"]))
	WorldStructures.stamp_chunk(b, Vector3i(0, 6, 0), SEED, ids, int(ids[&"air"]), int(ids[&"stone"]))
	var ok := max_step <= 8 and a == b
	if not ok:
		_failed = true
	print("BORDER max_height_step=%d stamp_deterministic=%s -> %s" % [max_step, str(a == b), "PASS" if ok else "FAIL"])


func _check_biomes(ids: Dictionary) -> void:
	var signature := {
		BiomeManager.ASHEN: [&"coal_ore"],
		BiomeManager.HUSH: [&"fungal_ore"],
		BiomeManager.FROST: [&"frost_crystal_ore"],
		BiomeManager.MIRE: [&"ancient_ore"],
		BiomeManager.DESERT: [&"silver_ore"],
		BiomeManager.MUSHROOM: [&"fungal_ore"],
	}
	var all_ok := true
	for biome in signature.keys():
		var center := _find_biome_column(biome)
		var chunk_x := floori(float(center.x) / 16.0)
		var chunk_z := floori(float(center.y) / 16.0)
		var names: Array = signature[biome]
		var counts := {}
		for ore_name in names:
			counts[ore_name] = 0
		for cz in range(chunk_z - 1, chunk_z + 2):
			for cx in range(chunk_x - 1, chunk_x + 2):
				for cy in [2, 4, 6, 8]:
					var blocks := WorldGenerator.generate_chunk(Vector3i(cx, cy, cz), SEED, ids)
					for i in range(blocks.size()):
						var id := int(blocks[i])
						for ore_name in names:
							if id == int(ids[ore_name]):
								counts[ore_name] = int(counts[ore_name]) + 1
		for ore_name in names:
			var c := int(counts[ore_name])
			if c <= 0:
				all_ok = false
			print("BIOME %s at %s %s=%d" % [BiomeManager.biome_name(biome), str(center), ore_name, c])
	if not all_ok:
		_failed = true
	print("BIOME_ORES -> %s" % ("PASS" if all_ok else "FAIL"))


func _find_biome_column(target: int) -> Vector2i:
	var best := Vector2i(1 << 20, 1 << 20)
	var best_weight := -1.0
	for z in range(-2048, 2049, 64):
		for x in range(-2048, 2049, 64):
			if BiomeManager.surface_biome(x, z) != target:
				continue
			var weight := BiomeManager.get_weights(x, z)[target]
			if weight > best_weight:
				best_weight = weight
				best = Vector2i(x, z)
	if best_weight < 0.0:
		return BiomeManager.find_biome_center(target, SEED, 64, 64)
	return best


func _check_underground_biomes(ids: Dictionary) -> void:
	var surface := BiomeManager.get_height(64, 64)
	var counts := {}
	for y in range(8, surface - 8, 3):
		for z in range(48, 80, 4):
			for x in range(48, 80, 4):
				var ub := WorldBiomes.underground_biome_at(x, y, z, surface, BiomeManager.dominant_biome(x, z))
				counts[ub] = int(counts.get(ub, 0)) + 1
	var distinct := counts.size()
	var stone_ok := WorldBiomes.stone_name(WorldBiomes.Underground.VOLCANIC, 80) == &"magma_stone" \
		and WorldBiomes.stone_name(WorldBiomes.Underground.FUNGAL, 40) == &"mycelium_stone" \
		and WorldBiomes.stone_name(WorldBiomes.Underground.CRYSTAL, 120) == &"crystal_stone"
	var ok := distinct >= 3 and stone_ok
	if not ok:
		_failed = true
	print("UNDERGROUND distinct=%d counts=%s stone_map=%s -> %s" % [distinct, str(counts), str(stone_ok), "PASS" if ok else "FAIL"])


func _check_cave_connectivity(ids: Dictionary) -> void:
	# Flood-fill carved cells in a 32^3 sample; a healthy cave network has one
	# dominant connected component rather than scattered single-cell holes.
	var surface := BiomeManager.get_height(64, 64)
	var size := 32
	var origin := Vector3i(40, surface - 88, 40)
	var cave_cells := {}
	for z in range(size):
		for y in range(size):
			for x in range(size):
				if WorldCaves.is_cave(origin.x + x, origin.y + y, origin.z + z, surface):
					cave_cells[Vector3i(x, y, z)] = true
	if cave_cells.is_empty():
		_failed = true
		print("CAVE_CONNECTIVITY empty -> FAIL")
		return
	var visited := {}
	var best := 0
	for start in cave_cells.keys():
		if visited.has(start):
			continue
		var stack: Array = [start]
		visited[start] = true
		var component := 0
		while not stack.is_empty():
			var cell: Vector3i = stack.pop_back()
			component += 1
			for offset in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var next: Vector3i = cell + offset
				if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= size or next.y >= size or next.z >= size:
					continue
				if visited.has(next) or not cave_cells.has(next):
					continue
				visited[next] = true
				stack.append(next)
		best = maxi(best, component)
	var ratio := float(best) / float(cave_cells.size())
	var ok := ratio > 0.35
	if not ok:
		_failed = true
	print("CAVE_CONNECTIVITY cells=%d largest=%d ratio=%.2f -> %s" % [cave_cells.size(), best, ratio, "PASS" if ok else "FAIL"])


func _check_cave_cache(ids: Dictionary) -> void:
	var origin := Vector3i(48, 96, 48)
	var cache := WorldCaves.build_cache(origin)
	var cave_mismatch := 0
	var liquid_mismatch := 0
	for z in range(0, 16, 3):
		for x in range(0, 16, 3):
			var wx := origin.x + x
			var wz := origin.z + z
			var surface := BiomeManager.get_height(wx, wz)
			for y in range(origin.y, origin.y + 16, 4):
				if WorldCaves.is_cave_cached(cache, wx, y, wz, surface) != WorldCaves.is_cave(wx, y, wz, surface):
					cave_mismatch += 1
				if WorldCaves.liquid_at_cached(cache, wx, y, wz, surface) != WorldCaves.liquid_at(wx, y, wz, surface):
					liquid_mismatch += 1
	var ok := cave_mismatch == 0 and liquid_mismatch == 0
	if not ok:
		_failed = true
	print("CACHE cave_mismatch=%d liquid_mismatch=%d -> %s" % [cave_mismatch, liquid_mismatch, "PASS" if ok else "FAIL"])


func _check_sky(ids: Dictionary) -> void:
	var air_id: int = int(ids[&"air"])
	var surface := BiomeManager.get_height(64, 64)
	var above_surface := 0
	var chunks := 0
	for cz in range(2, 7):
		for cx in range(2, 7):
			for cy in [13, 14, 15]:
				var blocks := WorldGenerator.generate_chunk(Vector3i(cx, cy, cz), SEED, ids)
				chunks += 1
				for i in range(blocks.size()):
					var world_y := int(cy) * 16 + int(i / 16) % 16
					if int(blocks[i]) != air_id and world_y > surface + 10:
						above_surface += 1
	var ok := above_surface > 0
	if not ok:
		_failed = true
	print("SKY chunks=%d blocks_above_surface=%d -> %s" % [chunks, above_surface, "PASS" if ok else "FAIL"])


func _check_liquid_sim(ids: Dictionary) -> void:
	var air_def: BlockLightDef = load("res://data/blocks/air.tres")
	var w := FakeWorld.new()
	w.air_id = int(ids[&"air"])
	w.block_ids = ids
	for i in range(ids.size()):
		w.block_defs.append(air_def)
	var sim := LiquidSim.new()
	sim.configure(w)
	# A stone floor stops the falling column, so the test can observe where it
	# settled instead of letting it fall out of the fake world.
	w.blocks[Vector3i(0, 2, 0)] = int(ids[&"stone"])
	var start := Vector3i(0, 10, 0)
	w.blocks[start] = int(ids[&"water"])
	sim.on_block_changed(w, start, int(ids[&"water"]))
	for i in range(24):
		sim.process(w, 8)
	var fell_to := 10
	for y in range(0, 11):
		if w.get_block_id(Vector3i(0, y, 0)) == int(ids[&"water"]):
			fell_to = y
	var bounded := sim.pending_count() <= LiquidSim.MAX_PENDING
	var water_ok := fell_to <= 7 and fell_to > 2 and bounded
	# Lava must be slower: the first tick does not move it, the third does.
	var w2 := FakeWorld.new()
	w2.air_id = int(ids[&"air"])
	w2.block_ids = ids
	w2.block_defs = w.block_defs
	var sim2 := LiquidSim.new()
	sim2.configure(w2)
	w2.blocks[Vector3i(4, 2, 0)] = int(ids[&"stone"])
	var lava_cell := Vector3i(4, 10, 0)
	w2.blocks[lava_cell] = int(ids[&"lava"])
	sim2.on_block_changed(w2, lava_cell, int(ids[&"lava"]))
	sim2.process(w2, 8)
	var lava_slow: bool = w2.get_block_id(lava_cell) == int(ids[&"lava"])
	sim2.process(w2, 8)
	sim2.process(w2, 8)
	var lava_fell_to := 10
	for y in range(0, 11):
		if w2.get_block_id(Vector3i(4, y, 0)) == int(ids[&"lava"]):
			lava_fell_to = y
	var lava_moved: bool = lava_fell_to < 10 and lava_fell_to > 2
	var ok := water_ok and lava_slow and lava_moved
	if not ok:
		_failed = true
	print("LIQUID fell_to=%d water_bounded=%s lava_slow=%s lava_fell_to=%d -> %s" % [fell_to, str(bounded), str(lava_slow), lava_fell_to, "PASS" if ok else "FAIL"])


func _check_mining(ids: Dictionary) -> void:
	var stone_def: BlockLightDef = load("res://data/blocks/stone.tres")
	var air_def: BlockLightDef = load("res://data/blocks/air.tres")
	var water_def: BlockLightDef = load("res://data/blocks/water.tres")
	var dirt_def: BlockLightDef = load("res://data/blocks/dirt.tres")
	var w := FakeWorld.new()
	w.air_id = int(ids[&"air"])
	w.block_ids = ids
	var defs: Array[BlockLightDef] = []
	for i in range(ids.size()):
		defs.append(air_def)
	defs[int(ids[&"stone"])] = stone_def
	defs[int(ids[&"water"])] = water_def
	defs[int(ids[&"dirt"])] = dirt_def
	w.block_defs = defs
	w.blocks[Vector3i(0, 0, 0)] = int(ids[&"stone"])
	w.blocks[Vector3i(2, 0, 0)] = int(ids[&"water"])
	var hit := MiningSystem.raycast(w, Vector3(-2.0, 0.5, 0.5), Vector3.RIGHT, 5.0)
	var ok1: bool = (not hit.is_empty()) and hit["cell"] == Vector3i(0, 0, 0)
	var ok2: bool = not MiningSystem.can_mine(w, Vector3i(0, 0, 0), 0)
	var ok3: bool = MiningSystem.can_mine(w, Vector3i(0, 0, 0), 1)
	var result := MiningSystem.break_block(w, Vector3i(0, 0, 0), 1)
	var drop: Dictionary = result.get("drop", {})
	var ok4: bool = bool(result.get("mined", false)) and StringName(drop.get("block_id", &"")) == &"stone"
	var ok5: bool = MiningSystem.drop_for(w, Vector3i(2, 0, 0)).is_empty() and MiningSystem.is_liquid(w, Vector3i(2, 0, 0))
	var placed := MiningSystem.place_block(w, Vector3i(4, 0, 0), &"dirt")
	var ok6: bool = placed and w.get_block_id(Vector3i(4, 0, 0)) == int(ids[&"dirt"])
	var replaced := MiningSystem.place_block(w, Vector3i(2, 0, 0), &"stone")
	var ok7: bool = replaced and not MiningSystem.is_liquid(w, Vector3i(2, 0, 0))
	var ok := ok1 and ok2 and ok3 and ok4 and ok5 and ok6 and ok7
	if not ok:
		_failed = true
	print("MINE ray=%s tier0_blocked=%s tier1_ok=%s drop=%s liquid=%s place=%s replace_liquid=%s -> %s" % [str(ok1), str(ok2), str(ok3), str(ok4), str(ok5), str(ok6), str(ok7), "PASS" if ok else "FAIL"])


func _check_save(ids: Dictionary) -> void:
	var world := SaveWorld.new()
	world.world_seed = 424242
	world.block_ids = ids
	var stone_def: BlockLightDef = load("res://data/blocks/stone.tres")
	for i in range(ids.size()):
		world.block_defs.append(stone_def)
	var journal := BlockEditJournal.new()
	var cell := Vector3i(256, 180, 256)
	journal.on_block_edited(cell, int(ids[&"stone"]))
	var saved := WorldSave.save_world(world, journal, Vector3(256.5, 181.0, 256.5), {})
	var loaded := WorldSave.load_world(424242, world) if saved else {}
	var edited: Dictionary = loaded.get("edited_cells", {})
	var ok: bool = saved and not loaded.is_empty() and int(edited.get(cell, -1)) == int(ids[&"stone"])
	if not ok:
		_failed = true
	_cleanup_save(424242)
	print("SAVE roundtrip=%s cells=%d -> %s" % [str(not loaded.is_empty()), edited.size(), "PASS" if ok else "FAIL"])


func _cleanup_save(seed: int) -> void:
	var dir := ProjectSettings.globalize_path("user://worlds/%d" % seed)
	for file in ["edits.bin", "metadata.json"]:
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _check_performance(ids: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	var chunks := 0
	for cz in range(0, 4):
		for cx in range(0, 4):
			WorldGenerator.generate_chunk(Vector3i(cx, 6, cz), SEED, ids)
			chunks += 1
	var usec := Time.get_ticks_usec() - start
	print("PERF chunks=%d total_ms=%.1f avg_ms=%.2f" % [chunks, float(usec) / 1000.0, float(usec) / 1000.0 / float(chunks)])


class FakeWorld:
	var air_id: int = 0
	var blocks: Dictionary = {}
	var block_ids: Dictionary = {}
	var block_defs: Array[BlockLightDef] = []

	func _inside_world(_cell: Vector3i) -> bool:
		return true

	func get_block_id(cell: Vector3i) -> int:
		return int(blocks.get(cell, air_id))

	func set_block(cell: Vector3i, id: int, _journal := true) -> bool:
		blocks[cell] = id
		return true

	func is_chunk_loaded_at(_cell: Vector3i) -> bool:
		return true


class SaveWorld extends Node:
	var world_seed := 139732
	var CHUNK_SIZE := 16
	var block_ids: Dictionary = {}
	var block_defs: Array[BlockLightDef] = []
