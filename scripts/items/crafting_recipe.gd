extends Resource
class_name CraftingRecipe

## Data-driven recipe. Ingredient/output keys are ItemDef ids (StringName).

@export var recipe_id: StringName = &""
@export var display_name: String = ""
@export_enum("none", "workbench", "furnace", "anvil") var station: String = "none"
@export var ingredients: Dictionary = {}
@export var outputs: Dictionary = {}
@export var required_flag: StringName = &""
@export_range(1, 9999, 1) var yield_count: int = 1

func output_id() -> StringName:
	for key in outputs.keys():
		return StringName(key)
	return &""

func output_amount() -> int:
	var id := output_id()
	return int(outputs.get(id, yield_count)) if id != &"" else 0
