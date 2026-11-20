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

	# A simple body marker (placeholder capsule) so the NPC is visible.
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	body.mesh = capsule
	body.position = Vector3(0, 0.8, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.86, 0.78)
	mat.roughness = 0.8
	body.material_override = mat
	add_child(body)

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
