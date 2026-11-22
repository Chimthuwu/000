extends RefCounted
class_name TerrainAtlas

## Deterministic, original pixel-art terrain atlas.
##
## Every block material points at a top / side / bottom tile. The mesher writes
## real UV coordinates into those tiles and the world shader samples the atlas
## with nearest filtering, so terrain is textured pixel art instead of flat
## vertex-coloured cubes. Tiles are greyscale detail: the block's palette colour
## (BlockLightDef.albedo) provides the material hue, which keeps every biome
## variant readable while sharing one texture.

const TILE_SIZE := 16
const COLUMNS := 16
const ATLAS_PIXELS := TILE_SIZE * COLUMNS
const TILE_COUNT := 49
const TILE_INSET := 0.5

enum Tile {
	PLAIN = 0,
	GRASS_TOP = 1,
	DIRT = 2,
	STONE = 3,
	DEEPSTONE = 4,
	CAVERN = 5,
	SAND = 6,
	SANDSTONE = 7,
	SNOW = 8,
	ICE = 9,
	MUD = 10,
	BARK = 11,
	LEAVES = 12,
	MUSHROOM = 13,
	EVILSTONE = 14,
	HALLOWSTONE = 15,
	ASH = 16,
	MAGMA = 17,
	OBSIDIAN = 18,
	ORE_METAL = 19,
	ORE_GEM = 20,
	LIQUID = 21,
	CRYSTAL = 22,
	BRICK = 23,
	PLANT = 24,
	CLOTH = 25,
	METAL = 26,
	GLOW = 27,
	# Biome-specific additions (direction-correction pass). These give grass a
	# proper dirt-with-fringe side face and let evil / hallow / jungle foliage
	# read apart instead of sharing one generic leaf tile.
	GRASS_SIDE = 28,
	JUNGLE_GRASS_SIDE = 29,
	EVIL_GRASS_SIDE = 30,
	HALLOW_GRASS_SIDE = 31,
	SNOW_SIDE = 32,
	WET_SAND = 33,
	LEAF_JUNGLE = 34,
	LEAF_EVIL = 35,
	LEAF_HALLOW = 36,
	DEEP_MUD = 37,
	ORE_CRYSTAL = 38,
	# Building set. These are the tiles the crafted furniture and construction
	# blocks use, so a player-built workbench or brick wall reads as its own
	# crafted material rather than a recoloured rock.
	PLANK = 39,
	PLATFORM = 40,
	GLASS = 41,
	WORKBENCH = 42,
	FURNACE = 43,
	CHEST = 44,
	DOOR = 45,
	DOOR_OPEN = 46,
	ANVIL = 47,
	CHAIR = 48,
}

# block id -> Vector3i(top tile, side tile, bottom tile)
static var BLOCK_TILES := {
	&"dirt": Vector3i(Tile.GRASS_TOP, Tile.GRASS_SIDE, Tile.DIRT),
	&"ashen_soil": Vector3i(Tile.GRASS_TOP, Tile.GRASS_SIDE, Tile.DIRT),
	&"hush_soil": Vector3i(Tile.GRASS_TOP, Tile.GRASS_SIDE, Tile.DIRT),
	&"rotted_dirt": Vector3i(Tile.DIRT, Tile.DIRT, Tile.DIRT),
	&"rotted_ashen_soil": Vector3i(Tile.DIRT, Tile.DIRT, Tile.DIRT),
	&"mire_mud": Vector3i(Tile.DEEP_MUD, Tile.DEEP_MUD, Tile.DEEP_MUD),
	&"toxic_silt": Vector3i(Tile.DEEP_MUD, Tile.DEEP_MUD, Tile.DEEP_MUD),
	&"canyon_gravel": Vector3i(Tile.STONE, Tile.STONE, Tile.STONE),
	&"stone": Vector3i(Tile.STONE, Tile.STONE, Tile.STONE),
	&"deepstone": Vector3i(Tile.DEEPSTONE, Tile.DEEPSTONE, Tile.DEEPSTONE),
	&"cavern_stone": Vector3i(Tile.CAVERN, Tile.CAVERN, Tile.CAVERN),
	&"magma_stone": Vector3i(Tile.MAGMA, Tile.MAGMA, Tile.MAGMA),
	&"crystal_stone": Vector3i(Tile.CRYSTAL, Tile.CRYSTAL, Tile.CRYSTAL),
	&"frost_stone": Vector3i(Tile.STONE, Tile.ICE, Tile.STONE),
	&"mycelium_stone": Vector3i(Tile.MUSHROOM, Tile.STONE, Tile.STONE),
	&"desert_sand": Vector3i(Tile.SAND, Tile.SAND, Tile.SANDSTONE),
	&"ocean_sand": Vector3i(Tile.WET_SAND, Tile.WET_SAND, Tile.SANDSTONE),
	&"sandstone": Vector3i(Tile.SANDSTONE, Tile.SANDSTONE, Tile.SANDSTONE),
	&"frost_snow": Vector3i(Tile.SNOW, Tile.SNOW_SIDE, Tile.SNOW),
	&"frost_ice": Vector3i(Tile.ICE, Tile.ICE, Tile.ICE),
	&"mushroom_soil": Vector3i(Tile.MUSHROOM, Tile.MUD, Tile.MUD),
	&"mushroom_stem": Vector3i(Tile.BARK, Tile.BARK, Tile.BARK),
	&"mushroom_cap": Vector3i(Tile.MUSHROOM, Tile.MUSHROOM, Tile.MUSHROOM),
	&"jungle_grass": Vector3i(Tile.GRASS_TOP, Tile.JUNGLE_GRASS_SIDE, Tile.MUD),
	&"jungle_mudstone": Vector3i(Tile.MUD, Tile.MUD, Tile.MUD),
	&"corrupted_grass": Vector3i(Tile.GRASS_TOP, Tile.EVIL_GRASS_SIDE, Tile.DIRT),
	&"crimson_grass": Vector3i(Tile.GRASS_TOP, Tile.EVIL_GRASS_SIDE, Tile.DIRT),
	&"ebonstone": Vector3i(Tile.EVILSTONE, Tile.EVILSTONE, Tile.EVILSTONE),
	&"crimstone": Vector3i(Tile.EVILSTONE, Tile.EVILSTONE, Tile.EVILSTONE),
	&"pearlstone": Vector3i(Tile.HALLOWSTONE, Tile.HALLOWSTONE, Tile.HALLOWSTONE),
	&"hallowed_grass": Vector3i(Tile.GRASS_TOP, Tile.HALLOW_GRASS_SIDE, Tile.DIRT),
	&"reefstone": Vector3i(Tile.STONE, Tile.STONE, Tile.STONE),
	&"coral": Vector3i(Tile.PLANT, Tile.PLANT, Tile.PLANT),
	&"dead_wood": Vector3i(Tile.BARK, Tile.BARK, Tile.BARK),
	&"pale_wood": Vector3i(Tile.BARK, Tile.BARK, Tile.BARK),
	&"jungle_leaves": Vector3i(Tile.LEAF_JUNGLE, Tile.LEAF_JUNGLE, Tile.LEAF_JUNGLE),
	&"ebon_leaves": Vector3i(Tile.LEAF_EVIL, Tile.LEAF_EVIL, Tile.LEAF_EVIL),
	&"crim_leaves": Vector3i(Tile.LEAF_EVIL, Tile.LEAF_EVIL, Tile.LEAF_EVIL),
	&"hallow_leaves": Vector3i(Tile.LEAF_HALLOW, Tile.LEAF_HALLOW, Tile.LEAF_HALLOW),
	&"cactus": Vector3i(Tile.PLANT, Tile.PLANT, Tile.PLANT),
	&"ash": Vector3i(Tile.ASH, Tile.ASH, Tile.ASH),
	&"obsidian": Vector3i(Tile.OBSIDIAN, Tile.OBSIDIAN, Tile.OBSIDIAN),
	&"hellstone": Vector3i(Tile.MAGMA, Tile.MAGMA, Tile.MAGMA),
	&"torch": Vector3i(Tile.BARK, Tile.BARK, Tile.BARK),
	&"mycelium": Vector3i(Tile.MUSHROOM, Tile.MUSHROOM, Tile.MUSHROOM),
	&"pale_bloom": Vector3i(Tile.GLOW, Tile.GLOW, Tile.GLOW),
	&"beacon": Vector3i(Tile.METAL, Tile.METAL, Tile.METAL),
	&"test_wall": Vector3i(Tile.BRICK, Tile.BRICK, Tile.BRICK),
	# --- Building set ---
	&"wood_platform": Vector3i(Tile.PLATFORM, Tile.PLATFORM, Tile.PLATFORM),
	&"wood_door": Vector3i(Tile.DOOR, Tile.DOOR, Tile.DOOR),
	&"wood_door_open": Vector3i(Tile.DOOR_OPEN, Tile.DOOR_OPEN, Tile.DOOR_OPEN),
	&"stone_brick": Vector3i(Tile.BRICK, Tile.BRICK, Tile.BRICK),
	&"glass": Vector3i(Tile.GLASS, Tile.GLASS, Tile.GLASS),
	&"workbench": Vector3i(Tile.WORKBENCH, Tile.WORKBENCH, Tile.WORKBENCH),
	&"furnace": Vector3i(Tile.FURNACE, Tile.FURNACE, Tile.FURNACE),
	&"anvil": Vector3i(Tile.ANVIL, Tile.ANVIL, Tile.ANVIL),
	&"chest": Vector3i(Tile.CHEST, Tile.CHEST, Tile.CHEST),
	&"chair": Vector3i(Tile.CHAIR, Tile.CHAIR, Tile.CHAIR),
	&"wood_stairs_n": Vector3i(Tile.PLANK, Tile.PLANK, Tile.PLANK),
	&"wood_stairs_e": Vector3i(Tile.PLANK, Tile.PLANK, Tile.PLANK),
	&"wood_stairs_s": Vector3i(Tile.PLANK, Tile.PLANK, Tile.PLANK),
	&"wood_stairs_w": Vector3i(Tile.PLANK, Tile.PLANK, Tile.PLANK),
	&"stone_stairs_n": Vector3i(Tile.BRICK, Tile.BRICK, Tile.BRICK),
	&"stone_stairs_e": Vector3i(Tile.BRICK, Tile.BRICK, Tile.BRICK),
	&"stone_stairs_s": Vector3i(Tile.BRICK, Tile.BRICK, Tile.BRICK),
	&"stone_stairs_w": Vector3i(Tile.BRICK, Tile.BRICK, Tile.BRICK),
	&"lumen_crystal": Vector3i(Tile.CRYSTAL, Tile.CRYSTAL, Tile.CRYSTAL),
	&"water": Vector3i(Tile.LIQUID, Tile.LIQUID, Tile.LIQUID),
	&"lava": Vector3i(Tile.LIQUID, Tile.LIQUID, Tile.LIQUID),
	&"coal_ore": Vector3i(Tile.ORE_METAL, Tile.ORE_METAL, Tile.ORE_METAL),
	&"copper_ore": Vector3i(Tile.ORE_METAL, Tile.ORE_METAL, Tile.ORE_METAL),
	&"iron_ore": Vector3i(Tile.ORE_METAL, Tile.ORE_METAL, Tile.ORE_METAL),
	&"silver_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"gold_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"ancient_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"frost_crystal_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"fungal_ore": Vector3i(Tile.ORE_METAL, Tile.ORE_METAL, Tile.ORE_METAL),
	&"volcanic_crystal_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"amber_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"void_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"blood_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"radiant_crystal_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
	&"pearl_ore": Vector3i(Tile.ORE_GEM, Tile.ORE_GEM, Tile.ORE_GEM),
}

static var _texture: ImageTexture
static var _image: Image


static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(build_image())
	return _texture


static func build_image() -> Image:
	if _image != null:
		return _image
	var image := Image.create(ATLAS_PIXELS, ATLAS_PIXELS, false, Image.FORMAT_RGB8)
	image.fill(Color(1, 1, 1))
	for tile in range(TILE_COUNT):
		_paint_tile(image, tile)
	_image = image
	return image


static func tile_rect(tile: int) -> Rect2:
	var column := tile % COLUMNS
	var row := floori(float(tile) / float(COLUMNS))
	return Rect2(column * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)


static func tiles_for_block(block_id: StringName) -> Vector3i:
	return BLOCK_TILES.get(block_id, Vector3i(Tile.PLAIN, Tile.PLAIN, Tile.PLAIN))


## Builds a per-block-id table in the same order as VoxelWorld.block_defs.
static func block_tile_table(block_defs: Array) -> Array:
	var table: Array = []
	for definition in block_defs:
		if definition == null:
			table.append(Vector3i(Tile.PLAIN, Tile.PLAIN, Tile.PLAIN))
			continue
		table.append(tiles_for_block(definition.block_id))
	return table


static func _paint_tile(image: Image, tile: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + tile * 7919
	var base := 1.0
	var column := tile % COLUMNS
	var row := floori(float(tile) / float(COLUMNS))
	var ox := column * TILE_SIZE
	var oy := row * TILE_SIZE
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var value := 1.0
			match tile:
				Tile.PLAIN:
					value = 0.97 + rng.randf() * 0.06
				Tile.GRASS_TOP:
					# Terraria grass is a bright, fairly even green; the old range
					# (0.72-0.86) multiplied the albedo down into dark moss.
					value = 0.86 + rng.randf() * 0.10
					# Upright blades in the top two thirds.
					if y < 9 and (x + tile) % 3 == 0:
						value += 0.14
					elif y < 5 and (x * 3 + y) % 5 == 0:
						value += 0.08
				Tile.DIRT:
					value = 0.72 + rng.randf() * 0.18
					if rng.randf() < 0.10:
						value = 0.54
				Tile.STONE:
					value = 0.88 + _crack(x, y, 0.34) * 0.18 + rng.randf() * 0.04
				Tile.DEEPSTONE:
					value = 0.66 + _strata(x, y) * 0.18 + rng.randf() * 0.05
					if _crack(x, y, 0.42) > 0.9:
						value -= 0.14
				Tile.CAVERN:
					value = 0.74 + _crack(x, y, 0.22) * 0.26 + rng.randf() * 0.05
					if rng.randf() < 0.05:
						value += 0.14
				Tile.SAND:
					value = 0.92 + rng.randf() * 0.10
					if rng.randf() < 0.08:
						value = 0.76
				Tile.SANDSTONE:
					value = 0.84 + (0.10 if (y + 3) % 5 == 0 else 0.0) + rng.randf() * 0.05
				Tile.SNOW:
					# RGB8 clamps at 1.0, so snow detail must live below white or it
					# renders as a flat sheet.
					value = 0.88 + rng.randf() * 0.10
					if rng.randf() < 0.10:
						value = 1.0
				Tile.ICE:
					value = 0.88 + rng.randf() * 0.08
					if (x + y * 2) % 9 == 0:
						value = 1.12
				Tile.MUD:
					value = 0.66 + rng.randf() * 0.16
					if rng.randf() < 0.14:
						value = 0.48
					elif rng.randf() < 0.06:
						value = 0.90
				Tile.BARK:
					value = 0.70 + absf(sin(float(x) * 1.7)) * 0.20 + rng.randf() * 0.05
					if x % 5 == 0:
						value *= 0.78
				Tile.LEAVES:
					value = 0.54 + rng.randf() * 0.34
					if (x * x + y * 3) % 7 == 0:
						value = 0.88
				Tile.MUSHROOM:
					value = 0.80 + rng.randf() * 0.10
					if (x - 4) * (x - 4) + (y - 5) * (y - 5) < 7:
						value = 1.10
					elif (x - 11) * (x - 11) + (y - 10) * (y - 10) < 5:
						value = 0.65
				Tile.EVILSTONE:
					value = 0.68 + rng.randf() * 0.12
					if _crack(x, y, 0.28) > 0.72:
						value = 0.92
				Tile.HALLOWSTONE:
					value = 0.90 + rng.randf() * 0.10
					if (x * 5 + y * 3) % 11 == 0:
						value = 1.24
				Tile.ASH:
					value = 0.78 + rng.randf() * 0.12
					if rng.randf() < 0.08:
						value = 0.62
				Tile.MAGMA:
					value = 0.52 + rng.randf() * 0.12
					if _crack(x, y, 0.20) > 0.62:
						value = 1.22
				Tile.OBSIDIAN:
					value = 0.46 + rng.randf() * 0.08
					if (x + y) % 8 == 0:
						value = 0.86
				Tile.ORE_METAL:
					value = 0.64 + rng.randf() * 0.06
					if (x * 3 + y * 7) % 17 < 3:
						value = 1.0
				Tile.ORE_GEM:
					value = 0.62 + rng.randf() * 0.06
					if (x - 8) * (x - 8) + (y - 8) * (y - 8) < 12 or (x * y) % 23 < 2:
						value = 1.0
				Tile.LIQUID:
					value = 0.92 + sin(float(y) * 0.55 + float(x) * 0.35) * 0.08
				Tile.CRYSTAL:
					value = 0.82 + absf(sin(float(x + y) * 0.6)) * 0.26
					if (x - y) % 7 == 0:
						value = 1.24
				Tile.BRICK:
					value = 0.86 + rng.randf() * 0.05
					if y % 6 == 0 or (x + (y / 6) * 4) % 8 == 0:
						value = 0.58
				Tile.PLANT:
					value = 0.62 + rng.randf() * 0.16
					if x % 4 == 0:
						value = 0.92
				Tile.CLOTH:
					value = 0.84 + rng.randf() * 0.06
					if (x + y) % 4 == 0:
						value = 0.70
				Tile.METAL:
					value = 0.74 + absf(sin(float(x) * 1.1)) * 0.16
					if y == 0 or y == 15:
						value = 0.56
				Tile.GLOW:
					value = 0.90 + rng.randf() * 0.08
					if rng.randf() < 0.14:
						value = 1.0
				Tile.GRASS_SIDE:
					value = 0.70 + rng.randf() * 0.16
					if y < 3:
						value = 0.96 + rng.randf() * 0.18
					elif y < 6 and (x + y) % 2 == 0:
						value = 0.92 + rng.randf() * 0.14
					elif y < 9 and x % 5 == 0:
						value = 0.88
				Tile.JUNGLE_GRASS_SIDE:
					value = 0.60 + rng.randf() * 0.16
					if y < 4:
						value = 0.92 + rng.randf() * 0.20
					elif y < 8 and (x + y * 2) % 3 == 0:
						value = 0.86 + rng.randf() * 0.10
				Tile.EVIL_GRASS_SIDE:
					value = 0.58 + rng.randf() * 0.14
					if y < 3:
						value = 0.94 + rng.randf() * 0.16
					elif y < 7 and (x * 3 + y) % 4 == 0:
						value = 0.84
				Tile.HALLOW_GRASS_SIDE:
					value = 0.80 + rng.randf() * 0.12
					if y < 4:
						value = 1.04 + rng.randf() * 0.18
					elif y < 8 and (x + y) % 3 == 0:
						value = 0.98
				Tile.SNOW_SIDE:
					value = 0.88 + rng.randf() * 0.08
					if y < 5:
						value = 1.04 + rng.randf() * 0.10
					elif y < 8 and (x + y) % 4 == 0:
						value = 0.96
				Tile.WET_SAND:
					value = 0.78 + rng.randf() * 0.12
					if (x * 2 + y) % 9 == 0:
						value = 0.96
				Tile.LEAF_JUNGLE:
					value = 0.48 + rng.randf() * 0.36
					if (x * x + y) % 6 == 0:
						value = 0.90
				Tile.LEAF_EVIL:
					value = 0.42 + rng.randf() * 0.34
					if (x + y * 3) % 7 == 0:
						value = 0.86
				Tile.LEAF_HALLOW:
					value = 0.74 + rng.randf() * 0.36
					if (x * 3 + y * 2) % 8 == 0:
						value = 1.16
				Tile.DEEP_MUD:
					value = 0.56 + rng.randf() * 0.16
					if rng.randf() < 0.16:
						value = 0.38
					elif rng.randf() < 0.08:
						value = 0.86
				Tile.ORE_CRYSTAL:
					value = 0.58 + rng.randf() * 0.06
					if (x * 5 + y * 3) % 13 < 3:
						value = 1.12
				Tile.PLANK:
					# Four horizontal boards with a dark seam and nail heads.
					value = 0.86 + absf(sin(float(x) * 0.9)) * 0.08 + rng.randf() * 0.04
					if y % 4 == 0:
						value = 0.60
					elif y % 4 == 3 and (x + (y / 4) * 5) % 7 == 0:
						value = 0.56
				Tile.PLATFORM:
					# Plank deck: bright top lip, dark underside rail.
					value = 0.90 + absf(sin(float(x) * 1.1)) * 0.08
					if y < 2:
						value = 1.02
					elif y > 12:
						value = 0.54
					elif y == 6 or y == 7:
						value = 0.74
					elif (x + y) % 9 == 0:
						value = 0.62
				Tile.GLASS:
					# Pale pane with a brighter bevel and a few sparkle pixels.
					value = 0.94 + rng.randf() * 0.05
					if x == 0 or y == 0 or x == 15 or y == 15:
						value = 1.10
					elif x == 1 or y == 1:
						value = 1.04
					elif rng.randf() < 0.05:
						value = 1.22
					elif (x + y) % 11 == 0:
						value = 0.80
				Tile.WORKBENCH:
					value = 0.88 + absf(sin(float(x) * 1.2)) * 0.08
					if y < 3:
						value = 1.02
					elif y == 4 or y == 5:
						value = 0.62
					elif y > 10 and (x < 4 or x > 11):
						value = 0.70
				Tile.FURNACE:
					# Firebrick courses; the mesher adds the lit mouth separately.
					value = 0.74 + rng.randf() * 0.08
					if y % 5 == 0 or (x + (y / 5) * 3) % 6 == 0:
						value = 0.50
					elif rng.randf() < 0.06:
						value = 0.92
				Tile.CHEST:
					value = 0.86 + absf(sin(float(x) * 1.4)) * 0.08
					if y >= 4 and y <= 6:
						value = 0.52
					elif x == 2 or x == 13:
						value = 0.58
					elif y < 4 and x % 5 == 0:
						value = 0.66
				Tile.DOOR:
					# Vertical boards with a pair of raised panels.
					value = 0.88 + absf(sin(float(y) * 1.3)) * 0.06
					if x % 4 == 0:
						value = 0.62
					elif y > 3 and y < 12 and x > 4 and x < 11:
						value = 0.98 if (x == 5 or x == 10 or y == 4 or y == 11) else 0.88
					elif y >= 6 and y <= 9 and (x == 3 or x == 12):
						value = 0.48
				Tile.DOOR_OPEN:
					value = 0.88 + absf(sin(float(x) * 1.3)) * 0.06
					if y % 4 == 0:
						value = 0.62
					elif x > 3 and x < 12 and y > 3 and y < 12:
						value = 0.96 if (x == 4 or x == 11 or y == 4 or y == 11) else 0.86
				Tile.CHAIR:
					# Upholstered seat band with vertical back slats.
					value = 0.86 + absf(sin(float(y) * 1.5)) * 0.06
					if y > 4 and y < 10:
						value = 0.70
					elif y >= 10:
						value = 0.96 if x % 4 == 0 else 0.84
				Tile.ANVIL:
					# Dark iron with a bright hammered top edge.
					value = 0.60 + rng.randf() * 0.08
					if y < 4:
						value = 0.96
					elif (x + y * 2) % 7 == 0:
						value = 0.80
			value = _material_detail(tile, x, y, value, rng)
			value = clampf(value, 0.0, 1.45)
			image.set_pixel(ox + x, oy + y, Color(value, value, value))
	# A one-pixel darker border on solid tiles gives crisp block seams without
	# turning every face into a black-outlined grid.
	if tile not in [Tile.PLAIN, Tile.LIQUID, Tile.GLOW, Tile.PLANT]:
		for i in range(TILE_SIZE):
			_scale_pixel(image, ox + i, oy, 0.93)
			_scale_pixel(image, ox + i, oy + TILE_SIZE - 1, 0.93)
			_scale_pixel(image, ox, oy + i, 0.95)
			_scale_pixel(image, ox + TILE_SIZE - 1, oy + i, 0.95)


static func _material_detail(tile: int, x: int, y: int, value: float, rng: RandomNumberGenerator) -> float:
	match tile:
		Tile.GRASS_TOP:
			var clump := 0.5 + 0.5 * sin(float(x) * 1.65 + float(y) * 0.55)
			# Grass is a bright, even green in Terraria. The old detail pass ran
			# 0.55-0.79 average with scattered 0.40 pixels, which multiplied the
			# palette down into dark moss and stamped a dot lattice on open
			# ground at every block seam.
			value = 0.90 + clump * 0.12 + rng.randf() * 0.05
			if y < 9 and x % 4 == 0:
				value += 0.10
			if y > 9 and x % 3 == 1:
				value -= 0.05
			if (x * 7 + y * 11) % 41 == 0:
				value = 1.15
			if (x * 5 + y * 3) % 29 == 0:
				value = 0.72
		Tile.DIRT:
			var clod := float((x / 4) * 3 + (y / 3) * 5)
			value = 0.62 + fposmod(sin(clod * 1.7) * 0.5 + 0.5, 1.0) * 0.26 + rng.randf() * 0.06
			if x % 5 == 1 or y % 7 == 2:
				value *= 0.66
			if (x + y * 3) % 23 == 0:
				value = 0.98
			if (x * 3 + y * 5) % 31 == 0:
				value = 0.40
		Tile.STONE, Tile.DEEPSTONE, Tile.CAVERN:
			var mortar := minf(absf(fmod(float(x) + float(y) * 0.55, 6.0) - 3.0), absf(fmod(float(y) + float(x) * 0.30, 5.0) - 2.5))
			value = 0.70 + clampf(mortar * 0.095, 0.0, 0.28) + rng.randf() * 0.05
			if (x * 3 + y * 7) % 19 == 0:
				value *= 0.56
			if (x * 5 + y * 2) % 29 == 0:
				value += 0.22
			value *= 1.08
		Tile.SAND, Tile.WET_SAND:
			var ripple := sin(float(y) * 0.95 + sin(float(x) * 0.28) * 2.2)
			value = 0.88 + ripple * 0.07 + rng.randf() * 0.035
			if (x * 3 + y) % 17 == 0:
				value = 0.72
		Tile.SANDSTONE:
			value = 0.78 + sin(float(y) * 0.85 + float(x) * 0.12) * 0.05 + rng.randf() * 0.03
			if y % 5 == 0:
				value *= 0.78
		Tile.SNOW:
			var drift := sin(float(x) * 0.35 + sin(float(y) * 0.25) * 2.0)
			value = 0.90 + drift * 0.035 + rng.randf() * 0.035
			if (x * 3 + y * 5) % 37 == 0:
				value = 1.0
		Tile.ICE:
			value = 0.82 + absf(sin(float(x) * 0.55 + float(y) * 0.44)) * 0.12 + rng.randf() * 0.04
			if (x + y) % 9 == 0:
				value += 0.16
		Tile.BARK:
			value = 0.58 + absf(sin(float(x) * 1.22 + sin(float(y) * 0.2))) * 0.24 + rng.randf() * 0.04
			if x % 5 == 0:
				value *= 0.70
			if (x * 5 + y * 3) % 31 == 0:
				value = 0.38
		Tile.LEAVES, Tile.LEAF_JUNGLE, Tile.LEAF_EVIL, Tile.LEAF_HALLOW:
			var vein := absf(sin(float(x) * 0.75 + float(y) * 0.45))
			value = 0.52 + vein * 0.26 + rng.randf() * 0.12
			if vein < 0.16:
				value *= 0.58
			if (x * 3 + y * 7) % 13 == 0:
				value = 0.98
		Tile.ORE_METAL, Tile.ORE_GEM, Tile.ORE_CRYSTAL:
			var cluster := (x - 5) * (x - 5) + (y - 6) * (y - 6)
			value = 0.57 + rng.randf() * 0.06
			if cluster < 9 or (x > 9 and y > 8 and (x - 12) * (x - 12) + (y - 12) * (y - 12) < 7):
				value = 1.18
			elif (x * 5 + y * 3) % 23 < 2:
				value = 0.94
		Tile.EVILSTONE:
			value = 0.68 + absf(sin(float(x) * 0.7 + float(y) * 0.4)) * 0.22 + rng.randf() * 0.05
			if (x * 3 + y * 5) % 13 == 0:
				value = 0.42
		Tile.HALLOWSTONE:
			value = 0.82 + absf(sin(float(x + y) * 0.46)) * 0.22 + rng.randf() * 0.05
			if (x * 5 + y * 3) % 17 == 0:
				value = 1.28
		Tile.MUD, Tile.DEEP_MUD:
			value = 0.52 + absf(sin(float(x) * 0.35 + float(y) * 0.7)) * 0.17 + rng.randf() * 0.06
			if (x * 2 + y) % 11 == 0:
				value = 0.34
		Tile.MAGMA:
			value = 0.48 + absf(sin(float(x) * 0.75 + float(y) * 0.5)) * 0.16 + rng.randf() * 0.04
			if (x * 3 + y * 4) % 9 == 0:
				value = 1.30
		Tile.LIQUID:
			value = 0.86 + sin(float(x) * 0.4 + float(y) * 0.55) * 0.10
			if (x + y * 3) % 13 == 0:
				value = 1.02
	return value


static func _scale_pixel(image: Image, x: int, y: int, factor: float) -> void:
	var color := image.get_pixel(x, y)
	image.set_pixel(x, y, Color(color.r * factor, color.g * factor, color.b * factor))


static func _crack(x: int, y: int, threshold: float) -> float:
	var wave := absf(sin(float(x) * 0.9 + float(y) * 0.4))
	if wave < threshold:
		return 0.0
	if (x * 3 + y * 5) % 13 == 0:
		return 1.0
	return wave * 0.5


static func _strata(x: int, y: int) -> float:
	return 0.5 + 0.5 * sin(float(y) * 1.3 + sin(float(x) * 0.4))
