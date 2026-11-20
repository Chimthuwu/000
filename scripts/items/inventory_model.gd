extends RefCounted
class_name InventoryModel

## Pure gameplay state. Contains no Control nodes, no textures, no references to
## the HUD. The UI observes signals and reads slots; it never owns item identity.

signal changed
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)
signal selection_changed(index: int)
signal equipment_changed(slot: String, item_id: StringName)

const HOTBAR_SIZE := 10
const MAIN_SIZE := 40
const EQUIPMENT_SLOTS = ["head", "chest", "legs", "accessory"]
const AREA_HOTBAR := "hotbar"
const AREA_MAIN := "main"
const AREA_EQUIPMENT := "equipment"

var hotbar: Array[Dictionary] = []
var main: Array[Dictionary] = []
var equipment: Dictionary = {}
var selected := 0


func _init() -> void:
	reset()


func clear() -> void:
	reset()


func reset() -> void:
	hotbar.clear()
	main.clear()
	for _i in range(HOTBAR_SIZE):
		hotbar.append(_empty_slot())
	for _i in range(MAIN_SIZE):
		main.append(_empty_slot())
	equipment.clear()
	for slot in EQUIPMENT_SLOTS:
		equipment[slot] = _empty_slot()
	selected = 0
	changed.emit()


func _empty_slot() -> Dictionary:
	return {"id": &"", "amount": 0, "metadata": {}}


func is_empty(stack: Dictionary) -> bool:
	return StringName(stack.get("id", &"")) == &"" or int(stack.get("amount", 0)) <= 0


func stack_limit(id: StringName) -> int:
	return ItemDatabase.stack_limit(id)


## Adds as much as possible, filling matching stacks first, then empty slots.
## Returns the amount that could NOT be added.
func add_item(id: StringName, amount: int, metadata: Dictionary = {}) -> int:
	if id == &"" or amount <= 0:
		return amount
	var remaining := amount
	for area in [AREA_HOTBAR, AREA_MAIN]:
		var slots := _area(area)
		for slot in slots:
			if remaining <= 0:
				break
			if StringName(slot["id"]) != id or int(slot["amount"]) >= stack_limit(id):
				continue
			if not _metadata_equal(slot.get("metadata", {}), metadata):
				continue
			var space := stack_limit(id) - int(slot["amount"])
			var moved := mini(space, remaining)
			slot["amount"] = int(slot["amount"]) + moved
			remaining -= moved
	for area in [AREA_HOTBAR, AREA_MAIN]:
		var slots := _area(area)
		for slot in slots:
			if remaining <= 0:
				break
			if not is_empty(slot):
				continue
			var moved := mini(stack_limit(id), remaining)
			slot["id"] = id
			slot["amount"] = moved
			slot["metadata"] = metadata.duplicate(true)
			remaining -= moved
	if remaining < amount:
		item_added.emit(id, amount - remaining)
		changed.emit()
	return remaining


## Removes up to `amount`. Returns how many were actually removed.
func remove_item(id: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	var remaining := amount
	for area in [AREA_HOTBAR, AREA_MAIN]:
		var slots := _area(area)
		for slot in slots:
			if remaining <= 0:
				break
			if StringName(slot["id"]) != id:
				continue
			var taken := mini(int(slot["amount"]), remaining)
			slot["amount"] = int(slot["amount"]) - taken
			remaining -= taken
			if int(slot["amount"]) <= 0:
				_clear_slot(slot)
	var removed := amount - remaining
	if removed > 0:
		item_removed.emit(id, removed)
		changed.emit()
	return removed


func consume(id: StringName, amount: int) -> bool:
	if not has_item(id, amount):
		return false
	remove_item(id, amount)
	return true


func has_item(id: StringName, amount := 1) -> bool:
	return count(id) >= amount


func count(id: StringName) -> int:
	var total := 0
	for area in [AREA_HOTBAR, AREA_MAIN]:
		for slot in _area(area):
			if StringName(slot["id"]) == id:
				total += int(slot["amount"])
	return total


func _area(area: String) -> Array[Dictionary]:
	match area:
		AREA_HOTBAR:
			return hotbar
		AREA_MAIN:
			return main
		AREA_EQUIPMENT:
			return equipment.values()
	return []


func get_slot(area: String, index: int) -> Dictionary:
	var slots := _area(area)
	if index < 0 or index >= slots.size():
		return _empty_slot()
	return slots[index]


func set_slot(area: String, index: int, stack: Dictionary) -> void:
	var slots := _area(area)
	if index < 0 or index >= slots.size():
		return
	slots[index] = {
		"id": StringName(stack.get("id", &"")),
		"amount": clampi(int(stack.get("amount", 0)), 0, stack_limit(StringName(stack.get("id", &"")))),
		"metadata": (stack.get("metadata", {}) as Dictionary).duplicate(true)
	}
	changed.emit()


func _clear_slot(slot: Dictionary) -> void:
	slot["id"] = &""
	slot["amount"] = 0
	slot["metadata"] = {}


## Moves/swaps two slots. Same-item stacks merge up to the stack limit.
func swap_slots(area_a: String, index_a: int, area_b: String, index_b: int) -> bool:
	var a := get_slot(area_a, index_a)
	var b := get_slot(area_b, index_b)
	if a.is_empty() and b.is_empty():
		return false
	var id_a := StringName(a["id"])
	var id_b := StringName(b["id"])
	if id_a != &"" and id_a == id_b and _metadata_equal(a.get("metadata", {}), b.get("metadata", {})):
		var limit := stack_limit(id_a)
		var room := limit - int(b["amount"])
		if room > 0:
			var moved := mini(room, int(a["amount"]))
			b["amount"] = int(b["amount"]) + moved
			a["amount"] = int(a["amount"]) - moved
			if int(a["amount"]) <= 0:
				_clear_slot(a)
			changed.emit()
			return true
	set_slot(area_a, index_a, b)
	set_slot(area_b, index_b, a)
	return true


## Splits `count` items off one stack into an empty destination slot.
func split_stack(from_area: String, from_index: int, to_area: String, to_index: int, count: int) -> bool:
	if from_area == to_area and from_index == to_index:
		return false
	var source := get_slot(from_area, from_index)
	var destination := get_slot(to_area, to_index)
	if is_empty(source) or not is_empty(destination) or count <= 0:
		return false
	var available := int(source["amount"])
	var moved := mini(count, available - 1)
	if moved <= 0:
		return false
	source["amount"] = available - moved
	set_slot(to_area, to_index, {
		"id": source["id"], "amount": moved,
		"metadata": (source.get("metadata", {}) as Dictionary).duplicate(true)
	})
	changed.emit()
	return true


func select(index: int) -> void:
	var next := clampi(index, 0, HOTBAR_SIZE - 1)
	if next == selected:
		return
	selected = next
	selection_changed.emit(selected)
	changed.emit()


func cycle_selection(direction: int) -> void:
	select(posmod(selected + direction, HOTBAR_SIZE))


func selected_slot() -> Dictionary:
	return hotbar[selected]


func held_item() -> StringName:
	return StringName(hotbar[selected]["id"])


func equip(slot: String, area: String, index: int) -> bool:
	if not equipment.has(slot):
		return false
	var item_id := StringName(get_slot(area, index)["id"])
	if item_id == &"":
		return false
	var def := ItemDatabase.get_item(item_id)
	if def == null or def.equipment_slot != slot:
		return false
	var previous: Dictionary = equipment[slot].duplicate(true)
	equipment[slot] = get_slot(area, index).duplicate(true)
	_clear_slot(get_slot(area, index))
	if not is_empty(previous):
		add_item(StringName(previous["id"]), int(previous["amount"]), previous.get("metadata", {}))
	equipment_changed.emit(slot, item_id)
	changed.emit()
	return true


func unequip(slot: String) -> Dictionary:
	if not equipment.has(slot) or is_empty(equipment[slot]):
		return {}
	var stack: Dictionary = equipment[slot].duplicate(true)
	equipment[slot] = _empty_slot()
	add_item(StringName(stack["id"]), int(stack["amount"]), stack.get("metadata", {}))
	equipment_changed.emit(slot, &"")
	changed.emit()
	return stack


func total_armor() -> int:
	var total := 0
	for slot in ["head", "chest", "legs"]:
		var stack: Dictionary = equipment.get(slot, {})
		var def := ItemDatabase.get_item(StringName(stack.get("id", &"")))
		if def != null:
			total += def.armor
	return total


## All equipped defence, including accessory bonuses. Used by damage calc.
func total_defense() -> int:
	var total := 0
	for slot in EQUIPMENT_SLOTS:
		var def := ItemDatabase.get_item(StringName(equipment.get(slot, {}).get("id", &"")))
		if def != null:
			total += def.armor + def.defense_bonus
	return total


func bonus_mining_speed() -> float:
	return _sum_bonus("mining_speed_bonus")


func bonus_move_speed() -> float:
	return _sum_bonus("move_speed_bonus")


func bonus_max_health() -> float:
	return _sum_bonus("max_health_bonus")


func _sum_bonus(property: String) -> float:
	var total := 0.0
	for slot in EQUIPMENT_SLOTS:
		var def := ItemDatabase.get_item(StringName(equipment.get(slot, {}).get("id", &"")))
		if def != null:
			total += float(def.get(property))
	return total


func _metadata_equal(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)


func serialize() -> Dictionary:
	var saved_equipment := {}
	for slot in EQUIPMENT_SLOTS:
		saved_equipment[slot] = _write_stack(equipment.get(slot, {}))
	return {
		"hotbar": _write_area(hotbar),
		"main": _write_area(main),
		"equipment": saved_equipment,
		"selected": selected,
	}


func _write_area(slots: Array[Dictionary]) -> Array:
	var result: Array = []
	for slot in slots:
		result.append(_write_stack(slot))
	return result


func _write_stack(slot: Dictionary) -> Dictionary:
	return {
		"id": String(slot.get("id", &"")),
		"amount": int(slot.get("amount", 0)),
		"metadata": slot.get("metadata", {})
	}


func deserialize(data: Dictionary) -> bool:
	if not data is Dictionary or not data.has("hotbar"):
		return false
	reset()
	_read_area(data.get("hotbar", []), hotbar)
	_read_area(data.get("main", []), main)
	var saved_equipment: Dictionary = data.get("equipment", {})
	for slot in EQUIPMENT_SLOTS:
		if saved_equipment.has(slot):
			equipment[slot] = _read_stack(saved_equipment[slot])
	selected = clampi(int(data.get("selected", 0)), 0, HOTBAR_SIZE - 1)
	changed.emit()
	return true


func _read_area(saved: Array, target: Array[Dictionary]) -> void:
	for index in range(mini(saved.size(), target.size())):
		target[index] = _read_stack(saved[index])


func _read_stack(saved: Variant) -> Dictionary:
	if not saved is Dictionary:
		return _empty_slot()
	var id := StringName(String(saved.get("id", "")))
	if id == &"" or not ItemDatabase.has(id):
		return _empty_slot()
	var metadata: Variant = saved.get("metadata", {})
	return {
		"id": id,
		"amount": clampi(int(saved.get("amount", 0)), 0, stack_limit(id)),
		"metadata": metadata if metadata is Dictionary else {}
	}
