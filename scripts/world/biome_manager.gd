extends RefCounted
class_name BiomeManager

# Macro biome field for the streaming world. Everything here is a pure function
# of (world_seed, x, z): no global maps and no world bounds, so any chunk can be
# generated independently in a worker and reproduced byte-for-byte after unload.
#
# Heights are the weighted sum of four continuous biome height functions, and
# surface blocks are chosen by a deterministic dither of the same weights. That
# is what makes "Forest gradually becoming Snow" read as a slope with
# a patchy treeline rather than a seam.

const ASHEN := 0
const HUSH := 1
const FROST := 2
const MIRE := 3
const DESERT := 4
const MUSHROOM := 5
# Core Terraria identities added in the direction-correction pass. FROST is
# Snow, MIRE is Forest, DESERT is Desert and MUSHROOM is Mushroom; ASHEN and
# HUSH remain regional variants of Forest and Jungle.
const JUNGLE := 6
const CORRUPTION := 7
const CRIMSON := 8
const HALLOW := 9
const OCEAN := 10
const BIOME_COUNT := 11
# Ocean regions form at the far eastern/western edges of the streaming world.
# There is no hard wall: past OCEAN_EDGE_FULL the ocean simply continues.
const OCEAN_EDGE_START := 3200.0
const OCEAN_EDGE_FULL := 3900.0

# The surface sits SURFACE_LIFT blocks above the original 64-tall slab, which
# turns the previously thin underground into ~99 blocks of genuine descent while
# keeping every height function local and deterministic.
const WORLD_Y := 256
const SURFACE_LIFT := 168
const WATER_LEVEL := 189

const SPAWN_X := 64
const SPAWN_Z := 64
const SPAWN_CLEAR_RADIUS := 4.0
const SPAWN_BLEND_RADIUS := 8.0
# The starting region is the green, lowland biome. It is presented to the player
# as "Overworld" even though its internal id remains MIRE (3).
const SPAWN_BIOME := MIRE
# The starting forest is a region, not a cap: until SPAWN_BIOME_RADIUS the
# weights are pure Forest, then they cross-fade to the climate field by
# SPAWN_BIOME_BLEND. Anything shorter puts Jungle or Mushroom a few seconds'
# walk from the player's feet.
const SPAWN_BIOME_RADIUS := 300.0
const SPAWN_BIOME_BLEND := 700.0
# The evil biome is a landmark you travel to, not the next-door neighbour. In
# Terraria it sits a good third of a world away from spawn; here the spread is
# radial, so the evil weights fade out inside EVIL_CLEAR_RADIUS and only reach
# full strength past EVIL_FULL_RADIUS. The mass they give up becomes Forest, so
# the ring around spawn reads as continuous woods instead of an abrupt edge.
const EVIL_CLEAR_RADIUS := 900.0
const EVIL_FULL_RADIUS := 1350.0

const SURFACE_BASE_HEIGHT := 23.0
const MESA_HEIGHT := 34.0
const RIVER_CENTER_X := 104.0
const RIVER_WIDTH := 7.0
const RIVER_WALL := 9.0
const RIVER_BED_HEIGHT := 14.0
const RAVINE_CENTER_X := 25.0
const RAVINE_WIDTH := 5.0
const RAVINE_WALL := 8.0
const RAVINE_BED_HEIGHT := 12.5
const RAVINE_MIN_Z := 48
const LANDMARK_SPIRES := [Vector2i(78, 110), Vector2i(44, 120), Vector2i(38, 58)]

# Anchor points in (heat, wet) noise space. They are spread far enough apart
# that a biome owns several hundred blocks before the next one dominates.
const ANCHORS := [
	Vector2(0.24, 0.28),
	Vector2(0.30, 0.78),
	Vector2(0.80, 0.26),
	Vector2(0.72, 0.76),
	Vector2(0.92, 0.10),
	Vector2(0.55, 0.96),
	Vector2(0.12, 0.62),
	Vector2(0.06, 0.12),
	Vector2(0.48, 0.10),
	Vector2(0.62, 0.48),
	Vector2(0.03, 0.94),
]

static var _seed := -1
static var _noise: Dictionary = {}
static var _spawn_height := -1
# Evil biomes are mutually exclusive by default; the world seed picks which one.
# Hallow is locked until world progression enables it.
static var _evil_mode := "corruption"
static var _hallow_enabled := false


static func configure(seed_value: int) -> void:
	if seed_value == _seed and not _noise.is_empty():
		return
	_seed = seed_value
	_spawn_height = -1
	# Deterministic per-world evil identity; overridable via set_evil_mode().
	_evil_mode = "crimson" if seed_value % 2 == 0 else "corruption"
	_hallow_enabled = false
	_noise = {
		"warp_x": _make(seed_value ^ 0x11A3, 2, 0.0032),
		"warp_z": _make(seed_value ^ 0x77C1, 2, 0.0032),
		"heat": _make(seed_value ^ 0x3B41, 3, 0.0016),
		"wet": _make(seed_value ^ 0x6D19, 3, 0.0018),
		"ashen_broad": _make(seed_value ^ 0x1A2B3C, 3, 0.0045),
		"ashen_hill": _make(seed_value ^ 0x51A7, 3, 0.012),
		"detail": _make(seed_value ^ 0x7C31, 2, 0.045),
		"ashen_shelf": _make(seed_value ^ 0x71C3, 3, 0.052, FastNoiseLite.FRACTAL_RIDGED),
		"ashen_ridge": _make(seed_value ^ 0x6D2B, 4, 0.013, FastNoiseLite.FRACTAL_RIDGED),
		"ashen_mesa": _make(seed_value ^ 0x39AF, 2, 0.017),
		"river": _make(seed_value ^ 0x2E77, 2, 0.06),
		"ravine": _make(seed_value ^ 0x5B2D, 2, 0.075),
		"hush_broad": _make(seed_value ^ 0x4B17, 3, 0.006),
		"hush_detail": _make(seed_value ^ 0x135F, 2, 0.03),
		"frost_broad": _make(seed_value ^ 0x2F81, 3, 0.0055),
		"frost_ridge": _make(seed_value ^ 0x58C3, 4, 0.019, FastNoiseLite.FRACTAL_RIDGED),
		"frost_detail": _make(seed_value ^ 0x44AB, 2, 0.06),
		"mire_broad": _make(seed_value ^ 0x6A47, 3, 0.008),
		"mire_detail": _make(seed_value ^ 0x2C95, 2, 0.05),
		"desert_broad": _make(seed_value ^ 0x5D11, 3, 0.006),
		"desert_dune": _make(seed_value ^ 0x3E77, 3, 0.020, FastNoiseLite.FRACTAL_RIDGED),
		"mushroom_broad": _make(seed_value ^ 0x2B4D, 3, 0.007),
		"mushroom_detail": _make(seed_value ^ 0x6F83, 2, 0.03),
		"rock": _make(seed_value ^ 0x33E1, 3, 0.021),
		"cave": _make(seed_value ^ 0x2C79, 2, 0.075),
		"jungle_broad": _make(seed_value ^ 0x1F4B, 3, 0.0075),
		"jungle_detail": _make(seed_value ^ 0x63A9, 3, 0.035),
		"evil_broad": _make(seed_value ^ 0x0E77, 3, 0.0065),
		"evil_ridge": _make(seed_value ^ 0x5C3B, 3, 0.022, FastNoiseLite.FRACTAL_RIDGED),
		"hallow_broad": _make(seed_value ^ 0x47D1, 3, 0.006),
		"ocean_broad": _make(seed_value ^ 0x2A6F, 3, 0.009),
		"ocean_detail": _make(seed_value ^ 0x71E5, 2, 0.04),
	}


static func _ensure() -> void:
	if _seed < 0 or _noise.is_empty():
		configure(139732)


static func _make(noise_seed: int, octaves: int, frequency: float, fractal: int = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	return noise


# --- Biome weights ----------------------------------------------------------

static func get_weights(x: int, z: int) -> PackedFloat32Array:
	_ensure()
	var warp_x: FastNoiseLite = _noise["warp_x"]
	var warp_z: FastNoiseLite = _noise["warp_z"]
	var heat_noise: FastNoiseLite = _noise["heat"]
	var wet_noise: FastNoiseLite = _noise["wet"]
	var warp_offset_x := warp_x.get_noise_2d(float(x), float(z)) * 85.0
	var warp_offset_z := warp_z.get_noise_2d(float(x), float(z)) * 85.0
	var heat := clampf(heat_noise.get_noise_2d(float(x) + warp_offset_x, float(z) + warp_offset_z) * 0.5 + 0.5, 0.0, 1.0)
	var wet := clampf(wet_noise.get_noise_2d(float(x) + warp_offset_x, float(z) + warp_offset_z) * 0.5 + 0.5, 0.0, 1.0)
	var point := Vector2(heat, wet)
	var weights := PackedFloat32Array()
	weights.resize(BIOME_COUNT)
	var total := 0.0
	for index in range(BIOME_COUNT):
		var anchor: Vector2 = ANCHORS[index]
		var distance := point.distance_squared_to(anchor)
		var value := exp(-distance / 0.028)
		weights[index] = value
		total += value
	if total > 0.000001:
		for index in range(BIOME_COUNT):
			weights[index] = weights[index] / total
	else:
		weights.fill(0.25)
	_apply_biome_policy(weights)
	var spawn_distance := Vector2(float(x - SPAWN_X), float(z - SPAWN_Z)).length()
	# Spawn safety: keep the evil biome out of the starting region.
	if spawn_distance < EVIL_FULL_RADIUS:
		var evil_ramp := clampf((spawn_distance - EVIL_CLEAR_RADIUS) / (EVIL_FULL_RADIUS - EVIL_CLEAR_RADIUS), 0.0, 1.0)
		evil_ramp = evil_ramp * evil_ramp * (3.0 - 2.0 * evil_ramp)
		var trimmed := weights[CORRUPTION] * (1.0 - evil_ramp) + weights[CRIMSON] * (1.0 - evil_ramp)
		weights[CORRUPTION] *= evil_ramp
		weights[CRIMSON] *= evil_ramp
		weights[MIRE] += trimmed
	# World-edge oceans: blend Ocean in toward the east/west limits so the map
	# reads like a Terraria world instead of endless inland climate.
	var edge := absf(float(x))
	if edge > OCEAN_EDGE_START:
		var ramp := clampf((edge - OCEAN_EDGE_START) / (OCEAN_EDGE_FULL - OCEAN_EDGE_START), 0.0, 1.0)
		for index in range(BIOME_COUNT):
			weights[index] *= 1.0 - ramp
		weights[OCEAN] += ramp
	# Spawn bias: the starting area is always the green Forest (MIRE id).
	if spawn_distance < SPAWN_BIOME_BLEND:
		var blend := clampf((spawn_distance - SPAWN_BIOME_RADIUS) / (SPAWN_BIOME_BLEND - SPAWN_BIOME_RADIUS), 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		for index in range(BIOME_COUNT):
			var home := 1.0 if index == SPAWN_BIOME else 0.0
			weights[index] = lerpf(home, weights[index], blend)
	return weights


static func dominant_biome(x: int, z: int) -> int:
	var weights := get_weights(x, z)
	var best := 0
	var best_weight := weights[0]
	for index in range(1, BIOME_COUNT):
		if weights[index] > best_weight:
			best_weight = weights[index]
			best = index
	return best


# Dithered surface pick: inside a border band a column can fall to either side
# of the cumulative weight, which feathers the transition in plan view.
static func surface_biome(x: int, z: int) -> int:
	var weights := get_weights(x, z)
	var roll := _hash01(x, z)
	var accumulated := 0.0
	for index in range(BIOME_COUNT):
		accumulated += weights[index]
		if roll <= accumulated:
			return index
	return MIRE


# Finds a representative column of a requested biome near an origin. Searches
# expanding rings so a teleport stays close to the player when possible; scores
# by the biome's own weight so the result is a centre, not a border sliver.
static func find_biome_center(biome: int, seed_value: int, x: int, z: int) -> Vector2i:
	configure(seed_value)
	var best := Vector2i(x, z)
	var best_score := -1.0
	for radius in [0, 12, 24, 48, 96, 160, 240, 360, 720, 1200, 1800]:
		var samples := maxi(8, radius)
		for index in range(samples):
			var angle := TAU * float(index) / float(samples)
			var cx := x + roundi(cos(angle) * float(radius))
			var cz := z + roundi(sin(angle) * float(radius))
			if dominant_biome(cx, cz) != biome:
				continue
			var score := get_weights(cx, cz)[biome] - float(radius) * 0.0004
			if score > best_score:
				best_score = score
				best = Vector2i(cx, cz)
		if best_score >= 0.0:
			break
	return best


static func sky_mode(x: int, z: int) -> int:
	var biome := dominant_biome(x, z)
	if biome == HUSH:
		return 2
	if biome == MIRE or biome == FROST or biome == MUSHROOM:
		return 3
	return 1


static func is_mire_water(x: int, z: int) -> bool:
	var weights := get_weights(x, z)
	# Forest lakes and the Ocean shore both stand below sea level.
	if weights[MIRE] <= 0.5 and weights[OCEAN] <= 0.5:
		return false
	return _height_with_weights(x, z, weights) < WATER_LEVEL


# Removes disallowed evil/Hallow identities and renormalises. Called on every
# weight evaluation, so the policy applies to workers and runtime queries alike.
static func _apply_biome_policy(weights: PackedFloat32Array) -> void:
	if _evil_mode == "corruption":
		weights[CRIMSON] = 0.0
	elif _evil_mode == "crimson":
		weights[CORRUPTION] = 0.0
	if not _hallow_enabled:
		weights[HALLOW] = 0.0
	var total := 0.0
	for value in weights:
		total += value
	if total <= 0.000001:
		return
	for index in range(weights.size()):
		weights[index] = weights[index] / total


# World-generation option: "corruption", "crimson" or "both".
static func set_evil_mode(mode: String) -> void:
	if mode == "corruption" or mode == "crimson" or mode == "both":
		_evil_mode = mode


static func evil_mode() -> String:
	return _evil_mode


# Progression gate for The Hallow. Enabling it affects newly generated chunks.
static func set_hallow_enabled(enabled: bool) -> void:
	_hallow_enabled = enabled


static func hallow_enabled() -> bool:
	return _hallow_enabled


static func biome_name(biome: int) -> String:
	match biome:
		HUSH:
			return "Jungle"
		FROST:
			return "Snow"
		MIRE:
			return "Forest"
		DESERT:
			return "Desert"
		MUSHROOM:
			return "Mushroom"
		JUNGLE:
			return "Jungle"
		CORRUPTION:
			return "The Corruption"
		CRIMSON:
			return "The Crimson"
		HALLOW:
			return "The Hallow"
		OCEAN:
			return "Ocean"
		_:
			return "Forest"


# --- Heights ----------------------------------------------------------------

static func get_height(x: int, z: int) -> int:
	_ensure()
	return _height_with_weights(x, z, get_weights(x, z))


# Height and sky mode share one biome-weight evaluation. The mesher needs both
# for every column of its 18x18 halo, so this halves the noise work there.
static func column_info(x: int, z: int) -> Vector2i:
	_ensure()
	var weights := get_weights(x, z)
	var best := 0
	for index in range(1, BIOME_COUNT):
		if weights[index] > weights[best]:
			best = index
	return Vector2i(_height_with_weights(x, z, weights), _sky_for(best))


static func _sky_for(biome: int) -> int:
	if biome == HUSH:
		return 2
	if biome == MIRE or biome == FROST or biome == MUSHROOM:
		return 3
	return 1


static func _height_with_weights(x: int, z: int, weights: PackedFloat32Array) -> int:
	var height := float(SURFACE_LIFT)
	for index in range(BIOME_COUNT):
		if weights[index] > 0.0005:
			height += weights[index] * _biome_height(index, x, z)
	height = float(clampi(roundi(height), SURFACE_LIFT + 4, WORLD_Y - 6))
	var spawn_distance := Vector2(float(x - SPAWN_X), float(z - SPAWN_Z)).length()
	if spawn_distance < SPAWN_BLEND_RADIUS:
		var spawn_height := float(_get_spawn_height())
		if spawn_distance <= SPAWN_CLEAR_RADIUS:
			return int(spawn_height)
		var blend := (spawn_distance - SPAWN_CLEAR_RADIUS) / (SPAWN_BLEND_RADIUS - SPAWN_CLEAR_RADIUS)
		return roundi(lerpf(spawn_height, height, blend))
	return roundi(height)


static func _get_spawn_height() -> int:
	if _spawn_height < 0:
		var natural := roundi(_mire_height(SPAWN_X, SPAWN_Z)) + SURFACE_LIFT
		# Keep the spawn above the standing water line.
		_spawn_height = maxi(WATER_LEVEL + 2, clampi(natural, SURFACE_LIFT + 12, SURFACE_LIFT + 52))
	return _spawn_height


static func _biome_height(biome: int, x: int, z: int) -> float:
	match biome:
		HUSH:
			return _hush_height(x, z)
		FROST:
			return _frost_height(x, z)
		MIRE:
			return _mire_height(x, z)
		DESERT:
			return _desert_height(x, z)
		MUSHROOM:
			return _mushroom_height(x, z)
		JUNGLE:
			return _jungle_height(x, z)
		CORRUPTION:
			return _corruption_height(x, z)
		CRIMSON:
			return _crimson_height(x, z)
		HALLOW:
			return _hallow_height(x, z)
		OCEAN:
			return _ocean_height(x, z)
		_:
			return _ashen_height(x, z)


static func _ashen_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["ashen_broad"]
	var hill: FastNoiseLite = _noise["ashen_hill"]
	var detail: FastNoiseLite = _noise["detail"]
	var shelf_noise: FastNoiseLite = _noise["ashen_shelf"]
	var ridge_noise: FastNoiseLite = _noise["ashen_ridge"]
	var mesa_noise: FastNoiseLite = _noise["ashen_mesa"]
	var river_noise: FastNoiseLite = _noise["river"]
	var ravine_noise: FastNoiseLite = _noise["ravine"]
	var height_value := SURFACE_BASE_HEIGHT
	height_value += broad.get_noise_2d(float(x), float(z)) * 8.4
	height_value += hill.get_noise_2d(float(x), float(z)) * 3.4
	height_value += detail.get_noise_2d(float(x), float(z)) * 0.4

	var shelf := clampf(shelf_noise.get_noise_2d(float(x), float(z)) * 0.5 + 0.5, 0.0, 1.0)
	height_value += smoothstep(0.42, 0.78, shelf) * 3.0

	var ridge := clampf(ridge_noise.get_noise_2d(float(x), float(z)) * 0.5 + 0.5, 0.0, 1.0)
	var ridge_mask := smoothstep(0.58, 0.92, ridge)
	height_value += ridge_mask * ridge_mask * 13.0

	var mesa := mesa_noise.get_noise_2d(float(x) * 0.62, float(z) * 0.62)
	var mesa_mask := smoothstep(0.14, 0.32, mesa)
	var plateau := MESA_HEIGHT + detail.get_noise_2d(float(x), float(z)) * 2.0
	height_value = lerpf(height_value, maxf(height_value, plateau), mesa_mask)

	for spire: Vector2i in LANDMARK_SPIRES:
		var spire_distance := Vector2(float(x - spire.x), float(z - spire.y)).length()
		if spire_distance < 10.0:
			height_value += smoothstep(10.0, 2.0, spire_distance) * 3.8

	var river_center := RIVER_CENTER_X + sin(float(z) * 0.07) * 8.0 + sin(float(z) * 0.023 + 2.1) * 4.0
	var river_distance := absf(float(x) - river_center)
	if river_distance < RIVER_WIDTH + RIVER_WALL:
		var canyon_bed := RIVER_BED_HEIGHT - 0.9 + river_noise.get_noise_2d(float(x), float(z)) * 0.9
		var braid := smoothstep(3.0, 0.5, river_distance) * 1.1
		var wall := smoothstep(RIVER_WIDTH, RIVER_WIDTH + RIVER_WALL, river_distance)
		height_value = lerpf(canyon_bed - braid, height_value, wall)

	if z > RAVINE_MIN_Z:
		var ravine_center := RAVINE_CENTER_X + sin(float(z) * 0.075) * 7.0 + sin(float(z) * 0.031 + 1.3) * 4.0
		var ravine_distance := absf(float(x) - ravine_center)
		if ravine_distance < RAVINE_WIDTH + RAVINE_WALL:
			var ravine_bed := RAVINE_BED_HEIGHT + ravine_noise.get_noise_2d(float(x), float(z)) * 1.2
			var ravine_wall := smoothstep(RAVINE_WIDTH, RAVINE_WIDTH + RAVINE_WALL, ravine_distance)
			var fade := smoothstep(float(RAVINE_MIN_Z), float(RAVINE_MIN_Z) + 12.0, float(z))
			height_value = lerpf(ravine_bed, height_value, lerpf(1.0, ravine_wall, fade))

	var tower_distance := Vector2(float(x) - 70.0, float(z) - 22.0).length()
	if tower_distance < 13.0:
		var tower_mask := smoothstep(13.0, 8.0, tower_distance)
		var crown := 50.0 + detail.get_noise_2d(float(x) * 0.8, float(z) * 0.8) * 1.2
		height_value = lerpf(height_value, crown, tower_mask)
	return height_value


static func _hush_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["hush_broad"]
	var detail: FastNoiseLite = _noise["hush_detail"]
	return 24.0 + broad.get_noise_2d(float(x), float(z)) * 4.2 + detail.get_noise_2d(float(x), float(z)) * 1.4


static func _frost_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["frost_broad"]
	var ridge: FastNoiseLite = _noise["frost_ridge"]
	var detail: FastNoiseLite = _noise["frost_detail"]
	var height_value := 26.0 + broad.get_noise_2d(float(x), float(z)) * 6.0
	height_value += detail.get_noise_2d(float(x), float(z)) * 1.2
	var ridged := clampf(ridge.get_noise_2d(float(x), float(z)) * 0.5 + 0.5, 0.0, 1.0)
	var mask := smoothstep(0.38, 0.86, ridged)
	height_value += mask * mask * 13.0
	return height_value


static func _mire_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["mire_broad"]
	var detail: FastNoiseLite = _noise["mire_detail"]
	var height_value := 22.0 + broad.get_noise_2d(float(x), float(z)) * 2.4
	height_value += detail.get_noise_2d(float(x), float(z)) * 0.9
	return height_value


# Desert: low, hot dunes broken by long ridged sand spines. It reads as a
# different landform, not just a different surface colour.
static func _desert_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["desert_broad"]
	var dune: FastNoiseLite = _noise["desert_dune"]
	var detail: FastNoiseLite = _noise["detail"]
	var height_value := 24.0 + broad.get_noise_2d(float(x), float(z)) * 4.0
	var ridge := clampf(dune.get_noise_2d(float(x) * 1.3, float(z) * 1.3) * 0.5 + 0.5, 0.0, 1.0)
	height_value += smoothstep(0.55, 0.90, ridge) * 7.0
	height_value += detail.get_noise_2d(float(x), float(z)) * 0.5
	return height_value


# Mushroom: damp rolling ground under a permanent spore canopy.
static func _mushroom_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["mushroom_broad"]
	var detail: FastNoiseLite = _noise["mushroom_detail"]
	return 23.0 + broad.get_noise_2d(float(x), float(z)) * 3.0 + detail.get_noise_2d(float(x), float(z)) * 1.0


static func _jungle_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["jungle_broad"]
	var detail: FastNoiseLite = _noise["jungle_detail"]
	return 24.5 + broad.get_noise_2d(float(x), float(z)) * 5.2 + detail.get_noise_2d(float(x), float(z)) * 1.8


# Corruption chasms: broad rolling ground carved by ridged negative spines.
static func _corruption_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["evil_broad"]
	var ridge: FastNoiseLite = _noise["evil_ridge"]
	var detail: FastNoiseLite = _noise["detail"]
	var height_value := 23.5 + broad.get_noise_2d(float(x), float(z)) * 4.6
	var ridged := clampf(ridge.get_noise_2d(float(x), float(z)) * 0.5 + 0.5, 0.0, 1.0) * -1.0 + 1.0
	height_value -= smoothstep(0.55, 0.95, ridged) * 2.6
	height_value += detail.get_noise_2d(float(x), float(z)) * 0.5
	return height_value


static func _crimson_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["evil_broad"]
	var detail: FastNoiseLite = _noise["detail"]
	return 25.0 + broad.get_noise_2d(float(x) + 311.0, float(z)) * 4.4 + detail.get_noise_2d(float(x), float(z)) * 0.6


static func _hallow_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["hallow_broad"]
	var detail: FastNoiseLite = _noise["detail"]
	return 26.0 + broad.get_noise_2d(float(x), float(z)) * 3.4 + detail.get_noise_2d(float(x), float(z)) * 0.8


# Ocean floor sits below sea level; the generator fills the water column above it.
static func _ocean_height(x: int, z: int) -> float:
	var broad: FastNoiseLite = _noise["ocean_broad"]
	var detail: FastNoiseLite = _noise["ocean_detail"]
	return 13.8 + broad.get_noise_2d(float(x), float(z)) * 1.6 + detail.get_noise_2d(float(x), float(z)) * 0.35


# --- Raw masks --------------------------------------------------------------

static func is_canyon_floor(x: int, z: int) -> bool:
	var river_center := RIVER_CENTER_X + sin(float(z) * 0.07) * 8.0 + sin(float(z) * 0.023 + 2.1) * 4.0
	if absf(float(x) - river_center) <= RIVER_WIDTH + 1.0:
		return true
	if z > RAVINE_MIN_Z:
		var ravine_center := RAVINE_CENTER_X + sin(float(z) * 0.075) * 7.0 + sin(float(z) * 0.031 + 1.3) * 4.0
		if absf(float(x) - ravine_center) <= RAVINE_WIDTH + 1.0:
			return true
	return false


static func rock_noise(x: int, z: int) -> float:
	_ensure()
	var noise: FastNoiseLite = _noise["rock"]
	return noise.get_noise_2d(float(x), float(z))


static func cave_noise(x: int, y: int, z: int) -> float:
	_ensure()
	var noise: FastNoiseLite = _noise["cave"]
	return noise.get_noise_3d(float(x), float(y), float(z))


static func _hash01(x: int, z: int) -> float:
	var value := _seed * 1103515245 + x * 73856093 + z * 19349663 + 0x5CA7
	value = (value ^ (value >> 13)) * 1274126177
	return float(value & 0xFFFF) / 65535.0
