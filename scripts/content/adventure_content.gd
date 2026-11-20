extends RefCounted
class_name AdventureContent

# Agent 4 — World Design / Adventure Architect. CANONICAL PORT.
#
# Deterministic content stamping for the authored adventure region
# "The Undercroft". Adapted to the canonical Deepworld engine:
#   * WorldLayers.WORLD_Y (256), not a hardcoded 64.
#   * Room Y is DEPTH-RELATIVE: levels are derived from the minimum local
#     surface across the region so rooms stay buried under any terrain.
#   * Block ids are resolved ONLY through the canonical block_ids map.
#     There are no numeric id fallbacks (canonical air=10, stone=13).
#
# Pure and worker-safe: no nodes, no signals, no randi(), no mutable globals.

const CONFIG: AdventureConfig = preload("res://data/world/adventure_config.tres")
const CHUNK_SIZE := 16

const ROOMS := [
	{"id": "entry_hall",        "cx": 0,  "cz": 0,   "hx": 5, "hz": 4, "y": "upper", "h": "room",  "vertical": false},
	{"id": "guard_room",        "cx": 18, "cz": 0,   "hx": 4, "hz": 4, "y": "upper", "h": "room",  "vertical": false},
	{"id": "shattered_gallery", "cx": 18, "cz": -16, "hx": 6, "hz": 4, "y": "upper", "h": "room",  "vertical": false},
	{"id": "hidden_cache",      "cx": 30, "cz": -16, "hx": 3, "hz": 3, "y": "upper", "h": "room",  "vertical": false},
	{"id": "lower_sanctum",     "cx": 18, "cz": 9,   "hx": 7, "hz": 7, "y": "lower", "h": "arena", "vertical": false},
	{"id": "ember_vault",       "cx": 34, "cz": 9,   "hx": 4, "hz": 3, "y": "lower", "h": "vault", "vertical": false},
]

const CORRIDORS := [
	{"id": "hall_to_guard",   "x0": 5,  "x1": 14, "z0": -1,  "z1": 1,  "y": "upper", "vertical": false},
	{"id": "guard_to_gallery", "x0": 17, "x1": 19, "z0": -12, "z1": -4, "y": "upper", "vertical": false},
	{"id": "gallery_to_cache", "x0": 24, "x1": 27, "z0": -17, "z1": -15, "y": "upper", "vertical": false},
	{"id": "guard_drop",      "x0": 17, "x1": 19, "z0": 1,   "z1": 3,  "y": "lower", "vertical": true},
	{"id": "sanctum_to_vault", "x0": 25, "x1": 30, "z0": 8,  "z1": 10, "y": "lower", "vertical": false},
]

const FALSE_WALL := {"x": 25, "z0": -17, "z1": -15, "room": "hidden_cache"}


# --- Public data queries -----------------------------------------------------

static func config() -> AdventureConfig:
	return CONFIG


static func world_anchor() -> Vector2i:
	return Vector2i(CONFIG.anchor_x, CONFIG.anchor_z)


# x/z footprint only; deliberately independent of Y so it can be used to
# compute the depth-relative level without a circular dependency.
static func _footprint_bounds() -> Dictionary:
	var anchor := world_anchor()
	var min_x := 1 << 30
	var max_x := -(1 << 30)
	var min_z := 1 << 30
	var max_z := -(1 << 30)
	for room in ROOMS:
		min_x = mini(min_x, anchor.x + int(room["cx"]) - int(room["hx"]))
		max_x = maxi(max_x, anchor.x + int(room["cx"]) + int(room["hx"]))
		min_z = mini(min_z, anchor.y + int(room["cz"]) - int(room["hz"]))
		max_z = maxi(max_z, anchor.y + int(room["cz"]) + int(room["hz"]))
	for corridor in CORRIDORS:
		min_x = mini(min_x, anchor.x + int(corridor["x0"]))
		max_x = maxi(max_x, anchor.x + int(corridor["x1"]))
		min_z = mini(min_z, anchor.y + int(corridor["z0"]))
		max_z = maxi(max_z, anchor.y + int(corridor["z1"]))
	return {
		"anchor": anchor,
		"min_x": min_x, "max_x": max_x,
		"min_z": min_z, "max_z": max_z,
	}


# Depth-relative levels. Sampling the LOWEST surface in the footprint means
# every room is below ground even where the terrain rises by 20+ blocks.
static func region_levels(world_seed: int) -> Dictionary:
	BiomeManager.configure(world_seed)
	var b := _footprint_bounds()
	var min_surface := 1 << 30
	var max_surface := -(1 << 30)
	var step := 12
	for z in range(int(b["min_z"]) - 4, int(b["max_z"]) + 5, step):
		for x in range(int(b["min_x"]) - 4, int(b["max_x"]) + 5, step):
			var h := BiomeManager.get_height(x, z)
			min_surface = mini(min_surface, h)
			max_surface = maxi(max_surface, h)
	var anchor_surface := BiomeManager.get_height(int(b["anchor"].x), int(b["anchor"].y))
	min_surface = mini(min_surface, anchor_surface)
	max_surface = maxi(max_surface, anchor_surface)
	var world_y := int(WorldLayers.WORLD_Y)
	var upper := clampi(min_surface - CONFIG.upper_room_depth, 4, world_y - CONFIG.arena_height - 10)
	var lower := clampi(upper - CONFIG.level_gap, 2, maxi(2, upper - CONFIG.room_height - 2))
	return {
		"min_surface": min_surface,
		"max_surface": max_surface,
		"upper": upper,
		"lower": lower,
	}


static func volumes_for(levels: Dictionary) -> Array:
	var anchor := world_anchor()
	var upper: int = levels["upper"]
	var lower: int = levels["lower"]
	var out: Array = []
	for room in ROOMS:
		var floor_y: int = lower if String(room["y"]) == "lower" else upper
		var height := _height(String(room["h"]))
		out.append({
			"id": String(room["id"]),
			"kind": "room",
			"min_x": anchor.x + int(room["cx"]) - int(room["hx"]),
			"max_x": anchor.x + int(room["cx"]) + int(room["hx"]),
			"min_z": anchor.y + int(room["cz"]) - int(room["hz"]),
			"max_z": anchor.y + int(room["cz"]) + int(room["hz"]),
			"floor_y": floor_y,
			"ceiling_y": floor_y + height,
			"vertical": bool(room["vertical"]),
		})
	for corridor in CORRIDORS:
		var floor_y: int = lower + 1
		var height := _height("room")
		if not bool(corridor["vertical"]):
			floor_y = lower if String(corridor["y"]) == "lower" else upper
		else:
			height = (upper + _height("room") - 1) - floor_y
		out.append({
			"id": String(corridor["id"]),
			"kind": "corridor",
			"min_x": anchor.x + int(corridor["x0"]),
			"max_x": anchor.x + int(corridor["x1"]),
			"min_z": anchor.y + int(corridor["z0"]),
			"max_z": anchor.y + int(corridor["z1"]),
			"floor_y": floor_y,
			"ceiling_y": floor_y + height,
			"vertical": bool(corridor["vertical"]),
		})
	return out


static func volumes(world_seed: int) -> Array:
	return volumes_for(region_levels(world_seed))


static func room_at(cell: Vector3i, world_seed: int) -> String:
	for volume in volumes(world_seed):
		var v: Dictionary = volume
		if cell.x >= int(v["min_x"]) and cell.x <= int(v["max_x"]) \
			and cell.z >= int(v["min_z"]) and cell.z <= int(v["max_z"]) \
			and cell.y > int(v["floor_y"]) and cell.y < int(v["ceiling_y"]):
			return String(v["id"])
	return ""


# Pure query for Agent 2's published EnemyDirector.encounter_center_provider:
#   enemy_director.encounter_center_provider = func(room_id):
#       return AdventureContent.room_center(room_id, world.world_seed)
static func room_center(room_id: String, world_seed: int) -> Vector3:
	for volume in volumes(world_seed):
		var v: Dictionary = volume
		if String(v["id"]) == room_id:
			return Vector3(
				float(int(v["min_x"]) + int(v["max_x"])) * 0.5,
				float(int(v["floor_y"]) + 1),
				float(int(v["min_z"]) + int(v["max_z"])) * 0.5)
	return Vector3(
		float(BiomeManager.SPAWN_X) + 0.5,
		float(BiomeManager.get_height(BiomeManager.SPAWN_X, BiomeManager.SPAWN_Z)) + 1.0,
		float(BiomeManager.SPAWN_Z) + 0.5)


static func region_bounds(world_seed: int) -> Dictionary:
	var b := _footprint_bounds()
	var levels := region_levels(world_seed)
	var bounds := b.duplicate()
	bounds["min_x"] = int(b["min_x"]) - 2
	bounds["max_x"] = int(b["max_x"]) + 2
	bounds["min_z"] = int(b["min_z"]) - 2
	bounds["max_z"] = int(b["max_z"]) + 2
	bounds["rooms"] = ROOMS.size()
	bounds["corridors"] = CORRIDORS.size()
	bounds["levels"] = levels
	return bounds


# --- Main generation hook ----------------------------------------------------

static func stamp_chunk(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, air_id_hint: int = -1, stone_id_hint: int = -1) -> void:
	var air_id: int = air_id_hint
	if air_id < 0:
		air_id = _id(block_ids, "air")
	if air_id < 0:
		return  # cannot carve without the canonical air id
	var stone_id: int = stone_id_hint
	if stone_id < 0:
		stone_id = _id(block_ids, "stone")
	if stone_id < 0:
		stone_id = air_id

	# CORE sandbox content: biome discoveries are independent of the optional
	# Undercroft. No second generator hook is required by Agent 1.
	BiomeDiscovery.stamp_chunk(output, origin, world_seed, block_ids, air_id, stone_id)

	if not CONFIG.enable_undercroft:
		return

	var levels := region_levels(world_seed)
	var vols := volumes_for(levels)

	for volume in vols:
		var v: Dictionary = volume
		if not _overlaps_chunk(v, origin):
			continue
		_carve_volume(output, origin, v, air_id, stone_id, vols)
	for volume in vols:
		var v: Dictionary = volume
		if not _overlaps_chunk(v, origin):
			continue
		_shell_volume(output, origin, v, stone_id, vols)

	for room in ROOMS:
		var room_id := String(room["id"])
		var floor_y: int = int(levels["lower"]) if String(room["y"]) == "lower" else int(levels["upper"])
		var height := _height(String(room["h"]))
		var box := _room_box(room, floor_y, height)
		if not _box_overlaps_chunk(box, origin):
			continue
		var rng := _rng(world_seed, "decor:" + room_id)
		_decorate_room(output, origin, room_id, box, floor_y, height, block_ids, rng)
	_stamp_false_wall(output, origin, world_seed, block_ids, levels)
	_stamp_boss_arena(output, origin, world_seed, block_ids, levels)
	if CONFIG.enable_surface_gate:
		_stamp_surface_gate(output, origin, world_seed, block_ids, levels, air_id, stone_id)


# --- Geometry primitives -----------------------------------------------------

static func _height(which: String) -> int:
	match which:
		"arena": return CONFIG.arena_height
		"vault": return maxi(4, CONFIG.arena_height - 2)
		_: return CONFIG.room_height


static func _room_box(room: Dictionary, floor_y: int, height: int) -> Dictionary:
	var anchor := world_anchor()
	return {
		"min_x": anchor.x + int(room["cx"]) - int(room["hx"]),
		"max_x": anchor.x + int(room["cx"]) + int(room["hx"]),
		"min_z": anchor.y + int(room["cz"]) - int(room["hz"]),
		"max_z": anchor.y + int(room["cz"]) + int(room["hz"]),
		"floor_y": floor_y,
		"ceiling_y": floor_y + height,
	}


static func _overlaps_chunk(v: Dictionary, origin: Vector3i) -> bool:
	var lo := origin
	var hi := origin + Vector3i(CHUNK_SIZE - 1, CHUNK_SIZE - 1, CHUNK_SIZE - 1)
	return int(v["min_x"]) - 1 <= hi.x and int(v["max_x"]) + 1 >= lo.x \
		and int(v["min_z"]) - 1 <= hi.z and int(v["max_z"]) + 1 >= lo.z \
		and int(v["floor_y"]) - 1 <= hi.y and int(v["ceiling_y"]) + 1 >= lo.y


static func _box_overlaps_chunk(box: Dictionary, origin: Vector3i) -> bool:
	return _overlaps_chunk(box, origin)


static func _interior(v: Dictionary, x: int, y: int, z: int) -> bool:
	return x >= int(v["min_x"]) and x <= int(v["max_x"]) \
		and z >= int(v["min_z"]) and z <= int(v["max_z"]) \
		and y > int(v["floor_y"]) and y < int(v["ceiling_y"])


static func _in_any_interior(vols: Array, x: int, y: int, z: int) -> bool:
	for volume in vols:
		if _interior(volume as Dictionary, x, y, z):
			return true
	return false


static func _carve_volume(output: PackedByteArray, origin: Vector3i, v: Dictionary, air_id: int, stone_id: int, vols: Array) -> void:
	var vertical := bool(v["vertical"])
	var y0: int = int(v["floor_y"]) + 1
	var y1: int = int(v["ceiling_y"]) - 1
	for z in range(int(v["min_z"]), int(v["max_z"]) + 1):
		for x in range(int(v["min_x"]), int(v["max_x"]) + 1):
			for y in range(y0, y1 + 1):
				if vertical or (_in_any_interior(vols, x, y, z) and _interior(v, x, y, z)):
					put_cell(output, origin, x, y, z, air_id)
			if not vertical:
				put_cell(output, origin, x, int(v["floor_y"]), z, stone_id)
				put_cell(output, origin, x, int(v["ceiling_y"]), z, stone_id)


static func _shell_volume(output: PackedByteArray, origin: Vector3i, v: Dictionary, stone_id: int, vols: Array) -> void:
	if bool(v["vertical"]):
		return
	for y in range(int(v["floor_y"]) + 1, int(v["ceiling_y"])):
		for z in range(int(v["min_z"]) - 1, int(v["max_z"]) + 2):
			for x in range(int(v["min_x"]) - 1, int(v["max_x"]) + 2):
				if _interior(v, x, y, z):
					continue
				if x > int(v["min_x"]) and x < int(v["max_x"]) and z > int(v["min_z"]) and z < int(v["max_z"]):
					continue
				if _in_any_interior(vols, x, y, z):
					continue
				put_cell(output, origin, x, y, z, stone_id)


static func put_cell(output: PackedByteArray, origin: Vector3i, x: int, y: int, z: int, block_id: int) -> void:
	if y < 0 or y >= int(WorldLayers.WORLD_Y) or block_id < 0:
		return
	var lx := x - origin.x
	var ly := y - origin.y
	var lz := z - origin.z
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE:
		return
	output[lx + ly * CHUNK_SIZE + lz * CHUNK_SIZE * CHUNK_SIZE] = block_id


static func read_cell(output: PackedByteArray, origin: Vector3i, x: int, y: int, z: int, fallback: int) -> int:
	if y < 0 or y >= int(WorldLayers.WORLD_Y):
		return fallback
	var lx := x - origin.x
	var ly := y - origin.y
	var lz := z - origin.z
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE:
		return fallback
	return int(output[lx + ly * CHUNK_SIZE + lz * CHUNK_SIZE * CHUNK_SIZE])


# Canonical block ids ONLY. Missing names return -1 and put_cell skips them;
# there are no hardcoded numeric fallbacks (canonical air=10, stone=13).
static func _id(block_ids: Dictionary, name: String) -> int:
	if block_ids.has(StringName(name)):
		return int(block_ids[StringName(name)])
	return -1


static func _rng(world_seed: int, feature: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ CONFIG.feature_salt) ^ feature.hash()
	return rng


# --- Set dressing ------------------------------------------------------------

static func _decorate_room(output: PackedByteArray, origin: Vector3i, room_id: String, box: Dictionary, floor_y: int, height: int, block_ids: Dictionary, rng: RandomNumberGenerator) -> void:
	var wood_id := _id(block_ids, "dead_wood")
	var torch_id := _id(block_ids, "torch")
	var gravel_id := _id(block_ids, "canyon_gravel")
	var min_x: int = box["min_x"]
	var max_x: int = box["max_x"]
	var min_z: int = box["min_z"]
	var max_z: int = box["max_z"]
	var cx: int = (min_x + max_x) / 2
	var cz: int = (min_z + max_z) / 2

	if room_id != "lower_sanctum":
		for px_variant in [min_x + 1, max_x - 1]:
			var px: int = px_variant
			for pz_variant in [min_z + 1, max_z - 1]:
				var pz: int = pz_variant
				for y in range(floor_y + 1, floor_y + height):
					put_cell(output, origin, px, y, pz, wood_id)
		for z in [min_z + 1, max_z - 1]:
			for x in range(min_x + 1, max_x):
				if (x - min_x) % 2 == 0:
					put_cell(output, origin, x, floor_y + height - 1, z, wood_id)

	if torch_id >= 0:
		put_cell(output, origin, min_x, floor_y + maxi(2, height - 2), cz, torch_id)
		put_cell(output, origin, max_x, floor_y + maxi(2, height - 2), cz, torch_id)

	for _i in range(3 + rng.randi_range(0, 3)):
		var rx := rng.randi_range(min_x + 1, max_x - 1)
		var rz := rng.randi_range(min_z + 1, max_z - 1)
		put_cell(output, origin, rx, floor_y + 1, rz, gravel_id)

	for entry in CONFIG.treasure:
		var d: Dictionary = entry as Dictionary
		if String(d.get("room", "")) != room_id:
			continue
		var block_name := String(d.get("block", "iron_ore"))
		var count := clampi(int(d.get("count", 1)), 0, 24)
		for _i in range(count):
			var tx := rng.randi_range(min_x + 1, max_x - 1)
			var tz := rng.randi_range(min_z + 1, max_z - 1)
			var ty := floor_y + (1 if rng.randf() < 0.7 else 2)
			put_cell(output, origin, tx, ty, tz, _id(block_ids, block_name))


static func _stamp_false_wall(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, levels: Dictionary) -> void:
	var anchor := world_anchor()
	var marker_id := _id(block_ids, "mycelium")
	var clue_id := _id(block_ids, "pale_bloom")
	var ore_id := _id(block_ids, "iron_ore")
	var floor_y: int = levels["upper"]
	var x := anchor.x + int(FALSE_WALL["x"])
	for z in range(anchor.y + int(FALSE_WALL["z0"]), anchor.y + int(FALSE_WALL["z1"]) + 1):
		for y in range(floor_y + 1, floor_y + CONFIG.room_height):
			put_cell(output, origin, x, y, z, marker_id)
	var gallery_edge := anchor.x + 24
	put_cell(output, origin, gallery_edge, floor_y + 2, anchor.y - 17, clue_id)
	put_cell(output, origin, gallery_edge, floor_y + 2, anchor.y - 15, clue_id)
	put_cell(output, origin, anchor.x + 28, floor_y + 1, anchor.y - 16, ore_id)


static func _stamp_boss_arena(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, levels: Dictionary) -> void:
	var anchor := world_anchor()
	var stone_id := _id(block_ids, "stone")
	var wood_id := _id(block_ids, "dead_wood")
	var beacon_id := _id(block_ids, "beacon")
	var iron_id := _id(block_ids, "iron_ore")
	var crystal_id := _id(block_ids, "lumen_crystal")
	var floor_y: int = levels["lower"]
	var cx := anchor.x + 18
	var cz := anchor.y + 9
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			put_cell(output, origin, cx + dx, floor_y + 1, cz + dz, stone_id)
	put_cell(output, origin, cx, floor_y + 2, cz, crystal_id)
	var inset := 2
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var px: int = cx + int(sx) * (7 - inset)
			var pz: int = cz + int(sz) * (7 - inset)
			for y in range(floor_y + 1, floor_y + 4):
				put_cell(output, origin, px, y, pz, stone_id)
			put_cell(output, origin, px, floor_y + 4, pz, beacon_id)
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var rx := cx + roundi(cos(angle) * 5.0)
		var rz := cz + roundi(sin(angle) * 5.0)
		put_cell(output, origin, rx, floor_y + 1, rz, iron_id)
	for i in range(4):
		put_cell(output, origin, cx - 2 + i, floor_y + 1, cz - 7, wood_id)


static func _stamp_surface_gate(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, levels: Dictionary, air_id: int, stone_id: int) -> void:
	var anchor := world_anchor()
	var ax := anchor.x
	var az := anchor.y
	if origin.x + CHUNK_SIZE - 1 < ax - 10 or origin.x > ax + 10 \
		or origin.z + CHUNK_SIZE - 1 < az - 10 or origin.z > az + 4:
		return
	BiomeManager.configure(world_seed)
	var gravel_id := _id(block_ids, "canyon_gravel")
	var wood_id := _id(block_ids, "dead_wood")
	var crystal_id := _id(block_ids, "lumen_crystal")
	var torch_id := _id(block_ids, "torch")
	var gate_z := az - 6
	var left_top := BiomeManager.get_height(ax - 4, gate_z) + 4
	var right_top := BiomeManager.get_height(ax + 4, gate_z) + 3
	for side_variant in [-1, 1]:
		var side: int = side_variant
		var px: int = ax + side * 4
		var ground := BiomeManager.get_height(px, gate_z)
		var pillar_height := 4 if side < 0 else 3
		for y in range(ground + 1, ground + pillar_height + 1):
			put_cell(output, origin, px, y, gate_z, stone_id)
		if torch_id >= 0:
			put_cell(output, origin, px, ground + pillar_height + 1, gate_z, torch_id)
	for x in range(ax - 4, ax + 5):
		if absi(x - ax) <= 1:
			continue
		put_cell(output, origin, x, maxi(left_top, right_top) + 1, gate_z, stone_id)
	for z in range(gate_z + 1, az + 1):
		put_cell(output, origin, ax, BiomeManager.get_height(ax, z) + 1, z, gravel_id)
	var wy := BiomeManager.get_height(ax - 7, az - 3)
	for y in range(wy + 1, wy + 4):
		put_cell(output, origin, ax - 7, y, az - 3, crystal_id)
	var sy := BiomeManager.get_height(ax + 7, az - 3)
	put_cell(output, origin, ax + 7, sy + 1, az - 3, wood_id)
	put_cell(output, origin, ax + 7, sy + 2, az - 3, wood_id)
	put_cell(output, origin, ax + 6, sy + 2, az - 3, wood_id)
	# Entrance shaft: open to the sky and ringed at the lip.
	var surface := BiomeManager.get_height(ax, az)
	var upper: int = levels["upper"]
	for z in range(az - 1, az + 2):
		for x in range(ax - 1, ax + 2):
			for y in range(upper + 1, surface + 2):
				put_cell(output, origin, x, y, z, air_id)
	for z in range(az - 2, az + 3):
		for x in range(ax - 2, ax + 3):
			if x == ax - 2 or x == ax + 2 or z == az - 2 or z == az + 2:
				put_cell(output, origin, x, surface + 1, z, stone_id)
	for y in range(upper + 2, surface, 2):
		if ((y - upper) / 2) % 2 == 0:
			put_cell(output, origin, ax - 1, y, az, stone_id)
		else:
			put_cell(output, origin, ax + 1, y, az, stone_id)
	if torch_id >= 0:
		put_cell(output, origin, ax - 2, surface + 2, az, torch_id)


# --- Pure validation ---------------------------------------------------------

static func validate_region(world_seed: int, block_ids: Dictionary) -> Dictionary:
	var failures: Array = []
	var levels := region_levels(world_seed)
	var vols := volumes_for(levels)
	if vols.size() != ROOMS.size() + CORRIDORS.size():
		failures.append("volume count")
	var air_id := _id(block_ids, "air")
	var stone_id := _id(block_ids, "stone")
	if air_id < 0:
		failures.append("missing canonical air id")

	var probe_origin := Vector3i(floori(float(world_anchor().x - 8) / 16.0) * 16, floori(float(levels["upper"]) / 16.0) * 16, floori(float(world_anchor().y - 4) / 16.0) * 16)
	var a := PackedByteArray()
	a.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
	a.fill(stone_id)
	var b := PackedByteArray()
	b.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
	b.fill(stone_id)
	stamp_chunk(a, probe_origin, world_seed, block_ids, air_id, stone_id)
	stamp_chunk(b, probe_origin, world_seed, block_ids, air_id, stone_id)
	if a != b:
		failures.append("determinism")

	var air_cells := 0
	for volume in vols:
		var v: Dictionary = volume
		var mid_y: int = (int(v["floor_y"]) + int(v["ceiling_y"])) / 2
		var found_air := false
		for sx in range(int(v["min_x"]), int(v["max_x"]) + 1):
			for sz in range(int(v["min_z"]), int(v["max_z"]) + 1):
				if found_air:
					break
				var origin := Vector3i(floori(float(sx) / 16.0) * 16, floori(float(mid_y) / 16.0) * 16, floori(float(sz) / 16.0) * 16)
				if not _overlaps_chunk(v, origin):
					continue
				var sample := PackedByteArray()
				sample.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)
				sample.fill(stone_id)
				stamp_chunk(sample, origin, world_seed, block_ids, air_id, stone_id)
				if read_cell(sample, origin, sx, mid_y, sz, stone_id) == air_id:
					found_air = true
		if found_air:
			air_cells += 1
		else:
			failures.append("not carved:" + String(v["id"]))

	if not _graph_connected():
		failures.append("connectivity")
	# Burial check: the upper ceiling must sit below the lowest local surface.
	if int(levels["upper"]) + CONFIG.room_height >= int(levels["min_surface"]):
		failures.append("rooms not buried")
	if CONFIG.boss_arena.get("room", "") != "lower_sanctum":
		failures.append("boss arena room")
	if CONFIG.secrets.is_empty() or CONFIG.encounters.is_empty():
		failures.append("content tables")

	return {
		"ok": failures.is_empty(),
		"failures": failures,
		"rooms": ROOMS.size(),
		"corridors": CORRIDORS.size(),
		"carved_rooms": air_cells,
		"bounds": region_bounds(world_seed),
	}


static func _graph_connected() -> bool:
	var neighbors := {}
	for room in ROOMS:
		neighbors[String(room["id"])] = []
	var anchor := world_anchor()
	for corridor in CORRIDORS:
		var x0 := anchor.x + int(corridor["x0"])
		var x1 := anchor.x + int(corridor["x1"])
		var z0 := anchor.y + int(corridor["z0"])
		var z1 := anchor.y + int(corridor["z1"])
		var touches: Array = []
		for room in ROOMS:
			var rx0 := anchor.x + int(room["cx"]) - int(room["hx"])
			var rx1 := anchor.x + int(room["cx"]) + int(room["hx"])
			var rz0 := anchor.y + int(room["cz"]) - int(room["hz"])
			var rz1 := anchor.y + int(room["cz"]) + int(room["hz"])
			if x1 >= rx0 and x0 <= rx1 and z1 >= rz0 and z0 <= rz1:
				touches.append(String(room["id"]))
		if touches.size() < 2:
			return false
		for i in range(touches.size()):
			for j in range(i + 1, touches.size()):
				(neighbors[touches[i]] as Array).append(touches[j])
				(neighbors[touches[j]] as Array).append(touches[i])
	var seen := {"entry_hall": true}
	var stack := ["entry_hall"]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		for next_room in neighbors.get(current, []):
			if not seen.has(next_room):
				seen[next_room] = true
				stack.append(next_room)
	return seen.size() == ROOMS.size()
