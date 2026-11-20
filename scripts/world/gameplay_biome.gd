extends RefCounted
class_name GameplayBiome

## Agent 2 gameplay adapter. World generation owns numeric biome ids; gameplay
## reasons about Terraria-style biome identities instead. Mapping lives here so
## Agent 1 can add/reorder ids without touching enemy or loot code.

enum Identity {
	FOREST,
	DESERT,
	JUNGLE,
	CORRUPTION,
	CRIMSON,
	HALLOW,
	SNOW,
	OCEAN,
	MUSHROOM,
}

# Ids are taken from BiomeManager so Agent 1 owns the numeric palette.
# 0 Ashen (Forest variant), 1 Hush (Jungle variant), 2 Frost/Snow,
# 3 Mire/Forest (the starting Overworld), 4 Desert, 5 Mushroom,
# 6 Jungle, 7 Corruption, 8 Crimson, 9 Hallow, 10 Ocean.

const IDENTITY_NAMES := [
	"Forest", "Desert", "Jungle", "Corruption", "Crimson",
	"The Hallow", "Snow", "Ocean", "Mushroom",
]


static func identity_for(world_biome: int) -> int:
	match world_biome:
		BiomeManager.ASHEN, BiomeManager.MIRE:
			return Identity.FOREST
		BiomeManager.HUSH, BiomeManager.JUNGLE:
			return Identity.JUNGLE
		BiomeManager.FROST:
			return Identity.SNOW
		BiomeManager.DESERT:
			return Identity.DESERT
		BiomeManager.MUSHROOM:
			return Identity.MUSHROOM
		BiomeManager.CORRUPTION:
			return Identity.CORRUPTION
		BiomeManager.CRIMSON:
			return Identity.CRIMSON
		BiomeManager.HALLOW:
			return Identity.HALLOW
		BiomeManager.OCEAN:
			return Identity.OCEAN
		_:
			return Identity.FOREST


static func identity_name(identity: int) -> String:
	return IDENTITY_NAMES[clampi(identity, 0, IDENTITY_NAMES.size() - 1)]


static func display_name_for(world_biome: int) -> String:
	return identity_name(identity_for(world_biome))
