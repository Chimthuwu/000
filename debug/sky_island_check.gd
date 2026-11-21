extends SceneTree

# Deterministic guard for the reshaped sky islands: a grass cap above a soil
# band, a stone body and a deeper tapered deepstone underside.

const SEED := 139732
const AIR := 0
const STONE := 1
const SOIL := 2
const GRASS := 3
const DEEP := 4
const VINE := 5
const CRYSTAL := 6


func _initialize() -> void:
	BiomeManager.configure(SEED)
	var ids := {
		&"ashen_soil": GRASS,
		&"dirt": SOIL,
		&"deepstone": DEEP,
		&"jungle_leaves": VINE,
		&"lumen_crystal": CRYSTAL,
	}
	var found := false
	var found_origin := Vector3i.ZERO
	var found_counts := {}
	for oy in range(208, 256, 16):
		for oz in range(0, 192, 16):
			for ox in range(0, 192, 16):
				var output := PackedByteArray()
				output.resize(4096)
				output.fill(AIR)
				WorldSky.stamp_chunk(output, Vector3i(ox, oy, oz), SEED, ids, AIR, STONE)
				var counts := _counts(output)
				if counts[GRASS] > 0 and counts[DEEP] > 0 and counts[STONE] > 0:
					found = true
					found_origin = Vector3i(ox, oy, oz)
					found_counts = counts
					break
			if found:
				break
		if found:
			break
	if not found:
		print("SKY ISLAND CHECK FAIL: no layered island chunk found")
		quit(1)
		return

	var first := PackedByteArray()
	first.resize(4096)
	first.fill(AIR)
	WorldSky.stamp_chunk(first, found_origin, SEED, ids, AIR, STONE)
	var second := PackedByteArray()
	second.resize(4096)
	second.fill(AIR)
	WorldSky.stamp_chunk(second, found_origin, SEED, ids, AIR, STONE)
	var deterministic := first == second
	var top_grass := -999
	var bottom_deep := 999
	var top_grass_cell := Vector3i.ZERO
	var top_grass_has_air := false
	for ly in range(16):
		for lz in range(16):
			for lx in range(16):
				var block := int(first[lx + ly * 16 + lz * 256])
				var y := found_origin.y + ly
				if block == GRASS:
					if y > top_grass:
						top_grass = y
						top_grass_cell = Vector3i(found_origin.x + lx, y, found_origin.z + lz)
				elif block == DEEP:
					bottom_deep = mini(bottom_deep, y)
	var top_index := top_grass_cell.y - found_origin.y
	var lx := top_grass_cell.x - found_origin.x
	var lz := top_grass_cell.z - found_origin.z
	if top_index >= 0 and top_index < 15:
		top_grass_has_air = int(first[lx + (top_index + 1) * 16 + lz * 256]) == AIR
	elif top_index == 15:
		var above_chunk := PackedByteArray()
		above_chunk.resize(4096)
		above_chunk.fill(AIR)
		WorldSky.stamp_chunk(above_chunk, found_origin + Vector3i.UP * 16, SEED, ids, AIR, STONE)
		top_grass_has_air = int(above_chunk[lx + 0 * 16 + lz * 256]) == AIR
	var layered := top_grass - bottom_deep >= 4
	var passed := deterministic and layered and top_grass_has_air
	print("SKY ISLAND origin=%s counts=%s grass_top=%d deep_bottom=%d depth=%d deterministic=%s grass_air=%s" % [
		str(found_origin), str(found_counts), top_grass, bottom_deep, top_grass - bottom_deep, str(deterministic), str(top_grass_has_air)
	])
	if passed:
		print("SKY ISLAND CHECK PASS: grass cap, stone body, tapered deepstone underside")
		quit(0)
	else:
		print("SKY ISLAND CHECK FAIL: missing cap, underside or determinism")
		quit(1)


func _counts(output: PackedByteArray) -> Dictionary:
	var counts := {AIR: 0, STONE: 0, SOIL: 0, GRASS: 0, DEEP: 0, VINE: 0, CRYSTAL: 0}
	for value in output:
		var block := int(value)
		counts[block] = int(counts.get(block, 0)) + 1
	return counts
