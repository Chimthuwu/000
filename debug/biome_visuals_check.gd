extends SceneTree

# Low-poly biome props, fog palettes, blizzard and Mire bubbles.

const COMPLETE := "BIOME VISUALS CHECK PASS: claw trees, fungi, ice spires, roots, blizzard and bubbles"

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("VISUAL PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("VISUAL FAIL: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	while not main.world.is_generated or not main.player.spawned:
		await process_frame
	var world: VoxelWorld = main.world
	var vegetation: WorldVegetation = world.vegetation

	_check(vegetation.hush_instances.size() == WorldVegetation.HUSH_ARCHETYPES, "Hushwoods claw-tree batches exist")
	_check(vegetation.mushroom_instance != null and vegetation.spire_instance != null and vegetation.root_instance != null, "fungi, spire and root batches exist")

	var hush := BiomeManager.find_biome_center(BiomeManager.HUSH, world.world_seed, 64, 64)
	var frost := BiomeManager.find_biome_center(BiomeManager.FROST, world.world_seed, 64, 64)
	var mire := BiomeManager.find_biome_center(BiomeManager.MIRE, world.world_seed, 64, 64)
	var hush_sites := WorldGenerator.collect_hush_sites_region(world.world_seed, hush.x - 72, hush.y - 72, hush.x + 72, hush.y + 72)
	var frost_sites := WorldGenerator.collect_frost_sites_region(world.world_seed, frost.x - 72, frost.y - 72, frost.x + 72, frost.y + 72)
	var root_sites := WorldGenerator.collect_mire_root_sites_region(world.world_seed, mire.x - 72, mire.y - 72, mire.x + 72, mire.y + 72)
	_check(hush_sites.size() > 20, "dense Hushwoods tree sites", "sites=%d" % hush_sites.size())
	_check(frost_sites.size() > 5, "Frostfall ice spire sites", "sites=%d" % frost_sites.size())
	_check(root_sites.size() > 5, "Mire root sites", "sites=%d" % root_sites.size())

	vegetation._build_biome_props(world.world_seed, hush, 72)
	var hush_instances := 0
	for multimesh in vegetation.hush_multimeshes:
		hush_instances += multimesh.instance_count
	_check(hush_instances > 0 and vegetation.mushroom_instance.multimesh.instance_count > 0, "Hushwoods MultiMeshes populate", "trees=%d fungi=%d" % [hush_instances, vegetation.mushroom_instance.multimesh.instance_count])
	vegetation._build_biome_props(world.world_seed, frost, 72)
	_check(vegetation.spire_instance.multimesh.instance_count > 0, "ice spires populate")
	vegetation._build_biome_props(world.world_seed, mire, 72)
	_check(vegetation.root_instance.multimesh.instance_count > 0, "swamp roots populate")

	_check(VoxelWorld.BIOME_FOG_SCALE[BiomeManager.HUSH] >= 3.0, "Hushwoods fog is claustrophobic")
	_check(VoxelWorld.BIOME_FOG_SCALE[BiomeManager.MIRE] >= 3.0 and VoxelWorld.BIOME_FOG_TINT[BiomeManager.MIRE].g > VoxelWorld.BIOME_FOG_TINT[BiomeManager.MIRE].r, "Mire fog is thick and green")
	_check(VoxelWorld.BIOME_FOG_TINT[BiomeManager.FROST].b >= 0.95, "Frostfall fog is pale freezing white")

	var blizzard: GPUParticles3D = main.get_node("Player/Camera3D/Blizzard")
	_check(blizzard != null, "blizzard particles attached to the camera")
	main.player.respawn_at(Vector3(float(frost.x) + 0.5, float(world.get_surface_height(frost.x, frost.y)) + 1.0, float(frost.y) + 0.5))
	await process_frame
	_check(blizzard.emitting, "blizzard emits inside Frostfall")
	main.player.respawn_at(Vector3(float(hush.x) + 0.5, float(world.get_surface_height(hush.x, hush.y)) + 1.0, float(hush.y) + 0.5))
	await process_frame
	_check(not blizzard.emitting, "blizzard stops outside Frostfall")

	_check(world.water.get_node_or_null("ToxicBubbles") is GPUParticles3D, "Mire puddles have bubble particles")

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
