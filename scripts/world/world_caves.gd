extends RefCounted
class_name WorldCaves

# Deterministic underground features used by WorldGenerator on worker threads.
# Everything is a pure function of (seed, world_x, world_y, world_z) so chunks
# regenerate identically after unload and seam cleanly across borders.
#
# Phase 2 shapes:
#   * broad "cheese" caverns that grow with depth
#   * winding spaghetti tunnels
#   * vertical shafts linking levels
#   * underground ravines
#   * natural rock bridges through large caverns
#   * rare crystal chambers
#   * aquifer lakes and deep lava pools (deterministic fill levels)

static var _seed := -1
static var _noise: Dictionary = {}


static func configure(world_seed: int) -> void:
	if world_seed == _seed and not _noise.is_empty():
		return
	_seed = world_seed
	_noise = {
		"cave": _make(world_seed ^ 0x2C79, 3, 0.042),
		"tunnel": _make(world_seed ^ 0xB14E, 2, 0.050),
		"chamber": _make(world_seed ^ 0x7E21, 2, 0.022),
		"shaft": _make(world_seed ^ 0x51AF, 2, 0.030),
		"ravine": _make(world_seed ^ 0x9D13, 2, 0.024),
		"chasm": _make(world_seed ^ 0x7C4A, 2, 0.012),
		"bridge": _make(world_seed ^ 0x3BC7, 2, 0.120),
		"crystal": _make(world_seed ^ 0x6A2D, 3, 0.055),
		"aquifer": _make(world_seed ^ 0x22E9, 3, 0.010),
		"water": _make(world_seed ^ 0x7711, 2, 0.070),
		"lava": _make(world_seed ^ 0x4C0B, 2, 0.055),
		"volcanic": _make(world_seed ^ 0x18A3, 3, 0.014),
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


# Natural rock shelf: rarely, a carved cell keeps its rock, leaving a bridge
# across a cavern instead of one giant open void.
static func _is_bridge(x: int, y: int, z: int, depth: int) -> bool:
	if depth < 24:
		return false
	if positive_mod(y, 23) > 1:
		return false
	var bridge: FastNoiseLite = _noise["bridge"]
	return bridge.get_noise_3d(float(x), float(y), float(z)) > 0.58


# True when the cell should be carved to air (before liquids are placed).
# The solid cap under the surface keeps plains from becoming sinks.
static func is_cave(x: int, y: int, z: int, surface_y: int) -> bool:
	_ensure()
	var depth := surface_y - y
	if y < 0 or depth < 3:
		return false
	if _is_bridge(x, y, z, depth):
		return false

	var cave: FastNoiseLite = _noise["cave"]
	var threshold := 0.55 - clampf(float(depth), 0.0, 100.0) * 0.0009
	if cave.get_noise_3d(float(x), float(y), float(z)) > threshold:
		return true

	var tunnel: FastNoiseLite = _noise["tunnel"]
	if absf(tunnel.get_noise_3d(float(x) * 1.7, float(y) * 0.8, float(z) * 1.7)) < 0.070:
		return true

	if depth >= 24:
		var chamber: FastNoiseLite = _noise["chamber"]
		if chamber.get_noise_3d(float(x), float(y), float(z)) > 0.60:
			return true

	# Vertical shafts: a narrow 2D ridge carved straight down, gated by a second
	# low-frequency field so shafts cluster into a plausible network.
	if depth >= 12:
		var shaft: FastNoiseLite = _noise["shaft"]
		var shaft_column := shaft.get_noise_2d(float(x) * 3.1, float(z) * 3.1)
		if absf(shaft_column) < 0.028:
			return true

	# Ravines: long narrow trenches, only in the upper-middle underground.
	if depth >= 26 and depth <= 78:
		var ravine: FastNoiseLite = _noise["ravine"]
		var ravine_line := ravine.get_noise_2d(float(x) * 2.4, float(z) * 2.4)
		if absf(ravine_line) < 0.045:
			return true

	# Deep chasms: rare, very wide vertical gashes that cut the lower world into
	# distinct regions and give long descending routes.
	if depth >= 118:
		var chasm: FastNoiseLite = _noise["chasm"]
		var chasm_line := chasm.get_noise_2d(float(x) * 1.2, float(z) * 1.2)
		if absf(chasm_line) < 0.018:
			return true

	return false


# Biome-shaped larger chambers. The Jungle opens into broad muddy grottoes,
# the Hallow into crystal-lit caverns; both only carve solid rock below the
# shallow cap, so the surface stays intact.
static func is_biome_chamber(x: int, y: int, z: int, surface_y: int, biome: int) -> bool:
	_ensure()
	var depth := surface_y - y
	if depth < 18:
		return false
	match biome:
		BiomeManager.JUNGLE:
			if depth > 130:
				return false
			var chamber: FastNoiseLite = _noise["chamber"]
			return chamber.get_noise_3d(float(x) * 0.85, float(y) * 0.85, float(z) * 0.85) > 0.47
		BiomeManager.HALLOW:
			if depth > 150:
				return false
			var crystal: FastNoiseLite = _noise["crystal"]
			return crystal.get_noise_3d(float(x), float(y), float(z)) > 0.68
		BiomeManager.OCEAN:
			if depth > 48:
				return false
			var cave: FastNoiseLite = _noise["cave"]
			return cave.get_noise_3d(float(x), float(y), float(z)) > 0.52
	return false


# Rare chamber envelope where crystal formations line the walls.
static func is_crystal_chamber(x: int, y: int, z: int, surface_y: int) -> bool:
	_ensure()
	var depth := surface_y - y
	if depth < 30:
		return false
	var crystal: FastNoiseLite = _noise["crystal"]
	return crystal.get_noise_3d(float(x), float(y), float(z)) > 0.66


# 0 = no liquid, 1 = water, 2 = lava. Fill levels are per-column noise fields so
# lakes have believable surfaces and neighbouring chunks agree at the border.
static func liquid_at(x: int, y: int, z: int, surface_y: int) -> int:
	_ensure()
	var depth := surface_y - y
	if depth < 4:
		return 0
	# Lava: deep pools and lakes, rarer than water and only in the lower world.
	if depth >= 74:
		var lava: FastNoiseLite = _noise["lava"]
		var lava_value := lava.get_noise_3d(float(x), float(y), float(z))
		if depth >= 86 and lava_value > -0.10:
			return 2
		if lava_value > 0.30:
			return 2
	# Aquifer: a per-column water table between 18 and 64 blocks down. Caves that
	# dip below it fill with water; shallow dry caves above it stay dry.
	var aquifer: FastNoiseLite = _noise["aquifer"]
	var table := 18.0 + (aquifer.get_noise_2d(float(x), float(z)) * 0.5 + 0.5) * 46.0
	if float(depth) > table and depth < 80:
		var water: FastNoiseLite = _noise["water"]
		if water.get_noise_3d(float(x), float(y), float(z)) > -0.45:
			return 1
	return 0


# Volcanic heat mask for deep geology. 0..1, only meaningful below DEEP_DEPTH.
static func volcanic_factor(x: int, y: int, z: int) -> float:
	_ensure()
	var volcanic: FastNoiseLite = _noise["volcanic"]
	return clampf(volcanic.get_noise_3d(float(x), float(y), float(z)) * 0.5 + 0.5, 0.0, 1.0)


# Shared vein field. Ores sample this so a deposit reads as one connected blob
# rather than isolated blocks. Returns roughly -1..1.
static func vein_value(x: int, y: int, z: int) -> float:
	_ensure()
	var ore: FastNoiseLite = _noise["crystal"]
	return ore.get_noise_3d(float(x) * 0.72, float(y) * 0.72, float(z) * 0.72)


# --- Per-column cache -------------------------------------------------------
# The generator asks about every cell in a chunk. Shaft/ravine/chasm masks and
# the aquifer table depend only on (x, z), so they are computed once per chunk
# column and reused for all 16 vertical cells. Only in-chunk columns are needed
# (the cached masks never look at a neighbouring column), so this is exactly a
# 16x16 table. This removes roughly 3 noise calls per underground cell without
# changing the generated result.
const CACHE_SIZE := 16

static func build_cache(origin: Vector3i) -> Dictionary:
	_ensure()
	var flags := PackedByteArray()
	flags.resize(CACHE_SIZE * CACHE_SIZE)
	var aquifer_table := PackedFloat32Array()
	aquifer_table.resize(CACHE_SIZE * CACHE_SIZE)
	var shaft: FastNoiseLite = _noise["shaft"]
	var ravine: FastNoiseLite = _noise["ravine"]
	var chasm: FastNoiseLite = _noise["chasm"]
	var aquifer: FastNoiseLite = _noise["aquifer"]
	for z in range(CACHE_SIZE):
		for x in range(CACHE_SIZE):
			var world_x := float(origin.x + x)
			var world_z := float(origin.z + z)
			var bits := 0
			if absf(shaft.get_noise_2d(world_x * 3.1, world_z * 3.1)) < 0.028:
				bits |= 1
			if absf(ravine.get_noise_2d(world_x * 2.4, world_z * 2.4)) < 0.045:
				bits |= 2
			if absf(chasm.get_noise_2d(world_x * 1.2, world_z * 1.2)) < 0.018:
				bits |= 4
			var index := x + z * CACHE_SIZE
			flags[index] = bits
			aquifer_table[index] = 18.0 + (aquifer.get_noise_2d(world_x, world_z) * 0.5 + 0.5) * 46.0
	return {"origin": origin, "flags": flags, "aquifer": aquifer_table}


static func _cache_index(cache: Dictionary, x: int, z: int) -> int:
	var origin: Vector3i = cache["origin"]
	return (x - origin.x) + (z - origin.z) * CACHE_SIZE


static func is_cave_cached(cache: Dictionary, x: int, y: int, z: int, surface_y: int) -> bool:
	var depth := surface_y - y
	if y < 0 or depth < 3:
		return false
	if _is_bridge(x, y, z, depth):
		return false
	var cave: FastNoiseLite = _noise["cave"]
	var threshold := 0.55 - clampf(float(depth), 0.0, 100.0) * 0.0009
	if cave.get_noise_3d(float(x), float(y), float(z)) > threshold:
		return true
	var tunnel: FastNoiseLite = _noise["tunnel"]
	if absf(tunnel.get_noise_3d(float(x) * 1.7, float(y) * 0.8, float(z) * 1.7)) < 0.070:
		return true
	if depth >= 24:
		var chamber: FastNoiseLite = _noise["chamber"]
		if chamber.get_noise_3d(float(x), float(y), float(z)) > 0.60:
			return true
	var bits := int(cache["flags"][_cache_index(cache, x, z)])
	if depth >= 12 and (bits & 1) != 0:
		return true
	if depth >= 26 and depth <= 78 and (bits & 2) != 0:
		return true
	if depth >= 118 and (bits & 4) != 0:
		return true
	return false


static func liquid_at_cached(cache: Dictionary, x: int, y: int, z: int, surface_y: int) -> int:
	var depth := surface_y - y
	if depth < 4:
		return 0
	if depth >= 74:
		var lava: FastNoiseLite = _noise["lava"]
		var lava_value := lava.get_noise_3d(float(x), float(y), float(z))
		if depth >= 86 and lava_value > -0.10:
			return 2
		if lava_value > 0.30:
			return 2
	var table: float = float(cache["aquifer"][_cache_index(cache, x, z)])
	if float(depth) > table and depth < 80:
		var water: FastNoiseLite = _noise["water"]
		if water.get_noise_3d(float(x), float(y), float(z)) > -0.45:
			return 1
	return 0


static func positive_mod(value: int, modulus: int) -> int:
	var result := value % modulus
	return result + modulus if result < 0 else result
