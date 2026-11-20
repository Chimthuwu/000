extends Node3D
class_name GameProjectile

## Generic projectile for ranged / magic / thrown weapons. Walks a short
## substepped path against the voxel grid so fast shots cannot tunnel, and
## applies damage + knockback to the first enemies it meets (pierce permitting).

var gateway: WorldGateway
var owner_node: Node3D
var attack: AttackDef
var velocity := Vector3.ZERO
var lifetime := 3.0
var pierce_left := 0
var _hit_enemies: Dictionary = {}
var _visual: MeshInstance3D


static func spawn(parent: Node, start: Vector3, direction: Vector3,
		attack_def: AttackDef, gw: WorldGateway, source: Node3D) -> GameProjectile:
	var scene := preload("res://scenes/gameplay/projectile.tscn")
	var shot := scene.instantiate() as GameProjectile
	shot.attack = attack_def
	shot.gateway = gw
	shot.owner_node = source
	shot.velocity = direction.normalized() * attack_def.projectile_speed
	shot.lifetime = attack_def.projectile_lifetime
	shot.pierce_left = attack_def.pierce
	parent.add_child(shot)
	shot.global_position = start
	shot._apply_visual()
	return shot


func _ready() -> void:
	add_to_group("projectiles")


func _apply_visual() -> void:
	_visual = get_node_or_null("Visual") as MeshInstance3D
	if _visual == null or attack == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = attack.accent_color
	material.emission_enabled = true
	material.emission = attack.accent_color
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visual.material_override = material


func _process(delta: float) -> void:
	if attack == null or gateway == null:
		queue_free()
		return
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var sub := delta / float(steps)
	for _i in range(steps):
		velocity.y -= attack.projectile_gravity * sub
		var next := global_position + velocity * sub
		var cell := Vector3i(floori(next.x), floori(next.y), floori(next.z))
		if gateway.inside(cell) and gateway.is_solid(cell):
			_impact(next, -velocity.normalized())
			return
		global_position = next
		if _check_enemies():
			return


func _check_enemies() -> bool:
	for candidate in get_tree().get_nodes_in_group("enemies"):
		var enemy := candidate as Node3D
		if enemy == null or not is_instance_valid(enemy) or enemy == owner_node:
			continue
		if _hit_enemies.has(enemy.get_instance_id()):
			continue
		if enemy.global_position.distance_to(global_position) > 0.75:
			continue
		_hit_enemies[enemy.get_instance_id()] = true
		if enemy.has_method("apply_damage"):
			enemy.call("apply_damage", attack.damage, attack.knockback, global_position, owner_node)
		Vfx.burst(get_parent(), global_position, attack.accent_color, velocity.normalized(), 10, 4.0, 0.05, 0.3)
		if pierce_left <= 0:
			queue_free()
			return true
		pierce_left -= 1
	return false


func _impact(point: Vector3, normal: Vector3) -> void:
	Vfx.burst(get_parent(), point, attack.accent_color, normal, 8, 3.5, 0.05, 0.3)
	queue_free()
