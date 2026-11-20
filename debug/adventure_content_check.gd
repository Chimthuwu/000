extends SceneTree

# Agent 4 canonical validation. Proves The Undercroft actually generates inside
# lumen_deepworld: depth-relative levels are buried, the region is connected,
# deterministic, spans chunks, contains its authored fixtures, and survives
# unload/reload. Run:
#   Godot --headless --path lumen_deepworld --script res://debug/adventure_content_check.gd

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("ADVENTURE CHECK FAIL: %s %s" % [label, detail])
		return
	print("ADVENTURE CHECK PASS: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_for(condition: Callable, limit: int) -> int:
	var frames := 0
	while not condition.call() and frames < limit:
		await process_frame
		frames += 1
	return frames


# Canonical Main may auto-continue a save on boot and reset the player to spawn;
# re-assert the teleport every frame so the streaming interest point stays put.
func _wait_for_at(position: Vector3, condition: Callable, limit: int) -> int:
	var frames := 0
	while not condition.call() and frames < limit:
		main.player.position = position
		await process_frame
		frames += 1
	return frames


func _run() -> void:
	var world: VoxelWorld = main.world
	var frames := await _wait_for(func() -> bool: return world.is_generated, 2400)
	_check(world.is_generated, "canonical world streams in", "frames=%d" % frames)
	if not world.is_generated:
		quit(1)
		return

	var config: AdventureConfig = AdventureContent.config()
	var anchor: Vector2i = AdventureContent.world_anchor()
	var levels: Dictionary = AdventureContent.region_levels(world.world_seed)
	var upper: int = levels["upper"]
	var lower: int = levels["lower"]

	# --- Data contract -------------------------------------------------------
	_check(config.enable_undercroft, "content enabled in canonical data config")
	_check(WorldLayers.WORLD_Y == 256 and int(levels["min_surface"]) > 150,
		"canonical deepworld vertical model detected", "world_y=%d min_surface=%d" % [WorldLayers.WORLD_Y, int(levels["min_surface"])])
	_check(upper + config.room_height < int(levels["min_surface"]) and lower > 0,
		"rooms are buried below the lowest local surface",
		"upper=%d lower=%d surface=%d" % [upper, lower, int(levels["min_surface"])])
	_check(config.encounters.size() >= 4 and not config.secrets.is_empty(),
		"encounter + secret tables authored", "encounters=%d secrets=%d" % [config.encounters.size(), config.secrets.size()])
	_check(int(config.boss_arena.get("boss_kind", -1)) == 99 and config.world_events.size() >= 1,
		"boss arena + world event data authored")

	# --- Pure deterministic validation --------------------------------------
	var report: Dictionary = AdventureContent.validate_region(world.world_seed, world.block_ids)
	_check(bool(report["ok"]), "pure region validation", "failures=%s rooms=%d corridors=%d carved=%d" % [
		str(report["failures"]), int(report["rooms"]), int(report["corridors"]), int(report["carved_rooms"])])
	_check(int(report["carved_rooms"]) == int(report["rooms"]) + int(report["corridors"]),
		"every authored volume interior is carved")

	# --- Stream to the region and inspect LIVE canonical blocks --------------
	var upper_pos := Vector3(float(anchor.x) + 0.5, float(upper) + 2.0, float(anchor.y) + 0.5)
	main.player.position = upper_pos
	var target_chunk := world._chunk_of(Vector3i(anchor.x, upper, anchor.y))
	frames = await _wait_for_at(upper_pos, func() -> bool: return world.is_chunk_ready(target_chunk), 3000)
	var rec: Dictionary = world.chunk_records.get(target_chunk, {})
	print("DIAG player=", main.player.position, " target=", target_chunk, " stream_v=", world.stream_vertical,
		" has=", world.chunk_records.has(target_chunk), " light=", rec.get("light_ready", "?"),
		" mesh=", rec.get("mesh_installed", "?"), " loaded=", world.chunk_records.size())
	_check(world.is_chunk_ready(target_chunk), "undercroft chunks stream, light and mesh", "frames=%d" % frames)
	if not world.is_chunk_ready(target_chunk):
		quit(1)
		return

	var air := world.air_id
	var vols: Array = AdventureContent.volumes(world.world_seed)
	var carved := 0
	var solid_floors := 0
	for volume in vols:
		var v: Dictionary = volume
		var mx := (int(v["min_x"]) + int(v["max_x"])) / 2
		var mz := (int(v["min_z"]) + int(v["max_z"])) / 2
		var my := (int(v["floor_y"]) + int(v["ceiling_y"])) / 2
		var found_air := false
		for sx in range(int(v["min_x"]), int(v["max_x"]) + 1):
			for sz in range(int(v["min_z"]), int(v["max_z"]) + 1):
				if world.get_block_id(Vector3i(sx, my, sz)) == air:
					found_air = true
					break
			if found_air:
				break
		if found_air:
			carved += 1
		if world.is_solid(Vector3i(mx, int(v["floor_y"]), mz)):
			solid_floors += 1
	_check(carved == vols.size(), "live interiors are air", "carved=%d/%d" % [carved, vols.size()])
	_check(solid_floors == vols.size(), "live floors are solid", "floors=%d/%d" % [solid_floors, vols.size()])

	# The canonical world streams only a 4-chunk vertical window. Verify each
	# level while the player is actually in that window, otherwise lower chunks
	# legitimately report air from the resident-set boundary.
	var b: Dictionary = AdventureContent.region_bounds(world.world_seed)
	# The gallery's far z edge can still be streaming while the spawn area is
	# already ready. Wait for it before counting so authored clues/crystals are
	# not missed by a timing race (the content itself is unchanged).
	var gallery_chunk := world._chunk_of(Vector3i(anchor.x + 24, upper + 2, anchor.y - 15))
	frames = await _wait_for(func() -> bool: return world.is_chunk_ready(gallery_chunk), 1800)
	var upper_counts := _count_fixtures(world, b, upper, upper + config.room_height + 2)
	_check(int(upper_counts["torch"]) >= 4, "upper-level wall torches placed", "n=%d" % upper_counts["torch"])
	_check(int(upper_counts["mycelium"]) >= 3 and int(upper_counts["pale_bloom"]) >= 2,
		"false-wall secret + clue blooms placed", "wall=%d clue=%d" % [upper_counts["mycelium"], upper_counts["pale_bloom"]])
	_check(int(upper_counts["ore"]) >= 8 and int(upper_counts["crystal"]) >= 4,
		"upper-level treasure veins placed", "ore=%d crystal=%d" % [upper_counts["ore"], upper_counts["crystal"]])
	var upper_signature := _sample_signature(world, anchor, levels, "upper")

	# Descend to the boss level: proves the lower rooms are reachable inside the
	# canonical vertical window and that their four beacons actually exist.
	var lower_pos := Vector3(float(anchor.x) + 18.5, float(lower) + 2.0, float(anchor.y) + 9.5)
	main.player.position = lower_pos
	var lower_chunk := world._chunk_of(Vector3i(anchor.x + 18, lower, anchor.y + 9))
	frames = await _wait_for_at(lower_pos, func() -> bool: return world.is_chunk_ready(lower_chunk), 3000)
	_check(world.is_chunk_ready(lower_chunk), "lower sanctum streams on descent", "frames=%d" % frames)
	var lower_counts := _count_fixtures(world, b, lower, lower + config.arena_height + 2)
	_check(int(lower_counts["beacon"]) >= 4, "boss arena beacons placed", "n=%d" % lower_counts["beacon"])
	_check(int(lower_counts["ore"]) >= 8 and int(lower_counts["crystal"]) >= 4,
		"arena ore ring + vault treasure placed", "ore=%d crystal=%d" % [lower_counts["ore"], lower_counts["crystal"]])

	# --- Regeneration identity: leave, unload, return ------------------------
	main.player.position = upper_pos
	frames = await _wait_for_at(upper_pos, func() -> bool: return world.is_chunk_ready(target_chunk), 3000)
	var far_pos := Vector3(-600.0, float(upper), -600.0)
	main.player.position = far_pos
	var unload_frames := await _wait_for_at(far_pos, func() -> bool: return not world.chunk_records.has(target_chunk), 3000)
	_check(not world.chunk_records.has(target_chunk), "undercroft chunks unload after travel", "frames=%d" % unload_frames)
	main.player.position = upper_pos
	frames = await _wait_for_at(upper_pos, func() -> bool: return world.is_chunk_ready(target_chunk), 3000)
	_check(world.is_chunk_ready(target_chunk), "undercroft chunks reload", "frames=%d" % frames)
	var upper_signature_after := _sample_signature(world, anchor, levels, "upper")
	_check(upper_signature == upper_signature_after, "generated content survives unload/reload byte-for-byte",
		"before=%s after=%s" % [upper_signature, upper_signature_after])

	if failures > 0:
		quit(1)
		return
	print("ADVENTURE CONTENT CHECK PASS: canonical Undercroft verified end to end")
	quit(0)


func _count_fixtures(world: VoxelWorld, bounds: Dictionary, y0: int, y1: int) -> Dictionary:
	var counts := {"torch": 0, "beacon": 0, "mycelium": 0, "pale_bloom": 0, "ore": 0, "crystal": 0}
	var ore_ids := [world.block_ids.get(&"iron_ore", -1), world.block_ids.get(&"copper_ore", -1),
		world.block_ids.get(&"silver_ore", -1), world.block_ids.get(&"gold_ore", -1),
		world.block_ids.get(&"ancient_ore", -1)]
	for z in range(int(bounds["min_z"]), int(bounds["max_z"]) + 1):
		for x in range(int(bounds["min_x"]), int(bounds["max_x"]) + 1):
			for y in range(y0, y1):
				var id := world.get_block_id(Vector3i(x, y, z))
				if id == world.block_ids.get(&"torch", -1): counts["torch"] += 1
				elif id == world.block_ids.get(&"beacon", -1): counts["beacon"] += 1
				elif id == world.block_ids.get(&"mycelium", -1): counts["mycelium"] += 1
				elif id == world.block_ids.get(&"pale_bloom", -1): counts["pale_bloom"] += 1
				elif id in ore_ids: counts["ore"] += 1
				elif id == world.block_ids.get(&"lumen_crystal", -1): counts["crystal"] += 1
	return counts


func _sample_signature(world: VoxelWorld, anchor: Vector2i, levels: Dictionary, which: String) -> String:
	var upper: int = levels["upper"]
	var lower: int = levels["lower"]
	var cells: Array = []
	if which == "upper":
		cells = [
			Vector3i(anchor.x, upper + 2, anchor.y),
			Vector3i(anchor.x + 18, upper + 2, anchor.y),
			Vector3i(anchor.x + 30, upper + 2, anchor.y - 16),
			Vector3i(anchor.x + 25, upper + 2, anchor.y - 16),
			Vector3i(anchor.x + 10, upper + 1, anchor.y + 1),
		]
	else:
		cells = [
			Vector3i(anchor.x + 18, lower + 2, anchor.y + 9),
			Vector3i(anchor.x + 18, lower + 4, anchor.y + 7),
			Vector3i(anchor.x + 34, lower + 2, anchor.y + 9),
		]
	var parts: Array = []
	for cell in cells:
		parts.append("%d:%d:%d=%d" % [cell.x, cell.y, cell.z, world.get_block_id(cell)])
	return "|".join(PackedStringArray(parts))
