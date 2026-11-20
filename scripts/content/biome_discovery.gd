extends RefCounted
class_name BiomeDiscovery

# Agent 4 — Phase 4: biome-specific world discoveries.
#
# Reusable authored content stamped into the SAME chunk byte array through the
# existing AdventureContent.stamp_chunk() hook. No Agent 1 file is modified.
#
# Design rules (all verified by debug/biome_discovery_check.gd):
#   * One candidate site per 128x128 world cell, jittered deterministically.
#   * Sites skip spawn, the Undercroft footprint, and any nearby
#     WorldStructures site (queried through Agent 1's real _site() API) so
#     structures never destructively overlap.
#   * Surface sites require flat ground; underground sites are deep-relative
#     and always keep a solid floor, an air interior and a sealed shell.
#   * Every write is clipped to the chunk being generated, so borders match.
#   * All randomness comes from (world_seed, grid cell, salt) — never randi().
#
# This module owns GEOMETRY and placement metadata only. Loot/items/bosses
# belong to Agent 2 and are exposed as DATA through discovery_at()/sites().

const CHUNK_SIZE := 16
const CELL := 128
const REACH := 30
const SPAWN_CLEAR := 44.0
const STRUCTURE_CLEAR := 30.0
const SALT := 0xA4B1
const MIN_DEPTH := 18
const MAX_DEPTH := 72

# Template definitions. `kind` selects one of three reusable builders; the
# remaining fields are pure data (palette, size, loot, secret, surface depth).
const TEMPLATES := {
	"house":      {"kind": "room", "wall": "dead_wood", "floor": "stone", "loot": ["iron_ore", "copper_ore"], "hx": 4, "hz": 3, "h": 4, "surface": true, "secret": false, "label": "Abandoned house"},
	"cabin":      {"kind": "room", "wall": "dead_wood", "floor": "stone", "loot": ["copper_ore", "iron_ore"], "hx": 3, "hz": 3, "h": 4, "surface": false, "secret": false, "label": "Underground cabin"},
	"ruin":       {"kind": "room", "wall": "stone", "floor": "stone", "loot": ["iron_ore"], "hx": 4, "hz": 4, "h": 4, "surface": false, "secret": false, "label": "Small ruin"},
	"passage":    {"kind": "room", "wall": "stone", "floor": "stone", "loot": ["silver_ore"], "hx": 2, "hz": 5, "h": 3, "surface": false, "secret": true, "label": "Hidden passage"},
	"vault":      {"kind": "room", "wall": "deepstone", "floor": "deepstone", "loot": ["gold_ore", "ancient_ore"], "hx": 3, "hz": 3, "h": 4, "surface": false, "secret": true, "label": "Treasure vault"},
	"temple":     {"kind": "room", "wall": "sandstone", "floor": "sandstone", "loot": ["gold_ore", "lumen_crystal"], "hx": 6, "hz": 5, "h": 6, "surface": false, "secret": true, "label": "Buried temple"},
	"fossil":     {"kind": "room", "wall": "sandstone", "floor": "desert_sand", "decor": "pale_bloom", "loot": ["amber_ore"], "hx": 5, "hz": 4, "h": 4, "surface": false, "secret": false, "label": "Fossil chamber"},
	"altar":      {"kind": "landmark", "wall": "ebonstone", "floor": "ebonstone", "core": "void_ore", "loot": ["void_ore", "silver_ore"], "surface": true, "secret": false, "label": "Ruined shadow altar"},
	"chasm":      {"kind": "landmark", "wall": "ebonstone", "floor": "ebonstone", "core": "void_ore", "loot": ["void_ore"], "surface": true, "secret": false, "label": "Chasm landmark"},
	"heart":      {"kind": "landmark", "wall": "crimstone", "floor": "crimstone", "core": "blood_ore", "loot": ["blood_ore", "gold_ore"], "surface": true, "secret": false, "label": "Crimson heart location"},
	"garden":     {"kind": "landmark", "wall": "pearlstone", "floor": "pearlstone", "core": "radiant_crystal_ore", "loot": ["pearl_ore", "radiant_crystal_ore"], "surface": true, "secret": false, "label": "Crystal garden"},
	"floating":   {"kind": "landmark", "wall": "pearlstone", "floor": "pearlstone", "core": "radiant_crystal_ore", "loot": ["radiant_crystal_ore"], "surface": true, "float": true, "secret": false, "label": "Suspended hallowed formation"},
	"wreck":      {"kind": "landmark", "wall": "pale_wood", "floor": "ocean_sand", "core": "gold_ore", "loot": ["gold_ore", "coral"], "surface": true, "secret": false, "label": "Shipwreck"},
	"grove":      {"kind": "landmark", "wall": "mushroom_stem", "floor": "mushroom_soil", "core": "mushroom_cap", "loot": ["fungal_ore", "lumen_crystal"], "surface": true, "secret": false, "label": "Glowing mushroom grove"},
	"root_cave":  {"kind": "cave", "wall": "dead_wood", "floor": "jungle_mudstone", "decor": "jungle_leaves", "loot": ["amber_ore", "silver_ore"], "label": "Root-filled cave"},
	"ice_cavern": {"kind": "cave", "wall": "frost_ice", "floor": "frost_stone", "decor": "frost_snow", "loot": ["frost_crystal_ore"], "label": "Ice cavern"},
	"fungal_cave": {"kind": "cave", "wall": "mushroom_stem", "floor": "mycelium_stone", "decor": "mushroom_cap", "loot": ["fungal_ore"], "label": "Fungal chamber"},
	"submerged":  {"kind": "cave", "wall": "reefstone", "floor": "ocean_sand", "decor": "coral", "loot": ["coral", "pearl_ore"], "label": "Submerged cave"},
}

# Biome id -> reusable template ids. Uses Agent 1's ACTUAL BiomeManager ids.
const BY_BIOME := {
	BiomeManager.ASHEN: ["house", "cabin", "vault", "ruin", "passage"],
	BiomeManager.MIRE: ["house", "cabin", "vault", "ruin", "passage"],
	BiomeManager.FROST: ["cabin", "ice_cavern", "vault", "ruin"],
	BiomeManager.DESERT: ["temple", "fossil", "vault", "root_cave"],
	BiomeManager.MUSHROOM: ["grove", "fungal_cave", "vault", "cabin"],
	BiomeManager.HUSH: ["temple", "root_cave", "vault", "grove"],
	BiomeManager.JUNGLE: ["temple", "root_cave", "vault", "grove"],
	BiomeManager.CORRUPTION: ["altar", "chasm", "vault", "root_cave"],
	BiomeManager.CRIMSON: ["heart", "altar", "vault", "root_cave"],
	BiomeManager.HALLOW: ["garden", "floating", "temple", "vault"],
	BiomeManager.OCEAN: ["wreck", "submerged", "vault", "temple"],
}


# --- Public queries ----------------------------------------------------------

static func enabled() -> bool:
	return TerrariaWorldContent.ENABLE_BIOME_DISCOVERIES


static func templates_for_biome(biome: int) -> Array:
	var out: Array = BY_BIOME.get(biome, [])
	return out.duplicate()


static func site_for(world_seed: int, grid_x: int, grid_z: int) -> Dictionary:
	BiomeManager.configure(world_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed ^ SALT) ^ (grid_x * 73856093) ^ (grid_z * 19349663)
	var cx := grid_x * CELL + rng.randi_range(24, CELL - 25)
	var cz := grid_z * CELL + rng.randi_range(24, CELL - 25)
	var spawn_distance := Vector2(float(cx - BiomeManager.SPAWN_X), float(cz - BiomeManager.SPAWN_Z)).length()
	if spawn_distance < SPAWN_CLEAR:
		return {}
	var biome := BiomeManager.dominant_biome(cx, cz)
	var candidates: Array = BY_BIOME.get(biome, [])
	if candidates.is_empty():
		return {}
	var template := String(candidates[rng.randi_range(0, candidates.size() - 1)])
	var def: Dictionary = TEMPLATES[template]
	var surface := BiomeManager.get_height(cx, cz)
	var depth := rng.randi_range(MIN_DEPTH, MAX_DEPTH)
	var y := clampi(surface - depth, 6, int(WorldLayers.WORLD_Y) - 12)
	if bool(def.get("surface", false)):
		if not _flat(cx, cz):
			return {}
		y = surface
	# Avoid Agent 1's WorldStructures sites (real API, same seed space).
	var min_gx := floori(float(cx - REACH) / float(WorldStructures.CELL))
	var max_gx := floori(float(cx + REACH) / float(WorldStructures.CELL))
	var min_gz := floori(float(cz - REACH) / float(WorldStructures.CELL))
	var max_gz := floori(float(cz + REACH) / float(WorldStructures.CELL))
	for gz in range(min_gz, max_gz + 1):
		for gx in range(min_gx, max_gx + 1):
			var other := WorldStructures._site(world_seed, gx, gz)
			if other.is_empty():
				continue
			if Vector2(float(int(other["x"]) - cx), float(int(other["z"]) - cz)).length() < STRUCTURE_CLEAR:
				return {}
	# Keep the optional Undercroft isolated from sandbox discoveries.
	if AdventureContent.config().enable_undercroft:
		var bounds := AdventureContent.region_bounds(world_seed)
		if cx >= int(bounds["min_x"]) - REACH and cx <= int(bounds["max_x"]) + REACH \
			and cz >= int(bounds["min_z"]) - REACH and cz <= int(bounds["max_z"]) + REACH:
			return {}
	return {
		"id": "disc_%d_%d" % [grid_x, grid_z],
		"grid": Vector2i(grid_x, grid_z),
		"template": template, "label": String(def["label"]),
		"kind": String(def["kind"]), "biome": biome,
		"x": cx, "y": y, "z": cz, "surface": surface,
		"seed": rng.randi(),
	}


static func sites_near(world_seed: int, x: int, z: int) -> Array:
	var gx := floori(float(x) / float(CELL))
	var gz := floori(float(z) / float(CELL))
	var out: Array = []
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var site := site_for(world_seed, gx + ox, gz + oz)
			if not site.is_empty():
				out.append(site)
	return out


static func discovery_at(world_seed: int, cell: Vector3i) -> Dictionary:
	for site in sites_near(world_seed, cell.x, cell.z):
		var s: Dictionary = site
		var def: Dictionary = TEMPLATES[String(s["template"])]
		var radius: int = int(def.get("hx", 6)) + 2
		if absi(cell.x - int(s["x"])) <= radius and absi(cell.z - int(s["z"])) <= radius \
			and absi(cell.y - int(s["y"])) <= 12:
			return {
				"id": s["id"], "label": s["label"], "template": s["template"],
				"biome": int(s["biome"]), "tier": _tier(int(s["biome"])),
				"loot": (def.get("loot", []) as Array).duplicate(),
				"hint": "A %s lies buried here." % String(s["label"]),
			}
	return {}


static func _tier(biome: int) -> String:
	if biome == BiomeManager.CORRUPTION or biome == BiomeManager.CRIMSON or biome == BiomeManager.HALLOW:
		return "rare"
	return "uncommon"


static func _flat(x: int, z: int) -> bool:
	var here := BiomeManager.get_height(x, z)
	return absi(BiomeManager.get_height(x - 3, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x + 3, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z - 3) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z + 3) - here) <= 1


# --- Generation entry (called by AdventureContent.stamp_chunk) ---------------

static func stamp_chunk(output: PackedByteArray, origin: Vector3i, world_seed: int, block_ids: Dictionary, air_id: int, stone_id: int) -> void:
	if not enabled():
		return
	var min_gx := floori(float(origin.x - REACH) / float(CELL))
	var max_gx := floori(float(origin.x + CHUNK_SIZE - 1 + REACH) / float(CELL))
	var min_gz := floori(float(origin.z - REACH) / float(CELL))
	var max_gz := floori(float(origin.z + CHUNK_SIZE - 1 + REACH) / float(CELL))
	for gz in range(min_gz, max_gz + 1):
		for gx in range(min_gx, max_gx + 1):
			var site := site_for(world_seed, gx, gz)
			if site.is_empty():
				continue
			var def: Dictionary = TEMPLATES[String(site["template"])]
			var rng := RandomNumberGenerator.new()
			rng.seed = int(site["seed"])
			var x: int = int(site["x"])
			var y: int = int(site["y"])
			var z: int = int(site["z"])
			match String(def["kind"]):
				"room": _stamp_room(output, origin, rng, site, def, block_ids, air_id, stone_id, x, y, z)
				"landmark": _stamp_landmark(output, origin, rng, site, def, block_ids, stone_id, x, y, z)
				"cave": _stamp_cave(output, origin, rng, site, def, block_ids, air_id, stone_id, x, y, z)


# --- Reusable builders -------------------------------------------------------

static func _stamp_room(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, site: Dictionary, def: Dictionary, block_ids: Dictionary, air_id: int, stone_id: int, x: int, y: int, z: int) -> void:
	var wall := _bid(block_ids, String(def["wall"]), stone_id)
	var floor_id := _bid(block_ids, String(def["floor"]), stone_id)
	var decor := _bid(block_ids, String(def.get("decor", "torch")), -1)
	var torch_id := _bid(block_ids, "torch", -1)
	var hx: int = int(def.get("hx", 4))
	var hz: int = int(def.get("hz", 3))
	var h: int = int(def.get("h", 4))
	# Carve interior; lay a solid floor and a solid cap.
	for dz in range(-hz, hz + 1):
		for dx in range(-hx, hx + 1):
			_put(output, origin, x + dx, y, z + dz, floor_id)
			_put(output, origin, x + dx, y + h, z + dz, wall)
			for dy in range(1, h):
				_put(output, origin, x + dx, y + dy, z + dz, air_id)
	# Shell walls (one block thick) and a deterministic doorway.
	for dy in range(1, h):
		for dx in range(-hx - 1, hx + 2):
			_put(output, origin, x + dx, y + dy, z - hz - 1, wall)
			_put(output, origin, x + dx, y + dy, z + hz + 1, wall)
		for dz in range(-hz - 1, hz + 2):
			_put(output, origin, x - hx - 1, y + dy, z + dz, wall)
			_put(output, origin, x + hx + 1, y + dy, z + dz, wall)
	var door := rng.randi_range(0, 3)
	for dy in range(1, 3):
		match door:
			0: _put(output, origin, x, y + dy, z - hz - 1, air_id)
			1: _put(output, origin, x, y + dy, z + hz + 1, air_id)
			2: _put(output, origin, x - hx - 1, y + dy, z, air_id)
			_: _put(output, origin, x + hx + 1, y + dy, z, air_id)
	if torch_id >= 0:
		_put(output, origin, x - hx, y + h - 1, z, torch_id)
		_put(output, origin, x + hx, y + h - 1, z, torch_id)
	_scatter_loot(output, origin, rng, def, block_ids, floor_id, x, y + 1, z, hx, hz)
	if bool(def.get("secret", false)):
		_stamp_secret(output, origin, rng, def, block_ids, air_id, x, y, z, hx, hz, h)


static func _stamp_secret(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, def: Dictionary, block_ids: Dictionary, air_id: int, x: int, y: int, z: int, hx: int, hz: int, h: int) -> void:
	# A 3x3 alcove beyond the north wall, sealed by a marker block. The clue is
	# a pair of pale blooms on the approach side (environmental, not a beacon).
	var marker := _bid(block_ids, "mycelium", -1)
	var clue := _bid(block_ids, "pale_bloom", -1)
	for dx in range(-1, 2):
		for dy in range(1, 3):
			_put(output, origin, x + dx, y + dy, z - hz - 3, air_id)
			_put(output, origin, x + dx, y + dy, z - hz - 2, marker)
	if clue >= 0:
		_put(output, origin, x - 1, y + 2, z - hz, clue)
		_put(output, origin, x + 1, y + 2, z - hz, clue)
	var bonus := _bid(block_ids, String((def.get("loot", ["gold_ore"]) as Array)[0]), -1)
	_put(output, origin, x, y + 1, z - hz - 3, bonus)
	_put(output, origin, x + 1, y + 1, z - hz - 3, bonus)


static func _stamp_landmark(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, site: Dictionary, def: Dictionary, block_ids: Dictionary, stone_id: int, x: int, y: int, z: int) -> void:
	var wall := _bid(block_ids, String(def["wall"]), stone_id)
	var core := _bid(block_ids, String(def.get("core", "lumen_crystal")), stone_id)
	var lift: int = 6 if bool(def.get("float", false)) else 0
	# A ring of themed blocks around a core resource. Floating variants hang
	# above the surface; everything else sits on the local ground.
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var px := x + roundi(cos(angle) * 3.0)
		var pz := z + roundi(sin(angle) * 3.0)
		_put(output, origin, px, y + lift, pz, wall)
		var height := rng.randi_range(1, 4)
		for dy in range(1, height + 1):
			_put(output, origin, px, y + lift + dy, pz, core)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if dx * dx + dz * dz <= 3:
				_put(output, origin, x + dx, y + lift, z + dz, wall)
	_put(output, origin, x, y + lift + 1, z, core)
	_scatter_loot(output, origin, rng, def, block_ids, wall, x, y + lift + 1, z, 2, 2)


static func _stamp_cave(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, site: Dictionary, def: Dictionary, block_ids: Dictionary, air_id: int, stone_id: int, x: int, y: int, z: int) -> void:
	var wall := _bid(block_ids, String(def["wall"]), stone_id)
	var floor_id := _bid(block_ids, String(def["floor"]), stone_id)
	var decor := _bid(block_ids, String(def.get("decor", "mycelium")), -1)
	var radius := rng.randi_range(4, 6)
	for dy in range(-2, 4):
		var r := radius - maxi(0, dy - 1)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				_put(output, origin, x + dx, y + dy, z + dz, air_id)
				if dy == -2:
					_put(output, origin, x + dx, y + dy, z + dz, floor_id)
	if decor >= 0:
		for index in range(6):
			var angle := TAU * float(index) / 6.0
			var px := x + roundi(cos(angle) * float(radius - 1))
			var pz := z + roundi(sin(angle) * float(radius - 1))
			for dy in range(0, rng.randi_range(1, 4)):
				_put(output, origin, px, y + dy, pz, decor)
	_scatter_loot(output, origin, rng, def, block_ids, floor_id, x, y - 1, z, radius - 1, radius - 1)


static func _scatter_loot(output: PackedByteArray, origin: Vector3i, rng: RandomNumberGenerator, def: Dictionary, block_ids: Dictionary, fallback: int, x: int, y: int, z: int, hx: int, hz: int) -> void:
	var loot: Array = def.get("loot", [])
	for i in range(2 + rng.randi_range(0, 3)):
		if loot.is_empty():
			return
		var block := _bid(block_ids, String(loot[rng.randi_range(0, loot.size() - 1)]), fallback)
		_put(output, origin, x + rng.randi_range(-hx + 1, hx - 1), y, z + rng.randi_range(-hz + 1, hz - 1), block)


static func _bid(block_ids: Dictionary, name: String, fallback: int) -> int:
	if block_ids.has(StringName(name)):
		return int(block_ids[StringName(name)])
	return fallback


static func _put(output: PackedByteArray, origin: Vector3i, x: int, y: int, z: int, block_id: int) -> void:
	if y < 0 or y >= int(WorldLayers.WORLD_Y) or block_id < 0:
		return
	var lx := x - origin.x
	var ly := y - origin.y
	var lz := z - origin.z
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE:
		return
	output[lx + ly * CHUNK_SIZE + lz * CHUNK_SIZE * CHUNK_SIZE] = block_id
