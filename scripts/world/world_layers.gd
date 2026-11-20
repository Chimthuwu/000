extends RefCounted
class_name WorldLayers

# Canonical depth model shared by world generation, enemies and UI.
#
# Phase 2 makes the model DEPTH-RELATIVE instead of tied to absolute Y, so the
# world can grow vertically without re-tuning every system. Every band is
# measured in blocks below the local surface height, which means a mountain and
# a riverbed at the same depth share the same layer.
#
#   depth 0..1          Surface
#   2..23               Upper underground (soil-adjacent rock, first pockets)
#   24..63              Underground
#   64..107             Deep underground (deepstone, richer ore)
#   108..149            Cavern depths (cavern stone, lava, big caverns)
#   150..167            Abyss (ancient crystal realm, rarest resources)
#   168+                Underworld (ash, lava seas, obsidian, hellstone)
#
# The world slab is 256 blocks tall and the surface sits near y=192, giving ~190
# blocks of genuine descent plus ~64 blocks of sky headroom for future sky
# islands. Nothing here assumes a specific WORLD_Y: change the constants below
# and in VoxelWorld together and every consumer follows.

const WORLD_Y := 256
const CHUNKS_Y := 16
const SURFACE_LIFT := 168
const SURFACE_BAND := 2

const UPPER_DEPTH := 24
const UNDERGROUND_DEPTH := 64
const DEEP_DEPTH := 108
const CAVERN_DEPTH := 150
const UNDERWORLD_DEPTH := 168

enum Layer { SURFACE = 0, UPPER_UNDERGROUND = 1, UNDERGROUND = 2, DEEP = 3, CAVERN = 4, ABYSS = 5, SKY = 6, UNDERWORLD = 7 }


static func is_underworld(y: int, surface_y: int) -> bool:
	return surface_y - y >= UNDERWORLD_DEPTH


static func depth_below_surface(y: int, surface_y: int) -> int:
	return surface_y - y


static func layer_at(y: int, surface_y: int) -> int:
	var depth := surface_y - y
	if depth < 0:
		return Layer.SKY
	if depth < SURFACE_BAND:
		return Layer.SURFACE
	if depth < UPPER_DEPTH:
		return Layer.UPPER_UNDERGROUND
	if depth < UNDERGROUND_DEPTH:
		return Layer.UNDERGROUND
	if depth < DEEP_DEPTH:
		return Layer.DEEP
	if depth < CAVERN_DEPTH:
		return Layer.CAVERN
	if depth < UNDERWORLD_DEPTH:
		return Layer.ABYSS
	return Layer.UNDERWORLD


static func layer_name(layer: int) -> String:
	match layer:
		Layer.SURFACE:
			return "Surface"
		Layer.UPPER_UNDERGROUND:
			return "Upper Underground"
		Layer.UNDERGROUND:
			return "Underground"
		Layer.DEEP:
			return "Deep Underground"
		Layer.CAVERN:
			return "Cavern Depths"
		Layer.ABYSS:
			return "The Abyss"
		Layer.UNDERWORLD:
			return "The Underworld"
		_:
			return "Sky"


# Zones are a coarser grouping used by audio/UI and by the geological palette.
# 0 = surface, 1 = shallow rock, 2 = deep rock, 3 = abyss.
static func zone_at(y: int, surface_y: int) -> int:
	var depth := surface_y - y
	if depth < SURFACE_BAND:
		return 0
	if depth < DEEP_DEPTH:
		return 1
	if depth < CAVERN_DEPTH:
		return 2
	if depth < UNDERWORLD_DEPTH:
		return 3
	return 4


# Normalised 0..1 progress into the underground, useful for fog/ambience.
static func depth_ratio(y: int, surface_y: int) -> float:
	var span := maxf(1.0, float(surface_y))
	return clampf(float(surface_y - y) / span, 0.0, 1.0)
