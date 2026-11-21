extends RefCounted
class_name WorldGateway

## The ONLY bridge from Agent 2 gameplay code into Agent 1's world engine.
## Every call is an existing VoxelWorld endpoint except get_mining_info() and
## has_station(), which are requested from Agent 1. Until those land, the
## clearly-labelled STUB table below keeps gameplay fully testable.

const STUB_MINING: Dictionary = {
	&"air":          {"hardness": 0.0, "tier": 0, "tool": "none",     "drop": &"",             "count": 0},
	&"ashen_soil":   {"hardness": 0.6, "tier": 0, "tool": "pickaxe",  "drop": &"dirt",          "count": 1},
	&"dirt":         {"hardness": 0.6, "tier": 0, "tool": "pickaxe",  "drop": &"dirt",          "count": 1},
	&"rotted_dirt":  {"hardness": 0.8, "tier": 0, "tool": "pickaxe",  "drop": &"dirt",          "count": 1},
	&"rotted_ashen_soil": {"hardness": 0.8, "tier": 0, "tool": "pickaxe", "drop": &"dirt",      "count": 1},
	&"hush_soil":    {"hardness": 0.9, "tier": 0, "tool": "pickaxe",  "drop": &"dirt",          "count": 1},
	&"mire_mud":     {"hardness": 0.9, "tier": 0, "tool": "pickaxe",  "drop": &"dirt",          "count": 1},
	&"toxic_silt":   {"hardness": 1.0, "tier": 0, "tool": "pickaxe",  "drop": &"dirt",          "count": 1},
	&"canyon_gravel":{"hardness": 1.2, "tier": 0, "tool": "pickaxe",  "drop": &"stone",         "count": 1},
	&"stone":        {"hardness": 1.6, "tier": 0, "tool": "pickaxe",  "drop": &"stone",         "count": 1},
	&"iron_ore":     {"hardness": 2.6, "tier": 2, "tool": "pickaxe",  "drop": &"iron_ore",      "count": 1},
	&"copper_ore":   {"hardness": 1.8, "tier": 1, "tool": "pickaxe",  "drop": &"copper_ore",    "count": 1},
	&"coal_block":   {"hardness": 1.5, "tier": 1, "tool": "pickaxe",  "drop": &"coal",          "count": 2},
	&"lumen_crystal":{"hardness": 3.2, "tier": 2, "tool": "pickaxe",  "drop": &"lumen_crystal", "count": 1},
	&"frost_snow":   {"hardness": 0.7, "tier": 0, "tool": "shovel",   "drop": &"frost_snow",    "count": 1},
	&"frost_ice":    {"hardness": 2.0, "tier": 1, "tool": "pickaxe",  "drop": &"frost_ice",     "count": 1},
	&"mycelium":     {"hardness": 0.5, "tier": 0, "tool": "none",     "drop": &"mycelium",      "count": 1},
	&"pale_bloom":   {"hardness": 0.4, "tier": 0, "tool": "none",     "drop": &"pale_bloom",    "count": 1},
	&"dead_wood":    {"hardness": 1.1, "tier": 0, "tool": "axe",      "drop": &"wood",          "count": 2},
	&"pale_wood":    {"hardness": 1.4, "tier": 1, "tool": "axe",      "drop": &"wood",          "count": 2},
	&"torch":        {"hardness": 0.1, "tier": 0, "tool": "none",     "drop": &"torch",         "count": 1},
	&"beacon":       {"hardness": 0.5, "tier": 0, "tool": "none",     "drop": &"torch",         "count": 1},
}

const BASELINE_STATIONS: Array[StringName] = [&"none", &"workbench", &"furnace", &"anvil"]

var world: Node3D


func _init(world_node: Node3D) -> void:
	world = world_node


func ready() -> bool:
	return world != null and is_instance_valid(world) and bool(world.get("is_generated"))


func inside(cell: Vector3i) -> bool:
	return world != null and world.call("_inside_world", cell)


func is_solid(cell: Vector3i) -> bool:
	return world != null and world.call("is_solid", cell)


func get_block_id(cell: Vector3i) -> int:
	return int(world.call("get_block_id", cell))


func get_block_name(cell: Vector3i) -> StringName:
	var id := get_block_id(cell)
	var defs = world.get("block_defs")
	if defs != null and id >= 0 and id < defs.size():
		return StringName(defs[id].block_id)
	return &""


func get_air_id() -> int:
	return int(world.get("air_id"))


func set_block(cell: Vector3i, block_id: int) -> bool:
	return bool(world.call("set_block", cell, block_id))


func block_id_for(block_name: StringName) -> int:
	var ids: Dictionary = world.get("block_ids")
	return int(ids.get(block_name, -1))


func get_light(cell: Vector3i) -> int:
	return int(world.call("get_light_level", cell))


func get_night(cell: Vector3i) -> float:
	return float(world.call("get_night_level", cell))


func biome_at(cell: Vector3i) -> int:
	return int(world.call("get_biome_at", cell))


func surface_height(x: int, z: int) -> int:
	return int(world.call("get_surface_height", x, z))


func spawn_origin() -> Vector2i:
	# VoxelWorld publishes a Vector3i spawn column; gameplay only needs X/Z.
	var cell: Vector3i = world.get("spawn_origin")
	return Vector2i(cell.x, cell.z)


func spawn_height() -> int:
	return int(world.call("spawn_height"))


func emit_noise(position: Vector3, strength: float) -> void:
	if world != null and world.has_method("emit_night_noise"):
		world.call("emit_night_noise", position, strength)


## Authoritative mining data comes from Agent 1's MiningSystem. The old STUB
## table is retained only as a labelled fallback for a world without it.
func mining_info(cell: Vector3i) -> Dictionary:
	if world != null:
		var def := MiningSystem.definition(world, cell)
		if def != null:
			var drop := MiningSystem.drop_for(world, cell)
			return {
				"block": def.block_id,
				"hardness": def.hardness,
				"tier": def.mining_tier,
				"drop": drop.get("block_id", &""),
				"count": drop.get("count", 1),
				"display_name": MiningSystem.display_name(world, cell),
			}
	return STUB_MINING.get(get_block_name(cell), {
		"hardness": 1.0, "tier": 0, "tool": "pickaxe", "drop": &"stone", "count": 1
	}).duplicate()


## Agent 1 endpoint: VoxelWorld.has_station(position, station) -> bool.
func has_station(station: StringName) -> bool:
	if world != null and world.has_method("has_station"):
		return bool(world.call("has_station", station))
	return BASELINE_STATIONS.has(station)
