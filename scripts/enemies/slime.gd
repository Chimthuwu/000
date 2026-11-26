extends NightEnemy
class_name Slime

## The classic gelatinous hopper: small, common in every biome, and the first
## real threat a new player meets. Built entirely from primitive meshes (no
## texture dependency), so it needs no art asset of its own. Unlike the
## dissolve-in-light nocturnal enemies it does not fear the sun — once spawned
## it keeps hopping around the clock, the way Terraria's slimes do.

const SKIN_GREEN := 0
const SKIN_PURPLE := 1
const SKIN_BLUE := 2
const SKIN_GOLD := 3

## Bright, flat, saturated — the classic Terraria slime palette, not a muted
## "RPG gelatinous cube" tone.
const BODY_COLORS := [
	Color(0.29, 0.80, 0.20),
	Color(0.62, 0.28, 0.86),
	Color(0.30, 0.62, 0.95),
	Color(0.95, 0.80, 0.18),
]
const EYE_COLOR := Color(0.03, 0.03, 0.04)

var visual_root: Node3D
var body_material: StandardMaterial3D
var eye_material: StandardMaterial3D
var skin := SKIN_GREEN
var hop_impulse := 4.8
var hop_interval := 0.82
var hop_cooldown := 0.0
var wobble_time := 0.0


func _init() -> void:
	body_half_extents = Vector3(0.38, 0.40, 0.38)
	attack_range = 1.25
	attack_interval = 1.1


func _ready() -> void:
	super._ready()
	_apply_skin()


func _process(delta: float) -> void:
	super._process(delta)
	if visual_root == null:
		return
	wobble_time += delta
	var airborne := minf(absf(velocity.y), 6.0)
	var stretch := 1.0 + airborne * 0.035
	var squash := 1.0 - airborne * 0.025
	var idle := 1.0 + sin(wobble_time * 3.0) * 0.012
	visual_root.scale = Vector3(stretch * idle, squash, stretch * idle)
	visual_root.position.y = 0.01 + sin(wobble_time * 2.2) * 0.008


func _update_behavior(delta: float) -> void:
	hop_cooldown = maxf(0.0, hop_cooldown - delta)
	super._update_behavior(delta)
	# The vertical hop is the slime's signature. It still chases continuously in
	# the air, so the hop changes the silhouette rather than stopping the pursuit.
	if on_floor and hop_cooldown <= 0.0 and velocity.y <= 0.1:
		velocity.y = hop_impulse
		hop_cooldown = hop_interval


func configure_skin(new_skin: int) -> void:
	skin = clampi(new_skin, SKIN_GREEN, SKIN_GOLD)
	if body_material != null:
		_apply_skin()


func _apply_skin() -> void:
	if body_material == null:
		return
	var body_color: Color = BODY_COLORS[skin]
	body_material.albedo_color = body_color
	body_material.emission = body_color
	body_material.emission_energy_multiplier = 0.45


## One smooth, bright, unshaded blob — a single colour, not a banded body and
## a differently-shaded "base" lobe. Terraria's slime reads instantly because
## its silhouette and colour are both that simple.
func _create_placeholder_mesh() -> void:
	visual_root = Node3D.new()
	visual_root.name = "Visual"
	add_child(visual_root)

	body_material = _make_material(BODY_COLORS[SKIN_GREEN], BODY_COLORS[SKIN_GREEN], 0.45)
	eye_material = _make_material(EYE_COLOR, EYE_COLOR, 0.0)

	# A teardrop silhouette: a wide, squashed lower sphere and a smaller, rounder
	# upper sphere of the exact same material, overlapping enough to read as one
	# continuous blob rather than two stacked balls.
	var lower := SphereMesh.new()
	lower.radius = 0.50
	lower.height = 0.62
	lower.radial_segments = 16
	lower.rings = 8
	var lower_instance := MeshInstance3D.new()
	lower_instance.name = "Lower"
	lower_instance.mesh = lower
	lower_instance.material_override = body_material
	lower_instance.position = Vector3(0.0, 0.26, 0.0)
	lower_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(lower_instance)

	var upper := SphereMesh.new()
	upper.radius = 0.38
	upper.height = 0.66
	upper.radial_segments = 16
	upper.rings = 8
	var upper_instance := MeshInstance3D.new()
	upper_instance.name = "Upper"
	upper_instance.mesh = upper
	upper_instance.material_override = body_material
	upper_instance.position = Vector3(0.0, 0.52, 0.0)
	upper_instance.scale = Vector3(1.0, 0.82, 1.0)
	upper_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(upper_instance)

	# The face sits on the -Z surface (look_at faces -Z). Two plain black ovals,
	# no glint or mouth — Terraria's slime face is just the eyes.
	for side in [-1.0, 1.0]:
		_add_part("Eye", Vector3(0.11, 0.15, 0.05), Vector3(side * 0.145, 0.50, -0.42), Vector3.ZERO, eye_material)


func _make_material(color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material


func _add_part(node_name: String, size: Vector3, offset: Vector3, part_rotation: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = box
	instance.material_override = material
	instance.position = offset
	instance.rotation = part_rotation
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(instance)
