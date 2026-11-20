extends Resource
class_name QuestDef

## Agent 2 NPC quest data. Agent 3 presents dialogue; this is only the state.

@export var quest_id: StringName = &""
@export var display_name: String = ""
@export var required_items: Dictionary = {}
@export var rewards: Dictionary = {}
@export var unlock_flag: StringName = &""
@export var dialogue_id: StringName = &""
