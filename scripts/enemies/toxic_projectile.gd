extends Node3D
class_name ToxicProjectile

# Bog Crawler spittle. A small projectile with voxel collision that
# drains the player's Arcane reserve instead of dealing health damage.

const SPEED := 13.0
const GRAVITY := 14.0
const LIFETIME := 3.0
const DRAIN := 14.0
const HIT_RADIUS := 0.85

var world: VoxelWorld
var player: VoxelPlayer
var velocity := Vector3.ZERO
var life := LIFETIME


func _ready() -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	sphere.radial_segments = 8
	sphere.rings = 4
	orb.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.95, 0.22)
	material.emission_enabled = true
	material.emission = Color(0.42, 0.9, 0.14)
	material.emission_energy_multiplier = 4.0
	orb.material_override = material
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(player):
		queue_free()
		return
	life -= delta
	if life <= 0.0:
		_expire()
		return
	velocity.y -= GRAVITY * delta
	var step_dt := delta / 3.0
	for _i in range(3):
		var next := global_position + velocity * step_dt
		var cell := Vector3i(floori(next.x), floori(next.y), floori(next.z))
		if world._inside_world(cell) and world.get_block_id(cell) != world.air_id:
			_expire()
			return
		if player.position.distance_to(next) < HIT_RADIUS:
			_hit_player()
			return
		global_position = next


func _hit_player() -> void:
	var caster := player.get_node_or_null("ArcaneCaster") as ArcaneCaster
	if caster != null:
		caster.reserve = maxf(0.0, caster.reserve - DRAIN)
		caster._set_status("TOXIC SPIT — MANA -%d" % int(DRAIN))
	Vfx.burst(get_parent() as Node3D, global_position, Color(0.42, 0.9, 0.14), Vector3.UP, 16, 3.0, 0.05, 0.4, 0.8)
	queue_free()


func _expire() -> void:
	Vfx.burst(get_parent() as Node3D, global_position, Color(0.3, 0.6, 0.12), Vector3.UP, 10, 2.0, 0.05, 0.3, 0.4)
	queue_free()
