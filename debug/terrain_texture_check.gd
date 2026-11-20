extends SceneTree

# Verifies the pixel-art terrain material pipeline:
#  - the generated atlas is the expected size and tiles are real patterns
#  - every block definition gets a top/side/bottom tile
#  - the mesher emits one UV per vertex inside the correct atlas tile
#  - the world shader actually samples the atlas
#   Godot --headless --path lumen_deepworld --script res://debug/terrain_texture_check.gd

var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("TERRAIN TEXTURE FAIL: %s %s" % [label, detail])
		return
	print("TERRAIN TEXTURE PASS: %s %s" % [label, detail])


func _initialize() -> void:
	_check_atlas()
	_check_block_table()
	_check_mesher_uvs()
	_check_shader()
	if failures > 0:
		quit(1)
		return
	print("TERRAIN TEXTURE CHECK PASS")
	quit(0)


func _check_atlas() -> void:
	var image := TerrainAtlas.build_image()
	_check(image != null, "atlas image exists")
	_check(image.get_width() == TerrainAtlas.ATLAS_PIXELS and image.get_height() == TerrainAtlas.ATLAS_PIXELS,
		"atlas is %dx%d" % [TerrainAtlas.ATLAS_PIXELS, TerrainAtlas.ATLAS_PIXELS])
	var grass := _tile_stats(image, TerrainAtlas.Tile.GRASS_TOP)
	var stone := _tile_stats(image, TerrainAtlas.Tile.STONE)
	var dirt := _tile_stats(image, TerrainAtlas.Tile.DIRT)
	_check(grass["variance"] > 0.0015, "grass tile has pixel detail", "var=%.5f" % grass["variance"])
	_check(stone["variance"] > 0.0010, "stone tile has cracks", "var=%.5f" % stone["variance"])
	_check(absf(grass["mean"] - stone["mean"]) > 0.02, "grass and stone tiles differ",
		"grass=%.3f stone=%.3f" % [grass["mean"], stone["mean"]])
	_check(dirt["mean"] < 0.95, "dirt tile is not flat white", "mean=%.3f" % dirt["mean"])
	# Ore tiles must have nuggets brighter than the rock base.
	var ore := _tile_stats(image, TerrainAtlas.Tile.ORE_METAL)
	_check(ore["max"] >= 0.99 and ore["min"] < 0.72, "metal ore tile has bright nuggets on dark rock",
		"min=%.2f max=%.2f" % [ore["min"], ore["max"]])


func _tile_stats(image: Image, tile: int) -> Dictionary:
	var rect := TerrainAtlas.tile_rect(tile)
	var count := 0
	var total := 0.0
	var maximum := 0.0
	var minimum := 1.0
	var values: Array[float] = []
	for y in range(int(rect.size.y)):
		for x in range(int(rect.size.x)):
			var value := image.get_pixel(int(rect.position.x) + x, int(rect.position.y) + y).r
			total += value
			maximum = maxf(maximum, value)
			minimum = minf(minimum, value)
			values.append(value)
			count += 1
	var mean := total / float(maxi(count, 1))
	var variance := 0.0
	for value in values:
		variance += (value - mean) * (value - mean)
	return {"mean": mean, "variance": variance / float(maxi(count, 1)), "max": maximum, "min": minimum}


func _check_block_table() -> void:
	var defs: Array = []
	for path in VoxelWorld.BLOCK_RESOURCE_PATHS:
		var definition := load(path) as BlockLightDef
		if definition != null:
			defs.append(definition)
	var table := TerrainAtlas.block_tile_table(defs)
	_check(table.size() == defs.size(), "every block has a tile entry", "%d/%d" % [table.size(), defs.size()])
	var grass_tile := TerrainAtlas.tiles_for_block(&"dirt")
	_check(grass_tile.x == TerrainAtlas.Tile.GRASS_TOP and grass_tile.y == TerrainAtlas.Tile.DIRT,
		"dirt uses grass top and dirt side", str(grass_tile))
	var stone_tile := TerrainAtlas.tiles_for_block(&"stone")
	_check(stone_tile.x == stone_tile.y and stone_tile.y == stone_tile.z, "stone uses one stone tile", str(stone_tile))
	var hellstone := TerrainAtlas.tiles_for_block(&"hellstone")
	_check(hellstone.x == TerrainAtlas.Tile.MAGMA, "hellstone uses magma tile", str(hellstone))
	var missing := 0
	for definition in defs:
		var tiles := TerrainAtlas.tiles_for_block(definition.block_id)
		if tiles == Vector3i(0, 0, 0) and definition.block_id not in [&"air", &"test_wall"]:
			missing += 1
	_check(missing == 0, "all gameplay materials have textured tiles", "missing=%d" % missing)


func _check_mesher_uvs() -> void:
	# Synthetic 18^3 snapshot: air everywhere, one dirt cell at the core.
	var air := 0
	var snapshot := PackedByteArray()
	snapshot.resize(18 * 18 * 18)
	snapshot.fill(air)
	var index := 1 + 1 * 18 + 1 * 18 * 18
	snapshot[index] = 1  # local cell (0, 0, 0)
	var light := PackedByteArray()
	light.resize(18 * 18 * 18)
	light.fill(15)
	var sky := PackedByteArray()
	sky.resize(18 * 18 * 18)
	sky.fill(1)
	var palette := PackedColorArray([Color(1, 1, 1), Color(0.55, 0.35, 0.20)])
	var tiles: Array = [Vector3i(TerrainAtlas.Tile.PLAIN, TerrainAtlas.Tile.PLAIN, TerrainAtlas.Tile.PLAIN), TerrainAtlas.tiles_for_block(&"dirt")]
	var result := ChunkMesher.build(snapshot, light, sky, palette, air, {}, {}, [], tiles)
	var vertices: PackedVector3Array = result["vertices"]
	var normals: PackedVector3Array = result["normals"]
	var uvs: PackedVector2Array = result["uvs"]
	_check(vertices.size() == 36, "one exposed cube emits six faces", "vertices=%d" % vertices.size())
	_check(uvs.size() == vertices.size(), "one UV per vertex", "%d/%d" % [uvs.size(), vertices.size()])
	var side_tile := TerrainAtlas.tiles_for_block(&"dirt").y
	var top_tile := TerrainAtlas.tiles_for_block(&"dirt").x
	var side_min := float(side_tile) / 16.0
	var side_max := float(side_tile + 1) / 16.0
	var top_min := float(top_tile) / 16.0
	var top_max := float(top_tile + 1) / 16.0
	var inside := true
	var top_found := false
	for i in range(uvs.size()):
		var uv := uvs[i]
		var vertex := vertices[i]
		if normals[i].y > 0.9:
			top_found = true
			if uv.x < top_min or uv.x > top_max or uv.y < 0.0 or uv.y > top_max + 0.01:
				inside = false
		else:
			if uv.x < side_min or uv.x > side_max:
				inside = false
	_check(inside, "UVs stay inside their material tile")
	_check(top_found, "top face uses the top tile")


func _check_shader() -> void:
	var file := FileAccess.open("res://shaders/light_dither.gdshader", FileAccess.READ)
	_check(file != null, "world shader is readable")
	if file == null:
		return
	var source := file.get_as_text()
	_check(source.contains("uniform sampler2D atlas_texture"), "shader declares the atlas sampler")
	_check(source.contains("texture(atlas_texture, atlas_uv)"), "shader samples per-vertex UVs")
	_check(source.contains("filter_nearest"), "atlas sampling is nearest-neighbour")
