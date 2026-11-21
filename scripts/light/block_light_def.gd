class_name BlockLightDef
extends Resource

@export var block_id: StringName
@export_range(1, 15, 1) var attenuation: int = 1
@export var albedo: Color = Color.WHITE

@export_range(0, 15, 1) var emitted_light: int = 0

@export var rotted_variant_id: StringName = &""
@export var is_rotted := false

# --- Mining / gameplay metadata (World Systems ownership) -------------------
# Data-driven so every block can describe how it is broken and what it yields.
# Defaults preserve the pre-existing behaviour: any block is breakable with any
# tool, drops one of itself.
@export var display_name: String = ""
@export_range(0.0, 100.0, 0.1) var hardness: float = 1.0
@export_range(0, 10, 1) var mining_tier: int = 0
@export var drop_block_id: StringName = &""
@export_range(0, 64, 1) var drop_count: int = 1
@export var is_solid_block: bool = true

# --- Furniture / station metadata -------------------------------------------
# Terraria furniture is placed inside a tile you can walk through, so these
# blocks keep normal mining rules (they still drop themselves) but report no
# collision. `station` names the crafting station this block provides when the
# player stands near it; "none" means it is plain furniture.
@export_enum("none", "workbench", "furnace", "anvil") var station: String = "none"
@export var passable: bool = false

# Seating for NPC housing: a room needs a chair and a table (any workbench)
# before a resident will move in, exactly like Terraria's house rules.
@export var seating: bool = false
