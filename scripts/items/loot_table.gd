extends Resource
class_name LootTable

## Enemy drops. Each entry: {"item": StringName, "min": int, "max": int,
## "chance": float}. Guaranteed entries use chance = 1.0.

@export var table_id: StringName = &""
@export var entries: Array[Dictionary] = []

func roll(rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = {}
	for entry in entries:
		var chance := float(entry.get("chance", 1.0))
		if chance < 1.0 and rng.randf() >= chance:
			continue
		var item_id := StringName(entry.get("item", &""))
		if item_id == &"":
			continue
		var low := maxi(0, int(entry.get("min", 1)))
		var high := maxi(low, int(entry.get("max", low)))
		var amount := rng.randi_range(low, high)
		if amount > 0:
			result[item_id] = int(result.get(item_id, 0)) + amount
	return result
