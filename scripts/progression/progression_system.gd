extends RefCounted
class_name ProgressionSystem

## Flags, unlocks and discoveries. Deliberately tiny: bosses, biomes and NPC
## quests all express progress through the same StringName key space.

signal flag_set(flag: StringName)
signal discovered(key: StringName)

var flags: Dictionary = {}
var discoveries: Dictionary = {}
var stats: Dictionary = {
	"blocks_mined": 0,
	"items_crafted": 0,
	"enemies_defeated": 0,
	"bosses_defeated": 0,
	"distance_walked": 0.0,
	"deaths": 0,
}


func set_flag(flag: StringName) -> void:
	if flag == &"" or bool(flags.get(flag, false)):
		return
	flags[flag] = true
	flag_set.emit(flag)


func has_flag(flag: StringName) -> bool:
	return bool(flags.get(flag, false))


func clear_flag(flag: StringName) -> void:
	flags.erase(flag)


## Terraria-style world evolution. Pre-hardmode exploration and crafting is the
## default; a major boss victory advances the world and unlocks harder content.
func advance_world() -> void:
	set_flag(&"hardmode")


func is_hardmode() -> bool:
	return has_flag(&"hardmode")


## The Hallow is introduced by a future Underworld boss/event, never by the
## optional Hollow Warden. Agent 1's main.gd reads this exact flag.
func unlock_hallow() -> void:
	set_flag(&"underworld_vanquished")


func is_hallow_unlocked() -> bool:
	return has_flag(&"underworld_vanquished")


func discover(key: StringName) -> void:
	if key == &"" or bool(discoveries.get(key, false)):
		return
	discoveries[key] = true
	discovered.emit(key)


func has_discovered(key: StringName) -> bool:
	return bool(discoveries.get(key, false))


func add_stat(key: StringName, amount: float) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount


func set_stat(key: StringName, value: float) -> void:
	stats[key] = value


func serialize() -> Dictionary:
	var saved_flags: Array[String] = []
	for key in flags.keys():
		if bool(flags[key]):
			saved_flags.append(String(key))
	var saved_discoveries: Array[String] = []
	for key in discoveries.keys():
		if bool(discoveries[key]):
			saved_discoveries.append(String(key))
	return {"flags": saved_flags, "discoveries": saved_discoveries, "stats": stats.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	flags.clear()
	discoveries.clear()
	for key in data.get("flags", []):
		set_flag(StringName(String(key)))
	for key in data.get("discoveries", []):
		discover(StringName(String(key)))
	var saved_stats: Dictionary = data.get("stats", {})
	for key in stats.keys():
		if saved_stats.has(key):
			stats[key] = saved_stats[key]
