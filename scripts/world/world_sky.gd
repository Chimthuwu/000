extends RefCounted
class_name WorldSky

# Floating sky islands. Real generation support for the reserved headroom above
# the surface: one island per deterministic grid cell, floating between 24 and
# 52 blocks above the local surface. Every chunk recomputes the same sites from
# world coordinates and writes only its own cells, so islands straddling a chunk
# border are stamped identically by both sides.
#
# The architecture intentionally mirrors WorldStructures: Agent 4 can later put
# suspended ruins or sky resources on the returned site list without touching
# streaming, meshing or persistence. Tops use the same ashen-soil surface as
# forest terrain; the underside is dirt, stone and tapered deepstone.

const CELL := 80
const CHANCE := 0.42
const REACH := 24
const MIN_RISE := 24
const MAX_RISE := 52

static func stamp_chunk(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var soil_id := int(block_ids.get(&"dirt", stone_id))
	var grass_id := int(block_ids.get(&"ashen_soil", block_ids.get(&"jungle_grass", soil_id)))
	var deepstone_id := int(block_ids.get(&"deepstone", stone_id))
	var vine_id := int(block_ids.get(&"jungle_leaves", block_ids.get(&"dead_wood", -1)))
	var crystal_id := int(block_ids.get(&"lumen_crystal", -1))
	var min_gx := floori(float(origin.x - REACH) / float(CELL))
	var max_gx := floori(float(origin.x + 15 + REACH) / float(CELL))
	var min_gz := floori(float(origin.z - REACH) / float(CELL))
	var max_gz := floori(float(origin.z + 15 + REACH) / float(CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = _seed(world_seed, grid_x, grid_z, 0x5C1E)
			if rng.randf() > CHANCE:
				continue
			var cx := grid_x * CELL + rng.randi_range(14, CELL - 15)
			var cz := grid_z * CELL + rng.randi_range(14, CELL - 15)
			var surface := BiomeManager.get_height(cx, cz)
			var base_y := surface + MIN_RISE + rng.randi_range(0, MAX_RISE - MIN_RISE)
			var radius_x := rng.randi_range(6, 11)
			var radius_y := rng.randi_range(2, 4)
			var radius_z := rng.randi_range(6, 11)
			if base_y + radius_y + 8 >= WorldLayers.WORLD_Y:
				continue
			# Cheap reject: this chunk cannot contain any of the island.
			var island_depth := int(round(float(radius_y) * 1.9))
			if origin.y + 15 < base_y - island_depth or origin.y > base_y + radius_y + 8:
				continue
			_stamp_island(output, origin, rng, cx, base_y, cz, radius_x, radius_y, radius_z, stone_id, soil_id, grass_id, deepstone_id, crystal_id, vine_id)


static func _stamp_island(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, cx: int, cy: int, cz: int, rx: int, ry: int, rz: int, stone_id: int, soil_id: int, grass_id: int, deepstone_id: int, crystal_id: int, vine_id: int) -> void:
	var rx2 := float(rx * rx)
	var rz2 := float(rz * rz)
	# Terraria-style floating terrain: a rounded grassy cap over a tapered,
	# layered dirt/stone underside. The old symmetrical ellipsoid read as a
	# flat disc from below.
	for dz in range(-rz, rz + 1):
		for dx in range(-rx, rx + 1):
			var nx := float(dx * dx) / rx2
			var nz := float(dz * dz) / rz2
			var radial := nx + nz
			if radial > 1.0:
				continue
			var top_offset := int(round(float(ry) * sqrt(maxf(0.0, 1.0 - radial))))
			var bottom_offset := int(round(float(ry) * 1.9 * pow(maxf(0.0, 1.0 - radial), 0.7)))
			for dy in range(-bottom_offset, top_offset + 1):
				var cell := Vector3i(cx + dx, cy + dy, cz + dz)
				var from_top := top_offset - dy
				var block := stone_id
				if from_top <= 1:
					block = grass_id
				elif from_top <= 3:
					block = soil_id if rng.randf() < 0.55 else stone_id
				elif dy <= -bottom_offset + 2:
					block = deepstone_id
				_put(output, origin, cell, block)
	# A few tapered stone stalactites break up the underside silhouette.
	for stalactite in range(3):
		var angle := TAU * float(stalactite) / 3.0 + rng.randf_range(-0.4, 0.4)
		var sx := cx + roundi(cos(angle) * float(rx) * 0.55)
		var sz := cz + roundi(sin(angle) * float(rz) * 0.55)
		var start_y := cy - int(round(float(ry) * 1.1))
		for step in range(rng.randi_range(1, 4)):
			_put(output, origin, Vector3i(sx, start_y - step, sz), deepstone_id)
	# Sparse hanging vines, not thick root columns; two short strands keep the
	# silhouette a floating island rather than a mushroom.
	if vine_id >= 0:
		for strand in range(2):
			var vx := cx + rng.randi_range(-rx + 2, rx - 2)
			var vz := cz + rng.randi_range(-rz + 2, rz - 2)
			var length := rng.randi_range(1, 3)
			var start_y := cy - int(round(float(ry) * 1.9))
			for step in range(length):
				_put(output, origin, Vector3i(vx, start_y - step, vz), vine_id)
	# A crystal beacon marks some islands as worth reaching.
	if crystal_id >= 0 and rng.randf() < 0.45:
		var spire_x := cx + rng.randi_range(-2, 2)
		var spire_z := cz + rng.randi_range(-2, 2)
		for step in range(rng.randi_range(2, 4)):
			_put(output, origin, Vector3i(spire_x, cy + ry + step, spire_z), crystal_id)


static func _put(output: PackedByteArray, origin: Vector3i, cell: Vector3i, block_id: int) -> void:
	if block_id < 0:
		return
	var lx := cell.x - origin.x
	var ly := cell.y - origin.y
	var lz := cell.z - origin.z
	if lx < 0 or lx >= 16 or ly < 0 or ly >= 16 or lz < 0 or lz >= 16:
		return
	output[lx + ly * 16 + lz * 256] = block_id


static func _seed(world_seed: int, x: int, z: int, salt: int) -> int:
	var value := world_seed * 1103515245 + x * 73856093 + z * 19349663 + salt
	value = (value ^ (value >> 13)) * 1274126177
	return value & 0x7fffffff
