extends Node3D
class_name WorldVegetation

const VEGETATION_SHADER := preload("res://shaders/vegetation.gdshader")
const ARCHETYPE_COUNT := 6
const ARCHETYPE_SEED := 4111
const GRASS_CELL := 2
const GRASS_CHANCE := 0.12
const HUSH_ARCHETYPES := 3
const HUSH_PALE := Color(0.78, 0.80, 0.72)
const HUSH_DARK := Color(0.30, 0.33, 0.29)
const ICE_PALE := Color(0.78, 0.90, 1.0)
const ICE_DEEP := Color(0.32, 0.54, 0.78)
const ROOT_DARK := Color(0.14, 0.19, 0.09)
const ROOT_LIGHT := Color(0.38, 0.46, 0.20)
const BARK_DARK := Color(0.16, 0.12, 0.11)
const BARK_LIGHT := Color(0.58, 0.49, 0.40)
const GRASS_DARK := Color(0.16, 0.17, 0.12)
const GRASS_LIGHT := Color(0.30, 0.40, 0.20)
# Terraria-style blocky leaf canopies. The old archetypes were bare dead
# branches from the horror build; every surface tree now carries foliage.
const LEAF_DARK := Color(0.10, 0.32, 0.09)
const LEAF_LIGHT := Color(0.36, 0.76, 0.24)
const JUNGLE_LEAF_DARK := Color(0.08, 0.30, 0.08)
const JUNGLE_LEAF_LIGHT := Color(0.28, 0.72, 0.18)

var tree_meshes: Array[ArrayMesh] = []
var tree_materials: Array[ShaderMaterial] = []
var materials: Array[ShaderMaterial] = []
var tree_instances: Array[MultiMeshInstance3D] = []
var tree_multimeshes: Array[MultiMesh] = []
var tree_texture: ImageTexture
var biome_tree_instances: Dictionary = {}
var biome_tree_multimeshes: Dictionary = {}
var grass_instance: MultiMeshInstance3D
var hush_instances: Array[MultiMeshInstance3D] = []
var hush_multimeshes: Array[MultiMesh] = []
var mushroom_instance: MultiMeshInstance3D
var flower_instance: MultiMeshInstance3D
var bush_instance: MultiMeshInstance3D
var spire_instance: MultiMeshInstance3D
var root_instance: MultiMeshInstance3D
var tree_sites: Array = []
var site_slots: Dictionary = {}
var tree_count := 0
var grass_count := 0
var region_center := Vector2i(1 << 30, 1 << 30)
var region_seed := -1
var region_radius := 0


func configure(world_bounds: AABB) -> void:
	tree_texture = TreeAtlas.texture()
	for index in range(ARCHETYPE_COUNT):
		tree_meshes.append(_build_archetype(index))
		tree_materials.append(_make_tree_material(0.0))
		tree_multimeshes.append(MultiMesh.new())
		var instance := MultiMeshInstance3D.new()
		instance.name = "Trees_%d" % index
		instance.multimesh = tree_multimeshes[index]
		instance.material_override = tree_materials[index]
		# Terraria foliage does not stamp hard black shadows on the grass; the
		# canopy already reads through the tree shader's own shading.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.custom_aabb = world_bounds
		instance.visibility_range_end = 0.0
		add_child(instance)
		tree_instances.append(instance)

	grass_instance = _make_cover_instance("AshGrass", _build_grass_mesh(), 0.10)
	flower_instance = _make_cover_instance("Wildflowers", _build_flower_mesh(), 0.12)
	bush_instance = _make_cover_instance("Bushes", _build_bush_mesh(), 0.10)
	bush_instance.material_override = _make_tree_material(0.10)
	flower_instance.custom_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(200000.0, 96.0, 200000.0))
	bush_instance.custom_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(200000.0, 96.0, 200000.0))

	# Jungle: dense broadleaf trees plus glowing ground fungi.
	for index in range(HUSH_ARCHETYPES):
		var mesh := _build_jungle_tree(index)
		var material := _make_tree_material(0.22)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		var instance := MultiMeshInstance3D.new()
		instance.name = "JungleTrees_%d" % index
		instance.multimesh = multimesh
		instance.material_override = material
		# Terraria foliage does not stamp hard black shadows on the grass; the
		# canopy already reads through the tree shader's own shading.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.custom_aabb = world_bounds
		instance.visibility_range_end = 0.0
		add_child(instance)
		hush_instances.append(instance)
		hush_multimeshes.append(multimesh)
	mushroom_instance = _make_glow_instance("HushMushrooms", _build_mushroom_mesh())
	for style in ["snow", "desert", "mushroom", "evil", "hallow"]:
		var biome_mesh := _build_biome_tree(style)
		var biome_material := _make_tree_material(0.10, 0.34 if style == "mushroom" else 0.0)
		var biome_multimesh := MultiMesh.new()
		biome_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		biome_multimesh.mesh = biome_mesh
		var biome_instance := MultiMeshInstance3D.new()
		biome_instance.name = "BiomeTrees_%s" % style
		biome_instance.multimesh = biome_multimesh
		biome_instance.material_override = biome_material
		biome_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		biome_instance.custom_aabb = world_bounds
		biome_instance.visibility_range_end = 0.0
		add_child(biome_instance)
		biome_tree_instances[style] = biome_instance
		biome_tree_multimeshes[style] = biome_multimesh

	# Snow spires and Mire roots share the biome-lit vegetation shader.
	spire_instance = _make_cover_instance("IceSpires", _build_spire_mesh(), 0.0)
	root_instance = _make_cover_instance("MireRoots", _build_root_mesh(), 0.04)
	# The streaming world is unbounded; a map-centred AABB would cull these
	# batches the moment the camera leaves the spawn area.
	var infinite_aabb := AABB(Vector3(-8.0, -8.0, -8.0), Vector3(200000.0, 96.0, 200000.0))
	spire_instance.custom_aabb = infinite_aabb
	root_instance.custom_aabb = infinite_aabb


# Region-based rebuild: trees and tufts follow the streaming centre instead of
# being baked once over a fixed 128x128 map.
func update_region(world_seed: int, center: Vector2i, radius: int) -> void:
	if world_seed == region_seed and radius == region_radius and center.distance_squared_to(region_center) < 48 * 48:
		return
	region_seed = world_seed
	region_center = center
	region_radius = radius
	BiomeManager.configure(world_seed)
	var sites := WorldGenerator.collect_tree_sites_region(world_seed, center.x - radius, center.y - radius, center.x + radius, center.y + radius)
	_apply_sites(sites)
	_build_biome_props(world_seed, center, mini(radius, 72))
	_build_biome_trees(world_seed, center, mini(radius, 72))
	_build_region_cover(world_seed, center, mini(radius, 72))
	_build_surface_details(world_seed, center, mini(radius, 72))


func _apply_sites(sites: Array) -> void:
	tree_sites = sites
	var per_archetype: Array = []
	for index in range(ARCHETYPE_COUNT):
		per_archetype.append([])
	site_slots.clear()
	for site in sites:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(site["seed"])
		var archetype := rng.randi_range(0, ARCHETYPE_COUNT - 1)
		var landmark := bool(site["landmark"])
		var scale_value := rng.randf_range(1.5, 1.9) if landmark else rng.randf_range(1.0, 1.32)
		var rotation := rng.randf_range(0.0, TAU)
		var position := Vector3(float(site["x"]) + 0.5, float(site["y"]) + 1.0, float(site["z"]) + 0.5)
		var transform := Transform3D(Basis(Vector3.UP, rotation).scaled(Vector3(scale_value, scale_value * rng.randf_range(0.95, 1.12), scale_value)), position)
		per_archetype[archetype].append(transform)

	for archetype in range(ARCHETYPE_COUNT):
		var transforms: Array = per_archetype[archetype]
		var multimesh := tree_multimeshes[archetype]
		# Transform format and mesh may only change while the batch is empty;
		# each streaming region rebuild arrives with the previous instances live.
		multimesh.instance_count = 0
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = tree_meshes[archetype]
		multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multimesh.set_instance_transform(index, transforms[index])

	# Site slots are built in the same order as each archetype's transforms so a
	# mined stump can hide its own tree without touching the rest of the batch.
	var archetype_cursor := PackedInt32Array()
	archetype_cursor.resize(ARCHETYPE_COUNT)
	archetype_cursor.fill(0)
	tree_count = 0
	for site in sites:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(site["seed"])
		var archetype := rng.randi_range(0, ARCHETYPE_COUNT - 1)
		site_slots[Vector3i(int(site["x"]), int(site["y"]), int(site["z"]))] = {
			"archetype": archetype,
			"index": archetype_cursor[archetype]
		}
		archetype_cursor[archetype] += 1
		tree_count += 1


func set_sun(direction: Vector3, color: Color, strength: float) -> void:
	for material in materials:
		material.set_shader_parameter("sun_direction", direction.normalized())
		material.set_shader_parameter("sun_color", Vector3(color.r, color.g, color.b))
		material.set_shader_parameter("sun_strength", clampf(strength, 0.0, 1.0))


func set_ambient_level(level: float) -> void:
	for material in materials:
		material.set_shader_parameter("ambient_sky_level", clampf(level, 0.0, 1.0))


func hide_tree_at(stump_cell: Vector3i) -> void:
	if not site_slots.has(stump_cell):
		return
	var slot: Dictionary = site_slots[stump_cell]
	var multimesh: MultiMesh = tree_multimeshes[int(slot["archetype"])]
	var index := int(slot["index"])
	if index < 0 or index >= multimesh.instance_count:
		return
	multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0)))


# --- Tree archetypes --------------------------------------------------------

func _build_archetype(index: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = ARCHETYPE_SEED + index * 7919
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	match index:
		0:
			_build_tall_tree(st, rng)
		1:
			_build_leaning_tree(st, rng)
		2:
			_build_gnarled_tree(st, rng)
		3:
			_build_snag(st, rng)
		4:
			_build_forked_tree(st, rng)
		_:
			_build_sparse_tree(st, rng)
	st.generate_normals()
	return st.commit()


func _build_tall_tree(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	# Terraria proportions: a stout trunk that is roughly one third of the
	# total silhouette, carrying a broad multi-tier crown.
	var height := 7.2
	var points := _add_trunk(st, rng, height, 0.54, 0.17, Vector3(0.30, 0.0, 0.16), 4, 6)
	_add_roots(st, rng, 0.60)
	for side_index in range(3):
		var origin: Vector3 = points[rng.randi_range(1, points.size() - 2)]
		var angle := TAU * float(side_index) / 3.0 + rng.randf_range(-0.35, 0.35)
		var direction := Vector3(cos(angle), rng.randf_range(0.55, 0.95), sin(angle))
		_add_branch(st, rng, origin, direction, rng.randf_range(1.2, 1.9), 0.14, height)
		var tip := origin + direction.normalized() * rng.randf_range(1.1, 1.7) + Vector3.UP * 0.45
		_add_leaf_cards(st, tip, Vector3(1.30, 0.80, 1.30), rng, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)
	_add_canopy(st, rng, points[points.size() - 1], 2.9, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)


func _build_leaning_tree(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var height := 6.8
	var points := _add_trunk(st, rng, height, 0.50, 0.15, Vector3(1.70, 0.0, 0.55), 4, 6)
	_add_roots(st, rng, 0.58)
	for branch in range(2):
		var origin: Vector3 = points[rng.randi_range(1, points.size() - 2)]
		var direction := Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.45, 0.85), rng.randf_range(-0.8, 0.8))
		_add_branch(st, rng, origin, direction, rng.randf_range(1.4, 2.1), 0.13, height)
		var tip := origin + direction.normalized() * 1.5 + Vector3.UP * 0.4
		_add_leaf_cards(st, tip, Vector3(1.25, 0.78, 1.25), rng, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)
	_add_canopy(st, rng, points[points.size() - 1], 2.7, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)


func _build_gnarled_tree(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var height := 6.2
	var points := _add_trunk(st, rng, height, 0.62, 0.19, Vector3(0.70, 0.0, 0.60), 5, 6)
	_add_roots(st, rng, 0.68)
	for branch in range(5):
		var origin: Vector3 = points[rng.randi_range(1, points.size() - 1)]
		var angle := TAU * float(branch) / 5.0 + rng.randf_range(-0.4, 0.4)
		var direction := Vector3(cos(angle), rng.randf_range(0.30, 0.85), sin(angle))
		_add_branch(st, rng, origin, direction, rng.randf_range(1.1, 1.9), 0.12, height, true)
	_add_canopy(st, rng, points[points.size() - 1], 3.1, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)


func _build_snag(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var height := 4.2
	var points := _add_trunk(st, rng, height, 0.62, 0.26, Vector3(0.25, 0.0, -0.2), 3, 5)
	_add_roots(st, rng, 0.70)
	for spike in range(2):
		var top: Vector3 = points[points.size() - 1]
		var direction := Vector3(rng.randf_range(-0.7, 0.7), 1.0, rng.randf_range(-0.7, 0.7))
		_add_limb(st, top, top + direction.normalized() * rng.randf_range(0.4, 0.9), 0.16, 0.02, 4, 0.85, 1.0)
	for stub in range(2):
		var origin: Vector3 = points[rng.randi_range(1, points.size() - 1)]
		var angle := rng.randf_range(0.0, TAU)
		_add_limb(st, origin, origin + Vector3(cos(angle), 0.25, sin(angle)) * rng.randf_range(0.5, 1.0), 0.14, 0.04, 4, 0.5, 0.7)
	_add_canopy(st, rng, points[points.size() - 1], 1.9, LEAF_DARK.lerp(Color(0.34, 0.30, 0.10), 0.35), LEAF_LIGHT.lerp(Color(0.72, 0.62, 0.24), 0.35), TreeAtlas.Tile.LEAF)


func _build_forked_tree(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var base := Vector3.ZERO
	_add_roots(st, rng, 0.52)
	for side_index in range(2):
		var side := -1.0 if side_index == 0 else 1.0
		var direction := Vector3(0.75 * side, 0.0, rng.randf_range(-0.3, 0.3))
		var points := _add_trunk(st, rng, 6.0, 0.40, 0.13, direction * 1.2, 4, 6, base + Vector3(0.12 * side, 0.0, 0.0))
		var origin: Vector3 = points[rng.randi_range(1, points.size() - 2)]
		var angle := rng.randf_range(-1.0, 1.0)
		_add_branch(st, rng, origin, Vector3(cos(angle), rng.randf_range(0.35, 0.8), sin(angle)), rng.randf_range(1.2, 1.9), 0.11, 6.0)
		_add_canopy(st, rng, points[points.size() - 1], 2.5, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)


func _build_sparse_tree(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var height := 5.4
	var points := _add_trunk(st, rng, height, 0.34, 0.10, Vector3(-0.45, 0.0, 0.35), 4, 5)
	_add_roots(st, rng, 0.38)
	for branch in range(2):
		var origin: Vector3 = points[rng.randi_range(1, points.size() - 2)]
		var angle := rng.randf_range(0.0, TAU)
		var direction := Vector3(cos(angle), rng.randf_range(0.5, 0.9), sin(angle))
		_add_branch(st, rng, origin, direction, rng.randf_range(1.2, 1.9), 0.09, height)
		var tip := origin + direction.normalized() * 1.2 + Vector3.UP * 0.3
		_add_leaf_cards(st, tip, Vector3(1.0, 0.65, 1.0), rng, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)
	_add_canopy(st, rng, points[points.size() - 1], 2.1, LEAF_DARK, LEAF_LIGHT, TreeAtlas.Tile.LEAF)


## Wide, layered crown in the Terraria read: several flat ragged leaf decks
## stacked with shrinking radius, each ringed by satellite lobes, topped by a
## crown cluster. Keeps a stepped pixel silhouette rather than a single blob.
func _add_canopy(st: SurfaceTool, rng: RandomNumberGenerator, top: Vector3, radius: float, dark: Color, light: Color, tile := TreeAtlas.Tile.LEAF) -> void:
	var tiers := 3
	for tier in range(tiers):
		var t := float(tier) / float(tiers - 1)
		var center := Vector3(top.x, top.y - 0.60 + t * 1.55, top.z)
		var reach_radius := radius * (1.12 - 0.40 * t)
		var lobes := 7
		for lobe in range(lobes):
			var angle := TAU * float(lobe) / float(lobes) + rng.randf_range(-0.16, 0.16) + t * 0.62
			var reach := reach_radius * rng.randf_range(0.52, 0.90)
			var lobe_center := center + Vector3(cos(angle) * reach, rng.randf_range(-0.12, 0.22), sin(angle) * reach)
			var lobe_dark := dark.lerp(light, rng.randf_range(0.0, 0.16))
			var lobe_light := light.lerp(dark, rng.randf_range(0.0, 0.24))
			_add_leaf_cards(st, lobe_center, Vector3(reach_radius * 0.56, reach_radius * 0.34, reach_radius * 0.56), rng, lobe_dark, lobe_light, tile)
		# A flatter deck plate per tier produces the stepped horizontal canopy edge.
		_add_leaf_cards(st, center, Vector3(reach_radius * 0.95, reach_radius * 0.15, reach_radius * 0.95), rng, dark.darkened(0.10), light, tile)
	_add_leaf_cluster(st, rng, top + Vector3.UP * 0.55, radius * 0.52, 3, dark, light, tile)


# --- Mesh construction helpers ----------------------------------------------

func _add_trunk(st: SurfaceTool, rng: RandomNumberGenerator, height: float, base_radius: float, tip_radius: float, lean: Vector3, segments: int, sides: int, base := Vector3.ZERO) -> Array[Vector3]:
	var points: Array[Vector3] = [base]
	var position := base
	var step_height := height / float(segments)
	for segment in range(segments):
		var t0 := float(segment) / float(segments)
		var t1 := float(segment + 1) / float(segments)
		var step := Vector3(
			lean.x / float(segments) + rng.randf_range(-0.10, 0.10),
			step_height,
			lean.z / float(segments) + rng.randf_range(-0.10, 0.10)
		)
		var next := position + step
		_add_limb(st, position, next, lerpf(base_radius, tip_radius, t0), lerpf(base_radius, tip_radius, t1), sides, t0, t1)
		points.append(next)
		position = next
	return points


func _add_branch(st: SurfaceTool, rng: RandomNumberGenerator, origin: Vector3, direction: Vector3, length: float, radius: float, tree_height: float, sub_branches := false) -> void:
	var dir := direction.normalized()
	var mid := origin + dir * length * 0.55 + Vector3.UP * length * 0.18
	var tip := mid + (dir + Vector3.UP * rng.randf_range(-0.1, 0.35)).normalized() * length * 0.45 + Vector3.DOWN * rng.randf_range(0.0, 0.55)
	var mid_height := clampf(mid.y / tree_height, 0.0, 1.0)
	var tip_height := clampf(tip.y / tree_height, 0.0, 1.0)
	var origin_height := clampf(origin.y / tree_height, 0.0, 1.0)
	_add_limb(st, origin, mid, radius, radius * 0.6, 4, origin_height, mid_height)
	_add_limb(st, mid, tip, radius * 0.6, 0.015, 4, mid_height, tip_height)
	if sub_branches and rng.randf() < 0.6:
		var angle := rng.randf_range(0.0, TAU)
		var sub_dir := Vector3(cos(angle), rng.randf_range(0.3, 0.8), sin(angle))
		var sub_tip := mid + sub_dir.normalized() * length * 0.55
		_add_limb(st, mid, sub_tip, radius * 0.45, 0.012, 4, mid_height, clampf(sub_tip.y / tree_height, 0.0, 1.0))


# Layered cutout leaf cards: each crown blob is several randomly oriented
# textured quads. This gives a leafy silhouette and real texture instead of
# faceted octahedron blobs. Vertex alpha stays 1.0 for the wind bend.
func _add_leaf_cluster(st: SurfaceTool, rng: RandomNumberGenerator, center: Vector3, radius: float, count: int, dark := LEAF_DARK, light := LEAF_LIGHT, tile := TreeAtlas.Tile.LEAF) -> void:
	for blob in range(count):
		var offset := Vector3(
			rng.randf_range(-1.0, 1.0) * radius * 0.85,
			rng.randf_range(-0.22, 0.55) * radius,
			rng.randf_range(-1.0, 1.0) * radius * 0.85
		)
		var blob_radius := radius * rng.randf_range(0.42, 0.68)
		_add_leaf_cards(st, center + offset, Vector3(blob_radius, blob_radius * 0.82, blob_radius), rng, dark, light, tile)


func _add_leaf_cards(st: SurfaceTool, center: Vector3, size: Vector3, rng: RandomNumberGenerator, dark: Color, light: Color, tile: int) -> void:
	var card_count := 5 + rng.randi_range(0, 2)
	var uv0 := TreeAtlas.uv(tile, Vector2(0.0, 1.0))
	var uv1 := TreeAtlas.uv(tile, Vector2(1.0, 1.0))
	var uv2 := TreeAtlas.uv(tile, Vector2(1.0, 0.0))
	var uv3 := TreeAtlas.uv(tile, Vector2(0.0, 0.0))
	for card in range(card_count):
		var yaw := rng.randf_range(0.0, TAU)
		var tilt := rng.randf_range(-0.65, 0.65)
		var right := Vector3(cos(yaw), 0.0, sin(yaw)) * size.x * rng.randf_range(0.34, 0.54)
		var side := Vector3(-sin(yaw), 0.0, cos(yaw)) * size.z * sin(tilt) * 0.50
		var up := Vector3.UP * size.y * rng.randf_range(0.40, 0.62) + side
		var a := center - right - up
		var b := center + right - up
		var c := center + right + up
		var d := center - right + up
		var bottom := dark.lerp(light, rng.randf_range(0.0, 0.22))
		var top := light.lerp(dark, rng.randf_range(0.0, 0.20))
		_add_textured_triangle(st, a, b, c, bottom, top, top, uv0, uv1, uv2)
		_add_textured_triangle(st, a, c, d, bottom, top, bottom, uv0, uv2, uv3)


func _add_roots(st: SurfaceTool, rng: RandomNumberGenerator, radius: float) -> void:
	for root in range(4):
		var angle := TAU * float(root) / 4.0 + rng.randf_range(-0.3, 0.3)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var start := direction * radius * 0.35 + Vector3.UP * 0.65
		var end := direction * radius * rng.randf_range(1.5, 2.0) + Vector3(0.0, 0.05, 0.0)
		_add_limb(st, start, end, radius * 0.42, 0.02, 4, 0.1, 0.0)


func _add_limb(st: SurfaceTool, from: Vector3, to: Vector3, radius_from: float, radius_to: float, sides: int, height_from: float, height_to: float) -> void:
	var axis := (to - from)
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	var reference := Vector3.UP if absf(axis.y) < 0.92 else Vector3.RIGHT
	var side := axis.cross(reference).normalized()
	var forward := axis.cross(side).normalized()
	var from_ring: Array[Vector3] = []
	var to_ring: Array[Vector3] = []
	for index in range(sides):
		var angle := TAU * float(index) / float(sides)
		var offset := side * cos(angle) + forward * sin(angle)
		from_ring.append(from + offset * radius_from)
		to_ring.append(to + offset * radius_to)
	var from_color := _bark_color(height_from)
	var to_color := _bark_color(height_to)
	for index in range(sides):
		var next := (index + 1) % sides
		_add_triangle(st, from_ring[index], to_ring[index], to_ring[next], from_color, to_color, to_color)
		_add_triangle(st, from_ring[index], to_ring[next], from_ring[next], from_color, to_color, from_color)
	var center_color := _bark_color(height_to)
	for index in range(sides):
		var next := (index + 1) % sides
		_add_triangle(st, to, to_ring[next], to_ring[index], center_color, to_color, to_color)


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() > 0.000001:
		normal = normal.normalized()
	var uv_a := TreeAtlas.uv(TreeAtlas.Tile.BARK, _bark_uv(a))
	var uv_b := TreeAtlas.uv(TreeAtlas.Tile.BARK, _bark_uv(b))
	var uv_c := TreeAtlas.uv(TreeAtlas.Tile.BARK, _bark_uv(c))
	st.set_normal(normal)
	st.set_color(color_a)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_color(color_b)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_color(color_c)
	st.set_uv(uv_c)
	st.add_vertex(c)


func _add_textured_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color, color_c: Color, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	# Leaf cards are double-sided; an up-facing normal keeps both sides from
	# becoming black silhouettes when the random card faces away from the sun.
	var normal := Vector3.UP
	st.set_normal(normal)
	st.set_color(color_a)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_color(color_b)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_color(color_c)
	st.set_uv(uv_c)
	st.add_vertex(c)


func _bark_uv(point: Vector3) -> Vector2:
	return Vector2(
		0.10 + fposmod(point.x * 0.21 + point.z * 0.13, 0.80),
		0.10 + fposmod(point.y * 0.19, 0.80)
	)


func _bark_color(height: float) -> Color:
	var color := BARK_DARK.lerp(BARK_LIGHT, clampf(height, 0.0, 1.0))
	color.a = clampf(height, 0.0, 1.0)
	return color


# --- Biome-specific low-poly props ------------------------------------------

func _add_limb_tinted(st: SurfaceTool, from: Vector3, to: Vector3, radius_from: float, radius_to: float, sides: int, color_from: Color, color_to: Color) -> void:
	var axis := to - from
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	var reference := Vector3.UP if absf(axis.y) < 0.92 else Vector3.RIGHT
	var side := axis.cross(reference).normalized()
	var forward := axis.cross(side).normalized()
	var from_ring: Array[Vector3] = []
	var to_ring: Array[Vector3] = []
	for index in range(sides):
		var angle := TAU * float(index) / float(sides)
		var offset := side * cos(angle) + forward * sin(angle)
		from_ring.append(from + offset * radius_from)
		to_ring.append(to + offset * radius_to)
	for index in range(sides):
		var next := (index + 1) % sides
		_add_triangle(st, from_ring[index], to_ring[index], to_ring[next], color_from, color_to, color_to)
		_add_triangle(st, from_ring[index], to_ring[next], from_ring[next], color_from, color_to, color_from)
	for index in range(sides):
		var next := (index + 1) % sides
		_add_triangle(st, to, to_ring[next], to_ring[index], color_to, color_to, color_to)


func _tinted(height: float, dark: Color, light: Color) -> Color:
	var color := dark.lerp(light, clampf(height, 0.0, 1.0))
	color.a = clampf(height, 0.0, 1.0)
	return color


# Broadleaf Jungle tree: a thick, slightly leaning trunk with buttress roots,
# wide green crown clusters and hanging vines. This replaces the old pale
# claw-tree silhouette entirely; no horror-style bare hooks remain.
func _build_jungle_tree(index: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9101 + index * 3313
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var height := 8.4 + float(index) * 1.1
	var lean := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.0, 1.0))
	var points := _add_trunk(st, rng, height, 0.58, 0.13, lean, 5, 6)
	_add_roots(st, rng, 0.72)
	# Buttress fins make the base read as a jungle tree rather than a pole.
	for fin in range(3):
		var angle := TAU * float(fin) / 3.0 + 0.4
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		_add_limb_tinted(st, Vector3(0.0, 1.2, 0.0), outward * 0.9 + Vector3(0.0, 0.02, 0.0), 0.18, 0.03, 4, BARK_DARK.lerp(BARK_LIGHT, 0.35), BARK_LIGHT)
	# Branches carry a crown cluster at each tip.
	for branch in range(4 + index):
		var origin: Vector3 = points[rng.randi_range(2, points.size() - 1)]
		var angle := TAU * float(branch) / float(4 + index) + rng.randf_range(-0.35, 0.35)
		var direction := Vector3(cos(angle), rng.randf_range(0.45, 0.9), sin(angle))
		var length := rng.randf_range(2.2, 3.8)
		_add_branch(st, rng, origin, direction, length, 0.17, height, true)
		var tip := origin + direction.normalized() * length * 0.9 + Vector3.UP * length * 0.2
		_add_leaf_cluster(st, rng, tip, rng.randf_range(1.7, 2.3), 5, JUNGLE_LEAF_DARK, JUNGLE_LEAF_LIGHT, TreeAtlas.Tile.LEAF_JUNGLE)
	var top: Vector3 = points[points.size() - 1]
	_add_canopy(st, rng, top, 3.2, JUNGLE_LEAF_DARK, JUNGLE_LEAF_LIGHT, TreeAtlas.Tile.LEAF_JUNGLE)
	# Short hanging vines under the upper crown.
	for vine in range(4):
		var origin: Vector3 = points[rng.randi_range(2, points.size() - 1)]
		var angle := rng.randf_range(0.0, TAU)
		var start := origin + Vector3(cos(angle) * 0.45, 0.0, sin(angle) * 0.45)
		var end := start + Vector3(rng.randf_range(-0.2, 0.2), -rng.randf_range(1.4, 3.0), rng.randf_range(-0.2, 0.2))
		_add_limb_tinted(st, start, end, 0.045, 0.015, 3, JUNGLE_LEAF_LIGHT, JUNGLE_LEAF_DARK)
	st.generate_normals()
	return st.commit()


# --- Biome-specific tree silhouettes ---------------------------------------

func _build_biome_trees(world_seed: int, center: Vector2i, radius: int) -> void:
	var grouped: Dictionary = {}
	for style in biome_tree_multimeshes.keys():
		grouped[style] = []
	var cell := 14
	var min_gx := floori(float(center.x - radius) / float(cell)) - 1
	var max_gx := floori(float(center.x + radius) / float(cell)) + 1
	var min_gz := floori(float(center.y - radius) / float(cell)) - 1
	var max_gz := floori(float(center.y + radius) / float(cell)) + 1
	for gz in range(min_gz, max_gz + 1):
		for gx in range(min_gx, max_gx + 1):
			var site_rng := RandomNumberGenerator.new()
			site_rng.seed = int(world_seed) ^ (gx * 73856093) ^ (gz * 19349663) ^ 0x6B10
			var x := gx * cell + site_rng.randi_range(2, cell - 3)
			var z := gz * cell + site_rng.randi_range(2, cell - 3)
			var style := _style_for_biome(BiomeManager.dominant_biome(x, z))
			if style.is_empty():
				continue
			if site_rng.randf() > _biome_tree_chance(style):
				continue
			if absi(x - 64) <= 8 and absi(z - 64) <= 8:
				continue
			if not _flat_ground(x, z):
				continue
			var y := BiomeManager.get_height(x, z)
			var scale_value := site_rng.randf_range(0.85, 1.30)
			var transform := Transform3D(
				Basis(Vector3.UP, site_rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value * site_rng.randf_range(0.92, 1.15), scale_value)),
				Vector3(float(x) + 0.5, float(y) + 1.0, float(z) + 0.5)
			)
			grouped[style].append(transform)
	for style in grouped.keys():
		_fill_cover_from_multimesh(biome_tree_multimeshes[style], grouped[style])


func _style_for_biome(biome: int) -> String:
	match biome:
		BiomeManager.FROST:
			return "snow"
		BiomeManager.DESERT:
			return "desert"
		BiomeManager.MUSHROOM:
			return "mushroom"
		BiomeManager.CORRUPTION, BiomeManager.CRIMSON:
			return "evil"
		BiomeManager.HALLOW:
			return "hallow"
		_:
			return ""


func _biome_tree_chance(style: String) -> float:
	match style:
		"snow":
			return 0.34
		"desert":
			return 0.16
		"mushroom":
			return 0.24
		"evil":
			return 0.28
		"hallow":
			return 0.24
		_:
			return 0.0


func _flat_ground(x: int, z: int) -> bool:
	var here := BiomeManager.get_height(x, z)
	return absi(BiomeManager.get_height(x - 1, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x + 1, z) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z - 1) - here) <= 1 \
		and absi(BiomeManager.get_height(x, z + 1) - here) <= 1


func _build_biome_tree(style: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	match style:
		"snow":
			_build_snow_tree(st)
		"desert":
			_build_desert_palm(st)
		"mushroom":
			_build_giant_mushroom(st)
		"evil":
			_build_evil_tree(st)
		"hallow":
			_build_hallow_tree(st)
	st.generate_normals()
	return st.commit()


func _build_snow_tree(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22031
	var points := _add_trunk(st, rng, 7.6, 0.36, 0.10, Vector3(0.2, 0.0, 0.15), 5, 5)
	_add_roots(st, rng, 0.42)
	for tier in range(4):
		var center := Vector3(0.0, 2.8 + float(tier) * 1.65, 0.0)
		var radius := 2.70 - float(tier) * 0.46
		_add_leaf_cluster(st, rng, center, radius, 3, Color(0.24, 0.43, 0.40), Color(0.67, 0.90, 0.82), TreeAtlas.Tile.NEEDLE)
		_add_leaf_cluster(st, rng, center + Vector3.UP * 0.28, radius * 0.72, 2, Color(0.82, 0.94, 1.0), Color(1.0, 1.0, 1.0), TreeAtlas.Tile.NEEDLE)
	_add_leaf_cluster(st, rng, points[points.size() - 1] + Vector3.UP * 0.5, 0.9, 3, Color(0.30, 0.50, 0.46), Color(0.82, 0.96, 1.0), TreeAtlas.Tile.NEEDLE)


func _build_desert_palm(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33017
	var position := Vector3.ZERO
	for segment in range(6):
		var next := position + Vector3(0.10 + float(segment) * 0.045, 1.15, 0.045)
		_add_limb_tinted(st, position, next, 0.24 - float(segment) * 0.022, 0.18 - float(segment) * 0.020, 5, Color(0.34, 0.23, 0.13), Color(0.72, 0.53, 0.28))
		position = next
	for frond in range(7):
		var angle := TAU * float(frond) / 7.0 + rng.randf_range(-0.18, 0.18)
		var center := position + Vector3(cos(angle) * 0.30, 0.18, sin(angle) * 0.30)
		_add_leaf_cluster(st, rng, center, rng.randf_range(1.7, 2.4), 2, Color(0.16, 0.36, 0.15), Color(0.48, 0.72, 0.28), TreeAtlas.Tile.FROND)
	for coconut in range(2):
		var angle := TAU * float(coconut) / 2.0 + 0.7
		_add_limb_tinted(st, position + Vector3(cos(angle) * 0.22, 0.05, sin(angle) * 0.22), position + Vector3(cos(angle) * 0.30, -0.22, sin(angle) * 0.30), 0.15, 0.12, 4, Color(0.24, 0.15, 0.07), Color(0.48, 0.30, 0.12))


func _build_evil_tree(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44009
	var height := 8.2
	var points := _add_trunk(st, rng, height, 0.34, 0.08, Vector3(1.0, 0.0, 0.55), 5, 4)
	_add_roots(st, rng, 0.55)
	for branch in range(6):
		var origin: Vector3 = points[rng.randi_range(2, points.size() - 1)]
		var angle := TAU * float(branch) / 6.0 + rng.randf_range(-0.45, 0.45)
		var direction := Vector3(cos(angle), rng.randf_range(0.25, 0.75), sin(angle))
		_add_branch(st, rng, origin, direction, rng.randf_range(1.8, 3.2), 0.12, height, true)
		var tip := origin + direction.normalized() * rng.randf_range(1.5, 2.6)
		_add_leaf_cluster(st, rng, tip, rng.randf_range(1.1, 1.6), 3, Color(0.14, 0.03, 0.18), Color(0.48, 0.13, 0.40), TreeAtlas.Tile.LEAF_EVIL)
	_add_canopy(st, rng, points[points.size() - 1], 2.3, Color(0.14, 0.03, 0.18), Color(0.48, 0.13, 0.40), TreeAtlas.Tile.LEAF_EVIL)
	# Bare thorn tips keep the corrupted silhouette hostile without horror props.
	for thorn in range(5):
		var origin: Vector3 = points[rng.randi_range(2, points.size() - 1)]
		var direction := Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.4, 0.9), rng.randf_range(-0.8, 0.8)).normalized()
		_add_limb_tinted(st, origin, origin + direction * rng.randf_range(0.7, 1.4), 0.09, 0.02, 3, Color(0.20, 0.05, 0.23), Color(0.52, 0.12, 0.34))


func _build_hallow_tree(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55021
	var height := 8.4
	var points := _add_trunk(st, rng, height, 0.30, 0.07, Vector3(0.5, 0.0, -0.3), 4, 5)
	_add_roots(st, rng, 0.44)
	for branch in range(5):
		var origin: Vector3 = points[rng.randi_range(2, points.size() - 1)]
		var angle := TAU * float(branch) / 5.0 + rng.randf_range(-0.2, 0.2)
		var direction := Vector3(cos(angle), rng.randf_range(0.45, 0.8), sin(angle))
		_add_branch(st, rng, origin, direction, rng.randf_range(2.0, 3.0), 0.10, height, true)
		var tip := origin + direction.normalized() * 2.3
		_add_leaf_cluster(st, rng, tip, rng.randf_range(1.5, 2.1), 4, Color(0.72, 0.34, 0.72), Color(1.0, 0.82, 1.0), TreeAtlas.Tile.LEAF_HALLOW)
	_add_canopy(st, rng, points[points.size() - 1], 2.5, Color(0.78, 0.42, 0.78), Color(1.0, 0.90, 1.0), TreeAtlas.Tile.LEAF_HALLOW)
	for shard in range(3):
		var angle := TAU * float(shard) / 3.0
		var start := points[rng.randi_range(2, points.size() - 1)]
		_add_limb_tinted(st, start, start + Vector3(cos(angle) * 0.7, 0.9, sin(angle) * 0.7), 0.08, 0.015, 4, Color(0.78, 0.55, 1.0), Color(1.0, 0.95, 1.0))


func _build_giant_mushroom(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 66013
	var height := 3.4
	_add_limb_tinted(st, Vector3.ZERO, Vector3.UP * height, 0.42, 0.28, 6, Color(0.42, 0.28, 0.34), Color(0.88, 0.78, 0.76))
	var cap_center := Vector3.UP * height
	var apex := cap_center + Vector3.UP * 1.25
	var ring: Array[Vector3] = []
	for index in range(10):
		var angle := TAU * float(index) / 10.0
		ring.append(cap_center + Vector3(cos(angle) * 2.1, 0.0, sin(angle) * 2.1))
	var uv_apex := TreeAtlas.uv(TreeAtlas.Tile.MUSHROOM, Vector2(0.5, 0.5))
	for index in range(10):
		var next := (index + 1) % 10
		var a: Vector3 = ring[index]
		var b: Vector3 = ring[next]
		var uv_a := TreeAtlas.uv(TreeAtlas.Tile.MUSHROOM, Vector2(0.1 + float(index) / 10.0, 0.1))
		var uv_b := TreeAtlas.uv(TreeAtlas.Tile.MUSHROOM, Vector2(0.1 + float(index + 1) / 10.0, 0.1))
		_add_textured_triangle(st, apex, a, b, Color(0.94, 0.48, 0.52), Color(0.72, 0.22, 0.34), Color(0.72, 0.22, 0.34), uv_apex, uv_a, uv_b)
	for spot in range(4):
		var angle := TAU * float(spot) / 4.0 + 0.3
		var center := cap_center + Vector3(cos(angle) * 1.15, 0.45, sin(angle) * 1.15)
		_add_leaf_cluster(st, rng, center, 0.34, 1, Color(0.88, 0.90, 0.86), Color(1.0, 1.0, 1.0), TreeAtlas.Tile.MUSHROOM)


func _make_glow_instance(node_name: String, mesh: ArrayMesh) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(0.66, 0.95, 0.72)
	material.emission_energy_multiplier = 2.4
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(200000.0, 96.0, 200000.0))
	add_child(instance)
	return instance


func _build_mushroom_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var pale := Color(0.86, 0.96, 0.80, 1.0)
	_add_limb_tinted(st, Vector3.ZERO, Vector3.UP * 0.42, 0.06, 0.04, 5, pale, pale)
	var cap_top := Vector3.UP * 0.72
	for index in range(6):
		var angle := TAU * float(index) / 6.0
		var next_angle := TAU * float(index + 1) / 6.0
		var a := Vector3(cos(angle) * 0.30, 0.46, sin(angle) * 0.30)
		var b := Vector3(cos(next_angle) * 0.30, 0.46, sin(next_angle) * 0.30)
		_add_triangle(st, a, cap_top, b, pale, pale, pale)
	st.generate_normals()
	return st.commit()


func _build_spire_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5527
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for shard in range(3):
		var base := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
		var lean := Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8))
		var height := rng.randf_range(5.0, 11.0) if shard == 0 else rng.randf_range(2.5, 5.5)
		var segments := 4
		var position := base
		for segment in range(segments):
			var t0 := float(segment) / float(segments)
			var t1 := float(segment + 1) / float(segments)
			var next := position + lean / float(segments) + Vector3.UP * (height / float(segments))
			_add_limb_tinted(st, position, next, lerpf(0.55, 0.02, t0), lerpf(0.55, 0.02, t1), 4, _tinted(t0, ICE_DEEP, ICE_PALE), _tinted(t1, ICE_DEEP, ICE_PALE))
			position = next
	st.generate_normals()
	return st.commit()


func _build_root_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for root in range(5):
		var angle := TAU * float(root) / 5.0 + rng.randf_range(-0.4, 0.4)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var start := direction * 0.25 + Vector3.UP * 0.55
		var elbow := direction * rng.randf_range(1.2, 2.3) + Vector3.UP * rng.randf_range(-0.1, 0.25)
		var tip := elbow + direction * rng.randf_range(0.6, 1.4) + Vector3.UP * rng.randf_range(0.5, 1.3)
		_add_limb_tinted(st, start, elbow, 0.16, 0.12, 4, _tinted(0.1, ROOT_DARK, ROOT_LIGHT), _tinted(0.4, ROOT_DARK, ROOT_LIGHT))
		_add_limb_tinted(st, elbow, tip, 0.12, 0.015, 4, _tinted(0.4, ROOT_DARK, ROOT_LIGHT), _tinted(0.8, ROOT_DARK, ROOT_LIGHT))
	st.generate_normals()
	return st.commit()


func _build_biome_props(world_seed: int, center: Vector2i, radius: int) -> void:
	var hush_sites := WorldGenerator.collect_hush_sites_region(world_seed, center.x - radius, center.y - radius, center.x + radius, center.y + radius)
	var per_archetype: Array = []
	for _i in range(HUSH_ARCHETYPES):
		per_archetype.append([])
	var mushrooms: Array[Transform3D] = []
	for site in hush_sites:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(site["seed"])
		var archetype := rng.randi_range(0, HUSH_ARCHETYPES - 1)
		var scale_value := float(site["scale"])
		var transform := Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value * rng.randf_range(0.9, 1.15), scale_value)),
			Vector3(float(site["x"]) + 0.5, float(site["y"]) + 1.0, float(site["z"]) + 0.5)
		)
		per_archetype[archetype].append(transform)
		# Clusters of pale glowing mushrooms at the tree roots.
		for _m in range(rng.randi_range(1, 3)):
			var mx := int(site["x"]) + rng.randi_range(-2, 2)
			var mz := int(site["z"]) + rng.randi_range(-2, 2)
			var my := BiomeManager.get_height(mx, mz) + 1
			var mscale := rng.randf_range(0.7, 1.5)
			mushrooms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(mscale, mscale, mscale)), Vector3(float(mx) + 0.5, float(my), float(mz) + 0.5)))
	for archetype in range(HUSH_ARCHETYPES):
		_fill_cover_from_multimesh(hush_multimeshes[archetype], per_archetype[archetype])
	_fill_cover(mushroom_instance, mushrooms)

	var frost_sites := WorldGenerator.collect_frost_sites_region(world_seed, center.x - radius, center.y - radius, center.x + radius, center.y + radius)
	var spires: Array[Transform3D] = []
	for site in frost_sites:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(site["seed"])
		var scale_value := float(site["scale"])
		spires.append(Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value * rng.randf_range(0.8, 1.3), scale_value)),
			Vector3(float(site["x"]) + 0.5, float(site["y"]) + 1.0, float(site["z"]) + 0.5)
		))
	_fill_cover(spire_instance, spires)

	var mire_sites := WorldGenerator.collect_mire_root_sites_region(world_seed, center.x - radius, center.y - radius, center.x + radius, center.y + radius)
	var roots: Array[Transform3D] = []
	for site in mire_sites:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(site["seed"])
		var scale_value := float(site["scale"])
		roots.append(Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value, scale_value)),
			Vector3(float(site["x"]) + 0.5, float(site["y"]) + 0.2, float(site["z"]) + 0.5)
		))
	_fill_cover(root_instance, roots)


func _fill_cover_from_multimesh(multimesh: MultiMesh, transforms: Array) -> void:
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])


# --- Ground cover -----------------------------------------------------------

func _build_surface_details(world_seed: int, center: Vector2i, radius: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world_seed) ^ 0x51F7
	var flowers: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	for z in range(center.y - radius, center.y + radius, 3):
		for x in range(center.x - radius, center.x + radius, 3):
			var biome := BiomeManager.dominant_biome(x, z)
			if biome in [BiomeManager.FROST, BiomeManager.DESERT, BiomeManager.MUSHROOM, BiomeManager.OCEAN]:
				continue
			if not _flat_ground(x, z):
				continue
			var position := Vector3(float(x) + rng.randf_range(0.1, 0.9), float(BiomeManager.get_height(x, z)) + 1.0, float(z) + rng.randf_range(0.1, 0.9))
			if rng.randf() < 0.12:
				var scale_value := rng.randf_range(0.75, 1.35)
				flowers.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale_value, scale_value, scale_value)), position))
			if rng.randf() < 0.045:
				var bush_scale := rng.randf_range(0.65, 1.20)
				bushes.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(bush_scale, bush_scale * rng.randf_range(0.8, 1.1), bush_scale)), position))
	_fill_cover(flower_instance, flowers)
	_fill_cover(bush_instance, bushes)


func _build_flower_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8811
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var petal_colors := [Color(0.95, 0.32, 0.28), Color(1.0, 0.78, 0.22), Color(0.82, 0.46, 0.92)]
	for flower in range(3):
		var center := Vector3(rng.randf_range(-0.24, 0.24), 0.0, rng.randf_range(-0.24, 0.24))
		var height := rng.randf_range(0.28, 0.52)
		var top := center + Vector3.UP * height
		var stem_color := Color(0.20, 0.48, 0.16)
		_add_triangle(st, center, top, center + Vector3(0.035, 0.0, 0.0), stem_color, stem_color, stem_color)
		var color: Color = petal_colors[flower % petal_colors.size()]
		for petal in range(5):
			var angle := TAU * float(petal) / 5.0
			var tip := top + Vector3(cos(angle) * 0.16, 0.04, sin(angle) * 0.16)
			var side_a := top + Vector3(cos(angle + 0.5) * 0.06, 0.0, sin(angle + 0.5) * 0.06)
			var side_b := top + Vector3(cos(angle - 0.5) * 0.06, 0.0, sin(angle - 0.5) * 0.06)
			_add_triangle(st, side_a, tip, side_b, color.darkened(0.15), color, color.darkened(0.15))
	_add_triangle(st, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.08), Vector3(0.0, 0.34, 0.04), Color(0.18, 0.42, 0.14), Color(0.18, 0.42, 0.14), Color(0.28, 0.58, 0.18))
	return st.commit()


func _build_bush_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9917
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_add_leaf_cluster(st, rng, Vector3(0.0, 0.58, 0.0), 0.66, 4, Color(0.08, 0.28, 0.08), Color(0.32, 0.66, 0.18), TreeAtlas.Tile.LEAF)
	st.generate_normals()
	return st.commit()


func _build_grass_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade_count := 6
	var height_range := Vector2(0.07, 0.19)
	for blade in range(blade_count):
		var angle := rng.randf_range(0.0, TAU)
		var spread := rng.randf_range(0.0, 0.13)
		var base := Vector3(cos(angle) * spread, 0.0, sin(angle) * spread)
		var direction := Vector3(cos(angle + rng.randf_range(-0.5, 0.5)), 0.0, sin(angle + rng.randf_range(-0.5, 0.5)))
		var width := rng.randf_range(0.022, 0.05)
		var height := rng.randf_range(height_range.x, height_range.y)
		var bend := rng.randf_range(0.08, 0.28) * height
		_add_blade(st, base, direction, width, height, bend, GRASS_DARK, GRASS_LIGHT)
	return st.commit()


func _add_blade(st: SurfaceTool, base: Vector3, direction: Vector3, width: float, height: float, bend: float, dark: Color, light: Color) -> void:
	var across := Vector3(-direction.z, 0.0, direction.x) * width
	var mid := base + Vector3.UP * height * 0.55 + direction * bend * 0.5
	var tip := base + Vector3.UP * height + direction * bend
	var bottom_a := base - across
	var bottom_b := base + across
	var mid_a := mid - across * 0.6
	var mid_b := mid + across * 0.6
	var bottom_color := dark
	bottom_color.a = 0.0
	var mid_color := dark.lerp(light, 0.55)
	mid_color.a = 0.55
	var tip_color := light
	tip_color.a = 1.0
	_grass_triangle(st, bottom_a, bottom_color, mid_a, mid_color, mid_b, mid_color)
	_grass_triangle(st, bottom_a, bottom_color, mid_b, mid_color, bottom_b, bottom_color)
	_grass_triangle(st, mid_a, mid_color, tip, tip_color, mid_b, mid_color)


func _grass_triangle(st: SurfaceTool, a: Vector3, color_a: Color, b: Vector3, color_b: Color, c: Vector3, color_c: Color) -> void:
	st.set_normal(Vector3.UP)
	st.set_color(color_a)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.set_color(color_b)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.set_color(color_c)
	st.add_vertex(c)


func _make_cover_instance(node_name: String, mesh: ArrayMesh, wind: float) -> MultiMeshInstance3D:
	var material := _make_material(wind)
	material.set_shader_parameter("ground_cover", 1.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# No visibility range: one MultiMesh covers the whole map, and range
	# culling is measured from the world-centred AABB, which would hide every
	# instance as soon as the camera left the map centre.
	instance.custom_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(144.0, 96.0, 144.0))
	add_child(instance)
	return instance


func _make_tree_material(wind: float, glow := 0.0) -> ShaderMaterial:
	var material := _make_material(wind)
	material.set_shader_parameter("tree_texture", tree_texture)
	material.set_shader_parameter("texture_strength", 1.0)
	material.set_shader_parameter("glow_strength", glow)
	return material


func _make_material(wind: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = VEGETATION_SHADER
	material.set_shader_parameter("tree_texture", tree_texture)
	material.set_shader_parameter("texture_strength", 0.0)
	material.set_shader_parameter("wind_strength", wind)
	material.set_shader_parameter("wind_speed", 1.7)
	material.set_shader_parameter("sky_tint", Vector3(0.74, 0.84, 1.0))
	material.set_shader_parameter("sun_strength", 0.0)
	material.set_shader_parameter("ambient_sky_level", 0.0)
	materials.append(material)
	return material


func _build_region_cover(world_seed: int, center: Vector2i, radius: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x51A5
	var grass_transforms: Array[Transform3D] = []
	for z in range(center.y - radius, center.y + radius, GRASS_CELL):
		for x in range(center.x - radius, center.x + radius, GRASS_CELL):
			if absi(x - 64) <= 6 and absi(z - 64) <= 6:
				continue
			if rng.randf() > GRASS_CHANCE:
				continue
			# Tufts cover every grassy surface; bare sand, snow, mushroom caps
			# and ocean floor stay clear so those biomes keep their own read.
			var grass_biome := BiomeManager.dominant_biome(x, z)
			if grass_biome in [BiomeManager.FROST, BiomeManager.DESERT, BiomeManager.MUSHROOM, BiomeManager.OCEAN]:
				continue
			var ground := BiomeManager.get_height(x, z)
			if BiomeManager.is_canyon_floor(x, z):
				continue
			if absi(BiomeManager.get_height(x + 1, z) - ground) > 1 or absi(BiomeManager.get_height(x - 1, z) - ground) > 1:
				continue
			if absi(BiomeManager.get_height(x, z + 1) - ground) > 1 or absi(BiomeManager.get_height(x, z - 1) - ground) > 1:
				continue
			var position := Vector3(float(x) + rng.randf_range(0.15, 0.85), float(ground) + 1.0, float(z) + rng.randf_range(0.15, 0.85))
			var scale_value := rng.randf_range(0.45, 0.85)
			var rotation := rng.randf_range(0.0, TAU)
			var basis := Basis(Vector3.UP, rotation).scaled(Vector3(scale_value, scale_value * rng.randf_range(0.8, 1.3), scale_value))
			grass_transforms.append(Transform3D(basis, position))
	_fill_cover(grass_instance, grass_transforms)
	grass_count = grass_transforms.size()


func _fill_cover(instance: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	var multimesh := instance.multimesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
