extends GPUParticles3D
class_name Blizzard

# Camera-attached snow and wind. Only emits inside Frostfall, so the rest of
# the world keeps its clean silhouette and the particle budget stays bounded.

var world: VoxelWorld
var player: VoxelPlayer


func _ready() -> void:
	world = get_parent().get_parent().get_parent().get_node("VoxelWorld") as VoxelWorld
	player = get_parent().get_parent() as VoxelPlayer
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(11.0, 7.0, 11.0)
	process.direction = Vector3(-0.65, -0.35, 0.18)
	process.spread = 12.0
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.initial_velocity_min = 9.0
	process.initial_velocity_max = 15.0
	process.scale_min = 0.03
	process.scale_max = 0.09
	process.color = Color(0.92, 0.97, 1.0, 0.85)
	self.process_material = process
	self.lifetime = 2.4
	amount = 320
	visibility_aabb = AABB(Vector3(-14.0, -10.0, -14.0), Vector3(28.0, 20.0, 28.0))
	local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.94, 0.98, 1.0, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	self.draw_pass_1 = quad
	emitting = false


func _process(_delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	var cell := Vector3i(floori(player.position.x), 0, floori(player.position.z))
	emitting = world.get_biome_at(cell) == BiomeManager.FROST
