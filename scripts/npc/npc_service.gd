extends RefCounted
class_name NpcService

## Gameplay side of NPC merchants and quests. Works with Agent 3's NpcBase
## (npc.shop_items / npc.quest_id) without owning any UI or nodes.

signal purchased(item_id: StringName, amount: int)
signal sold(item_id: StringName, amount: int)
signal quest_completed(quest_id: StringName)

const CURRENCY := &"coin"

var inventory: InventoryModel
var progression: ProgressionSystem
var quests: Dictionary = {}
var profiles: Dictionary = {}


func _init(inv: InventoryModel, prog: ProgressionSystem) -> void:
	inventory = inv
	progression = prog
	var quest: QuestDef = preload("res://data/npc/ore_delivery.tres")
	quests[quest.quest_id] = quest
	var dir := DirAccess.open("res://data/npc")
	if dir != null:
		for file_name in dir.get_files():
			if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				continue
			var resource := load("res://data/npc/".path_join(file_name))
			if resource is NpcProfile:
				var profile := resource as NpcProfile
				profiles[profile.npc_id] = profile
				if profile.display_name != "":
					profiles[StringName(profile.display_name.to_lower())] = profile


## Resolves the gameplay role for an Agent 3 NpcBase instance.
func profile_for(npc: Node3D) -> NpcProfile:
	if npc == null:
		return null
	var by_id := StringName(String(npc.get("npc_name")).to_lower())
	if profiles.has(by_id):
		return profiles[by_id]
	var by_display := StringName(String(npc.get("display_name")).to_lower())
	return profiles.get(by_display) as NpcProfile


func can_offer_shop(npc: Node3D) -> bool:
	var profile := profile_for(npc)
	if profile == null or profile.role != "merchant":
		return false
	if profile.required_flag != &"" and (progression == null or not progression.has_flag(profile.required_flag)):
		return false
	return is_resident(npc)


func is_resident(npc: Node3D) -> bool:
	var profile := profile_for(npc)
	return profile != null and profile.housing_flag != &"" and progression != null and progression.has_flag(profile.housing_flag)


## Settlement hook. World-side room validation belongs to Agent 1; this records
## the resulting gameplay state (the NPC has a home and offers its services).
func house_npc(npc: Node3D) -> bool:
	var profile := profile_for(npc)
	if profile == null or profile.housing_flag == &"" or progression == null:
		return false
	progression.set_flag(profile.housing_flag)
	return true


func price(item_id: StringName) -> int:
	var def := ItemDatabase.get_item(item_id)
	return maxi(1, def.value * 2) if def != null else 1


func can_buy(npc: Node3D, item_id: StringName, amount := 1) -> bool:
	if amount <= 0 or inventory == null:
		return false
	if npc != null and not (npc.get("shop_items") as Array).is_empty():
		if not (npc.get("shop_items") as Array).has(item_id):
			return false
	return inventory.count(CURRENCY) >= price(item_id) * amount


func buy(npc: Node3D, item_id: StringName, amount := 1) -> bool:
	if not can_buy(npc, item_id, amount):
		return false
	inventory.consume(CURRENCY, price(item_id) * amount)
	var leftover := inventory.add_item(item_id, amount)
	if leftover > 0:
		inventory.add_item(CURRENCY, price(item_id) * amount)
		return false
	purchased.emit(item_id, amount)
	return true


func sell(item_id: StringName, amount := 1) -> bool:
	if not inventory.consume(item_id, amount):
		return false
	var def := ItemDatabase.get_item(item_id)
	var payout := maxi(1, def.value) * amount if def != null else amount
	inventory.add_item(CURRENCY, payout)
	sold.emit(item_id, amount)
	return true


func available_quest(npc: Node3D) -> QuestDef:
	if npc == null:
		return null
	var quest_id := StringName(String(npc.get("quest_id")))
	var quest: QuestDef = quests.get(quest_id)
	if quest == null or (progression != null and progression.has_flag(quest.quest_id)):
		return null
	return quest


func can_complete(npc: Node3D) -> bool:
	var quest := available_quest(npc)
	if quest == null:
		return false
	for id in quest.required_items.keys():
		if not inventory.has_item(StringName(id), int(quest.required_items[id])):
			return false
	return true


func complete_quest(npc: Node3D) -> bool:
	if not can_complete(npc):
		return false
	var quest: QuestDef = available_quest(npc)
	for id in quest.required_items.keys():
		inventory.consume(StringName(id), int(quest.required_items[id]))
	for id in quest.rewards.keys():
		inventory.add_item(StringName(id), int(quest.rewards[id]))
	if progression != null:
		progression.set_flag(quest.quest_id)
		if quest.unlock_flag != &"":
			progression.set_flag(quest.unlock_flag)
	quest_completed.emit(quest.quest_id)
	return true
