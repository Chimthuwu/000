extends Resource
class_name NpcProfile

## Agent 2 gameplay data for an NPC role. Agent 3 renders NpcBase + dialogue.

@export var npc_id: StringName = &""
@export var display_name: String = ""
@export_enum("guide", "merchant", "nurse", "settler") var role: String = "settler"
@export var shop_items: Array[StringName] = []
@export var required_flag: StringName = &""
@export var housing_flag: StringName = &""
@export var dialogue_id: StringName = &""
