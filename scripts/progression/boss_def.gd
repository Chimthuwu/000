extends Resource
class_name BossDef

## Data-only boss framework. A boss is unlocked by flags, fought in a world
## condition, and on victory grants flags and loot. No boss AI is defined here;
## an arena/encounter script consumes this definition when Agent 1/3 are ready.

@export var boss_id: StringName = &""
@export var display_name: String = ""
@export var required_flags: Array[StringName] = []
@export var unlock_flags: Array[StringName] = []
@export var loot_table: LootTable = null
@export var arena_condition: String = ""
@export var encounter_scene: String = ""
