extends Node
class_name BossDirector

## Minimal boss progression framework: evaluates unlock conditions, tracks one
## active encounter and records victories. Deliberately does not implement boss
## AI or a boss roster. Add BossDef .tres files to extend.

signal boss_unlocked(boss_id: StringName)
signal boss_defeated(boss_id: StringName)

@export var bosses: Array[BossDef] = []

var progression: ProgressionSystem
var active_boss: StringName = &""
var defeated: Dictionary = {}


func setup(prog: ProgressionSystem) -> void:
	progression = prog


func is_unlocked(def: BossDef) -> bool:
	if progression == null:
		return false
	for flag in def.required_flags:
		if not progression.has_flag(flag):
			return false
	return true


func can_summon(def: BossDef, arena_ok := true) -> bool:
	return active_boss == &"" and not bool(defeated.get(def.boss_id, false)) and is_unlocked(def) and arena_ok


func summon(def: BossDef) -> bool:
	if not can_summon(def, true):
		return false
	active_boss = def.boss_id
	return true


## Called by the encounter when the boss dies.
func on_boss_defeated(def: BossDef, drop_parent: Node, position: Vector3) -> void:
	if active_boss != def.boss_id:
		return
	# Reward duplication guard: a reloaded save that already granted the boss
	# reward must never grant it a second time.
	if bool(defeated.get(def.boss_id, false)):
		return
	if progression != null:
		for flag in def.unlock_flags:
			if progression.has_flag(flag):
				return
	active_boss = &""
	defeated[def.boss_id] = true
	if progression != null:
		for flag in def.unlock_flags:
			progression.set_flag(flag)
		# Defeating the Warden is the world's progression gate.
		if def.boss_id == &"hollow_warden":
			progression.advance_world()
		progression.add_stat(&"bosses_defeated", 1.0)
	if def.loot_table != null and drop_parent != null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var drops := def.loot_table.roll(rng)
		for item_id in drops.keys():
			ItemEntity.spawn(drop_parent, position + Vector3.UP * 0.5, StringName(item_id), int(drops[item_id]))
	boss_defeated.emit(def.boss_id)


func boss_is_defeated(boss_id: StringName) -> bool:
	return bool(defeated.get(boss_id, false))


func has_flag_reward(flag: StringName) -> bool:
	return progression != null and progression.has_flag(flag)


func serialize() -> Dictionary:
	var saved: Array[String] = []
	for key in defeated.keys():
		if bool(defeated[key]):
			saved.append(String(key))
	return {"defeated": saved, "active": String(active_boss)}


func deserialize(data: Dictionary) -> void:
	defeated.clear()
	for key in data.get("defeated", []):
		defeated[StringName(String(key))] = true
	active_boss = StringName(String(data.get("active", "")))
