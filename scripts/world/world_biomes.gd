extends RefCounted
class_name WorldBiomes

# Underground biome layer. Surface biomes (BiomeManager) describe the climate;
# this class describes what a specific underground region *is*: fungal grotto,
# volcanic depth, crystal cavern, frozen underlayer or ancient abyss. It is a
# pure function of world coordinates so worker generation and runtime queries
# agree exactly.
#
# Stone and ore generation consume this, and gameplay/UI can read the same
# result through VoxelWorld.get_underground_biome(cell) for spawn metadata,
# ambience and discovery hints.

enum Underground { NORMAL = 0, FUNGAL = 1, VOLCANIC = 2, CRYSTAL = 3, FROZEN = 4, ANCIENT = 5, JUNGLE = 6, CORRUPTION = 7, CRIMSON = 8, HALLOW = 9, OCEAN = 10, UNDERWORLD = 11 }

static var _seed := -1
static var _noise: Dictionary = {}


static func configure(world_seed: int) -> void:
	if world_seed == _seed and not _noise.is_empty():
		return
	_seed = world_seed
	_noise = {
		"fungal": _make(world_seed ^ 0x4F21, 2, 0.020),
		"crystal": _make(world_seed ^ 0x71C3, 3, 0.045),
		"ancient": _make(world_seed ^ 0x2A9B, 3, 0.012),
		"frozen": _make(world_seed ^ 0x6D11, 2, 0.028),
	}


static func _make(noise_seed: int, octaves: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	return noise


static func _ensure() -> void:
	if _seed < 0 or _noise.is_empty():
		configure(139732)
	WorldCaves.configure(_seed)


static func underground_biome_at(x: int, y: int, z: int, surface_y: int, surface_biome: int) -> int:
	_ensure()
	var depth := surface_y - y
	if depth >= WorldLayers.UNDERWORLD_DEPTH:
		return Underground.UNDERWORLD
	if depth < 6:
		return Underground.NORMAL
	# Core surface identities own their shallow underground. This is what makes
	# the Jungle, evil biomes, Hallow and Ocean read differently below ground
	# instead of all becoming the same grey stone.
	match surface_biome:
		BiomeManager.JUNGLE:
			return Underground.JUNGLE
		BiomeManager.CORRUPTION:
			return Underground.CORRUPTION
		BiomeManager.CRIMSON:
			return Underground.CRIMSON
		BiomeManager.HALLOW:
			return Underground.HALLOW
		BiomeManager.OCEAN:
			return Underground.OCEAN
	# Abyss: the deepest band always reads as an ancient crystal realm.
	if depth >= WorldLayers.CAVERN_DEPTH:
		var ancient: FastNoiseLite = _noise["ancient"]
		if ancient.get_noise_3d(float(x), float(y), float(z)) > 0.35:
			return Underground.ANCIENT
		return Underground.CRYSTAL
	var crystal_value := 0.0
	if depth >= 30:
		var crystal: FastNoiseLite = _noise["crystal"]
		crystal_value = crystal.get_noise_3d(float(x), float(y), float(z))
	if depth >= WorldLayers.DEEP_DEPTH:
		if crystal_value > 0.58:
			return Underground.CRYSTAL
		if WorldCaves.volcanic_factor(x, y, z) > 0.45:
			return Underground.VOLCANIC
	# Frozen underlayer follows Snow and fades with depth.
	if surface_biome == BiomeManager.FROST and depth < 96:
		var frozen: FastNoiseLite = _noise["frozen"]
		if frozen.get_noise_3d(float(x), float(y), float(z)) > -0.55:
			return Underground.FROZEN
	# Fungal grottoes under the forest and mire, plus standalone patches.
	if depth >= 18 and depth < 130:
		var fungal: FastNoiseLite = _noise["fungal"]
		var fungal_value := fungal.get_noise_3d(float(x), float(y), float(z))
		if (surface_biome == BiomeManager.HUSH or surface_biome == BiomeManager.MIRE) and fungal_value > 0.32:
			return Underground.FUNGAL
		if fungal_value > 0.62:
			return Underground.FUNGAL
	if crystal_value > 0.70 and depth >= 30:
		return Underground.CRYSTAL
	return Underground.NORMAL


# Authoritative stone for an underground cell. Generator resolves the returned
# name through the live palette, so the same rules hold for every chunk.
static func stone_name(underground_biome: int, depth: int) -> StringName:
	match underground_biome:
		Underground.FROZEN:
			return &"frost_stone" if depth < 130 else &"cavern_stone"
		Underground.FUNGAL:
			return &"mycelium_stone" if depth < 150 else &"cavern_stone"
		Underground.VOLCANIC:
			return &"magma_stone"
		Underground.CRYSTAL:
			return &"crystal_stone"
		Underground.ANCIENT:
			return &"deepstone" if depth < 160 else &"crystal_stone"
		Underground.JUNGLE:
			return &"jungle_mudstone" if depth < WorldLayers.CAVERN_DEPTH else &"cavern_stone"
		Underground.CORRUPTION:
			return &"ebonstone"
		Underground.CRIMSON:
			return &"crimstone"
		Underground.HALLOW:
			return &"pearlstone"
		Underground.OCEAN:
			return &"reefstone" if depth < 80 else &"cavern_stone"
		Underground.UNDERWORLD:
			return &"ash"
	if depth < WorldLayers.UPPER_DEPTH:
		return &"stone"
	if depth < WorldLayers.DEEP_DEPTH:
		return &"stone" if depth < WorldLayers.UNDERGROUND_DEPTH else &"deepstone"
	if depth < WorldLayers.CAVERN_DEPTH:
		return &"cavern_stone"
	return &"cavern_stone"


# Metadata for Agent 2's spawn director: an enemy pool tag per underground biome.
static func enemy_tag(underground_biome: int) -> StringName:
	match underground_biome:
		Underground.FUNGAL:
			return &"fungal"
		Underground.VOLCANIC:
			return &"volcanic"
		Underground.CRYSTAL:
			return &"crystal"
		Underground.FROZEN:
			return &"frozen"
		Underground.ANCIENT:
			return &"ancient"
		Underground.JUNGLE:
			return &"jungle"
		Underground.CORRUPTION:
			return &"corruption"
		Underground.CRIMSON:
			return &"crimson"
		Underground.HALLOW:
			return &"hallow"
		Underground.OCEAN:
			return &"ocean"
		Underground.UNDERWORLD:
			return &"underworld"
		_:
			return &"underground"


# Suggested ambient light contribution (0..1) for presentation systems.
static func ambient_light(underground_biome: int) -> float:
	match underground_biome:
		Underground.CRYSTAL:
			return 0.35
		Underground.ANCIENT:
			return 0.28
		Underground.VOLCANIC:
			return 0.22
		Underground.FUNGAL:
			return 0.16
		Underground.HALLOW:
			return 0.18
		Underground.JUNGLE:
			return 0.08
		Underground.OCEAN:
			return 0.10
		Underground.UNDERWORLD:
			return 0.28
		_:
			return 0.0


static func biome_name(underground_biome: int) -> String:
	match underground_biome:
		Underground.FUNGAL:
			return "Fungal Grotto"
		Underground.VOLCANIC:
			return "Volcanic Depths"
		Underground.CRYSTAL:
			return "Crystal Caverns"
		Underground.FROZEN:
			return "Frozen Underlayer"
		Underground.ANCIENT:
			return "Ancient Abyss"
		Underground.JUNGLE:
			return "Underground Jungle"
		Underground.CORRUPTION:
			return "Corruption Depths"
		Underground.CRIMSON:
			return "Crimson Depths"
		Underground.HALLOW:
			return "Hallow Caverns"
		Underground.OCEAN:
			return "Ocean Floor"
		Underground.UNDERWORLD:
			return "The Underworld"
		_:
			return "Deep Rock"
