extends Node
class_name FallingStarDirector

## Fallen Stars: per the Terraria wiki, these drop from the sky at night and
## disappear at dawn; collected, they craft Mana Crystals (5 stars = +20 max
## mana each, via ItemDatabase's &"fallen_star" / &"mana_crystal" and
## data/recipes/craft_mana_crystal.tres). This director only handles the
## falling-and-landing spectacle; collection reuses the ordinary ItemEntity
## pickup/magnet path, and crafting goes through the normal recipe book.

const FALL_SPEED := 9.0
const SPAWN_INTERVAL_MIN := 5.0
const SPAWN_INTERVAL_MAX := 11.0
const SPAWN_RADIUS := 26.0
const MAX_ACTIVE := 4

var world: VoxelWorld
var player: VoxelPlayer
var cycle: DayNightCycle
var rng := RandomNumberGenerator.new()
var spawn_timer := 0.0
var falling: Array[Node3D] = []


func _ready() -> void:
	world = get_parent().get_node("VoxelWorld") as VoxelWorld
	player = get_parent().get_node("Player") as VoxelPlayer
	cycle = get_parent().get_node("DayNightCycle") as DayNightCycle
	rng.randomize()
	spawn_timer = rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)


func _process(delta: float) -> void:
	if not world.is_generated or not player.spawned:
		return
	var is_night := cycle != null and cycle.phase_name == "night"
	if not is_night:
		# Unclaimed stars vanish at dawn, same as the real thing.
		for star in falling:
			if is_instance_valid(star):
				star.queue_free()
		falling.clear()
		spawn_timer = rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0 and falling.size() < MAX_ACTIVE:
		spawn_timer = rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
		_spawn_star()
	_update_falling(delta)


func _spawn_star() -> void:
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(4.0, SPAWN_RADIUS)
	var x := floori(player.position.x + cos(angle) * distance)
	var z := floori(player.position.z + sin(angle) * distance)
	if not world._inside_world(Vector3i(x, 0, z)):
		return
	var surface: int = world.get_surface_height(x, z)
	if not world.is_chunk_loaded_at(Vector3i(x, surface, z)):
		return
	var star := Node3D.new()
	star.name = "FallingStar"
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.98, 0.85)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.95, 0.6)
	glow.emission_energy_multiplier = 5.0
	for index in range(4):
		var spike := BoxMesh.new()
		spike.size = Vector3(0.05, 0.22, 0.05)
		var part := MeshInstance3D.new()
		part.mesh = spike
		part.material_override = glow
		part.rotation.z = PI * 0.5 * float(index) + PI * 0.25
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		star.add_child(part)
	var core := BoxMesh.new()
	core.size = Vector3(0.09, 0.09, 0.09)
	var core_instance := MeshInstance3D.new()
	core_instance.mesh = core
	core_instance.material_override = glow
	core_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.add_child(core_instance)
	star.set_meta(&"target_surface", surface)
	get_parent().add_child(star)
	star.global_position = Vector3(float(x) + 0.5, float(surface) + rng.randf_range(26.0, 40.0), float(z) + 0.5)
	falling.append(star)


func _update_falling(delta: float) -> void:
	for index in range(falling.size() - 1, -1, -1):
		var star: Node3D = falling[index]
		if not is_instance_valid(star):
			falling.remove_at(index)
			continue
		star.rotation.y += delta * 6.0
		star.position.y -= FALL_SPEED * delta
		var target_surface: float = float(star.get_meta(&"target_surface", 0))
		if star.position.y <= target_surface + 1.0:
			var landing := star.global_position
			star.queue_free()
			falling.remove_at(index)
			Vfx.burst(world, landing, Color(1.0, 0.95, 0.6), Vector3.UP, 10, 2.6, 0.05, 0.3)
			ItemEntity.spawn(get_parent(), landing + Vector3.UP * 0.3, &"fallen_star", 1)
