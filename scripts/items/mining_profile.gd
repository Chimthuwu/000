extends Resource
class_name MiningProfile

## Block mining data. Agent 1 may replace this by implementing
## VoxelWorld.get_mining_info(cell); the WorldGateway prefers that endpoint.
## Block name -> {"hardness": float, "tier": int, "tool": StringName,
##                "drop": StringName, "count": int}

@export var profile: Dictionary = {}

func info(block_name: StringName) -> Dictionary:
	if profile.has(block_name):
		return profile[block_name]
	return {"hardness": 1.0, "tier": 0, "tool": "pickaxe", "drop": &"stone", "count": 1}
