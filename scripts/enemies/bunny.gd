extends NightEnemy
class_name Bunny

## Harmless overworld wildlife, the way Terraria's world is never just
## monsters: it hops around at random, bolts when the player gets close, and
## never deals or takes story-relevant damage. Reuses NightEnemy purely for
## its proven ground movement/collision sweep; touch_damage stays at 0 so it
## is not a threat, and it never dissolves, so it is a daytime-safe critter.

const FLEE_RADIUS := 5.0
const WANDER_SPEED := 1.6
const FLEE_SPEED := 4.2

var visual_root: Node3D
var ear_left: MeshInstance3D
var ear_right: MeshInstance3D
var hop_cooldown := 0.0
var wander_direction := Vector3.ZERO
var hop_impulse := 3.2
var bob_time := 0.0


func _init() -> void:
	body_half_extents = Vector3(0.18, 0.18, 0.18)
	max_health = 4.0
	touch_damage = 0.0
	attack_range = 0.0
	move_speed = WANDER_SPEED


## Not part of the night spawner's population: it would otherwise eat into
## EnemyConfig.max_active_enemies and get bucketed with real monsters.
func _ready() -> void:
	super._ready()
	remove_from_group("enemies")
	add_to_group("critters")


func _process(delta: float) -> void:
	super._process(delta)
	if visual_root == null:
		return
	bob_time += delta
	var hopping := absf(velocity.y) > 0.2
	visual_root.scale = Vector3(1.0, 1.0 if not hopping else 0.82, 1.0)
	if ear_left != null:
		var flick := sin(bob_time * 9.0) * 0.08
		ear_left.rotation.x = flick
		ear_right.rotation.x = -flick


func _update_behavior(delta: float) -> void:
	hop_cooldown = maxf(0.0, hop_cooldown - delta)
	var away := position - player.position
	away.y = 0.0
	var distance := away.length()
	if distance < FLEE_RADIUS:
		move_speed = FLEE_SPEED
		wish_direction = away.normalized() if distance > 0.01 else Vector3.FORWARD
		if wish_direction.length_squared() > 0.0001:
			look_at(position - wish_direction, Vector3.UP)
		if on_floor and hop_cooldown <= 0.0:
			velocity.y = hop_impulse * 0.8
			hop_cooldown = 0.35
		return
	move_speed = WANDER_SPEED
	if on_floor and hop_cooldown <= 0.0:
		if wander_direction == Vector3.ZERO or randf() < 0.3:
			var angle := randf_range(0.0, TAU)
			wander_direction = Vector3(cos(angle), 0.0, sin(angle))
		if randf() < 0.55:
			wish_direction = wander_direction
			velocity.y = hop_impulse
			if wish_direction.length_squared() > 0.0001:
				look_at(position - wish_direction, Vector3.UP)
		else:
			wish_direction = Vector3.ZERO
		hop_cooldown = randf_range(0.6, 1.6)
	elif not on_floor:
		wish_direction = wander_direction
	else:
		wish_direction = Vector3.ZERO


## Never fled from light, and its loot_table stays null, so NightEnemy's own
## death handling drops nothing — there is no reason to fight a bunny.
func _should_dissolve(_cell: Vector3i) -> bool:
	return false


func _create_placeholder_mesh() -> void:
	visual_root = Node3D.new()
	visual_root.name = "Visual"
	add_child(visual_root)

	var fur := _make_material(Color(0.86, 0.80, 0.70))
	var fur_dark := _make_material(Color(0.62, 0.54, 0.46))

	var body := SphereMesh.new()
	body.radius = 0.16
	body.height = 0.30
	body.radial_segments = 10
	body.rings = 6
	var body_instance := MeshInstance3D.new()
	body_instance.name = "Body"
	body_instance.mesh = body
	body_instance.material_override = fur
	body_instance.position = Vector3(0.0, 0.16, 0.0)
	body_instance.scale = Vector3(1.0, 0.85, 1.25)
	body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(body_instance)

	var head := SphereMesh.new()
	head.radius = 0.10
	head.height = 0.19
	head.radial_segments = 10
	head.rings = 6
	var head_instance := MeshInstance3D.new()
	head_instance.name = "Head"
	head_instance.mesh = head
	head_instance.material_override = fur
	head_instance.position = Vector3(0.0, 0.22, -0.16)
	head_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(head_instance)

	var tail := SphereMesh.new()
	tail.radius = 0.05
	tail.height = 0.09
	tail.radial_segments = 8
	tail.rings = 4
	var tail_instance := MeshInstance3D.new()
	tail_instance.name = "Tail"
	tail_instance.mesh = tail
	tail_instance.material_override = _make_material(Color(0.96, 0.95, 0.92))
	tail_instance.position = Vector3(0.0, 0.17, 0.17)
	tail_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(tail_instance)

	ear_left = _add_ear(-1.0, fur_dark)
	ear_right = _add_ear(1.0, fur_dark)


func _add_ear(side: float, material: Material) -> MeshInstance3D:
	var ear := BoxMesh.new()
	ear.size = Vector3(0.035, 0.16, 0.03)
	var instance := MeshInstance3D.new()
	instance.name = "Ear"
	instance.mesh = ear
	instance.material_override = material
	instance.position = Vector3(side * 0.045, 0.33, -0.17)
	instance.rotation = Vector3(0.0, 0.0, side * 0.15)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(instance)
	return instance


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.25
	return material
