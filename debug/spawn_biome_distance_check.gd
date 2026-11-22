extends SceneTree

# The surface biomes are places you travel to, not next-door neighbours. This
# asserts the spawn layout in BiomeManager still holds: spawn is Forest, no
# other biome is dominant close to spawn, no evil biome is dominant inside
# EVIL_CLEAR_RADIUS, and the evil biome still exists in reach (so the exclusion
# did not delete it outright).

const STEP := 8
const SEARCH_LIMIT := 2400
# Every non-Forest biome must sit at least this far out. Terraria puts the first
# neighbouring biome a few hundred tiles from spawn; anything under a couple of
# hundred blocks reads as "right next to spawn".
const MIN_OTHER_BIOME_DISTANCE := 400

var _failures := 0


func _init() -> void:
	BiomeManager.configure(BiomeManager._seed if BiomeManager._seed > 0 else 139732)
	var sx := BiomeManager.SPAWN_X
	var sz := BiomeManager.SPAWN_Z
	var nearest := {}
	for radius in range(0, SEARCH_LIMIT, STEP):
		var samples := maxi(8, radius / 2)
		for index in range(samples):
			var angle := TAU * float(index) / float(samples)
			var x := sx + roundi(cos(angle) * float(radius))
			var z := sz + roundi(sin(angle) * float(radius))
			var biome := BiomeManager.dominant_biome(x, z)
			if not nearest.has(biome):
				nearest[biome] = radius
	for index in range(BiomeManager.BIOME_COUNT):
		var found: String = "%d blocks" % nearest[index] if nearest.has(index) else "not found"
		print("SPAWN DIST %d %-16s first dominant at %s" % [index, BiomeManager.biome_name(index), found])

	var spawn_biome := BiomeManager.dominant_biome(sx, sz)
	_check(spawn_biome == BiomeManager.SPAWN_BIOME,
		"spawn is Forest", "biome=%s" % BiomeManager.biome_name(spawn_biome))

	var evil := BiomeManager.CRIMSON if BiomeManager.evil_mode() == "crimson" else BiomeManager.CORRUPTION
	var other := BiomeManager.CORRUPTION if evil == BiomeManager.CRIMSON else BiomeManager.CRIMSON
	_check(not nearest.has(other), "the excluded evil identity never dominates",
		BiomeManager.biome_name(other))
	var nearest_other := 1 << 30
	var nearest_other_name := ""
	for index in range(BiomeManager.BIOME_COUNT):
		if index == BiomeManager.SPAWN_BIOME or not nearest.has(index):
			continue
		if int(nearest[index]) < nearest_other:
			nearest_other = int(nearest[index])
			nearest_other_name = BiomeManager.biome_name(index)
	_check(nearest_other >= MIN_OTHER_BIOME_DISTANCE,
		"no other biome dominates near spawn",
		"closest is %s at %d, minimum %d" % [nearest_other_name, nearest_other, MIN_OTHER_BIOME_DISTANCE])

	var evil_distance: int = int(nearest[evil]) if nearest.has(evil) else -1
	_check(evil_distance < 0 or float(evil_distance) >= BiomeManager.EVIL_CLEAR_RADIUS,
		"evil biome stays outside EVIL_CLEAR_RADIUS",
		"first dominant at %d, clear radius %d" % [evil_distance, int(BiomeManager.EVIL_CLEAR_RADIUS)])
	_check(evil_distance >= 0 and evil_distance < SEARCH_LIMIT,
		"evil biome still generates in reach", "first dominant at %d" % evil_distance)

	if _failures > 0:
		printerr("SPAWN DISTANCE CHECK FAIL: %d failure(s)" % _failures)
		quit(1)
		return
	print("SPAWN DISTANCE CHECK PASS: nearest other biome %d blocks, evil %d blocks" % [nearest_other, evil_distance])
	quit(0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("SPAWN DISTANCE PASS: ", label, " ", detail)
	else:
		_failures += 1
		printerr("SPAWN DISTANCE FAIL: ", label, " ", detail)
