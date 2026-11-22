extends RefCounted
class_name WorldGenerator

# Coordinate-based chunk generation for the streaming world. The generator no
# longer reads a global height map: every column asks BiomeManager, every feature
# is derived from a world-coordinate grid, and the output depends only on
# (world_seed, chunk origin). That is what allows chunks to be built in worker
# threads and regenerated identically after they have been unloaded.

const DEFAULT_SEED := 139732
const CHUNK_SIZE := 16
const WORLD_Y := 256
const CHUNKS_Y := 16

const SPAWN_X := 64
const SPAWN_Z := 64
const SPAWN_CLEAR_RADIUS := 4.0
const SPAWN_BLEND_RADIUS := 8.0

const TREE_CELL := 14
const TREE_CHANCE := 0.18
# The Overworld (MIRE id) is the green starting region: more trees than Ashen.
const OVERWORLD_TREE_CHANCE := 0.46
const CRYSTAL_CELL := 24
const CRYSTAL_CHANCE := 0.26
const HUSH_TREE_CELL := 4
const HUSH_TREE_CHANCE := 0.78
const HUSH_TREE_REACH := 6
const HUSH_TREE_MIN_HEIGHT := 12
const HUSH_TREE_MAX_HEIGHT := 20
const FROST_SPIRE_CELL := 8
const FROST_SPIRE_CHANCE := 0.5
const FROST_SPIRE_REACH := 6
const MIRE_ROOT_CELL := 7
const MIRE_ROOT_CHANCE := 0.45
const MIRE_ROOT_REACH := 6
const PROP_CELL := 11
const PROP_CHANCE := 0.16
const PROP_REACH := 8
const DERELICT_CELL := 48
const DERELICT_CHANCE := 0.38
const DERELICT_REACH := 10
const SCATTER_CELL := 5
const SCATTER_CHANCE := 0.012

const LANDMARK_TREES := [
	Vector2i(75, 60), Vector2i(54, 67), Vector2i(68, 72), Vector2i(61, 80),
	Vector2i(57, 57), Vector2i(71, 69), Vector2i(58, 73), Vector2i(73, 56),
]
const LANDMARK_CRYSTALS := [Vector2i(80, 51), Vector2i(46, 77)]
const LANDMARK_SPIRES := [Vector2i(78, 110), Vector2i(44, 120), Vector2i(38, 58)]
const BRANCH_DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1),
	Vector3i(-1, 0, 1), Vector3i(-1, 0, -1)
]


static func generate_chunk(chunk: Vector3i, world_seed: int, block_ids: Dictionary, modifications: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	BiomeManager.configure(world_seed)
	WorldCaves.configure(world_seed)
	WorldOres.configure(world_seed)
	WorldBiomes.configure(world_seed)
	var origin := chunk * CHUNK_SIZE
	var output := PackedByteArray()
	output.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
	output.fill(int(block_ids[&"air"]))

	var air_id := int(block_ids[&"air"])
	var stone_id := int(block_ids[&"stone"])
	var ashen_soil_id := int(block_ids[&"ashen_soil"])
	var dirt_id := int(block_ids.get(&"dirt", ashen_soil_id))
	var gravel_id := int(block_ids.get(&"canyon_gravel", ashen_soil_id))
	var mycelium_id := int(block_ids.get(&"mycelium", ashen_soil_id))
	var rotted_id := int(block_ids.get(&"rotted_ashen_soil", ashen_soil_id))
	var frost_snow_id := int(block_ids.get(&"frost_snow", ashen_soil_id))
	var frost_ice_id := int(block_ids.get(&"frost_ice", stone_id))
	var mire_mud_id := int(block_ids.get(&"mire_mud", ashen_soil_id))
	var toxic_silt_id := int(block_ids.get(&"toxic_silt", mire_mud_id))
	var crystal_id := int(block_ids[&"lumen_crystal"])
	var deepstone_id := int(block_ids.get(&"deepstone", stone_id))
	var desert_sand_id := int(block_ids.get(&"desert_sand", ashen_soil_id))
	var sandstone_id := int(block_ids.get(&"sandstone", stone_id))
	var mushroom_soil_id := int(block_ids.get(&"mushroom_soil", mycelium_id))
	var jungle_grass_id := int(block_ids.get(&"jungle_grass", mire_mud_id))
	var jungle_mudstone_id := int(block_ids.get(&"jungle_mudstone", mire_mud_id))
	var ebonstone_id := int(block_ids.get(&"ebonstone", stone_id))
	var corrupted_grass_id := int(block_ids.get(&"corrupted_grass", ashen_soil_id))
	var crimstone_id := int(block_ids.get(&"crimstone", stone_id))
	var crimson_grass_id := int(block_ids.get(&"crimson_grass", ashen_soil_id))
	var pearlstone_id := int(block_ids.get(&"pearlstone", stone_id))
	var hallowed_grass_id := int(block_ids.get(&"hallowed_grass", frost_snow_id))
	var ocean_sand_id := int(block_ids.get(&"ocean_sand", desert_sand_id))
	var water_id := int(block_ids.get(&"water", -1))
	var lava_id := int(block_ids.get(&"lava", -1))
	var torch_id := int(block_ids.get(&"torch", -1))
	var ash_id := int(block_ids.get(&"ash", stone_id))
	var obsidian_id := int(block_ids.get(&"obsidian", stone_id))

	var heights := _height_cache(origin)
	# A chunk entirely above the local surface cannot contain a cave, so its
	# column cache is skipped. Sky/cloud chunks then cost almost nothing.
	var cave_cache: Dictionary = {}
	var max_surface := origin.y - 1
	for index in range(heights.size()):
		max_surface = maxi(max_surface, heights[index])
	if origin.y <= max_surface:
		cave_cache = WorldCaves.build_cache(origin)
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(world_seed, origin)
	for z in range(CHUNK_SIZE):
		var world_z := origin.z + z
		for x in range(CHUNK_SIZE):
			var world_x := origin.x + x
			var surface_y := heights[_cache_index(x, z)]
			var biome := BiomeManager.surface_biome(world_x, world_z)
			var slope := _cache_slope(heights, x, z)
			var canyon_floor := BiomeManager.is_canyon_floor(world_x, world_z)
			var rocky := slope >= 2 or BiomeManager.rock_noise(world_x, world_z) > 0.62
			# Per-biome surface/subsurface recipe.
			# Forest is green grass over brown dirt, as in Terraria; the old
			# build reused the grey ashen soil for both and read as olive mud.
			var top_id := ashen_soil_id
			var sub_id := dirt_id
			var sub_depth := 3
			match biome:
					BiomeManager.HUSH:
				# Jungle floor is bright jungle grass over jungle mudstone,
				# matching Terraria's vibrant Jungle biome.
				top_id = jungle_grass_id
				sub_id = jungle_mudstone_id
					sub_depth = 4
				BiomeManager.FROST:
				top_id = frost_snow_id
				sub_id = frost_ice_id
				sub_depth = 3
				BiomeManager.MIRE:
				# Forest ground is Terraria's bright grass over brown dirt. It
				# used to be mire_mud here, whose albedo (0.16,0.24,0.13) and
				# DEEP_MUD tile are the swamp material, which is what made the
				# forest floor read as near-black moss.
				top_id = ashen_soil_id
				sub_id = dirt_id
				sub_depth = 4
				BiomeManager.DESERT:
				top_id = desert_sand_id
				sub_id = sandstone_id
				sub_depth = 5
					BiomeManager.MUSHROOM:
						top_id = mycelium_id
						sub_id = mushroom_soil_id
						sub_depth = 4
						BiomeManager.JUNGLE:
				# Jungle floor is bright jungle grass over jungle mudstone,
				# matching Terraria's vibrant Jungle biome.
				top_id = jungle_grass_id
				sub_id = jungle_mudstone_id
				sub_depth = 5
				BiomeManager.CORRUPTION:
				top_id = corrupted_grass_id
				sub_id = ebonstone_id
				sub_depth = 4
				BiomeManager.CRIMSON:
				top_id = crimson_grass_id
				sub_id = crimstone_id
				sub_depth = 4
				BiomeManager.HALLOW:
				top_id = hallowed_grass_id
				sub_id = pearlstone_id
				sub_depth = 4
				BiomeManager.OCEAN:
				top_id = ocean_sand_id
					sub_id = sandstone_id
					sub_depth = 4
				_:
					if canyon_floor:
						top_id = gravel_id
						sub_id = gravel_id
					elif rocky:
						top_id = stone_id
						sub_id = stone_id
			for y in range(CHUNK_SIZE):
				var world_y := origin.y + y
				if world_x == 64 and world_z == 58 and world_y == surface_y + 1 and torch_id >= 0:
					output[_local_index(x, y, z)] = torch_id
					continue
				if world_y > surface_y:
					# Ocean columns are flooded up to sea level; inland air stays air.
					if biome == BiomeManager.OCEAN and world_y <= BiomeManager.WATER_LEVEL and water_id >= 0:
						output[_local_index(x, y, z)] = water_id
					continue
				var block_id: int
				if world_y == surface_y:
					block_id = top_id
				elif world_y >= surface_y - sub_depth:
					block_id = sub_id
					if biome == BiomeManager.MIRE and world_y <= BiomeManager.WATER_LEVEL + 2:
						block_id = toxic_silt_id if world_y < surface_y - 1 else mire_mud_id
				else:
					var depth := surface_y - world_y
					block_id = stone_id
					# The Underworld is a real generated region, not a renamed abyss:
					# a lava sea fills the floor, obsidian crusts its edges and the
					# rock above it is ash. It is reachable by digging any deep shaft.
					if depth >= WorldLayers.UNDERWORLD_DEPTH:
						var underworld_roll := _cell_hash(world_x, world_y, world_z, world_seed ^ 0x4E11)
						if world_y <= 19 and lava_id >= 0:
							block_id = lava_id if underworld_roll > 0.08 else obsidian_id
							output[_local_index(x, y, z)] = block_id
							continue
						if world_y <= 30 and underworld_roll < 0.55:
							block_id = obsidian_id if underworld_roll < 0.10 else air_id
							output[_local_index(x, y, z)] = block_id
							continue
						block_id = ash_id
					var carved := WorldCaves.is_cave_cached(cave_cache, world_x, world_y, world_z, surface_y)
					if not carved and WorldCaves.is_biome_chamber(world_x, world_y, world_z, surface_y, biome):
						carved = true
					if carved:
						var liquid := WorldCaves.liquid_at_cached(cave_cache, world_x, world_y, world_z, surface_y)
						if liquid == 1 and water_id >= 0:
							block_id = water_id
						elif liquid == 2 and lava_id >= 0:
							block_id = lava_id
						else:
							block_id = air_id
					else:
						# Rock identity is owned by WorldBiomes; only solid cells pay for
						# it, which keeps carved cave volumes cheap to generate.
						var underground_biome := WorldBiomes.underground_biome_at(world_x, world_y, world_z, surface_y, biome)
						var stone_name := WorldBiomes.stone_name(underground_biome, depth)
						if stone_name != &"" and block_ids.has(stone_name):
							block_id = int(block_ids[stone_name])
						var ore_name := WorldOres.ore_at(world_x, world_y, world_z, surface_y, biome, underground_biome)
						if ore_name != &"" and block_ids.has(ore_name):
							block_id = int(block_ids[ore_name])
						elif crystal_id >= 0 and WorldCaves.is_crystal_chamber(world_x, world_y, world_z, surface_y):
							# Crystal chambers line their walls sparsely, so the chamber
							# reads as a find rather than an ore blob.
							if _cell_hash(world_x, world_y, world_z, world_seed) < 0.12:
								block_id = crystal_id
				output[_local_index(x, y, z)] = block_id

	_stamp_tree_stumps(output, origin, world_seed, block_ids)
	_stamp_crystal_clusters(output, origin, world_seed, crystal_id)
	_stamp_ashen_props(output, origin, world_seed, stone_id, air_id)
	_stamp_derelict_camps(output, origin, world_seed, block_ids, stone_id, air_id)
	_stamp_landmark_spires(output, origin, world_seed, stone_id, air_id)
	WorldStructures.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)
	_stamp_biome_props(output, origin, world_seed, block_ids)
	_stamp_underground_props(output, origin, world_seed, block_ids, air_id)
	WorldSky.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)
	# Agent 4 authored region (additive, deterministic, worker-safe). The
	# Undercroft is ONE hand-authored multi-room dungeon rather than a repeating
	# WorldStructures template, so it is stamped directly with the canonical
	# air/stone ids. Disable via AdventureConfig.enable_undercroft.
	AdventureContent.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)
	# Jungle trees, Snow ice spires and Mire roots are now low-poly
	# MultiMesh props (WorldVegetation); no voxel tree/spire columns are stamped.

	if modifications.size() == CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE:
		return modifications.duplicate()
	return output


static func is_canyon_floor(x: int, z: int) -> bool:
	return BiomeManager.is_canyon_floor(x, z)


static func _height_cache(origin: Vector3i) -> PackedInt32Array:
	var cache := PackedInt32Array()
	cache.resize(18 * 18)
	for z in range(-1, CHUNK_SIZE + 1):
		for x in range(-1, CHUNK_SIZE + 1):
			cache[(x + 1) + (z + 1) * 18] = BiomeManager.get_height(origin.x + x, origin.z + z)
	return cache


static func _cache_index(x: int, z: int) -> int:
	return (x + 1) + (z + 1) * 18


static func _cache_slope(heights: PackedInt32Array, x: int, z: int) -> int:
	var here := heights[_cache_index(x, z)]
	var slope := absi(here - heights[_cache_index(x - 1, z)])
	slope = maxi(slope, absi(here - heights[_cache_index(x + 1, z)]))
	slope = maxi(slope, absi(here - heights[_cache_index(x, z - 1)]))
	slope = maxi(slope, absi(here - heights[_cache_index(x, z + 1)]))
	return slope


static func _flat_at(x: int, z: int) -> bool:
	var here := BiomeManager.get_height(x, z)
	return absi(BiomeManager.get_height(x - 1, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x + 1, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z - 1) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z + 1) - here) <= 1


static func _local_index(x: int, y: int, z: int) -> int:
	return x + y * CHUNK_SIZE + z * CHUNK_SIZE * CHUNK_SIZE


static func _get_cell(output: PackedByteArray, origin: Vector3i, cell: Vector3i) -> int:
	var local_x := cell.x - origin.x
	var local_y := cell.y - origin.y
	var local_z := cell.z - origin.z
	if local_x < 0 or local_x >= CHUNK_SIZE or local_y < 0 or local_y >= CHUNK_SIZE or local_z < 0 or local_z >= CHUNK_SIZE:
		return -1
	return output[_local_index(local_x, local_y, local_z)]


static func _set_cell(output: PackedByteArray, origin: Vector3i, cell: Vector3i, block_id: int) -> void:
	if block_id < 0:
		return
	var local_x := cell.x - origin.x
	var local_y := cell.y - origin.y
	var local_z := cell.z - origin.z
	if local_x < 0 or local_x >= CHUNK_SIZE or local_y < 0 or local_y >= CHUNK_SIZE or local_z < 0 or local_z >= CHUNK_SIZE:
		return
	output[_local_index(local_x, local_y, local_z)] = block_id


# --- Dead tree sites (Forest) -------------------------------------------

static func collect_tree_sites_region(world_seed: int, min_x: int, min_z: int, max_x: int, max_z: int) -> Array:
	BiomeManager.configure(world_seed)
	var sites: Array = []
	var min_gx := floori(float(min_x) / float(TREE_CELL)) - 1
	var max_gx := floori(float(max_x) / float(TREE_CELL)) + 1
	var min_gz := floori(float(min_z) / float(TREE_CELL)) - 1
	var max_gz := floori(float(max_z) / float(TREE_CELL)) + 1
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var site := _tree_site(world_seed, grid_x, grid_z)
			if site.is_empty():
				continue
			if int(site["x"]) < min_x or int(site["x"]) > max_x or int(site["z"]) < min_z or int(site["z"]) > max_z:
				continue
			sites.append(site)
	for landmark: Vector2i in LANDMARK_TREES:
		if landmark.x < min_x or landmark.x > max_x or landmark.y < min_z or landmark.y > max_z:
			continue
		var landmark_rng := RandomNumberGenerator.new()
		landmark_rng.seed = _column_seed(world_seed, landmark.x, landmark.y, 0x9E37)
		sites.append({
			"x": landmark.x,
			"z": landmark.y,
			"y": BiomeManager.get_height(landmark.x, landmark.y),
			"seed": landmark_rng.randi(),
			"landmark": true,
		})
	return sites


static func _tree_site(world_seed: int, grid_x: int, grid_z: int) -> Dictionary:
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = _column_seed(world_seed, grid_x, grid_z, 0x7A11)
	var base_x := grid_x * TREE_CELL + tree_rng.randi_range(3, TREE_CELL - 4)
	var base_z := grid_z * TREE_CELL + tree_rng.randi_range(3, TREE_CELL - 4)
	var biome := BiomeManager.dominant_biome(base_x, base_z)
	var chance := OVERWORLD_TREE_CHANCE if biome == BiomeManager.MIRE else TREE_CHANCE
	if biome != BiomeManager.ASHEN and biome != BiomeManager.MIRE:
		return {}
	if tree_rng.randf() > chance:
		return {}
	if absi(base_x - SPAWN_X) <= 7 and absi(base_z - SPAWN_Z) <= 7:
		return {}
	if BiomeManager.is_canyon_floor(base_x, base_z):
		return {}
	for landmark: Vector2i in LANDMARK_TREES:
		if absi(base_x - landmark.x) <= 4 and absi(base_z - landmark.y) <= 4:
			return {}
	for landmark: Vector2i in LANDMARK_CRYSTALS:
		if absi(base_x - landmark.x) <= 7 and absi(base_z - landmark.y) <= 7:
			return {}
	if not _flat_at(base_x, base_z):
		return {}
	return {
		"x": base_x,
		"z": base_z,
		"y": BiomeManager.get_height(base_x, base_z),
		"seed": tree_rng.randi(),
		"landmark": false,
	}


static func _stamp_tree_stumps(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary) -> void:
	var wood_id := int(block_ids.get(&"dead_wood", -1))
	if wood_id < 0:
		return
	var sites := collect_tree_sites_region(world_seed, origin.x, origin.z, origin.x + CHUNK_SIZE - 1, origin.z + CHUNK_SIZE - 1)
	for site in sites:
		_set_cell(output, origin, Vector3i(int(site["x"]), int(site["y"]), int(site["z"])), wood_id)


# --- Arcane crystal clusters --------------------------------------------------

static func _stamp_crystal_clusters(output: PackedByteArray, origin: Vector3i, world_seed: int, crystal_id: int) -> void:
	var min_gx := floori(float(origin.x - 10) / float(CRYSTAL_CELL))
	var max_gx := floori(float(origin.x + CHUNK_SIZE - 1 + 10) / float(CRYSTAL_CELL))
	var min_gz := floori(float(origin.z - 10) / float(CRYSTAL_CELL))
	var max_gz := floori(float(origin.z + CHUNK_SIZE - 1 + 10) / float(CRYSTAL_CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var cluster_rng := RandomNumberGenerator.new()
			cluster_rng.seed = _column_seed(world_seed, grid_x, grid_z, 0xC0DE)
			if cluster_rng.randf() > CRYSTAL_CHANCE:
				continue
			var base_x := grid_x * CRYSTAL_CELL + cluster_rng.randi_range(3, CRYSTAL_CELL - 4)
			var base_z := grid_z * CRYSTAL_CELL + cluster_rng.randi_range(3, CRYSTAL_CELL - 4)
			if BiomeManager.dominant_biome(base_x, base_z) != BiomeManager.ASHEN:
				continue
			if absi(base_x - SPAWN_X) <= 7 and absi(base_z - SPAWN_Z) <= 7:
				continue
			if not _flat_at(base_x, base_z):
				continue
			var base_y := BiomeManager.get_height(base_x, base_z)
			var center_height := cluster_rng.randi_range(6, 8)
			_stamp_shard(output, origin, crystal_id, base_x, base_z, base_y, center_height, 1)
			var shard_count := cluster_rng.randi_range(2, 3)
			for shard in range(shard_count):
				var angle := cluster_rng.randf_range(0.0, TAU)
				var radius := cluster_rng.randf_range(2.2, 3.8)
				var shard_x := base_x + roundi(cos(angle) * radius)
				var shard_z := base_z + roundi(sin(angle) * radius)
				var shard_y := BiomeManager.get_height(shard_x, shard_z)
				_stamp_shard(output, origin, crystal_id, shard_x, shard_z, shard_y, cluster_rng.randi_range(3, 5), 1)


static func _stamp_shard(output: PackedByteArray, origin: Vector3i, crystal_id: int, base_x: int, base_z: int, ground_y: int, shard_height: int, width: int) -> void:
	for step in range(shard_height):
		var step_width := width if step < shard_height - 3 else 1
		for wide_x in range(step_width):
			for wide_z in range(step_width):
				_set_cell(output, origin, Vector3i(base_x + wide_x, ground_y + step, base_z + wide_z), crystal_id)


# --- Ashen props -------------------------------------------------------------

static func _stamp_ashen_props(output: PackedByteArray, origin: Vector3i, world_seed: int, stone_id: int, air_id: int) -> void:
	var min_gx := floori(float(origin.x - PROP_REACH) / float(PROP_CELL))
	var max_gx := floori(float(origin.x + CHUNK_SIZE - 1 + PROP_REACH) / float(PROP_CELL))
	var min_gz := floori(float(origin.z - PROP_REACH) / float(PROP_CELL))
	var max_gz := floori(float(origin.z + CHUNK_SIZE - 1 + PROP_REACH) / float(PROP_CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var prop_rng := RandomNumberGenerator.new()
			prop_rng.seed = _column_seed(world_seed, grid_x, grid_z, 0x9A17)
			if prop_rng.randf() > PROP_CHANCE:
				continue
			var base_x := grid_x * PROP_CELL + prop_rng.randi_range(1, PROP_CELL - 2)
			var base_z := grid_z * PROP_CELL + prop_rng.randi_range(1, PROP_CELL - 2)
			if absi(base_x - SPAWN_X) <= 7 and absi(base_z - SPAWN_Z) <= 7:
				continue
			if BiomeManager.dominant_biome(base_x, base_z) != BiomeManager.ASHEN:
				continue
			if BiomeManager.is_canyon_floor(base_x, base_z) or not _flat_at(base_x, base_z):
				continue
			if prop_rng.randf() < 0.45:
				_stamp_pebbles(output, origin, prop_rng, base_x, base_z, stone_id, air_id)
			else:
				_stamp_boulder(output, origin, prop_rng, base_x, base_z, stone_id, air_id)


static func _stamp_pebbles(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, base_x: int, base_z: int, stone_id: int, air_id: int) -> void:
	_place_prop_cell(output, origin, base_x, base_z, 1, stone_id, air_id)
	for pebble in range(rng.randi_range(1, 3)):
		_place_prop_cell(output, origin, base_x + rng.randi_range(-1, 1), base_z + rng.randi_range(-1, 1), 1, stone_id, air_id)


static func _stamp_boulder(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, base_x: int, base_z: int, stone_id: int, air_id: int) -> void:
	var width := rng.randi_range(1, 2)
	var height := rng.randi_range(2, 4)
	for level in range(height):
		var radius := width if level == 0 else maxi(0, width - 1)
		for offset_z in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if offset_x * offset_x + offset_z * offset_z > radius * radius + 1:
					continue
				if level > 0 and rng.randf() < 0.22:
					continue
				_place_prop_cell(output, origin, base_x + offset_x, base_z + offset_z, 1 + level, stone_id, air_id)


static func _place_prop_cell(output: PackedByteArray, origin: Vector3i, x: int, z: int, offset_y: int, block_id: int, air_id: int) -> void:
	var cell := Vector3i(x, BiomeManager.get_height(x, z) + offset_y, z)
	if cell.y < 1 or cell.y >= WORLD_Y - 1:
		return
	if _get_cell(output, origin, cell) != air_id:
		return
	_set_cell(output, origin, cell, block_id)


# --- Abandoned camps (environmental storytelling + resource caches) ----------

static func _derelict_site(world_seed: int, grid_x: int, grid_z: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _column_seed(world_seed, grid_x, grid_z, 0xD1E1)
	if rng.randf() > DERELICT_CHANCE:
		return {}
	var base_x := grid_x * DERELICT_CELL + rng.randi_range(6, DERELICT_CELL - 7)
	var base_z := grid_z * DERELICT_CELL + rng.randi_range(6, DERELICT_CELL - 7)
	if BiomeManager.dominant_biome(base_x, base_z) != BiomeManager.ASHEN:
		return {}
	if BiomeManager.is_canyon_floor(base_x, base_z) or not _flat_at(base_x, base_z):
		return {}
	if Vector2(float(base_x - SPAWN_X), float(base_z - SPAWN_Z)).length() < 24.0:
		return {}
	return {"x": base_x, "z": base_z, "y": BiomeManager.get_height(base_x, base_z)}


static func derelict_site_near(world_seed: int, x: int, z: int) -> Dictionary:
	var grid_x := floori(float(x) / float(DERELICT_CELL))
	var grid_z := floori(float(z) / float(DERELICT_CELL))
	for offset_z in range(-1, 2):
		for offset_x in range(-1, 2):
			var site := _derelict_site(world_seed, grid_x + offset_x, grid_z + offset_z)
			if site.is_empty():
				continue
			if absi(int(site["x"]) - x) <= 4 and absi(int(site["z"]) - z) <= 4:
				return site
	return {}


static func _stamp_derelict_camps(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, stone_id: int, air_id: int) -> void:
	var torch_id := int(block_ids.get(&"torch", -1))
	var iron_id := int(block_ids.get(&"iron_ore", -1))
	var crystal_id := int(block_ids.get(&"lumen_crystal", -1))
	var min_gx := floori(float(origin.x - DERELICT_REACH) / float(DERELICT_CELL))
	var max_gx := floori(float(origin.x + CHUNK_SIZE - 1 + DERELICT_REACH) / float(DERELICT_CELL))
	var min_gz := floori(float(origin.z - DERELICT_REACH) / float(DERELICT_CELL))
	var max_gz := floori(float(origin.z + CHUNK_SIZE - 1 + DERELICT_REACH) / float(DERELICT_CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var site := _derelict_site(world_seed, grid_x, grid_z)
			if site.is_empty():
				continue
			var base_x := int(site["x"])
			var base_z := int(site["z"])
			var rng := RandomNumberGenerator.new()
			rng.seed = _column_seed(world_seed, base_x, base_z, 0xCAF1)
			# A collapsed shelter: three stub walls and one low lintel remnant.
			for offset in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2), Vector2i(-2, 0), Vector2i(2, 0)]:
				if rng.randf() < 0.28:
					continue
				_place_prop_cell(output, origin, base_x + offset.x, base_z + offset.y, 1, stone_id, air_id)
				if rng.randf() < 0.45:
					_place_prop_cell(output, origin, base_x + offset.x, base_z + offset.y, 2, stone_id, air_id)
			# The one good light: a beacon of the people who camped here. It is
			# also bait for the Lamp Eater, which makes the site contested.
			if torch_id >= 0:
				_place_prop_cell(output, origin, base_x + 1, base_z, 1, torch_id, air_id)
			# A small, collectible cache for the survivor who finds the site.
			if iron_id >= 0:
				_place_prop_cell(output, origin, base_x - 1, base_z, 1, iron_id, air_id)
			if crystal_id >= 0:
				_place_prop_cell(output, origin, base_x, base_z + 1, 1, crystal_id, air_id)


# --- Jungle pale trees ----------------------------------------------------

static func _stamp_hush_trees(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary) -> void:
	var wood_id := int(block_ids.get(&"pale_wood", block_ids.get(&"dead_wood", -1)))
	if wood_id < 0:
		return
	var min_gx := floori(float(origin.x - HUSH_TREE_REACH) / float(HUSH_TREE_CELL))
	var max_gx := floori(float(origin.x + CHUNK_SIZE - 1 + HUSH_TREE_REACH) / float(HUSH_TREE_CELL))
	var min_gz := floori(float(origin.z - HUSH_TREE_REACH) / float(HUSH_TREE_CELL))
	var max_gz := floori(float(origin.z + CHUNK_SIZE - 1 + HUSH_TREE_REACH) / float(HUSH_TREE_CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var tree_rng := RandomNumberGenerator.new()
			tree_rng.seed = _column_seed(world_seed, grid_x, grid_z, 0x6E55)
			if tree_rng.randf() > HUSH_TREE_CHANCE:
				continue
			var base_x := grid_x * HUSH_TREE_CELL + tree_rng.randi_range(1, HUSH_TREE_CELL - 2)
			var base_z := grid_z * HUSH_TREE_CELL + tree_rng.randi_range(1, HUSH_TREE_CELL - 2)
			if BiomeManager.get_weights(base_x, base_z)[BiomeManager.HUSH] <= 0.5:
				continue
			if not _flat_at(base_x, base_z):
				continue
			var base_y := BiomeManager.get_height(base_x, base_z)
			if base_y < 15:
				continue
			var height := tree_rng.randi_range(HUSH_TREE_MIN_HEIGHT, HUSH_TREE_MAX_HEIGHT)
			_stamp_hush_tree(output, origin, tree_rng, base_x, base_y, base_z, height, wood_id)


static func _stamp_hush_tree(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, base_x: int, base_y: int, base_z: int, height: int, wood_id: int) -> void:
	var lean := Vector2i.ZERO
	if rng.randf() < 0.7:
		lean = Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		if lean == Vector2i.ZERO:
			lean = Vector2i(1, 0)
	var x := base_x
	var z := base_z
	for step in range(height):
		var y := base_y + 1 + step
		_set_cell(output, origin, Vector3i(x, y, z), wood_id)
		if step == 0:
			_set_cell(output, origin, Vector3i(x + lean.x, y, z), wood_id)
			_set_cell(output, origin, Vector3i(x, y, z + lean.y), wood_id)
		if step >= 4 and step <= height - 3 and step % 3 == 2 and rng.randf() < 0.6:
			x += lean.x
			z += lean.y
		if step >= 4 and step % 3 == 0 and rng.randf() < 0.7:
			_stamp_hush_branch(output, origin, rng, Vector3i(x, y, z), wood_id)
	_stamp_hush_branch(output, origin, rng, Vector3i(x, base_y + height, z), wood_id)


static func _stamp_hush_branch(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, start: Vector3i, wood_id: int) -> void:
	var direction: Vector3i = BRANCH_DIRECTIONS[rng.randi_range(0, BRANCH_DIRECTIONS.size() - 1)]
	var length := rng.randi_range(2, 4)
	var x := start.x
	var y := start.y
	var z := start.z
	for step in range(length):
		x += direction.x
		z += direction.z
		if step % 2 == 1:
			y += 1
		_set_cell(output, origin, Vector3i(x, y, z), wood_id)
		if rng.randf() < 0.3:
			_set_cell(output, origin, Vector3i(x, y + 1, z), wood_id)
	_set_cell(output, origin, Vector3i(x, y + 1, z), wood_id)
	_set_cell(output, origin, Vector3i(x, y + 2, z), wood_id)


# --- Ashen landmark spires ---------------------------------------------------

# Three deliberate stone buttes break the horizon. Each is stamped from its
# fixed root, so neighbouring chunks reproduce the same blocks without seams.
static func _stamp_landmark_spires(output: PackedByteArray, origin: Vector3i, world_seed: int, stone_id: int, air_id: int) -> void:
	var chunk_max_x := origin.x + CHUNK_SIZE - 1
	var chunk_max_z := origin.z + CHUNK_SIZE - 1
	for spire: Vector2i in LANDMARK_SPIRES:
		if spire.x + 12 < origin.x or spire.x - 12 > chunk_max_x or spire.y + 12 < origin.z or spire.y - 12 > chunk_max_z:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _column_seed(world_seed, spire.x, spire.y, 0x5A17)
		var base_y := BiomeManager.get_height(spire.x, spire.y)
		var height := rng.randi_range(6, 9)
		var lean := Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		if lean == Vector2i.ZERO:
			lean = Vector2i(1, 0)
		var x := spire.x
		var z := spire.y
		for step in range(height):
			var y := base_y + 1 + step
			var radius := 2 if step < height - 3 else 1
			if step == 0:
				radius = 3
			for offset_z in range(-radius, radius + 1):
				for offset_x in range(-radius, radius + 1):
					if offset_x * offset_x + offset_z * offset_z > radius * radius + 1:
						continue
					if step > 0 and rng.randf() < 0.16:
						continue
					var cell_x := x + offset_x
					var cell_z := z + offset_z
					var column_ground := BiomeManager.get_height(cell_x, cell_z)
					for fill_y in range(maxi(column_ground, y - 5), y):
						_set_cell(output, origin, Vector3i(cell_x, fill_y, cell_z), stone_id)
					_set_cell(output, origin, Vector3i(cell_x, y, cell_z), stone_id)
			if step > 2 and step % 4 == 0:
				x += lean.x
				z += lean.y
		_set_cell(output, origin, Vector3i(x, base_y + height + 1, z), stone_id)
		for piece in range(7):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(3.0, 6.5)
			var rubble_x := spire.x + roundi(cos(angle) * radius)
			var rubble_z := spire.y + roundi(sin(angle) * radius)
			_place_prop_cell(output, origin, rubble_x, rubble_z, 1, stone_id, air_id)


# --- Snow ice spires ----------------------------------------------------

static func _stamp_frost_spires(output: PackedByteArray, origin: Vector3i, world_seed: int, ice_id: int, stone_id: int) -> void:
	var min_gx := floori(float(origin.x - FROST_SPIRE_REACH) / float(FROST_SPIRE_CELL))
	var max_gx := floori(float(origin.x + CHUNK_SIZE - 1 + FROST_SPIRE_REACH) / float(FROST_SPIRE_CELL))
	var min_gz := floori(float(origin.z - FROST_SPIRE_REACH) / float(FROST_SPIRE_CELL))
	var max_gz := floori(float(origin.z + CHUNK_SIZE - 1 + FROST_SPIRE_REACH) / float(FROST_SPIRE_CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var spire_rng := RandomNumberGenerator.new()
			spire_rng.seed = _column_seed(world_seed, grid_x, grid_z, 0x1CE5)
			if spire_rng.randf() > FROST_SPIRE_CHANCE:
				continue
			var base_x := grid_x * FROST_SPIRE_CELL + spire_rng.randi_range(2, FROST_SPIRE_CELL - 2)
			var base_z := grid_z * FROST_SPIRE_CELL + spire_rng.randi_range(2, FROST_SPIRE_CELL - 2)
			if BiomeManager.dominant_biome(base_x, base_z) != BiomeManager.FROST:
				continue
			if not _flat_at(base_x, base_z):
				continue
			var base_y := BiomeManager.get_height(base_x, base_z)
			# Broad height/lean variance so frost columns read as a jagged,
			# wind-thrown field rather than evenly turned posts.
			var height := spire_rng.randi_range(4, 17)
			var lean := Vector2i.ZERO
			if spire_rng.randf() < 0.6:
				lean = Vector2i(spire_rng.randi_range(-1, 1), spire_rng.randi_range(-1, 1))
			var x := base_x
			var z := base_z
			for step in range(height):
				var y := base_y + 1 + step
				var radius := 1 if step < height - 4 else 0
				for offset_z in range(-radius, radius + 1):
					for offset_x in range(-radius, radius + 1):
						if offset_x * offset_x + offset_z * offset_z > radius * radius + 1:
							continue
						var cell := Vector3i(x + offset_x, y, z + offset_z)
						if _get_cell(output, origin, cell) != -1:
							_set_cell(output, origin, cell, ice_id)
				if step == 0:
					var foot := Vector3i(x, base_y, z)
					_set_cell(output, origin, foot, ice_id)
				if step > 1 and step % (3 if height > 10 else 4) == 0 and lean != Vector2i.ZERO:
					x += lean.x
					z += lean.y
			if height > 10 and spire_rng.randf() < 0.4:
				var companion_x := base_x + spire_rng.randi_range(-3, 3)
				var companion_z := base_z + spire_rng.randi_range(-3, 3)
				if _flat_at(companion_x, companion_z):
					var companion_y := BiomeManager.get_height(companion_x, companion_z)
					_stamp_shard(output, origin, ice_id, companion_x, companion_z, companion_y + 1, spire_rng.randi_range(3, 7), 1)
			# Splinters around the base catch the low sun.
			for splinter in range(3):
				var angle := spire_rng.randf_range(0.0, TAU)
				var side_x := base_x + roundi(cos(angle) * 2.0)
				var side_z := base_z + roundi(sin(angle) * 2.0)
				var side_y := BiomeManager.get_height(side_x, side_z)
				_stamp_shard(output, origin, ice_id, side_x, side_z, side_y + 1, spire_rng.randi_range(1, 3), 1)


# --- MultiMesh prop sites ----------------------------------------------------
# These mirror the old voxel-stamping grids but return transform inputs only;
# the meshes live in WorldVegetation, so no block state is needed for them.

static func collect_hush_sites_region(world_seed: int, min_x: int, min_z: int, max_x: int, max_z: int) -> Array:
	var sites: Array = []
	var min_gx := floori(float(min_x) / float(HUSH_TREE_CELL)) - 1
	var max_gx := floori(float(max_x) / float(HUSH_TREE_CELL)) + 1
	var min_gz := floori(float(min_z) / float(HUSH_TREE_CELL)) - 1
	var max_gz := floori(float(max_z) / float(HUSH_TREE_CELL)) + 1
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = _column_seed(world_seed, grid_x, grid_z, 0x6E55)
			if rng.randf() > HUSH_TREE_CHANCE:
				continue
			var x := grid_x * HUSH_TREE_CELL + rng.randi_range(1, HUSH_TREE_CELL - 2)
			var z := grid_z * HUSH_TREE_CELL + rng.randi_range(1, HUSH_TREE_CELL - 2)
			if x < min_x or x > max_x or z < min_z or z > max_z:
				continue
			if BiomeManager.get_weights(x, z)[BiomeManager.HUSH] <= 0.45 or not _flat_at(x, z):
				continue
			var y := BiomeManager.get_height(x, z)
			if y < 15:
				continue
			sites.append({"x": x, "y": y, "z": z, "seed": rng.randi(), "scale": rng.randf_range(0.85, 1.45)})
	return sites


static func collect_frost_sites_region(world_seed: int, min_x: int, min_z: int, max_x: int, max_z: int) -> Array:
	var sites: Array = []
	var min_gx := floori(float(min_x) / float(FROST_SPIRE_CELL)) - 1
	var max_gx := floori(float(max_x) / float(FROST_SPIRE_CELL)) + 1
	var min_gz := floori(float(min_z) / float(FROST_SPIRE_CELL)) - 1
	var max_gz := floori(float(max_z) / float(FROST_SPIRE_CELL)) + 1
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = _column_seed(world_seed, grid_x, grid_z, 0x1CE5)
			if rng.randf() > FROST_SPIRE_CHANCE:
				continue
			var x := grid_x * FROST_SPIRE_CELL + rng.randi_range(1, FROST_SPIRE_CELL - 2)
			var z := grid_z * FROST_SPIRE_CELL + rng.randi_range(1, FROST_SPIRE_CELL - 2)
			if x < min_x or x > max_x or z < min_z or z > max_z:
				continue
			if BiomeManager.get_weights(x, z)[BiomeManager.FROST] <= 0.4 or not _flat_at(x, z):
				continue
			sites.append({"x": x, "y": BiomeManager.get_height(x, z), "z": z, "seed": rng.randi(), "scale": rng.randf_range(0.7, 1.9)})
	return sites


static func collect_mire_root_sites_region(world_seed: int, min_x: int, min_z: int, max_x: int, max_z: int) -> Array:
	var sites: Array = []
	var min_gx := floori(float(min_x) / float(MIRE_ROOT_CELL)) - 1
	var max_gx := floori(float(max_x) / float(MIRE_ROOT_CELL)) + 1
	var min_gz := floori(float(min_z) / float(MIRE_ROOT_CELL)) - 1
	var max_gz := floori(float(max_z) / float(MIRE_ROOT_CELL)) + 1
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = _column_seed(world_seed, grid_x, grid_z, 0xB006)
			if rng.randf() > MIRE_ROOT_CHANCE:
				continue
			var x := grid_x * MIRE_ROOT_CELL + rng.randi_range(1, MIRE_ROOT_CELL - 2)
			var z := grid_z * MIRE_ROOT_CELL + rng.randi_range(1, MIRE_ROOT_CELL - 2)
			if x < min_x or x > max_x or z < min_z or z > max_z:
				continue
			if BiomeManager.get_weights(x, z)[BiomeManager.MIRE] <= 0.4 or not _flat_at(x, z):
				continue
			var y := BiomeManager.get_height(x, z)
			sites.append({"x": x, "y": maxi(y, BiomeManager.WATER_LEVEL), "z": z, "seed": rng.randi(), "scale": rng.randf_range(0.8, 1.6)})
	return sites


# --- Surface biome features (Desert cacti, Mushroom mushrooms) --------
# A deterministic grid keeps every feature reproducible from world coordinates,
# so a cactus or cap that straddles a chunk border is stamped by both chunks.
const BIOME_PROP_CELL := 14
const BIOME_PROP_CHANCE := 0.22

static func _stamp_biome_props(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary) -> void:
	var cactus_id := int(block_ids.get(&"cactus", -1))
	var stem_id := int(block_ids.get(&"mushroom_stem", -1))
	var cap_id := int(block_ids.get(&"mushroom_cap", -1))
	var trunk_id := int(block_ids.get(&"pale_wood", -1))
	var coral_id := int(block_ids.get(&"coral", -1))
	var radiant_id := int(block_ids.get(&"radiant_crystal_ore", -1))
	if cactus_id < 0 and (stem_id < 0 or cap_id < 0) and trunk_id < 0:
		return
	var min_gx := floori(float(origin.x - 6) / float(BIOME_PROP_CELL))
	var max_gx := floori(float(origin.x + 15 + 6) / float(BIOME_PROP_CELL))
	var min_gz := floori(float(origin.z - 6) / float(BIOME_PROP_CELL))
	var max_gz := floori(float(origin.z + 15 + 6) / float(BIOME_PROP_CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = _column_seed(world_seed, grid_x, grid_z, 0xB10B)
			if rng.randf() > BIOME_PROP_CHANCE:
				continue
			var base_x := grid_x * BIOME_PROP_CELL + rng.randi_range(2, BIOME_PROP_CELL - 3)
			var base_z := grid_z * BIOME_PROP_CELL + rng.randi_range(2, BIOME_PROP_CELL - 3)
			var biome := BiomeManager.dominant_biome(base_x, base_z)
			if not _flat_at(base_x, base_z):
				continue
			var base_y := BiomeManager.get_height(base_x, base_z)
			if biome == BiomeManager.DESERT and cactus_id >= 0:
				var height := rng.randi_range(3, 5)
				for step in range(height):
					_set_cell(output, origin, Vector3i(base_x, base_y + 1 + step, base_z), cactus_id)
				if rng.randf() < 0.5:
					_set_cell(output, origin, Vector3i(base_x + 1, base_y + 2, base_z), cactus_id)
			elif biome == BiomeManager.MUSHROOM and stem_id >= 0 and cap_id >= 0:
				var height := rng.randi_range(3, 6)
				for step in range(height):
					_set_cell(output, origin, Vector3i(base_x, base_y + 1 + step, base_z), stem_id)
				var cap_y := base_y + height
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if absi(dx) + absi(dz) > 1:
							continue
						_set_cell(output, origin, Vector3i(base_x + dx, cap_y, base_z + dz), cap_id)
				_set_cell(output, origin, Vector3i(base_x, cap_y + 1, base_z), cap_id)
			elif biome == BiomeManager.JUNGLE or biome == BiomeManager.CORRUPTION \
					or biome == BiomeManager.CRIMSON or biome == BiomeManager.HALLOW:
				var leaf_id := -1
				match biome:
					BiomeManager.JUNGLE:
						leaf_id = int(block_ids.get(&"jungle_leaves", -1))
					BiomeManager.CORRUPTION:
						leaf_id = int(block_ids.get(&"ebon_leaves", -1))
					BiomeManager.CRIMSON:
						leaf_id = int(block_ids.get(&"crim_leaves", -1))
					BiomeManager.HALLOW:
						leaf_id = int(block_ids.get(&"hallow_leaves", -1))
				if trunk_id < 0 or leaf_id < 0:
					continue
				var tree_height := rng.randi_range(6, 10) if biome == BiomeManager.JUNGLE else rng.randi_range(3, 6)
				for step in range(tree_height):
					_set_cell(output, origin, Vector3i(base_x, base_y + 1 + step, base_z), trunk_id)
				var crown_y := base_y + tree_height
				for dz in range(-2, 3):
					for dx in range(-2, 3):
						if absi(dx) + absi(dz) > 2:
							continue
						_set_cell(output, origin, Vector3i(base_x + dx, crown_y, base_z + dz), leaf_id)
				_set_cell(output, origin, Vector3i(base_x, crown_y + 1, base_z), leaf_id)
			if biome == BiomeManager.OCEAN and coral_id >= 0:
				for coral in range(rng.randi_range(2, 4)):
					var cx := base_x + rng.randi_range(-2, 2)
					var cz := base_z + rng.randi_range(-2, 2)
					var cy := BiomeManager.get_height(cx, cz) + 1 + rng.randi_range(0, 2)
					_set_cell(output, origin, Vector3i(cx, cy, cz), coral_id)
			if biome == BiomeManager.HALLOW and radiant_id >= 0:
				var spire_height := rng.randi_range(2, 4)
				for step in range(spire_height):
					_set_cell(output, origin, Vector3i(base_x, base_y + 1 + step, base_z), radiant_id)
				if rng.randf() < 0.5:
					_set_cell(output, origin, Vector3i(base_x + 1, base_y + 1, base_z), radiant_id)


# --- Underground biome formations -------------------------------------------
# Giant mushrooms, crystal spires, ice pillars and magma vents placed inside
# caves according to the local underground biome. They only fill air, so they
# never overwrite ore or authored rooms' walls.
const UPROP_CELL := 44
const UPROP_CHANCE := 0.55

static func _stamp_underground_props(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, air_id: int) -> void:
	var stem_id := int(block_ids.get(&"mushroom_stem", -1))
	var cap_id := int(block_ids.get(&"mushroom_cap", -1))
	var crystal_id := int(block_ids.get(&"lumen_crystal", -1))
	var ice_id := int(block_ids.get(&"frost_ice", -1))
	var magma_id := int(block_ids.get(&"magma_stone", -1))
	var min_gx := floori(float(origin.x - 8) / float(UPROP_CELL))
	var max_gx := floori(float(origin.x + 15 + 8) / float(UPROP_CELL))
	var min_gz := floori(float(origin.z - 8) / float(UPROP_CELL))
	var max_gz := floori(float(origin.z + 15 + 8) / float(UPROP_CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = _column_seed(world_seed, grid_x, grid_z, 0x2D07)
			if rng.randf() > UPROP_CHANCE:
				continue
			var x := grid_x * UPROP_CELL + rng.randi_range(4, UPROP_CELL - 5)
			var z := grid_z * UPROP_CELL + rng.randi_range(4, UPROP_CELL - 5)
			var surface := BiomeManager.get_height(x, z)
			var depth := rng.randi_range(30, 138)
			var y := surface - depth
			var ub := WorldBiomes.underground_biome_at(x, y, z, surface, BiomeManager.dominant_biome(x, z))
			match ub:
				WorldBiomes.Underground.FUNGAL:
					if stem_id < 0 or cap_id < 0:
						continue
					var height := rng.randi_range(3, 6)
					for step in range(height):
						_set_if_air(output, origin, Vector3i(x, y + step, z), stem_id, air_id)
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							if absi(dx) + absi(dz) > 1:
								continue
							_set_if_air(output, origin, Vector3i(x + dx, y + height, z + dz), cap_id, air_id)
				WorldBiomes.Underground.CRYSTAL:
					if crystal_id < 0:
						continue
					for step in range(rng.randi_range(2, 5)):
						_set_if_air(output, origin, Vector3i(x, y + step, z), crystal_id, air_id)
				WorldBiomes.Underground.FROZEN:
					if ice_id < 0:
						continue
					for step in range(rng.randi_range(2, 5)):
						_set_if_air(output, origin, Vector3i(x, y + step, z), ice_id, air_id)
				WorldBiomes.Underground.VOLCANIC:
					if magma_id < 0:
						continue
					for step in range(rng.randi_range(1, 3)):
						_set_if_air(output, origin, Vector3i(x, y + step, z), magma_id, air_id)


static func _set_if_air(output: PackedByteArray, origin: Vector3i, cell: Vector3i, block_id: int, air_id: int) -> void:
	if _get_cell(output, origin, cell) == air_id:
		_set_cell(output, origin, cell, block_id)


static func _chunk_seed(world_seed: int, origin: Vector3i) -> int:
	var value := world_seed * 1103515245 + origin.x * 73856093 + origin.y * 19349663 + origin.z * 83492791
	value = (value ^ (value >> 13)) * 1274126177
	return value & 0x7fffffff


static func _column_seed(world_seed: int, x: int, z: int, salt: int) -> int:
	var value := world_seed * 1103515245 + x * 73856093 + z * 19349663 + salt
	value = (value ^ (value >> 13)) * 1274126177
	return value & 0x7fffffff


static func _cell_hash(x: int, y: int, z: int, world_seed: int) -> float:
	var value := world_seed * 1103515245 + x * 73856093 + y * 19349663 + z * 83492791
	value = (value ^ (value >> 13)) * 1274126177
	return float(value & 0xFFFF) / 65535.0


