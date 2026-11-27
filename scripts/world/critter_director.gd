extends Node
class_name CritterDirector

## Ambient overworld wildlife, independent of EnemyDirector's night-only
## monster population: bunnies spawn on the surface in daylight or dark alike,
## in a small fixed number, and never compete with the real spawn budget.

const BunnyScript = preload("res://scripts/enemies/bunny.gd")

const SPAWN_TICK_SECONDS := 2.5
const MAX_ACTIVE := 10
# A 22-unit max let bunnies spawn behind trees/hills with no sightline to the
# player, so they existed but were practically never seen. Narrowing the band
# keeps spawns close enough to land in or near view in typical terrain.
const MIN_SPAWN_DISTANCE := 6.0
const MAX_SPAWN_DISTANCE := 14.0

var world: VoxelWorld
var player: VoxelPlayer
var spawn_timer := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	world = get_parent().get_node("VoxelWorld") as VoxelWorld
	player = get_parent().get_node("Player") as VoxelPlayer
	rng.randomize()


func _process(delta: float) -> void:
	if not world.is_generated or not player.spawned:
		return
	spawn_timer += delta
	if spawn_timer < SPAWN_TICK_SECONDS:
		return
	spawn_timer = 0.0
	_try_spawn()


func _try_spawn() -> void:
	var critters := get_tree().get_nodes_in_group("critters")
	if critters.size() >= MAX_ACTIVE:
		return
	for attempt in range(6):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
		var x := floori(player.position.x + cos(angle) * distance)
		var z := floori(player.position.z + sin(angle) * distance)
		if not world._inside_world(Vector3i(x, 0, z)):
			continue
		var floor_y: int = world.get_surface_height(x, z)
		if not world.is_chunk_loaded_at(Vector3i(x, floor_y, z)):
			continue
		var spawn := Vector3(x + 0.5, floor_y + 1.05, z + 0.5)
		var headroom_clear := true
		for level in range(1, 3):
			if world.get_block_id(Vector3i(x, floor_y + level, z)) != world.air_id:
				headroom_clear = false
				break
		if not headroom_clear:
			continue
		var bunny: Bunny = BunnyScript.new()
		bunny.position = spawn
		get_parent().add_child(bunny)
		return
