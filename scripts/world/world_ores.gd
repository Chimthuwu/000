extends RefCounted
class_name WorldOres

# Data-driven, biome- and depth-aware ore distribution. The ore type is chosen
# per coarse vein cell (8 x 6 x 8 blocks) so a noise-shaped deposit is made of a
# single material, then the shared WorldCaves vein field decides where deposits
# exist at all. This keeps veins connected and readable instead of speckling.
#
# Entry layout: [block_id: StringName, min_depth: int, max_depth: int,
#                weight: float, min_vein: float]
# Depth is blocks below the surface, matching WorldLayers.

const VEIN_THRESHOLD := 0.50
const VEIN_CELL_XZ := 8
const VEIN_CELL_Y := 6

const BIOME_ORES := {
	0: [ # Ashen Flats: the baseline industrial ladder
		[&"coal_ore", 4, 80, 3.4, 0.50],
		[&"copper_ore", 8, 80, 2.6, 0.50],
		[&"iron_ore", 18, 88, 2.4, 0.52],
		[&"silver_ore", 42, 96, 1.2, 0.58],
		[&"gold_ore", 60, 104, 0.9, 0.60],
		[&"lumen_crystal", 26, 104, 0.35, 0.64],
	],
	1: [ # Hushwoods: organic and fungal wealth, less metal
		[&"coal_ore", 6, 70, 2.2, 0.50],
		[&"copper_ore", 10, 76, 2.0, 0.52],
		[&"iron_ore", 22, 88, 1.8, 0.54],
		[&"fungal_ore", 12, 84, 3.0, 0.50],
		[&"lumen_crystal", 28, 100, 0.7, 0.58],
		[&"ancient_ore", 62, 104, 0.35, 0.66],
	],
	2: [ # Frostfall: iron/silver and frozen crystal
		[&"coal_ore", 6, 60, 1.2, 0.56],
		[&"iron_ore", 10, 88, 3.0, 0.50],
		[&"silver_ore", 20, 96, 2.8, 0.50],
		[&"frost_crystal_ore", 24, 104, 2.0, 0.52],
		[&"gold_ore", 50, 104, 0.8, 0.62],
	],
	3: [ # The Mire: buried ancient material and fungus
		[&"copper_ore", 8, 74, 2.2, 0.52],
		[&"iron_ore", 20, 86, 2.0, 0.54],
		[&"fungal_ore", 10, 78, 2.4, 0.50],
		[&"ancient_ore", 36, 104, 1.8, 0.54],
		[&"gold_ore", 62, 104, 0.7, 0.62],
	],
	4: [ # The Scorchlands: copper/silver in sandstone, deep ancient caches
		[&"copper_ore", 6, 92, 2.4, 0.52],
		[&"silver_ore", 24, 120, 2.2, 0.52],
		[&"gold_ore", 60, 160, 1.2, 0.58],
		[&"ancient_ore", 92, 180, 1.0, 0.60],
	],
	5: [ # Glowgrove: fungal wealth with a little metal and crystal
		[&"fungal_ore", 6, 130, 3.4, 0.50],
		[&"coal_ore", 8, 90, 1.8, 0.54],
		[&"iron_ore", 30, 120, 1.6, 0.56],
		[&"lumen_crystal", 20, 160, 0.9, 0.56],
		[&"ancient_ore", 84, 170, 0.5, 0.64],
	],
	6: [ # Jungle: amber and organic wealth, deeper metal is sparse
		[&"amber_ore", 8, 120, 3.2, 0.50],
		[&"coal_ore", 10, 90, 1.6, 0.54],
		[&"iron_ore", 34, 120, 1.4, 0.56],
		[&"lumen_crystal", 30, 150, 0.8, 0.58],
		[&"ancient_ore", 90, 180, 0.4, 0.66],
	],
	7: [ # Corruption: void ore and deep metal
		[&"void_ore", 8, 150, 2.8, 0.50],
		[&"coal_ore", 10, 100, 1.8, 0.54],
		[&"silver_ore", 36, 140, 1.4, 0.56],
		[&"gold_ore", 70, 170, 1.0, 0.60],
		[&"lumen_crystal", 26, 160, 0.6, 0.60],
	],
	8: [ # Crimson: blood ore and precious metal
		[&"blood_ore", 8, 150, 2.8, 0.50],
		[&"gold_ore", 40, 160, 1.6, 0.56],
		[&"silver_ore", 20, 130, 1.6, 0.54],
		[&"ancient_ore", 90, 190, 0.7, 0.60],
	],
	9: [ # Hallow: radiant crystal and precious metal
		[&"radiant_crystal_ore", 10, 170, 2.6, 0.50],
		[&"gold_ore", 30, 160, 1.6, 0.56],
		[&"silver_ore", 16, 130, 1.4, 0.54],
		[&"lumen_crystal", 24, 170, 1.2, 0.56],
		[&"ancient_ore", 80, 190, 0.8, 0.62],
	],
	10: [ # Ocean: pearl and seabed metal
		[&"pearl_ore", 4, 100, 2.6, 0.50],
		[&"copper_ore", 8, 90, 1.8, 0.54],
		[&"silver_ore", 26, 120, 1.4, 0.56],
		[&"gold_ore", 55, 160, 0.8, 0.62],
		[&"ancient_ore", 90, 180, 0.4, 0.66],
	],
}

# Volcanic depths add heat-loving materials regardless of surface biome.
const VOLCANIC_ORES := [
	[&"volcanic_crystal_ore", 66, 110, 1.6, 0.50],
	[&"gold_ore", 66, 110, 1.1, 0.56],
	[&"magma_stone", 0, 0, 0.0, 1.0], # never chosen as an ore; placeholder-free
]

static var _seed := -1


static func configure(world_seed: int) -> void:
	_seed = world_seed
	WorldCaves.configure(world_seed)


static func _ensure() -> void:
	if _seed < 0:
		configure(139732)


# Returns the ore block id for a solid underground cell, or &"" for plain rock.
static func ore_at(x: int, y: int, z: int, surface_y: int, biome: int, underground_biome: int = -1) -> StringName:
	_ensure()
	var depth := surface_y - y
	if depth < 4:
		return &""
	var vein := WorldCaves.vein_value(x, y, z)
	if vein < VEIN_THRESHOLD:
		return &""
	var pool: Array = BIOME_ORES.get(biome, BIOME_ORES[0]).duplicate()
	# Underground biomes add their signature material to the local pool.
	match underground_biome:
		WorldBiomes.Underground.FUNGAL:
			pool.append([&"fungal_ore", 6, 150, 2.6, 0.50])
		WorldBiomes.Underground.CRYSTAL:
			pool.append([&"lumen_crystal", 10, 180, 1.8, 0.52])
			pool.append([&"ancient_ore", 90, 190, 0.8, 0.60])
		WorldBiomes.Underground.VOLCANIC:
			pool.append([&"volcanic_crystal_ore", 60, 200, 2.4, 0.50])
			pool.append([&"gold_ore", 60, 200, 1.0, 0.56])
		WorldBiomes.Underground.FROZEN:
			pool.append([&"frost_crystal_ore", 10, 140, 2.2, 0.50])
		WorldBiomes.Underground.ANCIENT:
			pool.append([&"ancient_ore", 120, 220, 2.6, 0.48])
		WorldBiomes.Underground.JUNGLE:
			pool.append([&"amber_ore", 6, 140, 2.4, 0.50])
		WorldBiomes.Underground.CORRUPTION:
			pool.append([&"void_ore", 6, 160, 2.4, 0.50])
		WorldBiomes.Underground.CRIMSON:
			pool.append([&"blood_ore", 6, 160, 2.4, 0.50])
		WorldBiomes.Underground.HALLOW:
			pool.append([&"radiant_crystal_ore", 8, 180, 2.2, 0.50])
		WorldBiomes.Underground.OCEAN:
			pool.append([&"pearl_ore", 4, 110, 2.2, 0.50])
		WorldBiomes.Underground.UNDERWORLD:
			pool.append([&"hellstone", 168, 260, 3.4, 0.46])
	if depth >= WorldLayers.DEEP_DEPTH:
		for entry: Array in VOLCANIC_ORES:
			if float(entry[3]) > 0.0:
				pool.append(entry)
	var total := 0.0
	for entry: Array in pool:
		if depth < int(entry[1]) or depth > int(entry[2]) or vein < float(entry[4]):
			continue
		total += float(entry[3])
	if total <= 0.0:
		return &""
	# Pick one material per coarse vein cell so deposits stay coherent.
	var vein_x := floori(float(x) / float(VEIN_CELL_XZ))
	var vein_y := floori(float(y) / float(VEIN_CELL_Y))
	var vein_z := floori(float(z) / float(VEIN_CELL_XZ))
	var roll := _hash01(vein_x, vein_y, vein_z, _seed ^ 0x0FE1) * total
	for entry: Array in pool:
		if depth < int(entry[1]) or depth > int(entry[2]) or vein < float(entry[4]):
			continue
		roll -= float(entry[3])
		if roll <= 0.0:
			return entry[0]
	return &""


static func _hash01(x: int, y: int, z: int, salt: int) -> float:
	var value := salt * 1103515245 + x * 73856093 + y * 19349663 + z * 83492791
	value = (value ^ (value >> 13)) * 1274126177
	return float(value & 0xFFFF) / 65535.0
