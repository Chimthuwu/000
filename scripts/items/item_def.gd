extends Resource
class_name ItemDef

## Central, data-driven item identity. The inventory stores only the StringName
## `item_id`; all presentation and behaviour comes from this resource.

enum Category { MATERIAL, TOOL, WEAPON, ARMOR, CONSUMABLE, BLOCK, QUEST, ACCESSORY }

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var category: Category = Category.MATERIAL
@export_range(1, 9999, 1) var stack_limit: int = 99
@export_range(0, 4, 1) var rarity: int = 0
@export_range(0, 1000000, 1) var value: int = 1
@export_enum("none", "head", "chest", "legs", "accessory") var equipment_slot: String = "none"

# --- Tool properties ---
@export var is_tool: bool = false
@export_enum("none", "pickaxe", "axe", "hammer", "shovel") var tool_type: String = "none"
@export_range(0, 6, 1) var tool_tier: int = 0
@export_range(0.0, 100.0, 0.1) var mining_power: float = 1.0
@export_range(0.0, 100.0, 0.1) var mining_speed: float = 1.0
@export var effective_blocks: Array[StringName] = []
@export_range(0, 100000, 1) var durability: int = 0

# --- Weapon properties ---
@export var is_weapon: bool = false
@export var attack: AttackDef = null

# --- Consumable properties ---
@export var is_consumable: bool = false
@export_range(0.0, 1000.0, 1.0) var heal_amount: float = 0.0
@export_range(0.0, 1000.0, 1.0) var mana_restore: float = 0.0
@export var applies_status: StringName = &""
@export_range(0.0, 300.0, 0.5) var status_duration: float = 0.0

# --- Block placement / armour / crafting ---
@export var place_block: StringName = &""
@export_range(0, 100, 1) var armor: int = 0
# Accessory / equipment bonuses. These change real gameplay statistics.
@export_range(0, 100, 1) var defense_bonus: int = 0
@export_range(0.0, 5.0, 0.05) var mining_speed_bonus: float = 0.0
@export_range(0.0, 5.0, 0.05) var move_speed_bonus: float = 0.0
@export_range(0.0, 500.0, 5.0) var max_health_bonus: float = 0.0
@export var is_ingredient: bool = true

func tier_name() -> String:
	var names := ["Wood", "Copper", "Iron", "Silver", "Gold", "Adamantite"]
	return names[clampi(tool_tier, 0, names.size() - 1)]
