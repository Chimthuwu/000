extends Node3D
class_name ItemEntity

## A dropped item in the world. Self-contained: drifts toward the player, then
## deposits itself into the player's inventory. Spawned by mining, loot and
## inventory drops. The visual is a pair of crossed, icon-textured quads (the
## same art as the hotbar), so a pile of logs on the ground actually reads as
## logs instead of an anonymous tinted cube.

const GROUP := "item_drops"
const PICKUP_DELAY := 0.45
const PICKUP_RADIUS := 1.25
const MAGNET_RADIUS := 3.0

var item_id: StringName = &""
var amount := 0
var age := 0.0
var _visual: MeshInstance3D
var _player: Node3D


static func spawn(parent: Node, position: Vector3, id: StringName, count: int) -> ItemEntity:
	if parent == null or id == &"" or count <= 0:
		return null
	var scene := preload("res://scenes/gameplay/item_entity.tscn")
	var entity := scene.instantiate() as ItemEntity
	entity.item_id = id
	entity.amount = count
	parent.add_child(entity)
	entity.global_position = position
	return entity


func _ready() -> void:
	add_to_group(GROUP)
	_visual = get_node_or_null("Visual") as MeshInstance3D
	_apply_visual()


func _apply_visual() -> void:
	if _visual == null:
		return
	_visual.mesh = null
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.35
	material.albedo_texture = ItemIcons.icon_for(item_id)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	for angle in [0.0, PI * 0.5]:
		var part := MeshInstance3D.new()
		part.mesh = quad
		part.material_override = material
		part.rotation.y = angle
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(part)


func _process(delta: float) -> void:
	age += delta
	if _visual != null:
		_visual.rotation.y += delta * 2.2
		_visual.position.y = 0.28 + sin(age * 3.4) * 0.06
	if age < PICKUP_DELAY:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	var to_player: Vector3 = _player.global_position - global_position
	var distance := to_player.length()
	if distance <= MAGNET_RADIUS and distance > 0.001:
		global_position += to_player.normalized() * minf(distance, 7.0 * delta)
	if distance <= PICKUP_RADIUS:
		_collect()


func _collect() -> void:
	var inventory: InventoryModel = _player.get("inventory") as InventoryModel
	if inventory == null:
		return
	var leftover := inventory.add_item(item_id, amount)
	if leftover <= 0:
		Sfx.pickup(get_parent(), global_position)
		queue_free()
	else:
		amount = leftover
		age = PICKUP_DELAY - 0.1
