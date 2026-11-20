extends RefCounted
class_name MiningSystem

# World-owned block interaction API. Gameplay, UI and combat code should call
# these instead of reaching into world.set_block directly, so the rules for
# "what is breakable, with which tool, and what drops" live in one place and
# the block data stays authoritative.
#
# Query:   raycast / definition / display_name / hardness / mining_tier
# Rules:   can_mine
# Mutate:  break_block (returns drop) / place_block

const RAY_STEP := 0.05
const NO_CELL := Vector3i(-1000000, -1000000, -1000000)


# Voxel DDA-ish raymarch. Returns {} on a miss, else:
#   cell, previous_air, face_normal, point, distance
static func raycast(world, origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var dir := direction.normalized()
	var last := NO_CELL
	var steps := ceili(max_distance / RAY_STEP)
	for step_index in range(1, steps + 1):
		var distance := float(step_index) * RAY_STEP
		var point := origin + dir * distance
		var cell := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if not world._inside_world(cell):
			return {}
		if world.get_block_id(cell) != world.air_id:
			var normal := Vector3i.ZERO
			if last != NO_CELL:
				normal = last - cell
			return {
				"cell": cell,
				"previous_air": last,
				"face_normal": normal,
				"point": point,
				"distance": distance,
			}
		last = cell
	return {}


static func definition(world, cell: Vector3i) -> BlockLightDef:
	var block_id: int = world.get_block_id(cell)
	if block_id < 0 or block_id >= world.block_defs.size():
		return null
	return world.block_defs[block_id]


static func display_name(world, cell: Vector3i) -> String:
	var def := definition(world, cell)
	if def == null:
		return ""
	if def.display_name != "":
		return def.display_name
	return String(def.block_id).capitalize()


static func hardness(world, cell: Vector3i) -> float:
	var def := definition(world, cell)
	return maxf(0.05, def.hardness) if def != null else 0.05


static func mining_tier(world, cell: Vector3i) -> int:
	var def := definition(world, cell)
	return def.mining_tier if def != null else 0


static func can_mine(world, cell: Vector3i, tool_tier: int) -> bool:
	var block_id: int = world.get_block_id(cell)
	if block_id == world.air_id:
		return false
	return tool_tier >= mining_tier(world, cell)


# Drop descriptor for the block currently at cell: {block_id: StringName, count: int}
# Liquids and explicit drop_count = 0 yield nothing.
static func drop_for(world, cell: Vector3i) -> Dictionary:
	var def := definition(world, cell)
	if def == null:
		return {}
	if not def.is_solid_block or def.drop_count <= 0:
		return {}
	var drop_id: StringName = def.drop_block_id
	if drop_id == &"":
		drop_id = def.block_id
	return {"block_id": drop_id, "count": maxi(1, def.drop_count)}


static func is_liquid(world, cell: Vector3i) -> bool:
	var def := definition(world, cell)
	return def != null and not def.is_solid_block


# A liquid cell can be replaced by a placed block; air can always be filled.
static func is_replaceable(world, cell: Vector3i) -> bool:
	var block_id: int = world.get_block_id(cell)
	if block_id == world.air_id:
		return true
	var def := definition(world, cell)
	return def != null and not def.is_solid_block


static func can_place(world, cell: Vector3i, block_id_name: StringName) -> bool:
	if not world._inside_world(cell):
		return false
	if not world.block_ids.has(block_id_name):
		return false
	return is_replaceable(world, cell)


# Break a block if the tool tier allows it. Returns:
#   {"mined": true,  "drop": {block_id, count}}
#   {"mined": false, "blocked": true}   when the tier is too low
#   {"mined": false}                    otherwise
static func break_block(world, cell: Vector3i, tool_tier: int) -> Dictionary:
	if not world._inside_world(cell):
		return {"mined": false}
	if not can_mine(world, cell, tool_tier):
		return {"mined": false, "blocked": true, "tier": mining_tier(world, cell)}
	var def := definition(world, cell)
	var drop := drop_for(world, cell)
	if not world.set_block(cell, world.air_id):
		return {"mined": false}
	return {
		"mined": true,
		"drop": drop,
		"block_id": def.block_id if def != null else &"",
		"display_name": display_name(world, cell) if def != null else "",
		"hardness": hardness(world, cell),
	}


static func place_block(world, cell: Vector3i, block_id_name: StringName) -> bool:
	if not can_place(world, cell, block_id_name):
		return false
	var block_id: int = int(world.block_ids.get(block_id_name, -1))
	return world.set_block(cell, block_id)
