extends SceneTree

# Proves the Underworld is a generated world region, not a renamed layer:
# ashen rock, a lava sea, obsidian crust, hellstone and a distinct layer id.
#   Godot --headless --path Terraria3D --script res://debug/underworld_check.gd

const SEED := 139732

var failures := 0
var ids: Dictionary = {}
var names: Dictionary = {}


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("UNDERWORLD FAIL: %s %s" % [label, detail])
		return
	print("UNDERWORLD PASS: %s %s" % [label, detail])


func _initialize() -> void:
	for path in VoxelWorld.BLOCK_RESOURCE_PATHS:
		var definition := load(path) as BlockLightDef
		if definition != null:
			names[ids.size()] = definition.block_id
			ids[definition.block_id] = ids.size()
	_check_layers()
	_check_biomes()
	_check_generation()
	if failures > 0:
		quit(1)
		return
	print("UNDERWORLD CHECK PASS")
	quit(0)


func _check_layers() -> void:
	var surface := BiomeManager.get_height(64, 64)
	_check(WorldLayers.layer_at(surface - 170, surface) == WorldLayers.Layer.UNDERWORLD,
		"deep layer resolves to Underworld", "surface=%d" % surface)
	_check(WorldLayers.layer_name(WorldLayers.Layer.UNDERWORLD) == "The Underworld", "layer is named The Underworld")
	_check(WorldLayers.UNDERWORLD_DEPTH > WorldLayers.CAVERN_DEPTH, "Underworld sits below the caverns",
		"%d > %d" % [WorldLayers.UNDERWORLD_DEPTH, WorldLayers.CAVERN_DEPTH])


func _check_biomes() -> void:
	BiomeManager.configure(SEED)
	var surface := BiomeManager.get_height(64, 64)
	var underground := WorldBiomes.underground_biome_at(64, surface - 180, 64, surface, BiomeManager.surface_biome(64, 64))
	_check(underground == WorldBiomes.Underground.UNDERWORLD, "classification is Underworld", str(underground))
	_check(WorldBiomes.stone_name(underground, 180) == &"ash", "Underworld rock is ash")
	_check(WorldBiomes.enemy_tag(underground) == &"underworld", "Underworld has its own enemy tag")
	_check(WorldBiomes.biome_name(underground) == "The Underworld", "Underworld has its own name")


func _check_generation() -> void:
	var generator = load("res://scripts/world/world_generator.gd")
	var totals := {&"ash": 0, &"lava": 0, &"obsidian": 0, &"hellstone": 0, &"air": 0}
	var lava_below_floor := 0
	var non_air_below_floor := 0
	var deterministic := true
	var origin_samples := 0
	for cx in range(4, 12):
		for cz in range(4, 9):
			for cy in [0, 1]:
				var origin := Vector3i(cx * 16, cy * 16, cz * 16)
				var blocks: PackedByteArray = generator.generate_chunk(Vector3i(cx, cy, cz), SEED, ids)
				var again: PackedByteArray = generator.generate_chunk(Vector3i(cx, cy, cz), SEED, ids)
				if blocks != again:
					deterministic = false
				origin_samples += 1
				for index in range(blocks.size()):
					var block_id := int(blocks[index])
					var block_name: StringName = names.get(block_id, &"")
					if totals.has(block_name):
						totals[block_name] += 1
					var world_y := origin.y + (index / 16) % 16
					if world_y <= 19:
						non_air_below_floor += 1
						if block_name == &"lava":
							lava_below_floor += 1
	_check(deterministic, "deep generation is deterministic", "%d chunks" % origin_samples)
	_check(int(totals[&"ash"]) > 2000, "ash rock fills the Underworld", "ash=%d" % int(totals[&"ash"]))
	_check(int(totals[&"lava"]) > 1000, "lava sea is generated", "lava=%d" % int(totals[&"lava"]))
	_check(int(totals[&"obsidian"]) > 20, "obsidian crust is generated", "obsidian=%d" % int(totals[&"obsidian"]))
	_check(int(totals[&"hellstone"]) > 10, "hellstone deposits are generated", "hellstone=%d" % int(totals[&"hellstone"]))
	var lava_ratio := float(lava_below_floor) / float(maxi(non_air_below_floor, 1))
	_check(lava_ratio > 0.85, "the floor is a continuous lava sea", "ratio=%.2f" % lava_ratio)

