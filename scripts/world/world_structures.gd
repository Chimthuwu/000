extends RefCounted
class_name WorldStructures

# Reusable, chunk-safe structure placement infrastructure.
#
# Structures are placed on a deterministic world grid: one site per 96 x 96 cell,
# jittered inside the cell. Because the grid cell is larger than any template,
# sites can never overlap, and every chunk recomputes the same sites from world
# coordinates, so a structure straddling a border is stamped identically by both
# chunks. Templates only write cells inside the chunk being generated.
#
# The templates here are world-engine examples (mine entrance, ruin, chamber,
# treasure vault, crystal shrine, watchtower). Agent 4 can add templates to
# TEMPLATES without touching streaming, persistence or chunk code.

const CELL := 96
const REACH := 26
const SPAWN_CLEAR := 26.0
const MIN_DEPTH := 12
const MAX_DEPTH := 74

enum Kind { MINE_ENTRANCE, SMALL_RUIN, ANCIENT_CHAMBER, TREASURE_VAULT, CRYSTAL_SHRINE, WATCHTOWER, BIOME_LANDMARK }


static func stamp_chunk(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var min_gx := floori(float(origin.x - REACH) / float(CELL))
	var max_gx := floori(float(origin.x + 15 + REACH) / float(CELL))
	var min_gz := floori(float(origin.z - REACH) / float(CELL))
	var max_gz := floori(float(origin.z + 15 + REACH) / float(CELL))
	for grid_z in range(min_gz, max_gz + 1):
		for grid_x in range(min_gx, max_gx + 1):
			var site := _site(world_seed, grid_x, grid_z)
			if site.is_empty():
				continue
			_stamp_site(output, origin, site, block_ids, air_id, stone_id)


static func _site(world_seed: int, grid_x: int, grid_z: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(world_seed, grid_x, grid_z, 0x571C)
	var cx := grid_x * CELL + rng.randi_range(10, CELL - 11)
	var cz := grid_z * CELL + rng.randi_range(10, CELL - 11)
	if Vector2(float(cx - BiomeManager.SPAWN_X), float(cz - BiomeManager.SPAWN_Z)).length() < SPAWN_CLEAR:
		return {}
	var surface := BiomeManager.get_height(cx, cz)
	var biome := BiomeManager.dominant_biome(cx, cz)
	# Biome landmarks take priority in the core identities so each region has
	# recognisable architecture, not just different ground colours.
	if biome == BiomeManager.JUNGLE or biome == BiomeManager.CORRUPTION \
			or biome == BiomeManager.CRIMSON or biome == BiomeManager.HALLOW \
			or biome == BiomeManager.OCEAN:
		if rng.randf() < 0.6:
			return {"kind": Kind.BIOME_LANDMARK, "x": cx, "z": cz, "y": surface, "surface": surface, "seed": rng.randi(), "biome": biome}
	var roll := rng.randf()
	var kind := int(roll * float(Kind.size()))
	if kind >= Kind.size():
		kind = Kind.SMALL_RUIN
	if kind == Kind.MINE_ENTRANCE:
		# Only cut entrances into ground flat enough to walk into.
		if not _flat(cx, cz):
			kind = Kind.SMALL_RUIN
		else:
			return {"kind": kind, "x": cx, "z": cz, "y": surface, "surface": surface, "seed": rng.randi()}
	var depth := rng.randi_range(MIN_DEPTH, MAX_DEPTH)
	# Keep deep sites above the absolute floor.
	depth = mini(depth, maxi(8, surface - 6))
	var y := surface - depth
	return {"kind": kind, "x": cx, "z": cz, "y": y, "surface": surface, "seed": rng.randi()}


static func _flat(x: int, z: int) -> bool:
	var here := BiomeManager.get_height(x, z)
	return absi(BiomeManager.get_height(x - 3, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x + 3, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z - 3) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z + 3) - here) <= 1


static func _stamp_site(output: PackedByteArray, origin: Vector3i, site: Dictionary, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site["seed"])
	var x := int(site["x"])
	var y := int(site["y"])
	var z := int(site["z"])
	match int(site["kind"]):
		Kind.MINE_ENTRANCE:
			_stamp_mine_entrance(output, origin, rng, x, y, z, block_ids, air_id, stone_id)
		Kind.SMALL_RUIN:
			_stamp_ruin(output, origin, rng, x, y, z, block_ids, air_id, stone_id)
		Kind.ANCIENT_CHAMBER:
			_stamp_ancient_chamber(output, origin, rng, x, y, z, block_ids, air_id, stone_id)
		Kind.TREASURE_VAULT:
			_stamp_treasure(output, origin, rng, x, y, z, block_ids, air_id, stone_id)
		Kind.CRYSTAL_SHRINE:
			_stamp_crystal_shrine(output, origin, rng, x, y, z, block_ids, air_id, stone_id)
		Kind.WATCHTOWER:
			_stamp_watchtower(output, origin, rng, x, y, z, block_ids, air_id, stone_id)
		Kind.BIOME_LANDMARK:
			_stamp_biome_landmark(output, origin, rng, x, y, z, block_ids, air_id, stone_id, int(site.get("biome", -1)))


# --- Templates --------------------------------------------------------------

# A 3 x 3 tunnel driven into the hillside from the surface, propped with wood,
# ending in a small torch-lit chamber that links into whatever cave it meets.
static func _stamp_mine_entrance(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, x: int, surface: int, z: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var wood_id := int(block_ids.get(&"dead_wood", stone_id))
	var torch_id := int(block_ids.get(&"torch", -1))
	var direction := Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
	if direction == Vector2i.ZERO:
		direction = Vector2i(1, 0)
	var length := rng.randi_range(14, 22)
	for step in range(length):
		var step_x := x + direction.x * step
		var step_z := z + direction.y * step
		var ground := BiomeManager.get_height(step_x, step_z)
		var floor_y := mini(surface, ground) - 1
		for dy in range(0, 3):
			for dw in range(-1, 2):
				var cell := Vector3i(step_x + (1 if direction.y != 0 else 0) * 0, floor_y + dy, step_z)
				if direction.y != 0:
					cell.x += dw
				else:
					cell.z += dw
				_put(output, origin, cell, air_id)
		if step % 5 == 2:
			_place_support(output, origin, step_x, floor_y, step_z, direction, wood_id)
		# Descend gently so the tunnel follows the rock, not the sky.
		surface = floor_y
	if torch_id >= 0:
		_put(output, origin, Vector3i(x + direction.x * (length - 2), BiomeManager.get_height(x + direction.x * (length - 2), z + direction.y * (length - 2)) + 1, z + direction.y * (length - 2)), torch_id)


static func _place_support(output: PackedByteArray, origin: Vector3i, x: int, floor_y: int, z: int, direction: Vector2i, wood_id: int) -> void:
	for dy in range(0, 3):
		if direction.y != 0:
			_put(output, origin, Vector3i(x - 1, floor_y + dy, z), wood_id)
			_put(output, origin, Vector3i(x + 1, floor_y + dy, z), wood_id)
		else:
			_put(output, origin, Vector3i(x, floor_y + dy, z - 1), wood_id)
			_put(output, origin, Vector3i(x, floor_y + dy, z + 1), wood_id)
	if direction.y != 0:
		_put(output, origin, Vector3i(x - 1, floor_y + 3, z), wood_id)
		_put(output, origin, Vector3i(x + 1, floor_y + 3, z), wood_id)
	else:
		_put(output, origin, Vector3i(x, floor_y + 3, z - 1), wood_id)
		_put(output, origin, Vector3i(x, floor_y + 3, z + 1), wood_id)


# A small collapsed room: shell of stone, a doorway, torch, and a little ore.
static func _stamp_ruin(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, x: int, y: int, z: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var torch_id := int(block_ids.get(&"torch", -1))
	var copper_id := int(block_ids.get(&"copper_ore", stone_id))
	var half_w := 3
	var half_d := 3
	var height := 4
	for dz in range(-half_d, half_d + 1):
		for dx in range(-half_w, half_w + 1):
			for dy in range(0, height):
				var cell := Vector3i(x + dx, y + dy, z + dz)
				var inside := absi(dx) <= half_w - 1 and absi(dz) <= half_d - 1 and dy < height - 1
				_put(output, origin, cell, air_id if inside else stone_id)
	# Doorway on one side, always carved through the shell.
	var door := rng.randi_range(0, 3)
	for dy in range(0, 2):
		_put(output, origin, _side_cell(x, y + dy, z, door, half_w, half_d), air_id)
	if torch_id >= 0:
		_put(output, origin, Vector3i(x, y + 1, z), torch_id)
	_put(output, origin, Vector3i(x + 1, y, z + 1), copper_id)


# A wider pillared hall. Two rows of deepstone columns, a torch per bay.
static func _stamp_ancient_chamber(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, x: int, y: int, z: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var deep_id := int(block_ids.get(&"deepstone", stone_id))
	var torch_id := int(block_ids.get(&"torch", -1))
	var crystal_id := int(block_ids.get(&"lumen_crystal", -1))
	var half_w := 5
	var half_d := 6
	var height := 6
	for dz in range(-half_d, half_d + 1):
		for dx in range(-half_w, half_w + 1):
			for dy in range(0, height):
				var cell := Vector3i(x + dx, y + dy, z + dz)
				var inside := absi(dx) <= half_w - 1 and absi(dz) <= half_d - 1 and dy < height - 1
				_put(output, origin, cell, air_id if inside else deep_id)
	for pillar_z in [-3, 0, 3]:
		for pillar_x in [-2, 2]:
			for dy in range(0, height - 1):
				_put(output, origin, Vector3i(x + pillar_x, y + dy, z + pillar_z), deep_id)
	if torch_id >= 0:
		_put(output, origin, Vector3i(x, y + 2, z), torch_id)
	if crystal_id >= 0:
		_put(output, origin, Vector3i(x, y, z - half_d + 1), crystal_id)
	_put(output, origin, Vector3i(x + 1, y, z + 1), int(block_ids.get(&"silver_ore", stone_id)))


# A compact vault with a deep-ore cache. The gold is the reward; the door is
# sealed with stone that a player must mine through.
static func _stamp_treasure(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, x: int, y: int, z: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var gold_id := int(block_ids.get(&"gold_ore", stone_id))
	var silver_id := int(block_ids.get(&"silver_ore", stone_id))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for dy in range(0, 4):
				var cell := Vector3i(x + dx, y + dy, z + dz)
				var inside := absi(dx) <= 1 and absi(dz) <= 1 and dy < 3
				_put(output, origin, cell, air_id if inside else stone_id)
	_put(output, origin, Vector3i(x, y, z), gold_id)
	_put(output, origin, Vector3i(x + 1, y, z), gold_id)
	_put(output, origin, Vector3i(x - 1, y, z + 1), silver_id)
	if rng.randf() < 0.5:
		_put(output, origin, Vector3i(x, y, z + 1), int(block_ids.get(&"lumen_crystal", gold_id)))


# A natural shrine: crystal columns around a raised altar.
static func _stamp_crystal_shrine(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, x: int, y: int, z: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var crystal_id := int(block_ids.get(&"lumen_crystal", stone_id))
	var altar_id := int(block_ids.get(&"deepstone", stone_id))
	var radius := 4
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			for dy in range(0, 5):
				var cell := Vector3i(x + dx, y + dy, z + dz)
				var inside := dx * dx + dz * dz <= (radius - 1) * (radius - 1) and dy < 4
				_put(output, origin, cell, air_id if inside else altar_id)
	for offset in [Vector3i(-2, 0, -2), Vector3i(2, 0, -2), Vector3i(-2, 0, 2), Vector3i(2, 0, 2)]:
		for dy in range(0, rng.randi_range(2, 4)):
			_put(output, origin, Vector3i(x + offset.x, y + dy, z + offset.z), crystal_id)
	_put(output, origin, Vector3i(x, y, z), altar_id)
	_put(output, origin, Vector3i(x, y + 1, z), crystal_id)


# A buried vertical shaft with ledges and a lookout cap.
static func _stamp_watchtower(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, x: int, y: int, z: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	var height := rng.randi_range(12, 20)
	for dy in range(0, height):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var cell := Vector3i(x + dx, y + dy, z + dz)
				var shell := absi(dx) == 1 or absi(dz) == 1
				_put(output, origin, cell, stone_id if shell and dy % 4 == 0 else air_id)
	# Ledges spiral so the shaft is climbable in principle.
	for dy in range(2, height, 3):
		var side := (dy / 3) % 4
		var cell := Vector3i(x, y + dy, z)
		match side:
			0: cell.x += 1
			1: cell.z += 1
			2: cell.x -= 1
			_: cell.z -= 1
		_put(output, origin, cell, stone_id)
	# Cap platform and a torch.
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			_put(output, origin, Vector3i(x + dx, y + height, z + dz), stone_id)
	var torch_id := int(block_ids.get(&"torch", -1))
	if torch_id >= 0:
		_put(output, origin, Vector3i(x, y + height + 1, z), torch_id)


static func _stamp_biome_landmark(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, x: int, y: int, z: int, block_ids: Dictionary, air_id: int, stone_id: int, biome: int) -> void:
	var torch_id := int(block_ids.get(&"torch", -1))
	match biome:
		BiomeManager.JUNGLE:
			# Stepped ziggurat of jungle mudstone with a torch-lit inner room.
			var mud_id := int(block_ids.get(&"jungle_mudstone", stone_id))
			for layer in range(3):
				var radius := 4 - layer
				for dz in range(-radius, radius + 1):
					for dx in range(-radius, radius + 1):
						if absi(dx) + absi(dz) > radius + 1:
							continue
						_put(output, origin, Vector3i(x + dx, y + layer * 2, z + dz), mud_id)
			for dy in range(0, 3):
				_put(output, origin, Vector3i(x, y + dy, z), air_id)
			if torch_id >= 0:
				_put(output, origin, Vector3i(x, y + 2, z), torch_id)
		BiomeManager.CORRUPTION, BiomeManager.CRIMSON:
			# A ring of evil stone around a sacrificial altar, with the biome ore.
			var evil_id := int(block_ids.get(&"ebonstone" if biome == BiomeManager.CORRUPTION else &"crimstone", stone_id))
			var ore_id := int(block_ids.get(&"void_ore" if biome == BiomeManager.CORRUPTION else &"blood_ore", evil_id))
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					var distance := absi(dx) + absi(dz)
					if distance == 3:
						_put(output, origin, Vector3i(x + dx, y + 1, z + dz), evil_id)
					if distance <= 1:
						_put(output, origin, Vector3i(x + dx, y, z + dz), evil_id)
			_put(output, origin, Vector3i(x, y + 1, z), ore_id)
		BiomeManager.HALLOW:
			# Pearlstone ring with radiant crystal spires.
			var pearl_id := int(block_ids.get(&"pearlstone", stone_id))
			var crystal_id := int(block_ids.get(&"radiant_crystal_ore", pearl_id))
			for index in range(8):
				var angle := TAU * float(index) / 8.0
				var px := x + roundi(cos(angle) * 3.5)
				var pz := z + roundi(sin(angle) * 3.5)
				_put(output, origin, Vector3i(px, y, pz), pearl_id)
				for dy in range(1, rng.randi_range(2, 4)):
					_put(output, origin, Vector3i(px, y + dy, pz), crystal_id)
		BiomeManager.OCEAN:
			# Half-buried shipwreck ribs with a gold cache in the hold.
			var wood_id := int(block_ids.get(&"pale_wood", stone_id))
			var gold_id := int(block_ids.get(&"gold_ore", stone_id))
			for step in range(7):
				_put(output, origin, Vector3i(x + step, y, z), wood_id)
				if step % 2 == 0:
					_put(output, origin, Vector3i(x + step, y + 1, z), wood_id)
					_put(output, origin, Vector3i(x + step, y + 2, z), wood_id)
			_put(output, origin, Vector3i(x + 3, y + 1, z), gold_id)


# --- Helpers ----------------------------------------------------------------

static func _side_cell(x: int, y: int, z: int, side: int, half_w: int, half_d: int) -> Vector3i:
	match side:
		0: return Vector3i(x + half_w, y, z)
		1: return Vector3i(x - half_w, y, z)
		2: return Vector3i(x, y, z + half_d)
		_: return Vector3i(x, y, z - half_d)


static func _put(output: PackedByteArray, origin: Vector3i, cell: Vector3i, block_id: int) -> void:
	if block_id < 0:
		return
	var local_x := cell.x - origin.x
	var local_y := cell.y - origin.y
	var local_z := cell.z - origin.z
	if local_x < 0 or local_x >= 16 or local_y < 0 or local_y >= 16 or local_z < 0 or local_z >= 16:
		return
	output[local_x + local_y * 16 + local_z * 16 * 16] = block_id


static func _seed(world_seed: int, x: int, z: int, salt: int) -> int:
	var value := world_seed * 1103515245 + x * 73856093 + z * 19349663 + salt
	value = (value ^ (value >> 13)) * 1274126177
	return value & 0x7fffffff
