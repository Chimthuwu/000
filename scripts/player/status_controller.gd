extends RefCounted
class_name StatusController

## Generic timed status architecture. The player interprets the active ids;
## systems only call apply()/remove(). No status logic lives in the UI.

signal status_applied(id: StringName, duration: float)
signal status_removed(id: StringName)

var active: Dictionary = {}


func apply(id: StringName, duration: float) -> void:
	if id == &"" or duration <= 0.0:
		return
	active[id] = maxf(float(active.get(id, 0.0)), duration)
	status_applied.emit(id, duration)


func remove(id: StringName) -> void:
	if active.erase(id):
		status_removed.emit(id)


func has(id: StringName) -> bool:
	return float(active.get(id, 0.0)) > 0.0


func remaining(id: StringName) -> float:
	return float(active.get(id, 0.0))


func tick(delta: float) -> void:
	for id in active.keys():
		var left := float(active[id]) - delta
		if left <= 0.0:
			active.erase(id)
			status_removed.emit(id)
		else:
			active[id] = left


func clear() -> void:
	active.clear()


func serialize() -> Dictionary:
	return active.duplicate()


func deserialize(data: Dictionary) -> void:
	active.clear()
	for id in data.keys():
		if float(data[id]) > 0.0:
			active[StringName(id)] = float(data[id])
