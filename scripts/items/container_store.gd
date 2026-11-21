extends RefCounted
class_name ContainerStore

## Per-cell storage for chests. Terraria chests hold 20 stacks and live in the
## world, not in the player, so the store is keyed by the chest's voxel cell.
## Only occupied slots are serialized; breaking a chest drops its contents
## (the player owns that behaviour) and clears the cell here.

const SLOTS := 20

var containers: Dictionary = {}


func slots(cell: Vector3i) -> Array[Dictionary]:
	if not containers.has(cell):
		var created: Array[Dictionary] = []
		for _index in range(SLOTS):
			created.append(_empty())
		containers[cell] = created
	return containers[cell]


func _empty() -> Dictionary:
	return {"id": &"", "amount": 0, "metadata": {}}


func total(cell: Vector3i) -> int:
	var count := 0
	for slot in slots(cell):
		count += int(slot.get("amount", 0))
	return count


func has_items(cell: Vector3i) -> bool:
	return total(cell) > 0


## Stacks as much of `id` as fits. Returns the amount that did not fit.
func deposit(cell: Vector3i, id: StringName, amount: int, metadata: Dictionary = {}) -> int:
	if id == &"" or amount <= 0:
		return amount
	var remaining := amount
	var limit := ItemDatabase.stack_limit(id)
	var stacks := slots(cell)
	for slot in stacks:
		if remaining <= 0:
			break
		if StringName(slot["id"]) != id or int(slot["amount"]) >= limit:
			continue
		var moved: int = mini(limit - int(slot["amount"]), remaining)
		slot["amount"] = int(slot["amount"]) + moved
		remaining -= moved
	for slot in stacks:
		if remaining <= 0:
			break
		if StringName(slot["id"]) != &"" and int(slot["amount"]) > 0:
			continue
		var moved: int = mini(limit, remaining)
		slot["id"] = id
		slot["amount"] = moved
		slot["metadata"] = metadata.duplicate(true)
		remaining -= moved
	return remaining


## Removes up to `amount` from one slot and returns what was taken, as a real
## inventory stack ({id, amount, metadata}) or an empty dictionary.
func take(cell: Vector3i, index: int, amount: int) -> Dictionary:
	var stacks := slots(cell)
	if index < 0 or index >= stacks.size() or amount <= 0:
		return {}
	var slot: Dictionary = stacks[index]
	var id := StringName(slot.get("id", &""))
	var held := int(slot.get("amount", 0))
	if id == &"" or held <= 0:
		return {}
	var moved: int = mini(held, amount)
	slot["amount"] = held - moved
	var taken := {"id": id, "amount": moved, "metadata": slot.get("metadata", {}).duplicate(true)}
	if int(slot["amount"]) <= 0:
		stacks[index] = _empty()
	return taken


## Breaks a chest: hands back everything it held and forgets the cell.
func empty_into(cell: Vector3i) -> Array[Dictionary]:
	var contents: Array[Dictionary] = []
	for index in range(slots(cell).size()):
		var stack: Dictionary = slots(cell)[index]
		if StringName(stack.get("id", &"")) != &"" and int(stack.get("amount", 0)) > 0:
			contents.append(stack.duplicate(true))
	containers.erase(cell)
	return contents


# --- Persistence -------------------------------------------------------------

func serialize() -> Dictionary:
	var cells: Array = []
	for cell: Vector3i in containers.keys():
		var stack_array: Array = []
		for slot in slots(cell):
			var id := StringName(slot.get("id", &""))
			var amount := int(slot.get("amount", 0))
			if id == &"" or amount <= 0:
				continue
			stack_array.append({"id": String(id), "amount": amount})
		if stack_array.is_empty():
			continue
		cells.append({"cell": [cell.x, cell.y, cell.z], "slots": stack_array})
	return {"cells": cells}


func deserialize(data: Dictionary) -> bool:
	containers.clear()
	var cells: Array = data.get("cells", [])
	for entry_variant in cells:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var coords: Array = entry.get("cell", [])
		if coords.size() != 3:
			continue
		var cell := Vector3i(int(coords[0]), int(coords[1]), int(coords[2]))
		var stacks := slots(cell)
		var saved: Array = entry.get("slots", [])
		for index in range(saved.size()):
			if index >= stacks.size() or not saved[index] is Dictionary:
				continue
			var saved_stack: Dictionary = saved[index]
			var id := StringName(saved_stack.get("id", ""))
			var amount := int(saved_stack.get("amount", 0))
			if id == &"" or amount <= 0:
				continue
			stacks[index] = {"id": id, "amount": amount, "metadata": {}}
	return true
