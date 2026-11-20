extends GloomEnemy
class_name HollowWarden

## Agent 2 boss: The Hollow Warden (reserved enemy kind 99). Three readable
## phases with telegraphed attacks. Content-agnostic: it can be summoned into
## any arena through EnemyDirector.spawn_boss(room_id).

signal phase_changed(phase: int)

const BOLT: AttackDef = preload("res://data/bosses/warden_bolt.tres")
const SLAM_ITEM: ItemDef = preload("res://data/items/iron_sword.tres")

@export var slam_radius := 3.4
@export var slam_damage := 22.0
@export var telegraph_seconds := 0.9

var phase := 1
var state := "idle"
var state_time := 0.0
var _gateway: WorldGateway
var _slam_attack: AttackDef


func _ready() -> void:
	max_health = 900.0
	move_speed = 2.6
	touch_damage = 14.0
	attack_range = 2.4
	attack_interval = 1.6
	dissolve_light_level = 99
	body_half_extents = Vector3(0.62, 1.2, 0.62)
	health = max_health * difficulty_scale
	loot_table = preload("res://data/bosses/hollow_warden.tres").loot_table
	_gateway = WorldGateway.new(world)
	_slam_attack = SLAM_ITEM.attack
	_create_boss_mesh()


func _create_boss_mesh() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 2.4, 1.3)
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.10, 0.22)
	material.emission_enabled = true
	material.emission = Color(0.62, 0.12, 0.54)
	material.emission_energy_multiplier = 1.6
	mesh.material_override = material
	mesh.position.y = 1.2
	add_child(mesh)


func _update_behavior(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var to_player: Vector3 = player.position - position
	var distance := to_player.length()
	if state == "idle":
		wish_direction = to_player.normalized() if distance > attack_range * 1.4 else Vector3.ZERO
		look_at(Vector3(player.position.x, position.y, player.position.z), Vector3.UP)
		state_time -= _delta
		if state_time <= 0.0:
			state = "telegraph"
			state_time = telegraph_seconds * (0.7 if phase == 3 else 1.0)
			_set_telegraph(true)
	elif state == "telegraph":
		wish_direction = Vector3.ZERO
		state_time -= _delta
		if state_time <= 0.0:
			_set_telegraph(false)
			_execute_attack(distance)
			state = "recover"
			state_time = 1.1 if phase < 3 else 0.7
	else:
		wish_direction = Vector3.ZERO
		state_time -= _delta
		if state_time <= 0.0:
			state = "idle"
			state_time = 0.4


func _set_telegraph(on: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var material := child.material_override as StandardMaterial3D
			if material != null:
				material.emission_energy_multiplier = 5.0 if on else 1.6


func _execute_attack(distance: float) -> void:
	# Phase 1: melee slam. Phase 2+: bolt volley. Phase 3: both.
	if distance <= slam_radius or phase == 1:
		_slam()
	if phase >= 2:
		_fire_volley(2 if phase == 2 else 3)


func _slam() -> void:
	if not is_instance_valid(player) or player.global_position.distance_to(global_position) > slam_radius:
		return
	player.call("take_damage", slam_damage * (1.0 + 0.25 * float(phase - 1)))
	Vfx.burst(world, global_position + Vector3.UP * 0.5, Color(0.92, 0.35, 0.72), Vector3.UP, 22, 7.0, 0.08, 0.45)


func _fire_volley(count: int) -> void:
	if _gateway == null or not is_instance_valid(player):
		return
	var origin := global_position + Vector3.UP * 1.5
	var base_dir: Vector3 = (player.global_position + Vector3.UP - origin).normalized()
	for index in range(count):
		var spread := (float(index) - float(count - 1) * 0.5) * 0.16
		var direction := base_dir.rotated(Vector3.UP, spread)
		GameProjectile.spawn(world, origin, direction, BOLT, _gateway, self)


func apply_damage(amount: float, knockback := 0.0, from_position := Vector3.ZERO, source: Node = null) -> void:
	if health <= 0.0:
		return
	var previous := phase
	# Bosses resist knockback; telegraphs stay readable.
	super.apply_damage(amount, knockback * 0.15, from_position, source)
	var ratio := health / max_health
	phase = 1 if ratio > 0.66 else (2 if ratio > 0.33 else 3)
	if phase != previous:
		phase_changed.emit(phase)
		state = "telegraph"
		state_time = 0.6
