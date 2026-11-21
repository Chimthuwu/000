extends RefCounted
class_name HouseValidator

## Terraria-style NPC housing check, adapted to a single-layer voxel world.
##
## There are no background walls here, so a room is "sealed" when a flood fill
## of the air the player is standing in cannot escape: every escape route ends
## at a solid block. A valid house needs that seal plus a door on its boundary,
## a light source inside it, a chair and a table (any workbench).
##
## The flood is capped so an outdoor fill bails out quickly instead of walking
## the whole map, and unloaded chunks count as a leak because we cannot prove
## they are enclosed.

const MIN_VOLUME := 8
const MAX_VOLUME := 2048
# A fill that travels this far from the player has escaped the room: a house
# is a room, not a cave system, so report it as unsealed rather than huge.
const MAX_SPAN := 12
const NEIGHBORS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

const REASON_OPEN := "not sealed"
const REASON_LARGE := "too large for a house"
const REASON_DOOR := "no door"
const REASON_LIGHT := "no light"
const REASON_SEAT := "no chair"
const REASON_TABLE := "no table"


static func validate(world, start: Vector3i) -> Dictionary:
	var report := {
		"valid": false,
		"reason": "not inside a room",
		"volume": 0,
		"door": false,
		"light": false,
		"seat": false,
		"table": false,
		"sealed": false,
		"cells": [],
	}
	if world == null or not world.is_loaded(start) or world.is_solid(start):
		return report
	var visited: Dictionary = {start: true}
	var queue: Array[Vector3i] = [start]
	var interior: Array[Vector3i] = []
	var leaked := false
	var found := {"door": false, "light": false, "seat": false, "table": false}
	var head := 0
	while head < queue.size():
		var cell: Vector3i = queue[head]
		head += 1
		interior.append(cell)
		# Passable furniture (chair, bench, an open door) sits inside the air
		# the fill walks through, so inspect the cell itself as well as its walls.
		_inspect(world, cell, found)
		for offset in NEIGHBORS:
			var neighbor: Vector3i = cell + offset
			if visited.has(neighbor):
				continue
			if not world.is_loaded(neighbor):
				# Unloaded chunk: cannot prove the room is closed.
				leaked = true
				continue
			if world.is_solid(neighbor):
				_inspect(world, neighbor, found)
				continue
			visited[neighbor] = true
			queue.append(neighbor)
			if absi(neighbor.x - start.x) > MAX_SPAN or absi(neighbor.y - start.y) > MAX_SPAN or absi(neighbor.z - start.z) > MAX_SPAN:
				report["volume"] = interior.size()
				report["reason"] = REASON_OPEN
				return report
			if interior.size() > MAX_VOLUME:
				report["volume"] = interior.size()
				report["reason"] = REASON_LARGE
				return report
	report["volume"] = interior.size()
	report["sealed"] = not leaked and interior.size() >= MIN_VOLUME
	if leaked:
		report["reason"] = REASON_OPEN
		return report
	if interior.size() < MIN_VOLUME:
		report["reason"] = REASON_OPEN
		return report
	report["door"] = bool(found["door"])
	report["light"] = bool(found["light"])
	report["seat"] = bool(found["seat"])
	report["table"] = bool(found["table"])
	if not bool(found["door"]):
		report["reason"] = REASON_DOOR
	elif not bool(found["light"]):
		report["reason"] = REASON_LIGHT
	elif not bool(found["seat"]):
		report["reason"] = REASON_SEAT
	elif not bool(found["table"]):
		report["reason"] = REASON_TABLE
	else:
		report["valid"] = true
		report["reason"] = ""
		report["cells"] = interior
	return report


## Records the housing features a single block provides, if any.
static func _inspect(world, cell: Vector3i, found: Dictionary) -> void:
	var block_id: int = world.get_block_id(cell)
	if block_id == world.air_id or block_id < 0 or block_id >= world.block_defs.size():
		return
	var def = world.block_defs[block_id]
	var block_name := String(def.block_id)
	if block_name.ends_with("_door") or block_name.ends_with("_door_open"):
		found["door"] = true
	if int(def.emitted_light) > 0:
		found["light"] = true
	if bool(def.seating):
		found["seat"] = true
	if String(def.station) == "workbench":
		found["table"] = true

## One short line for the HUD: what the room has, and what it is missing.
static func summary(report: Dictionary) -> String:
	if bool(report.get("valid", false)):
		return "HOUSE READY  ·  %d CELLS" % int(report.get("volume", 0))
	var missing: Array[String] = []
	if not bool(report.get("door", false)):
		missing.append("DOOR")
	if not bool(report.get("light", false)):
		missing.append("LIGHT")
	if not bool(report.get("seat", false)):
		missing.append("CHAIR")
	if not bool(report.get("table", false)):
		missing.append("TABLE")
	var reason := String(report.get("reason", ""))
	if missing.is_empty():
		return "HOUSE: %s" % reason.to_upper()
	return "HOUSE: %s  ·  NEED %s" % [reason.to_upper(), " + ".join(missing)]
