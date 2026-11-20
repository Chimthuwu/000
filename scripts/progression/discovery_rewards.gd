extends RefCounted
class_name DiscoveryRewards

## Agent 2 gameplay layer for Agent 4's discovery metadata. The physical treasure
## is already stamped as mineable blocks; this grants a small, ONE-TIME discovery
## bonus and records the visit in ProgressionSystem so it survives save/load.

signal discovery_claimed(discovery_id: StringName, label: String, granted: Dictionary)


static func claim_flag(discovery_id: String) -> StringName:
	return StringName("disc_claimed_" + discovery_id)


func was_claimed(discovery_id: String, progression: ProgressionSystem) -> bool:
	if discovery_id == "" or progression == null:
		return false
	return progression.has_flag(claim_flag(discovery_id))


## Maps Agent 4 loot names (block ids or item ids) through the single item
## database alias table. Invalid/empty names are skipped, never granted blindly.
static func resolve_item_id(loot_name: String) -> StringName:
	var id := ItemDatabase.item_id_for_drop(StringName(loot_name))
	if id == &"" or not ItemDatabase.has(id):
		return &""
	return id


## Returns {"claimed": bool, "granted": Dictionary}. A second visit with the
## same id grants nothing. The claim flag is set only after a successful grant.
func try_claim(discovery: Dictionary, inventory: InventoryModel, progression: ProgressionSystem) -> Dictionary:
	var result := {"claimed": false, "granted": {}}
	if discovery.is_empty() or inventory == null or progression == null:
		return result
	var discovery_id := String(discovery.get("id", ""))
	if discovery_id == "" or was_claimed(discovery_id, progression):
		return result
	var loot: Array = discovery.get("loot", []) as Array
	if loot.is_empty():
		return result
	var granted: Dictionary = {}
	for entry in loot:
		var raw := String(entry)
		var item_id := resolve_item_id(raw)
		if item_id == &"":
			continue
		# A discovery bonus is one of each named reward; world blocks supply the
		# rest through normal mining.
		granted[item_id] = int(granted.get(item_id, 0)) + 1
	if granted.is_empty():
		return result
	for item_id in granted.keys():
		var leftover := inventory.add_item(StringName(item_id), int(granted[item_id]))
		if leftover > 0:
			granted[item_id] = int(granted[item_id]) - leftover
	progression.set_flag(claim_flag(discovery_id))
	progression.discover(StringName(discovery_id))
	result["claimed"] = true
	result["granted"] = granted
	discovery_claimed.emit(claim_flag(discovery_id), String(discovery.get("label", "")), granted)
	return result
