extends NightEnemy
class_name Zombie

## A shambling ground attacker built from the voxel zombie meshes under
## art/models/zombie/ (three palette variants) instead of a procedural body —
## the blocky voxel look already matches this game's own art style. A plain
## melee chaser: no special ability, just more health and bite than a Nightling.

const MESHES := [
	preload("res://art/models/zombie/zombie1/zombie1.obj"),
	preload("res://art/models/zombie/zombie2/zombie2.obj"),
	preload("res://art/models/zombie/zombie3/zombie3.obj"),
]
# The source voxel model is ~20 voxels tall; scaled down it stands about as
# tall as the player.
const MODEL_SCALE := 0.095

var visual_root: Node3D
var bob_time := 0.0


func _init() -> void:
	body_half_extents = Vector3(0.34, 0.92, 0.34)
	attack_range = 1.35


## The source mesh is one rigid T-pose with no skeleton, so there is no real
## leg-cycle to play. This fakes a shamble instead: a forward lean while
## chasing, plus an exaggerated side-to-side stagger and lurching bob, so the
## whole body reads as stumbling forward rather than sliding across the
## ground frozen in place.
func _process(delta: float) -> void:
	super._process(delta)
	if visual_root == null:
		return
	var stride := 1.0 if wish_direction.length_squared() > 0.01 else 0.0
	bob_time += delta * (1.0 if stride > 0.0 else 0.4)
	var stagger := sin(bob_time * 5.0)
	visual_root.rotation.x = lerp(visual_root.rotation.x, deg_to_rad(10.0) * stride, 0.12)
	visual_root.rotation.z = stagger * deg_to_rad(9.0) * stride
	visual_root.position.y = absf(sin(bob_time * 10.0)) * 0.05 * stride


func _create_placeholder_mesh() -> void:
	visual_root = Node3D.new()
	visual_root.name = "Visual"
	add_child(visual_root)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Model"
	var mesh: Mesh = MESHES[randi() % MESHES.size()]
	mesh_instance.mesh = mesh
	mesh_instance.scale = Vector3.ONE * MODEL_SCALE
	# The voxel export's arms-out T-pose sits centred on the origin; lift it so
	# the feet (not the hips) touch the ground this enemy's body box stands on.
	mesh_instance.position = Vector3(0.0, 0.0, 0.0)
	mesh_instance.rotation.y = PI
	visual_root.add_child(mesh_instance)
	_make_visible_in_the_dark(mesh_instance, mesh)


## The OBJ importer bakes the voxel palette into a normally-lit material,
## which this game's night lighting renders almost black — every other enemy
## here is unshaded with emission so it reads against the dark instead. Swap
## in an unshaded copy of the same texture, with a little glow added, rather
## than leaving the zombie invisible at the exact time it is meant to spawn.
func _make_visible_in_the_dark(mesh_instance: MeshInstance3D, mesh: Mesh) -> void:
	for surface in range(mesh.get_surface_count()):
		var source := mesh.surface_get_material(surface) as StandardMaterial3D
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if source != null:
			material.albedo_texture = source.albedo_texture
			material.albedo_color = source.albedo_color
		material.emission_enabled = true
		material.emission_texture = material.albedo_texture
		material.emission = Color(1.0, 1.0, 1.0)
		material.emission_energy_multiplier = 0.55
		mesh_instance.set_surface_override_material(surface, material)
