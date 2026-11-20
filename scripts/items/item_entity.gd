extends Node3D
class_name ItemEntity

## A dropped item in the world. Self-contained: drifts toward the player, then
## deposits itself into the player's inventory. Spawned by mining, loot and
## inventory drops. Purely gameplay logic; the visual is a tiny coloured cube.

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
	var def := ItemDatabase.get_item(item_id)
	var tint := Color(0.85, 0.85, 0.85)
	if def != null:
		var rarities := [
			Color(0.86, 0.87, 0.84), Color(0.42, 0.86, 0.46), Color(0.36, 0.62, 1.0),
			Color(0.78, 0.42, 0.96), Color(1.0, 0.72, 0.24)
		]
		tint = rarities[clampi(def.rarity, 0, rarities.size() - 1)]
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.7
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visual.material_override = material


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
		queue_free()
	else:
		amount = leftover
		age = PICKUP_DELAY - 0.1
