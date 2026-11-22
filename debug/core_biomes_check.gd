extends SceneTree

# Direction-correction check: the live generator must expose all nine core
# Terraria surface identities, keep Corruption/Crimson exclusive, gate Hallow
# behind progression, and flood the Ocean.
#   Godot --headless --path Terraria3D --script res://debug/core_biomes_check.gd

const SEED := 139732
const SCAN_RADIUS := 2048
const SCAN_STEP := 64

var failures := 0
var block_ids: Dictionary = {}
var block_names: Dictionary = {}


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("CORE BIOME FAIL: %s %s" % [label, detail])
		return
	print("CORE BIOME PASS: %s %s" % [label, detail])


func _initialize() -> void:
	BiomeManager.configure(SEED)
	BiomeManager.set_evil_mode("both")
	BiomeManager.set_hallow_enabled(true)
	_load_blocks()
	_run()
	if failures > 0:
		quit(1)
		return
	print("CORE BIOMES CHECK PASS: all core identities generate")
	quit(0)


func _load_blocks() -> void:
	for path in VoxelWorld.BLOCK_RESOURCE_PATHS:
		var definition := load(path) as BlockLightDef
		if definition == null:
			push_error("CORE BIOME FAIL: cannot load " + path)
			continue
		block_names[block_ids.size()] = definition.block_id
		block_ids[definition.block_id] = block_ids.size()


func _run() -> void:
	_check(BiomeManager.BIOME_COUNT == 11, "engine exposes eleven surface regions", str(BiomeManager.BIOME_COUNT))
	_check(BiomeManager.dominant_biome(BiomeManager.SPAWN_X, BiomeManager.SPAWN_Z) == BiomeManager.MIRE,
		"spawn is Forest")
	# Gameplay metadata must track the live engine ids, or enemies get the wrong
	# biome table even though the terrain is correct.
	var identity_for_biome := {
		BiomeManager.JUNGLE: GameplayBiome.Identity.JUNGLE,
		BiomeManager.CORRUPTION: GameplayBiome.Identity.CORRUPTION,
		BiomeManager.CRIMSON: GameplayBiome.Identity.CRIMSON,
		BiomeManager.HALLOW: GameplayBiome.Identity.HALLOW,
		BiomeManager.OCEAN: GameplayBiome.Identity.OCEAN,
	}
	for biome: int in identity_for_biome.keys():
		_check(GameplayBiome.identity_for(biome) == identity_for_biome[biome],
			"gameplay identity matches engine id for " + BiomeManager.biome_name(biome))

	var centers := {}
	for biome in range(11):
		centers[biome] = _find_center(biome)
	var required := {
		# Forest lays green grass over dirt; mire_mud is the swamp/Jungle floor.
		BiomeManager.MIRE: &"ashen_soil",
		BiomeManager.DESERT: &"desert_sand",
		BiomeManager.JUNGLE: &"jungle_grass",
		BiomeManager.CORRUPTION: &"corrupted_grass",
		BiomeManager.CRIMSON: &"crimson_grass",
		BiomeManager.HALLOW: &"hallowed_grass",
		BiomeManager.FROST: &"frost_snow",
		BiomeManager.OCEAN: &"ocean_sand",
		BiomeManager.MUSHROOM: &"mycelium",
	}
	for biome: int in required.keys():
		var center: Vector2i = centers[biome]
		_check(center.x != 1 << 30, "biome has a region in the survey", BiomeManager.biome_name(biome))
		if center.x == 1 << 30:
			continue
		var expected: StringName = required[biome]
		var actual := _surface_block_at(center, biome)
		_check(actual == expected, "%s generates its signature surface" % BiomeManager.biome_name(biome),
			"expected=%s actual=%s at %s" % [String(expected), String(actual), str(center)])

	# The two evil identities must never both be active by default.
	var corruption_center: Vector2i = centers[BiomeManager.CORRUPTION]
	var crimson_center: Vector2i = centers[BiomeManager.CRIMSON]
	var hallow_center: Vector2i = centers[BiomeManager.HALLOW]
	BiomeManager.set_evil_mode("corruption")
	BiomeManager.set_hallow_enabled(false)
	var w := BiomeManager.get_weights(corruption_center.x, corruption_center.y)
	_check(w[BiomeManager.CRIMSON] == 0.0, "Corruption excludes The Crimson")
	_check(w[BiomeManager.HALLOW] == 0.0, "Hallow is locked before progression")
	_check(w[BiomeManager.CORRUPTION] > 0.0, "Corruption remains active")
	BiomeManager.set_evil_mode("crimson")
	w = BiomeManager.get_weights(crimson_center.x, crimson_center.y)
	_check(w[BiomeManager.CORRUPTION] == 0.0, "The Crimson excludes The Corruption")
	BiomeManager.set_evil_mode("both")
	w = BiomeManager.get_weights(crimson_center.x, crimson_center.y)
	_check(w[BiomeManager.CORRUPTION] > 0.0 and w[BiomeManager.CRIMSON] > 0.0,
		"explicit both-evil option keeps both identities available")
	BiomeManager.set_hallow_enabled(true)
	w = BiomeManager.get_weights(hallow_center.x, hallow_center.y)
	_check(w[BiomeManager.HALLOW] > 0.0, "Hallow unlocks when the progression gate opens")

	var ocean_center: Vector2i = centers[BiomeManager.OCEAN]
	var ocean_surface := BiomeManager.get_height(ocean_center.x, ocean_center.y)
	_check(ocean_surface < BiomeManager.WATER_LEVEL, "Ocean floor sits below sea level",
		"surface=%d sea=%d" % [ocean_surface, BiomeManager.WATER_LEVEL])
	var cx := ocean_center.x
	var cz := ocean_center.y
	var water_id := int(block_ids.get(&"water", -1))
	var chunk := Vector3i(floori(float(cx) / 16.0), floori(float(BiomeManager.WATER_LEVEL) / 16.0), floori(float(cz) / 16.0))
	var blocks := WorldGenerator.generate_chunk(chunk, SEED, block_ids)
	var local := posmod(cx, 16) + posmod(BiomeManager.WATER_LEVEL, 16) * 16 + posmod(cz, 16) * 256
	_check(int(blocks[local]) == water_id, "Ocean is flooded to sea level", "block=%s" % String(block_names.get(int(blocks[local]), &"?")))

	# Edge oceans: the far east/west limits of the streamed world become Ocean.
	for edge_x in [-4000, 4000]:
		var edge_weights := BiomeManager.get_weights(edge_x, 0)
		_check(edge_weights[BiomeManager.OCEAN] > 0.95, "edge ocean dominates at x=%d" % edge_x,
			"%.3f" % edge_weights[BiomeManager.OCEAN])
		var edge_surface := BiomeManager.get_height(edge_x, 0)
		_check(edge_surface < BiomeManager.WATER_LEVEL, "edge ocean floor is below sea level at x=%d" % edge_x,
			str(edge_surface))
		var edge_chunk := Vector3i(floori(float(edge_x) / 16.0), floori(float(BiomeManager.WATER_LEVEL) / 16.0), 0)
		var edge_blocks := WorldGenerator.generate_chunk(edge_chunk, SEED, block_ids)
		var edge_local := posmod(edge_x, 16) + posmod(BiomeManager.WATER_LEVEL, 16) * 16
		_check(int(edge_blocks[edge_local]) == water_id, "edge ocean is flooded at x=%d" % edge_x)

	# Underground identity: each new biome must own its stone below the surface.
	var underground_stones := {
		BiomeManager.JUNGLE: &"jungle_mudstone",
		BiomeManager.CORRUPTION: &"ebonstone",
		BiomeManager.CRIMSON: &"crimstone",
		BiomeManager.HALLOW: &"pearlstone",
		BiomeManager.OCEAN: &"reefstone",
	}
	for biome: int in underground_stones.keys():
		var center: Vector2i = centers[biome]
		var stone_name: StringName = underground_stones[biome]
		var count := _count_in_chunks(center, stone_name, 1, [28, 42, 56])
		_check(count > 0, "%s has its own underground stone" % BiomeManager.biome_name(biome),
			"%s=%d" % [String(stone_name), count])

	# Unique biome resources must physically appear in generated terrain.
	var biome_ores := {
		BiomeManager.JUNGLE: &"amber_ore",
		BiomeManager.CORRUPTION: &"void_ore",
		BiomeManager.CRIMSON: &"blood_ore",
		BiomeManager.HALLOW: &"radiant_crystal_ore",
		BiomeManager.OCEAN: &"pearl_ore",
	}
	for biome: int in biome_ores.keys():
		var center: Vector2i = centers[biome]
		var ore_name: StringName = biome_ores[biome]
		var count := _count_in_chunks(center, ore_name, 1, [24, 48, 72])
		_check(count > 0, "%s generates its unique ore" % BiomeManager.biome_name(biome),
			"%s=%d" % [String(ore_name), count])

	# Hallow is NOT unlocked by the optional Hollow Warden; the debug override
	# and a future Underworld event are the only ways in.
	_check(TerrariaWorldContent.HALLOW_INTRODUCTION_FLAG != "hollow_warden_defeated",
		"the Hollow Warden is not the Hallow unlock")
	_check(TerrariaWorldContent.HALLOW_DEBUG_OVERRIDE, "Hallow debug override is available")
	BiomeManager.set_hallow_enabled(false)
	w = BiomeManager.get_weights(hallow_center.x, hallow_center.y)
	_check(w[BiomeManager.HALLOW] == 0.0, "Hallow stays locked by default")
	BiomeManager.set_hallow_enabled(true)
	w = BiomeManager.get_weights(hallow_center.x, hallow_center.y)
	_check(w[BiomeManager.HALLOW] > 0.0, "Hallow debug override generates the biome")

	# Jungle caves are physically larger than the normal tunnel field.
	var jungle_center: Vector2i = centers[BiomeManager.JUNGLE]
	var jungle_surface := BiomeManager.get_height(jungle_center.x, jungle_center.y)
	var chamber_cells := 0
	for z in range(jungle_center.y - 8, jungle_center.y + 9, 4):
		for x in range(jungle_center.x - 8, jungle_center.x + 9, 4):
			for y in range(jungle_surface - 96, jungle_surface - 18, 4):
				if WorldCaves.is_biome_chamber(x, y, z, jungle_surface, BiomeManager.JUNGLE):
					chamber_cells += 1
	_check(chamber_cells > 0, "Jungle opens larger underground chambers", str(chamber_cells))

	# Determinism and border continuity on the new field.
	var jungle_chunk := Vector3i(jungle_center.x >> 4, (jungle_surface - 40) >> 4, jungle_center.y >> 4)
	var first := WorldGenerator.generate_chunk(jungle_chunk, SEED, block_ids)
	var second := WorldGenerator.generate_chunk(jungle_chunk, SEED, block_ids)
	_check(first == second, "identical seeds regenerate identical terrain")
	var max_step := 0
	for step in range(256):
		var sx := jungle_center.x - 128 + step
		max_step = maxi(max_step, absi(BiomeManager.get_height(sx, 0) - BiomeManager.get_height(sx + 1, 0)))
	_check(max_step <= 12, "biome borders remain walkable", "max_height_step=%d" % max_step)


func _count_in_chunks(center: Vector2i, block_name: StringName, radius_chunks: int, depths: Array) -> int:
	var target := int(block_ids.get(block_name, -1))
	if target < 0:
		return 0
	var surface := BiomeManager.get_height(center.x, center.y)
	var count := 0
	var seen: Dictionary = {}
	for dz in range(-radius_chunks, radius_chunks + 1):
		for dx in range(-radius_chunks, radius_chunks + 1):
			for depth: int in depths:
				var chunk := Vector3i((center.x >> 4) + dx, (surface - depth) >> 4, (center.y >> 4) + dz)
				if seen.has(chunk):
					continue
				seen[chunk] = true
				var blocks := WorldGenerator.generate_chunk(chunk, SEED, block_ids)
				for index in range(blocks.size()):
					if int(blocks[index]) == target:
						count += 1
	return count


func _find_center(biome: int) -> Vector2i:
	var best := Vector2i(1 << 30, 1 << 30)
	var best_weight := -1.0
	for z in range(-SCAN_RADIUS, SCAN_RADIUS + 1, SCAN_STEP):
		for x in range(-SCAN_RADIUS, SCAN_RADIUS + 1, SCAN_STEP):
			if BiomeManager.surface_biome(x, z) != biome:
				continue
			var weight := BiomeManager.get_weights(x, z)[biome]
			if weight > best_weight:
				best_weight = weight
				best = Vector2i(x, z)
	return best


func _surface_block_at(center: Vector2i, biome: int) -> StringName:
	# The dominant sample can sit on a dithered border, so nudge to a column
	# that the generator itself classifies as this biome.
	for dz in [0, 8, -8, 16, -16, 24, -24, 32, -32, 48, -48]:
		for dx in [0, 8, -8, 16, -16, 24, -24, 32, -32, 48, -48]:
			var cx: int = center.x + int(dx)
			var cz: int = center.y + int(dz)
			if BiomeManager.surface_biome(cx, cz) != biome:
				continue
			var surface_y := BiomeManager.get_height(cx, cz)
			var chunk := Vector3i(floori(float(cx) / 16.0), floori(float(surface_y) / 16.0), floori(float(cz) / 16.0))
			var blocks := WorldGenerator.generate_chunk(chunk, SEED, block_ids)
			var local := posmod(cx, 16) + posmod(surface_y, 16) * 16 + posmod(cz, 16) * 256
			return StringName(block_names.get(int(blocks[local]), &"?"))
	return &"?"
