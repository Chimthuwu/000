extends Node3D
class_name HeldItemViewmodel

## First-person held item. Terraria always shows what you are holding, and that
## is how a player knows an axe is an axe before swinging it. Tools and weapons
## are built from the same blocky boxes as the avatar so they match the world;
## everything else (blocks, potions, materials) becomes the item's own icon on a
## small card, which keeps the hotbar art and the hand art identical.

const TOOL_WOOD := Color(0.46, 0.32, 0.20)
const TOOL_WOOD_DARK := Color(0.30, 0.20, 0.12)
const BLADE := Color(0.72, 0.76, 0.80)
const GUARD := Color(0.44, 0.30, 0.18)
const TORCH_STICK := Color(0.42, 0.30, 0.18)
const FLAME := Color(1.0, 0.68, 0.24)

var item_id: StringName = &""
var display_name := ""
var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3.ZERO
var _swing := 0.0
var _clock := 0.0
var _model: Node3D
var _icon_material: StandardMaterial3D
var _first_person := false


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	_build_icon_material()
	set_item(&"")


## Rebuilds the hand model for the newly selected hotbar item. Cheap because it
## only runs on selection change, never per frame.
func set_item(id: StringName) -> void:
	if id == item_id and (_model != null or id == &""):
		return
	item_id = id
	if _model != null:
		_model.queue_free()
		_model = null
	var def := ItemDatabase.get_item(id)
	if def != null:
		_model = Node3D.new()
		_model.name = "Model"
		add_child(_model)
		_build_model(def)
	_update_visibility()


## The hand is a first-person object; third person shows the avatar instead.
func set_first_person(on: bool) -> void:
	_first_person = on
	_update_visibility()


func _update_visibility() -> void:
	visible = _first_person and _model != null


func _build_model(def: ItemDef) -> void:
	if def.is_tool and def.tool_type == "axe":
		_build_axe(def)
	elif def.is_tool and def.tool_type == "pickaxe":
		_build_pickaxe(def)
	elif def.is_weapon:
		_build_sword(def)
	elif def.item_id == &"torch":
		_build_torch()
	else:
		_build_card(def)


# --- Tools ------------------------------------------------------------------

func _build_axe(def: ItemDef) -> void:
	var metal := _tier_color(def.tool_tier)
	# Handle angled across the hand, the way a hand actually grips a haft.
	_box(Vector3(0.052, 0.52, 0.052), Vector3(0.0, -0.02, 0.0), TOOL_WOOD, Vector3(0.0, 0.0, 0.06))
	_box(Vector3(0.058, 0.10, 0.058), Vector3(-0.014, -0.26, 0.0), TOOL_WOOD_DARK, Vector3(0.0, 0.0, 0.06))
	# Head: a wedge hanging off the top of the haft, edge facing away from you.
	_box(Vector3(0.040, 0.150, 0.055), Vector3(0.018, 0.215, -0.055), metal, Vector3(0.10, 0.0, 0.0))
	_box(Vector3(0.052, 0.190, 0.030), Vector3(0.020, 0.245, -0.140), metal, Vector3(0.24, 0.0, 0.0))
	_box(Vector3(0.030, 0.200, 0.014), Vector3(0.020, 0.248, -0.163), metal.lightened(0.35), Vector3(0.24, 0.0, 0.0))
	_box(Vector3(0.050, 0.048, 0.060), Vector3(0.016, 0.200, 0.006), metal.darkened(0.25))


func _build_pickaxe(def: ItemDef) -> void:
	var metal := _tier_color(def.tool_tier)
	_box(Vector3(0.052, 0.52, 0.052), Vector3(0.0, -0.02, 0.0), TOOL_WOOD, Vector3(0.0, 0.0, 0.06))
	_box(Vector3(0.058, 0.10, 0.058), Vector3(-0.014, -0.26, 0.0), TOOL_WOOD_DARK, Vector3(0.0, 0.0, 0.06))
	# A curved head: three boxes crossing the haft with the tips angled down.
	_box(Vector3(0.150, 0.046, 0.048), Vector3(0.010, 0.215, 0.0), metal)
	_box(Vector3(0.120, 0.040, 0.040), Vector3(-0.115, 0.196, 0.0), metal, Vector3(0.0, 0.0, 0.42))
	_box(Vector3(0.120, 0.040, 0.040), Vector3(0.135, 0.196, 0.0), metal, Vector3(0.0, 0.0, -0.42))
	_box(Vector3(0.070, 0.026, 0.034), Vector3(-0.175, 0.150, 0.0), metal.lightened(0.30), Vector3(0.0, 0.0, 0.42))
	_box(Vector3(0.070, 0.026, 0.034), Vector3(0.195, 0.150, 0.0), metal.lightened(0.30), Vector3(0.0, 0.0, -0.42))


func _build_sword(def: ItemDef) -> void:
	var metal := _tier_color(def.tool_tier) if def.tool_tier > 0 else BLADE
	_box(Vector3(0.050, 0.130, 0.048), Vector3(0.0, -0.02, 0.0), GUARD)
	_box(Vector3(0.055, 0.030, 0.058), Vector3(0.0, 0.050, 0.0), metal.darkened(0.35))
	_box(Vector3(0.185, 0.030, 0.050), Vector3(0.0, 0.075, 0.0), metal.darkened(0.15))
	# Blade, with a lighter fuller so it reads as an edge rather than a plank.
	_box(Vector3(0.052, 0.420, 0.016), Vector3(0.0, 0.300, 0.0), metal)
	_box(Vector3(0.014, 0.400, 0.020), Vector3(0.0, 0.298, -0.002), metal.lightened(0.40))
	_box(Vector3(0.036, 0.060, 0.016), Vector3(0.0, 0.540, 0.0), metal.lightened(0.20))


func _build_torch() -> void:
	_box(Vector3(0.038, 0.300, 0.038), Vector3(0.0, -0.04, 0.0), TORCH_STICK)
	_box(Vector3(0.072, 0.090, 0.072), Vector3(0.0, 0.156, 0.0), FLAME.lightened(0.25), Vector3.ZERO, 2.6)
	_box(Vector3(0.044, 0.060, 0.044), Vector3(0.0, 0.216, 0.0), FLAME, Vector3.ZERO, 3.4)


# --- Everything else: the item's own hotbar icon on a card -------------------

func _build_card(def: ItemDef) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.21, 0.21)
	var part := MeshInstance3D.new()
	part.name = "Card"
	part.mesh = quad
	_icon_material.albedo_texture = ItemIcons.icon_for(def.item_id)
	part.material_override = _icon_material
	part.position = Vector3(0.0, 0.06, 0.0)
	part.rotation = Vector3(0.0, -0.45, 0.10)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(part)
	# A small dark plinth under the card so it does not float in empty space.
	_box(Vector3(0.11, 0.026, 0.08), Vector3(0.0, -0.070, 0.008), TOOL_WOOD_DARK)


func _build_icon_material() -> void:
	_icon_material = StandardMaterial3D.new()
	# Unshaded so the icons keep their art colours instead of being tinted by
	# whatever the local light happens to be in a cave.
	_icon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_icon_material.alpha_scissor_threshold = 0.35
	_icon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_icon_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


# --- Animation ---------------------------------------------------------------

## Called every frame. `active` is true while the player is mining or swinging,
## which drives a chop that loops until the button is released.
func tick(delta: float, active: bool) -> void:
	if active:
		_clock = fmod(_clock + delta * 7.5, TAU)
		_swing = 0.5 - 0.5 * cos(_clock)
	else:
		_swing = maxf(0.0, _swing - delta * 7.0)
		_clock = 0.0
	rotation = _rest_rotation + Vector3(-0.95 * _swing, 0.30 * _swing, 0.22 * _swing)
	position = _rest_position + Vector3(-0.07 * _swing, 0.05 * _swing, -0.14 * _swing)


# --- Build helpers -----------------------------------------------------------

func _box(size: Vector3, at: Vector3, color: Color, box_rotation := Vector3.ZERO, glow := 0.16) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.metallic = 0.0
	# The hand has to stay readable under the deep canopy and in caves, the same
	# way the avatar does.
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.rotation = box_rotation
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(part)
	return part


## Tier colours come from the same palette the hotbar icons use, so a copper axe
## in hand and a copper axe in the hotbar are the same metal.
func _tier_color(tier: int) -> Color:
	return ItemIcons._metal_color(tier)
