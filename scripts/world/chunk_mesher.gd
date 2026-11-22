extends RefCounted
class_name ChunkMesher

const CHUNK_SIZE := 16
const PADDED_SIZE := 18
const FACE_DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]
const FACE_NORMALS := [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
	Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
]
const FACE_CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]
]
# UV corner order matching FACE_CORNERS, so textures stay upright on every face.
const FACE_UV_CORNERS := [
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
	[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)],
	[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)],
	[Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)]
]
# Fake sun shading so untextured cubes read as solid objects instead of flat paint.
const FACE_SHADE := [0.94, 0.84, 1.0, 0.74, 0.90, 0.86]
# Tangent axes used to find the cells that occlude each face corner.
const FACE_TANGENTS := [
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0)],
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0)]
]
# Corner sign pairs (u, v) matching FACE_CORNERS order per face.
const FACE_CORNER_SIGNS := [
	[Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)],
	[Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, -1)],
	[Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, -1)],
	[Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)],
	[Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)],
	[Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1)]
]
const AO_SHADE := [1.0, 0.82, 0.66, 0.46]
# Top faces carry the ground the player walks on. Terraria's lighting is flat
# there, so a concave dip must not go black; side faces keep the firm ramp that
# gives cliffs and caves their shape.
const TOP_AO_SHADE := [1.0, 0.93, 0.86, 0.78]
# Coloured light cast: torches warm, radiant crystals cool.
# UV2.x gates sky fill, UV2.y scales the sun. Canopy columns get no sky fill
# and a heavily cut sun term, which is what keeps the Jungle dark at noon.
const HUSH_SUN_SHADE := 0.22
const LIGHT_TINT_RADIUS := 12.0
const WARM_LIGHT_TINT := Color(1.0, 0.66, 0.34)
const COOL_LIGHT_TINT := Color(0.40, 0.82, 1.0)
const ATLAS_COLUMNS := 16

static func _sky_uv(sky_value: int) -> Vector2:
	if sky_value <= 0:
		return Vector2(0.0, 1.0)
	if sky_value == 2:
		# Deep canopy: no sky fill and only a sliver of direct sun.
		return Vector2(0.0, HUSH_SUN_SHADE)
	if sky_value == 3:
		# Overcast: diffuse fill, muted direct sun (Snow and Forest).
		return Vector2(0.70, 0.50)
	return Vector2(1.0, 1.0)


## Maps a (u, v) corner inside one tile to atlas space. A half-texel inset
## stops nearest-neighbour sampling from bleeding into neighbouring tiles.
static func atlas_uv(tile: int, uv: Vector2) -> Vector2:
	var column := tile % ATLAS_COLUMNS
	var row := floori(float(tile) / float(ATLAS_COLUMNS))
	var inset := 0.5 / 256.0
	var local := Vector2(
		clampf(uv.x, 0.035, 0.965),
		clampf(uv.y, 0.035, 0.965)
	)
	return Vector2((float(column) + local.x) / float(ATLAS_COLUMNS), (float(row) + local.y) / float(ATLAS_COLUMNS)) + Vector2(inset, inset) * 0.0


static func _append_uv(uvs: PackedVector2Array, tile: int, face: int, corner_index: int) -> void:
	var corners: Array = FACE_UV_CORNERS[face]
	uvs.append(atlas_uv(tile, corners[corner_index]))


static func build(snapshot: PackedByteArray, light_snapshot: PackedByteArray, sky_snapshot: PackedByteArray, palette: PackedColorArray, air_id: int, fixture_ids: Dictionary = {}, emissive_ids: Dictionary = {}, light_sources: Array = [], block_tiles: Array = []) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var uvs := PackedVector2Array()
	for z in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			for x in range(CHUNK_SIZE):
				var cell_index := (x + 1) + (y + 1) * PADDED_SIZE + (z + 1) * PADDED_SIZE * PADDED_SIZE
				var block_id := int(snapshot[cell_index])
				if block_id == air_id:
					continue
				var cell := Vector3i(x, y, z)
				var hash_value := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
				var tone := float(hash_value & 0xFF) / 255.0
				# Gentle block-to-block toning. The old +/-6% range read as a
				# checkerboard on open grass; Terraria surfaces are even.
				var variation := 0.975 + tone * 0.05
				# Deterministic per-cell hue jitter so a large flat surface reads as
				# individual pixel-art blocks instead of one tinted plane.
				var hue_jitter := Color(
					1.0 + (tone - 0.5) * 0.03,
					1.0 + (fposmod(tone * 3.7, 1.0) - 0.5) * 0.03,
					1.0 + (fposmod(tone * 7.3, 1.0) - 0.5) * 0.03,
					1.0
				)
				var base_color: Color = palette[block_id]
				base_color = Color(
					minf(base_color.r * hue_jitter.r, 1.0),
					minf(base_color.g * hue_jitter.g, 1.0),
					minf(base_color.b * hue_jitter.b, 1.0),
					base_color.a
				)
				var block_tile := Vector3i(0, 0, 0)
				if block_id < block_tiles.size():
					block_tile = block_tiles[block_id]
				var fixture: StringName = fixture_ids.get(block_id, &"")
				if emissive_ids.has(block_id):
					# Crystals keep their facets readable instead of blooming into
					# flat cyan slabs; torches and beacons need the hotter boost.
					var boost := 1.5
					if fixture == &"lumen_crystal" or fixture == &"lava":
						boost = 1.15
					base_color = Color(base_color.r * boost, base_color.g * boost, base_color.b * boost, 1.0)
				if fixture != &"":
					if fixture == &"lumen_crystal":
						# A crystal column is one continuous shard. Only its base cell
						# draws geometry; stacked cells above it stay empty so the
						# spire does not become a stack of repeating shapes.
						var below_id := int(snapshot[cell_index - PADDED_SIZE])
						if below_id == block_id and y > 0:
							continue
						var run_height := 1
						while y + run_height < CHUNK_SIZE and int(snapshot[cell_index + run_height * PADDED_SIZE]) == block_id:
							run_height += 1
						_append_fixture(vertices, normals, colors, uv2, uvs, cell, fixture, base_color, float(int(light_snapshot[cell_index])) / 15.0, int(sky_snapshot[cell_index]), tone, run_height, block_tile)
					else:
						_append_fixture(vertices, normals, colors, uv2, uvs, cell, fixture, base_color, float(int(light_snapshot[cell_index])) / 15.0, int(sky_snapshot[cell_index]), tone, 1, block_tile)
					continue
				var face_ao := PackedFloat32Array()
				face_ao.resize(4)
				for face in range(6):
					var direction: Vector3i = FACE_DIRECTIONS[face]
					var neighbor_index := cell_index + direction.x + direction.y * PADDED_SIZE + direction.z * PADDED_SIZE * PADDED_SIZE
					var neighbor_id := int(snapshot[neighbor_index])
					# Emit solid-to-open faces. Fixtures are solid for gameplay but must not
					# occlude their neighbours, or removing their cubes leaves see-through holes.
					if neighbor_id != air_id and not fixture_ids.has(neighbor_id):
						continue
					var face_light := maxi(int(light_snapshot[cell_index]), int(light_snapshot[neighbor_index]))
					var shade: float = FACE_SHADE[face] * variation
					var light_alpha := float(face_light) / 15.0
					var tint := _light_tint(light_sources, Vector3(cell) + Vector3(0.5, 0.5, 0.5), light_alpha)
					_calculate_corner_ao(snapshot, cell_index, face, air_id, face_ao)
					var tile := block_tile.y
					if face == 2:
						tile = block_tile.x
					elif face == 3:
						tile = block_tile.z
					_append_face(vertices, normals, colors, uv2, uvs, cell, face, face_ao, shade, base_color, light_alpha, int(sky_snapshot[cell_index]), tint, tile)
	return {"vertices": vertices, "normals": normals, "colors": colors, "uv2": uv2, "uvs": uvs}


static func _calculate_corner_ao(snapshot: PackedByteArray, cell_index: int, face: int, air_id: int, result: PackedFloat32Array) -> void:
	var direction: Vector3i = FACE_DIRECTIONS[face]
	var tangent: Array = FACE_TANGENTS[face]
	var u: Vector3i = tangent[0]
	var v: Vector3i = tangent[1]
	var n_offset := direction.x + direction.y * PADDED_SIZE + direction.z * PADDED_SIZE * PADDED_SIZE
	var u_offset := u.x + u.y * PADDED_SIZE + u.z * PADDED_SIZE * PADDED_SIZE
	var v_offset := v.x + v.y * PADDED_SIZE + v.z * PADDED_SIZE * PADDED_SIZE
	var face_base := cell_index + n_offset
	var signs: Array = FACE_CORNER_SIGNS[face]
	for corner_index in range(4):
		var sign: Vector2i = signs[corner_index]
		var side_a := face_base + u_offset * sign.x
		var side_b := face_base + v_offset * sign.y
		var occluders := 0
		if int(snapshot[side_a]) != air_id:
			occluders += 1
		if int(snapshot[side_b]) != air_id:
			occluders += 1
		if int(snapshot[side_a + v_offset * sign.y]) != air_id:
			occluders += 1
		if face == 2:
			result[corner_index] = TOP_AO_SHADE[occluders]
		else:
			result[corner_index] = AO_SHADE[occluders]


# Nearest-source colour blend for cells reached by static light. Intensity still
# comes from the baked light buffer; this only shifts the hue toward the light
# that actually reaches the cell, so torches read warm and crystals cool.
static func _light_tint(sources: Array, center: Vector3, strength: float) -> Color:
	if sources.is_empty() or strength <= 0.02:
		return Color.WHITE
	var warm := 0.0
	var cool := 0.0
	for source in sources:
		var position: Vector3 = source["position"]
		var distance := center.distance_to(position)
		if distance >= LIGHT_TINT_RADIUS:
			continue
		var falloff := 1.0 - distance / LIGHT_TINT_RADIUS
		falloff *= falloff
		if bool(source.get("cool", false)):
			cool += falloff
		else:
			warm += falloff
	var total := warm + cool
	if total <= 0.0:
		return Color.WHITE
	var tint := COOL_LIGHT_TINT.lerp(WARM_LIGHT_TINT, warm / total)
	return Color.WHITE.lerp(tint, clampf(strength * 0.9, 0.0, 0.9))


# Torches and flora are drawn as small fixtures instead of full 1 m cubes.
static func _append_fixture(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, cell: Vector3i, fixture: StringName, block_color: Color, light_alpha: float, sky_value: int, tone: float, run_height: int, block_tile: Vector3i) -> void:
	var origin := Vector3(cell)
	var fixture_tile := 0
	if fixture == &"water" or fixture == &"lava":
		fixture_tile = 21
	elif fixture == &"lumen_crystal":
		fixture_tile = 22
	elif fixture == &"mycelium" or fixture == &"pale_bloom":
		fixture_tile = 24
	if fixture == &"torch":
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.24, 0.5), Vector3(0.12, 0.48, 0.12), Color(0.22, 0.20, 0.21), light_alpha, sky_value, 11)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.54, 0.5), Vector3(0.24, 0.20, 0.24), block_color, light_alpha, sky_value, 27)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.67, 0.5), Vector3(0.16, 0.06, 0.16), Color(0.18, 0.16, 0.17), light_alpha, sky_value, 0)
	elif fixture == &"beacon":
		_append_beacon(vertices, normals, colors, uv2, uvs, origin, block_color, light_alpha, sky_value, tone, 26)
	elif fixture == &"water":
		# Liquids are inset boxes so they never z-fight with neighbouring voxels;
		# the short top leaves a readable surface line inside the cell.
		_append_liquid(vertices, normals, colors, uv2, uvs, origin, block_color, light_alpha, sky_value, 0.86, tone, fixture_tile)
	elif fixture == &"lava":
		var hot := Color(minf(block_color.r * 1.08, 1.35), minf(block_color.g * 1.05, 1.35), minf(block_color.b * 1.02, 1.35), 1.0)
		_append_liquid(vertices, normals, colors, uv2, uvs, origin, hot, light_alpha, sky_value, 0.78, tone, fixture_tile)
	elif fixture == &"lumen_crystal":
		_append_crystal(vertices, normals, colors, uv2, uvs, origin, block_color, light_alpha, sky_value, tone, run_height, fixture_tile)
	elif fixture == &"mycelium":
		_append_cross(vertices, normals, colors, uv2, uvs, origin, 0.32, 0.18 + tone * 0.12, block_color, light_alpha, sky_value, tone, fixture_tile)
	elif fixture == &"wood_platform":
		# Deck flush with the top of the cell, so a platform is exactly a
		# surface you can stand on, with two brackets underneath for the
		# Terraria plank silhouette.
		var rail := block_color.darkened(0.30)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.93, 0.5), Vector3(0.99, 0.14, 0.99), block_color, light_alpha, sky_value, 40)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.79, 0.09), Vector3(0.99, 0.18, 0.12), rail, light_alpha, sky_value, 39)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.79, 0.91), Vector3(0.99, 0.18, 0.12), rail, light_alpha, sky_value, 39)
	elif fixture == &"glass":
		# A clear pane: only the frame is drawn, so you genuinely look through
		# the window while the block still blocks movement.
		var frame := Color(0.86, 0.94, 0.98, 1.0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.05, 0.5), Vector3(0.99, 0.10, 0.99), frame, light_alpha, sky_value, 41)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.95, 0.5), Vector3(0.99, 0.10, 0.99), frame, light_alpha, sky_value, 41)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.05, 0.5, 0.5), Vector3(0.10, 0.90, 0.99), frame, light_alpha, sky_value, 41)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.95, 0.5, 0.5), Vector3(0.10, 0.90, 0.99), frame, light_alpha, sky_value, 41)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.5, 0.5), Vector3(0.99, 0.05, 0.99), frame, light_alpha, sky_value, 41)
	elif fixture == &"workbench":
		var leg := block_color.darkened(0.28)
		var iron := Color(0.44, 0.46, 0.50, 1.0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.86, 0.5), Vector3(0.98, 0.12, 0.98), block_color, light_alpha, sky_value, 42)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.09, 0.44, 0.09), Vector3(0.10, 0.80, 0.10), leg, light_alpha, sky_value, 39)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.91, 0.44, 0.09), Vector3(0.10, 0.80, 0.10), leg, light_alpha, sky_value, 39)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.09, 0.44, 0.91), Vector3(0.10, 0.80, 0.10), leg, light_alpha, sky_value, 39)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.91, 0.44, 0.91), Vector3(0.10, 0.80, 0.10), leg, light_alpha, sky_value, 39)
		# A vice clamped to the bench and a hammer lying on it.
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.17, 0.96, 0.5), Vector3(0.20, 0.12, 0.28), iron, light_alpha, sky_value, 47)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.62, 0.96, 0.45), Vector3(0.26, 0.06, 0.10), iron, light_alpha, sky_value, 47)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.74, 0.95, 0.45), Vector3(0.05, 0.05, 0.05), leg, light_alpha, sky_value, 39)
	elif fixture == &"furnace":
		var brick := block_color
		var mouth := Color(1.0, 0.58, 0.18, 1.0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.44, 0.5), Vector3(0.92, 0.86, 0.92), brick, light_alpha, sky_value, 43)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.90, 0.5), Vector3(0.74, 0.10, 0.74), brick.darkened(0.25), light_alpha, sky_value, 43)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.30, 0.05), Vector3(0.54, 0.40, 0.10), mouth, light_alpha, sky_value, 27)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.49, 0.05), Vector3(0.58, 0.10, 0.12), brick.darkened(0.40), light_alpha, sky_value, 0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.08, 0.5), Vector3(0.98, 0.12, 0.98), brick.darkened(0.35), light_alpha, sky_value, 43)
	elif fixture == &"anvil":
		var dark_iron := Color(0.30, 0.32, 0.36, 1.0)
		var steel := Color(0.52, 0.55, 0.60, 1.0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.07, 0.5), Vector3(0.46, 0.14, 0.34), dark_iron, light_alpha, sky_value, 47)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.24, 0.5), Vector3(0.28, 0.22, 0.24), dark_iron, light_alpha, sky_value, 47)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.54, 0.42, 0.5), Vector3(0.66, 0.18, 0.34), steel, light_alpha, sky_value, 47)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.16, 0.42, 0.5), Vector3(0.26, 0.12, 0.18), steel, light_alpha, sky_value, 47)
	elif fixture == &"chest":
		var band := Color(0.30, 0.31, 0.35, 1.0)
		var lock := Color(0.92, 0.76, 0.34, 1.0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.34, 0.5), Vector3(0.86, 0.64, 0.64), block_color, light_alpha, sky_value, 44)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.70, 0.5), Vector3(0.90, 0.14, 0.68), block_color.lightened(0.08), light_alpha, sky_value, 44)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.24, 0.48, 0.5), Vector3(0.08, 0.66, 0.68), band, light_alpha, sky_value, 26)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.76, 0.48, 0.5), Vector3(0.08, 0.66, 0.68), band, light_alpha, sky_value, 26)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.58, 0.16), Vector3(0.14, 0.18, 0.10), lock, light_alpha, sky_value, 26)
	elif fixture == &"chair":
		# Terraria chair: four legs, a seat at hip height and a slatted back.
		var timber := block_color
		var leg_wood := block_color.darkened(0.30)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.47, 0.5), Vector3(0.52, 0.09, 0.52), timber, light_alpha, sky_value, 48)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.76, 0.14), Vector3(0.52, 0.50, 0.09), timber, light_alpha, sky_value, 48)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.90, 0.14), Vector3(0.40, 0.08, 0.12), leg_wood, light_alpha, sky_value, 48)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.24, 0.22, 0.24), Vector3(0.08, 0.44, 0.08), leg_wood, light_alpha, sky_value, 48)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.76, 0.22, 0.24), Vector3(0.08, 0.44, 0.08), leg_wood, light_alpha, sky_value, 48)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.24, 0.22, 0.76), Vector3(0.08, 0.44, 0.08), leg_wood, light_alpha, sky_value, 48)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.76, 0.22, 0.76), Vector3(0.08, 0.44, 0.08), leg_wood, light_alpha, sky_value, 48)
	elif fixture == &"stairs_n" or fixture == &"stairs_e" or fixture == &"stairs_s" or fixture == &"stairs_w":
		# Minecraft-style stairs: a full bottom slab plus a half slab on the
		# high side. The facing is the direction the steps climb.
		var step_tile: int = block_tile.x
		var stair_color := block_color
		var step_shadow := block_color.darkened(0.18)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.25, 0.5), Vector3(0.99, 0.5, 0.99), stair_color, light_alpha, sky_value, step_tile)
		var high := Vector3(0.5, 0.75, 0.5)
		var size := Vector3(0.99, 0.5, 0.5)
		if fixture == &"stairs_n":
			high.z = 0.25
		elif fixture == &"stairs_s":
			high.z = 0.75
		elif fixture == &"stairs_e":
			high.x = 0.75
			size.x = 0.5
		elif fixture == &"stairs_w":
			high.x = 0.25
			size.x = 0.5
		_append_box(vertices, normals, colors, uv2, uvs, origin + high, size, step_shadow, light_alpha, sky_value, step_tile)
	elif fixture == &"wood_door":
		var trim := block_color.darkened(0.40)
		var knob := Color(0.90, 0.74, 0.32, 1.0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.5, 0.03), Vector3(0.99, 1.0, 0.06), trim, light_alpha, sky_value, 45)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, 0.5, 0.10), Vector3(0.92, 0.98, 0.10), block_color, light_alpha, sky_value, 45)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.82, 0.48, 0.17), Vector3(0.09, 0.09, 0.06), knob, light_alpha, sky_value, 26)
	elif fixture == &"wood_door_open":
		# Swung into the cell: a thin panel hinged along the -X edge, leaving
		# the doorway clear.
		var trim_open := block_color.darkened(0.40)
		var knob_open := Color(0.90, 0.74, 0.32, 1.0)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.03, 0.5, 0.5), Vector3(0.06, 1.0, 0.99), trim_open, light_alpha, sky_value, 46)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.10, 0.5, 0.5), Vector3(0.10, 0.98, 0.92), block_color, light_alpha, sky_value, 46)
		_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.17, 0.48, 0.84), Vector3(0.06, 0.09, 0.09), knob_open, light_alpha, sky_value, 26)
	else:
		_append_cross(vertices, normals, colors, uv2, uvs, origin, 0.26, 0.50 + tone * 0.32, block_color, light_alpha, sky_value, tone, fixture_tile)


static func _append_liquid(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, origin: Vector3, color: Color, light_alpha: float, sky_value: int, surface_level: float, tone: float, tile: int) -> void:
	# Keep a hairline inset so cube faces never coincide at a chunk seam, and a
	# level top so lakes read as flat bodies of liquid rather than glass cubes.
	var wobble := (tone - 0.5) * 0.03
	var inset := 0.99
	_append_box(vertices, normals, colors, uv2, uvs, origin + Vector3(0.5, (surface_level + wobble) * 0.5, 0.5), Vector3(inset, surface_level + wobble, inset), color, light_alpha, sky_value, tile)


static func _append_cross(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, origin: Vector3, width: float, height: float, color: Color, light_alpha: float, sky_value: int, tone: float, tile: int) -> void:
	var half := width * 0.5
	var center_x := origin.x + 0.5 + (tone - 0.5) * 0.22
	var center_z := origin.z + 0.5 + (fposmod(tone * 7.0, 1.0) - 0.5) * 0.22
	var base_y := origin.y
	var top_y := origin.y + height
	_append_quad_2sided(vertices, normals, colors, uv2, uvs,
		Vector3(center_x - half, base_y, center_z), Vector3(center_x + half, base_y, center_z),
		Vector3(center_x + half, top_y, center_z), Vector3(center_x - half, top_y, center_z),
		color, light_alpha, sky_value, tile)
	_append_quad_2sided(vertices, normals, colors, uv2, uvs,
		Vector3(center_x, base_y, center_z - half), Vector3(center_x, base_y, center_z + half),
		Vector3(center_x, top_y, center_z + half), Vector3(center_x, top_y, center_z - half),
		color, light_alpha, sky_value, tile)


static func _append_quad_2sided(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, light_alpha: float, sky_value: int, tile: int) -> void:
	var points: Array[Vector3] = [a, b, c, d]
	var order := [0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3]
	var uv_points := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for index in order:
		vertices.append(points[index])
		normals.append(Vector3.UP)
		colors.append(Color(color.r, color.g, color.b, light_alpha))
		uv2.append(_sky_uv(sky_value))
		uvs.append(atlas_uv(tile, uv_points[index]))


static func _append_shaded_tri(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, color: Color, light_alpha: float, sky_value: int, outward: Vector3, tile: int) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		return
	normal = normal.normalized()
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	var uv_points := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
	var index := 0
	for point in [a, b, c]:
		vertices.append(point)
		normals.append(normal)
		colors.append(Color(color.r, color.g, color.b, light_alpha))
		uv2.append(_sky_uv(sky_value))
		uvs.append(atlas_uv(tile, uv_points[index]))
		index += 1


static func _append_shaded_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, light_alpha: float, sky_value: int, outward: Vector3, tile: int) -> void:
	_append_shaded_tri(vertices, normals, colors, uv2, uvs, a, b, c, color, light_alpha, sky_value, outward, tile)
	_append_shaded_tri(vertices, normals, colors, uv2, uvs, a, c, d, color, light_alpha, sky_value, outward, tile)


# One crystal column is one long faceted shard rooted at the floor, plus a few
# short splinters at its base. run_height is the number of stacked crystal
# blocks, so the geometry never repeats once per block.
static func _append_crystal(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, origin: Vector3, color: Color, light_alpha: float, sky_value: int, tone: float, run_height: int, tile: int) -> void:
	var center := origin + Vector3(0.5 + (tone - 0.5) * 0.08, 0.0, 0.5 + (fposmod(tone * 9.7, 1.0) - 0.5) * 0.08)
	var base_color := Color(color.r * 0.46, color.g * 0.56, color.b * 0.62, 1.0)
	var mid_color := Color(color.r * 0.92, color.g * 1.0, color.b * 1.02, 1.0)
	var tip_color := Color(minf(color.r * 1.60, 1.9), minf(color.g * 1.60, 1.9), minf(color.b * 1.64, 1.9), 1.0)
	var height := float(run_height) + 0.35 + tone * 0.30
	var radius := 0.17 + tone * 0.05 + minf(float(run_height), 8.0) * 0.010
	var lean := Vector3((tone - 0.5) * 0.34, 0.0, (fposmod(tone * 5.3, 1.0) - 0.5) * 0.30)
	_append_crystal_blade(vertices, normals, colors, uv2, uvs, center, lean, height, radius, 5, tone, base_color, mid_color, tip_color, light_alpha, sky_value, tile)
	for splinter in range(3):
		var angle := tone * TAU + TAU * float(splinter) / 3.0 + 0.8
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var splinter_base := center + outward * (0.20 + tone * 0.06)
		var splinter_height := 0.42 + fposmod(tone * 11.0 + float(splinter) * 0.31, 1.0) * 0.55
		_append_crystal_blade(vertices, normals, colors, uv2, uvs, splinter_base, outward * (0.16 + tone * 0.08), splinter_height, 0.075 + tone * 0.02, 4, tone + 0.17 * float(splinter), base_color, mid_color, tip_color, light_alpha, sky_value, tile)


static func _append_crystal_blade(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, base: Vector3, lean: Vector3, height: float, radius: float, sides: int, phase: float, base_color: Color, mid_color: Color, tip_color: Color, light_alpha: float, sky_value: int, tile: int) -> void:
	var low_ring: Array[Vector3] = []
	var mid_ring: Array[Vector3] = []
	var high_ring: Array[Vector3] = []
	for index in range(sides):
		var angle := phase * TAU + TAU * float(index) / float(sides)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var wobble := 0.80 + 0.28 * sin(float(index) * 2.4 + phase * 8.0)
		low_ring.append(base + direction * radius * wobble + Vector3.UP * -0.04)
		mid_ring.append(base + lean * 0.35 + direction * radius * wobble * 0.82 + Vector3.UP * height * 0.46)
		high_ring.append(base + lean * 0.72 + direction * radius * wobble * 0.46 + Vector3.UP * height * 0.78)
	var apex := base + lean + Vector3.UP * height
	for index in range(sides):
		var next := (index + 1) % sides
		var outward := (low_ring[index] + low_ring[next]) * 0.5 - base
		outward.y = 0.0
		var facet := 0.62 + 0.18 * float(index % 3)
		var facet_base := Color(base_color.r * facet, base_color.g * facet, base_color.b * facet, 1.0)
		var facet_mid := Color(mid_color.r * facet, mid_color.g * facet, mid_color.b * facet, 1.0)
		_append_shaded_quad(vertices, normals, colors, uv2, uvs, low_ring[index], low_ring[next], mid_ring[next], mid_ring[index], facet_base, light_alpha, sky_value, outward, tile)
		_append_shaded_quad(vertices, normals, colors, uv2, uvs, mid_ring[index], mid_ring[next], high_ring[next], high_ring[index], facet_mid, light_alpha, sky_value, outward, tile)
		_append_shaded_tri(vertices, normals, colors, uv2, uvs, high_ring[index], high_ring[next], apex, tip_color, light_alpha, sky_value, outward, tile)


static func _append_spike(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, base: Vector3, tip: Vector3, radius: float, color: Color, light_alpha: float, sky_value: int, tile: int) -> void:
	var sides := 4
	var ring: Array[Vector3] = []
	for index in range(sides):
		var angle := TAU * float(index) / float(sides) + 0.4
		ring.append(base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	var axis := (tip - base).normalized()
	for index in range(sides):
		var next := (index + 1) % sides
		var outward := (ring[index] + ring[next]) * 0.5 - base
		outward -= axis * outward.dot(axis)
		_append_shaded_tri(vertices, normals, colors, uv2, uvs, ring[index], ring[next], tip, color, light_alpha, sky_value, outward, tile)


# Deployed Beacon: dark plinth, emitter collar, tapered light spike and fins.
static func _append_beacon(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, origin: Vector3, color: Color, light_alpha: float, sky_value: int, tone: float, tile: int) -> void:
	var center := origin + Vector3(0.5, 0.0, 0.5)
	var metal := Color(0.10, 0.12, 0.14)
	_append_box(vertices, normals, colors, uv2, uvs, center + Vector3(0, 0.07, 0), Vector3(0.64, 0.14, 0.64), metal, light_alpha, sky_value, tile)
	_append_box(vertices, normals, colors, uv2, uvs, center + Vector3(0, 0.17, 0), Vector3(0.46, 0.08, 0.46), Color(color.r * 0.30, color.g * 0.34, color.b * 0.36), light_alpha, sky_value, tile)
	_append_box(vertices, normals, colors, uv2, uvs, center + Vector3(0, 0.24, 0), Vector3(0.52, 0.035, 0.10), Color(color.r * 0.55, color.g * 0.62, color.b * 0.64), light_alpha, sky_value, tile)
	_append_box(vertices, normals, colors, uv2, uvs, center + Vector3(0, 0.24, 0), Vector3(0.10, 0.035, 0.52), Color(color.r * 0.55, color.g * 0.62, color.b * 0.64), light_alpha, sky_value, tile)
	_append_spike(vertices, normals, colors, uv2, uvs, center + Vector3(0, 0.20, 0), center + Vector3(0, 0.86 + tone * 0.10, 0), 0.13, Color(color.r * 1.2, color.g * 1.2, color.b * 1.2), light_alpha, sky_value, 22)
	_append_box(vertices, normals, colors, uv2, uvs, center + Vector3(0, 0.93 + tone * 0.10, 0), Vector3(0.11, 0.11, 0.11), Color(color.r * 1.45, color.g * 1.45, color.b * 1.45), light_alpha, sky_value, 27)


static func _append_box(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, center: Vector3, size: Vector3, color: Color, light_alpha: float, sky_value: int, tile: int) -> void:
	var vertex_order := [0, 2, 1, 0, 3, 2]
	for face in range(6):
		var corners: Array = FACE_CORNERS[face]
		for corner_index in vertex_order:
			var corner: Vector3 = corners[corner_index]
			vertices.append(center + (corner - Vector3(0.5, 0.5, 0.5)) * size)
			normals.append(FACE_NORMALS[face])
			colors.append(Color(color.r, color.g, color.b, light_alpha))
			uv2.append(_sky_uv(sky_value))
			_append_uv(uvs, tile, face, corner_index)


static func _append_face(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uv2: PackedVector2Array, uvs: PackedVector2Array, cell: Vector3i, face: int, face_ao: PackedFloat32Array, shade: float, block_color: Color, light_alpha: float, sky_value: int, tint: Color, tile: int) -> void:
	var corners: Array = FACE_CORNERS[face]
	var vertex_order := [0, 2, 1, 0, 3, 2]
	for corner_index in vertex_order:
		vertices.append(Vector3(cell) + corners[corner_index])
		normals.append(FACE_NORMALS[face])
		var ao: float = face_ao[corner_index]
		colors.append(Color(
			block_color.r * shade * ao * tint.r,
			block_color.g * shade * ao * tint.g,
			block_color.b * shade * ao * tint.b,
			light_alpha
		))
		uv2.append(_sky_uv(sky_value))
		_append_uv(uvs, tile, face, corner_index)
