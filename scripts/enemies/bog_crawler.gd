extends LampEater
class_name BogCrawler

# The Mire variant of the Lamp Eater: the same lantern-hunting brain, but the
# stilt-legged silhouette is crushed down into a flat carapace that scuttles
# across the mud. Physically it slips through gaps a standing LampEater could
# not, and visually it never rises above the fog line.

const BOG_SHELL := Color(0.16, 0.26, 0.10)
const BOG_RIM := Color(0.42, 0.55, 0.22)
const SQUASH_Y := 0.42
const SPREAD := Vector3(1.18, 1.0, 1.10)
const SPIT_RANGE := 9.0
const SPIT_COOLDOWN := 2.6
const CONTACT_DRAIN := 6.0

var spit_cooldown := 0.0


func _init() -> void:
	# Small enough to squeeze under one-block ledges while chasing the player.
	body_half_extents = Vector3(0.34, 0.28, 0.34)


# The Mire crawler abandoned light-hunting: it closes on the player and spits
# toxin that eats their Lumen reserve, leaving the health bar intact but the
# lamp defenceless.
func _update_behavior(delta: float) -> void:
	spit_cooldown = maxf(0.0, spit_cooldown - delta)
	var target := player.position
	var flat := target - position
	flat.y = 0.0
	var distance := flat.length()
	if distance > 0.01:
		wish_direction = flat.normalized()
		look_at(Vector3(target.x, position.y, target.z), Vector3.UP)
	else:
		wish_direction = Vector3.ZERO
	if distance <= SPIT_RANGE and spit_cooldown <= 0.0 and _clear_shot():
		_spit(target)
		spit_cooldown = SPIT_COOLDOWN


func _clear_shot() -> bool:
	var from := global_position + Vector3.UP * 0.35
	var to := player.position + Vector3.UP * 0.9
	var offset := to - from
	var distance := offset.length()
	var steps := ceili(distance / 0.35)
	for step in range(1, steps):
		var point := from + offset * (float(step) / float(steps))
		var cell := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if world._inside_world(cell) and world.get_block_id(cell) != world.air_id:
			return false
	return true


func _spit(target: Vector3) -> void:
	var projectile := ToxicProjectile.new()
	projectile.world = world
	projectile.player = player
	get_parent().add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * 0.5
	var aim := target + Vector3.UP * 0.9 - projectile.global_position
	var distance := maxf(aim.length(), 0.001)
	# A mild upward lob keeps the arc readable at the 854x480 internal res.
	projectile.velocity = aim.normalized() * ToxicProjectile.SPEED + Vector3.UP * (distance * 0.35)


func on_hit_player() -> void:
	var caster := player.get_node_or_null("Lumencaster") as Lumencaster
	if caster != null:
		caster.reserve = maxf(0.0, caster.reserve - CONTACT_DRAIN)


func _create_placeholder_mesh() -> void:
	super._create_placeholder_mesh()
	for child in get_children():
		if not child is MeshInstance3D:
			continue
		child.position = Vector3(child.position.x * SPREAD.x, child.position.y * SQUASH_Y + 0.16, child.position.z * SPREAD.z)
		child.scale = Vector3(SPREAD.x, SQUASH_Y + 0.5, SPREAD.z)
		var material := child.material_override as StandardMaterial3D
		if material == null:
			continue
		if material.emission_energy_multiplier >= 3.0:
			# The lantern glow turns sickly swamp-green.
			material.emission = Color(0.35, 0.75, 0.18)
			material.albedo_color = Color(0.85, 1.0, 0.35)
		else:
			material.albedo_color = material.albedo_color.lerp(BOG_SHELL, 0.55)
			if material.emission_enabled:
				material.emission = material.emission.lerp(BOG_RIM.darkened(0.5), 0.45)
