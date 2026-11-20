extends SceneTree

# Validates the terrain atlas + per-face block tile mapping.
# Confirms terrain is textured per material (not one flat tile for every block),
# that grass has a distinct side fringe, that biome foliage/ores differ, that the
# atlas is deterministic, and that mesher UVs stay inside their tile cells.

const COMPLETE := "TERRAIN ATLAS CHECK PASS: %d tiles, per-face materials, deterministic atlas and in-cell UVs"

var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("ATLAS PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("ATLAS FAIL: %s %s" % [label, detail])


func _initialize() -> void:
	var atlas = load("res://scripts/world/terrain_atlas.gd")
	var mesher = load("res://scripts/world/chunk_mesher.gd")

	# --- Atlas image -----------------------------------------------------
	var image: Image = atlas.build_image()
	_check(image != null, "atlas image builds")
	_check(image.get_width() == atlas.ATLAS_PIXELS and image.get_height() == atlas.ATLAS_PIXELS, "atlas is 256x256", "size=%dx%d" % [image.get_width(), image.get_height()] if image != null else "")
	_check(image.get_format() == Image.FORMAT_RGB8, "atlas is RGB8")

	var again: Image = atlas.build_image()
	_check(image.get_data() == again.get_data(), "atlas is deterministic")

	# Every declared tile must be painted with more than one value (real detail).
	var painted := 0
	var flat_tiles: Array = []
	for tile in range(atlas.TILE_COUNT):
		var rect: Rect2i = Rect2i(Vector2i(atlas.tile_rect(tile).position), Vector2i(atlas.TILE_SIZE, atlas.TILE_SIZE))
		var seen := {}
		for y in range(atlas.TILE_SIZE):
			for x in range(atlas.TILE_SIZE):
				seen[image.get_pixel(rect.position.x + x, rect.position.y + y)] = true
		if seen.size() > 1:
			painted += 1
		else:
			flat_tiles.append(tile)
	_check(painted == atlas.TILE_COUNT, "every tile has pixel detail", "detailed=%d/%d flat=%s" % [painted, atlas.TILE_COUNT, str(flat_tiles)])

	# --- Block -> face mapping ------------------------------------------
	var dir := DirAccess.open("res://data/blocks")
	var defs: Array = []
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var def = load("res://data/blocks/" + file)
				if def != null:
					defs.append(def)
	_check(defs.size() >= 60, "block definitions load", "count=%d" % defs.size())

	var table: Array = atlas.block_tile_table(defs)
	var plain := Vector3i(atlas.Tile.PLAIN, atlas.Tile.PLAIN, atlas.Tile.PLAIN)
	var unmapped: Array = []
	var bad_index := false
	for i in range(defs.size()):
		var def = defs[i]
		var tiles: Vector3i = table[i]
		if def.block_id != &"air":
			if tiles == plain:
				unmapped.append(def.block_id)
			if tiles.x >= atlas.TILE_COUNT or tiles.y >= atlas.TILE_COUNT or tiles.z >= atlas.TILE_COUNT:
				bad_index = true
	_check(unmapped.is_empty(), "every non-air block has a material", "missing=%s" % str(unmapped))
	_check(not bad_index, "all tile indices are in range")

	# --- Per-face differentiation ---------------------------------------
	for biome_grass in [&"dirt", &"ashen_soil", &"hush_soil", &"jungle_grass", &"corrupted_grass", &"crimson_grass", &"hallowed_grass"]:
		var t: Vector3i = atlas.tiles_for_block(biome_grass)
		_check(t.z != t.y, "%s grass side differs from top" % biome_grass, "tiles=%s" % str(t))
		_check(t.x == atlas.Tile.GRASS_TOP, "%s uses grass top" % biome_grass, "top=%d" % t.x)

	var dirt_side: int = atlas.tiles_for_block(&"dirt").y
	var jungle_side: int = atlas.tiles_for_block(&"jungle_grass").y
	var evil_side: int = atlas.tiles_for_block(&"corrupted_grass").y
	var hallow_side: int = atlas.tiles_for_block(&"hallowed_grass").y
	_check(dirt_side != jungle_side and dirt_side != evil_side and dirt_side != hallow_side, "biome grass sides are distinct", "dirt=%d jungle=%d evil=%d hallow=%d" % [dirt_side, jungle_side, evil_side, hallow_side])

	var leaf_tiles := {}
	for leaf in [&"jungle_leaves", &"ebon_leaves", &"crim_leaves", &"hallow_leaves"]:
		leaf_tiles[atlas.tiles_for_block(leaf).x] = true
	_check(leaf_tiles.size() == 3, "jungle/evil/hallow leaf materials are distinct", "distinct=%d" % leaf_tiles.size())
	_check(atlas.tiles_for_block(&"ebon_leaves") == atlas.tiles_for_block(&"crim_leaves"), "corruption and crimson share the evil leaf material")

	var stone_tile: int = atlas.tiles_for_block(&"stone").x
	var ore_tiles := {}
	for ore in [&"coal_ore", &"copper_ore", &"iron_ore", &"silver_ore", &"gold_ore", &"ancient_ore", &"frost_crystal_ore", &"volcanic_crystal_ore"]:
		var ore_tile: int = atlas.tiles_for_block(ore).x
		_check(ore_tile != stone_tile, "%s differs from stone" % ore)
		ore_tiles[ore_tile] = true
	_check(ore_tiles.size() >= 2, "ore materials are varied", "distinct=%d" % ore_tiles.size())

	var surface: Vector3i = atlas.tiles_for_block(&"desert_sand")
	var ocean: Vector3i = atlas.tiles_for_block(&"ocean_sand")
	_check(surface.x != ocean.x, "ocean sand differs from desert sand", "desert=%d ocean=%d" % [surface.x, ocean.x])

	# --- UV sanity -------------------------------------------------------
	var uv_ok := true
	var columns: int = atlas.COLUMNS
	var tile_count: int = atlas.TILE_COUNT
	for tile in range(tile_count):
		var column: int = tile % columns
		var row: int = floori(float(tile) / float(columns))
		var lo := Vector2(float(column) / float(columns), float(row) / float(columns))
		var hi := Vector2(float(column + 1) / float(columns), float(row + 1) / float(columns))
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			var uv: Vector2 = mesher.atlas_uv(tile, corner)
			if uv.x < lo.x - 0.0001 or uv.x > hi.x + 0.0001 or uv.y < lo.y - 0.0001 or uv.y > hi.y + 0.0001:
				uv_ok = false
				push_error("ATLAS FAIL: tile %d corner %s -> %s outside %s..%s" % [tile, str(corner), str(uv), str(lo), str(hi)])
	_check(uv_ok, "mesher UVs stay inside their tile cell")

	if failures == 0:
		print(COMPLETE % atlas.TILE_COUNT)
		quit(0)
	else:
		push_error("TERRAIN ATLAS CHECK FAIL: %d assertion(s)" % failures)
		quit(1)
