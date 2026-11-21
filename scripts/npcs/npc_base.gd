extends Node3D
class_name NpcBase

# Agent 3 — NPC presentation/interaction foundation.
# Gameplay state (quests, shops, housing) is owned by Agent 2; this node only
# renders the NPC and exposes an interaction hook so the presentation layer
# (dialogue panel, portraits, shop UI) can react without duplicating state.

signal interacted(npc: NpcBase)

@export var npc_name: String = "Stranger"
@export var display_name: String = ""
@export var dialogue_lines: PackedStringArray = PackedStringArray(["..."])
@export var interaction_radius: float = 2.5
# Merchant / quest hooks (Agent 2 publishes data; Agent 3 renders).
@export var shop_items: Array[StringName] = []
@export var quest_id: StringName = &""
var progression: ProgressionSystem = null

func setup(prog: ProgressionSystem) -> void:
	progression = prog

var _current_line: int = 0
var _player: Node = null

@onready var label: Label3D = null

func _ready() -> void:
	add_to_group("npcs")
	add_to_group("npc")
	# Build a tiny diegetic nameplate so NPCs read as characters, not cubes.
	var plate := Label3D.new()
	plate.text = npc_name
	plate.font_size = 24
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.position = Vector3(0, 2.0, 0)
	plate.modulate = Color(0.92, 0.98, 0.95)
	add_child(plate)
	label = plate

	_build_body()


## Blocky humanoid in the same pixel-art language as the player: boots, trousers,
## a belted tunic with a vest, bare arms, a head and a wide-brimmed hat. The
## palette follows the role so the Guide reads as the Terraria Guide (brown hat,
## cream shirt, green vest) instead of a grey capsule.
func _build_body() -> void:
	var role_name := npc_name.to_lower()
	var hat_color := Color(0.42, 0.28, 0.14)
	var shirt_color := Color(0.88, 0.85, 0.75)
	var vest_color := Color(0.24, 0.38, 0.26)
	var trouser_color := Color(0.30, 0.26, 0.34)
	if role_name.contains("merchant"):
		hat_color = Color(0.30, 0.22, 0.34)
		shirt_color = Color(0.80, 0.72, 0.56)
		vest_color = Color(0.44, 0.24, 0.20)
	var skin := Color(0.86, 0.68, 0.52)

	_part(Vector3(0.17, 0.58, 0.19), Vector3(-0.11, 0.29, 0.0), trouser_color)
	_part(Vector3(0.17, 0.58, 0.19), Vector3(0.11, 0.29, 0.0), trouser_color)
	_part(Vector3(0.20, 0.09, 0.22), Vector3(-0.11, 0.045, 0.02), Color(0.20, 0.15, 0.12))
	_part(Vector3(0.20, 0.09, 0.22), Vector3(0.11, 0.045, 0.02), Color(0.20, 0.15, 0.12))
	_part(Vector3(0.50, 0.56, 0.30), Vector3(0.0, 0.88, 0.0), shirt_color)
	_part(Vector3(0.34, 0.40, 0.32), Vector3(0.0, 0.90, 0.0), vest_color)
	_part(Vector3(0.52, 0.10, 0.32), Vector3(0.0, 0.63, 0.0), Color(0.26, 0.18, 0.12))
	_part(Vector3(0.13, 0.44, 0.15), Vector3(-0.31, 0.90, 0.0), shirt_color)
	_part(Vector3(0.13, 0.44, 0.15), Vector3(0.31, 0.90, 0.0), shirt_color)
	_part(Vector3(0.12, 0.12, 0.14), Vector3(-0.31, 0.62, 0.0), skin)
	_part(Vector3(0.12, 0.12, 0.14), Vector3(0.31, 0.62, 0.0), skin)
	_part(Vector3(0.34, 0.34, 0.32), Vector3(0.0, 1.32, 0.0), skin)
	# Eyes: two small dark blocks so the face has a direction.
	_part(Vector3(0.055, 0.055, 0.03), Vector3(-0.075, 1.36, 0.165), Color(0.16, 0.14, 0.13))
	_part(Vector3(0.055, 0.055, 0.03), Vector3(0.075, 1.36, 0.165), Color(0.16, 0.14, 0.13))
	_part(Vector3(0.58, 0.07, 0.58), Vector3(0.0, 1.51, 0.0), hat_color)
	_part(Vector3(0.32, 0.20, 0.32), Vector3(0.0, 1.62, 0.0), hat_color.darkened(0.12))


func _part(size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = offset
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.metallic_specular = 0.1
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.20
	mesh_instance.material_override = material
	add_child(mesh_instance)

func interact(player_node: Node) -> void:
	_player = player_node
	emit_signal("interacted", self)

func get_dialogue_line() -> String:
	if dialogue_lines.is_empty():
		return ""
	return dialogue_lines[_current_line % dialogue_lines.size()]

func advance_dialogue() -> bool:
	_current_line += 1
	if _current_line >= dialogue_lines.size():
		_current_line = 0
		return false
	return true

func reset_dialogue() -> void:
	_current_line = 0

func is_player_near(player_pos: Vector3) -> bool:
	return global_position.distance_to(player_pos) <= interaction_radius
