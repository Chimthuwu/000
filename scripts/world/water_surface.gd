extends Node3D
class_name ToxicWater

# Flat translucent water plane for Forest lakes and the Ocean. Rebuilt per
# loaded region instead of per block type, which keeps the chunk mesher untouched.
#
# The region scan evaluates biome noise for up to 192x192 cells; doing that on
# the main thread produced 100-250ms hitches whenever the streaming centre
# crossed the Mire. The scan now runs on a worker and only the small vertex
# buffer is installed here.

const WATER_LEVEL := BiomeManager.WATER_LEVEL
const REBUILD_DISTANCE := 40

var mesh_instance: MeshInstance3D
var bubbles: GPUParticles3D
var material: StandardMaterial3D
var region_center := Vector2i(1 << 30, 1 << 30)
var region_radius := 0

var _queued_center := Vector2i(1 << 30, 1 << 30)
var _queued_radius := 0
var _request_id := 0
var _task_id := -1
var _result: Dictionary = {}
var _mutex := Mutex.new()


func _ready() -> void:
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.16, 0.36, 0.24, 0.58)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ToxicWaterSurface"
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	_build_bubbles()


func _build_bubbles() -> void:
	bubbles = GPUParticles3D.new()
	bubbles.name = "ToxicBubbles"
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(48.0, 0.2, 48.0)
	process.direction = Vector3.UP
	process.spread = 12.0
	process.gravity = Vector3(0.0, 1.4, 0.0)
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.2
	process.scale_min = 0.06
	process.scale_max = 0.18
	process.color = Color(0.45, 0.85, 0.22, 0.55)
	bubbles.process_material = process
	bubbles.lifetime = 1.1
	bubbles.amount = 90
	bubbles.local_coords = false
	bubbles.visibility_aabb = AABB(Vector3(-56.0, -2.0, -56.0), Vector3(112.0, 8.0, 112.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var bubble_material := StandardMaterial3D.new()
	bubble_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_material.albedo_color = Color(0.55, 0.92, 0.28, 0.45)
	bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = bubble_material
	bubbles.draw_pass_1 = quad
	bubbles.emitting = false
	add_child(bubbles)


func clear() -> void:
	region_center = Vector2i(1 << 30, 1 << 30)
	region_radius = 0
	_queued_center = region_center
	_queued_radius = 0
	_request_id += 1
	if mesh_instance != null:
		mesh_instance.mesh = null
		mesh_instance.visible = false
	if bubbles != null:
		bubbles.emitting = false


func update_region(center: Vector2i, radius: int) -> void:
	# Rebuild only after the centre has moved far enough to matter; re-running
	# the scan every chunk crossing was a visible hitch.
	if radius == region_radius and mesh_instance.mesh != null and center.distance_squared_to(region_center) < REBUILD_DISTANCE * REBUILD_DISTANCE:
		return
	_queued_center = center
	_queued_radius = radius
	region_center = center
	region_radius = radius
	if bubbles != null:
		bubbles.global_position = Vector3(float(center.x * 16 + 8), float(WATER_LEVEL), float(center.y * 16 + 8))
	if _task_id == -1:
		_start_build()


func _start_build() -> void:
	if _queued_radius <= 0:
		return
	_request_id += 1
	var request := _request_id
	var center := _queued_center
	var radius := _queued_radius
	_task_id = WorkerThreadPool.add_task(Callable(self, "_build_region_task").bind(request, center, radius))


func _build_region_task(request: int, center: Vector2i, radius: int) -> void:
	var vertices := _scan_region(center, radius)
	_mutex.lock()
	_result = {"id": request, "center": center, "radius": radius, "vertices": vertices}
	_mutex.unlock()


func _process(_delta: float) -> void:
	if bubbles != null:
		bubbles.emitting = mesh_instance != null and mesh_instance.visible
	if _task_id == -1:
		return
	if not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_mutex.lock()
	var result := _result
	_result = {}
	_mutex.unlock()
	if result.is_empty():
		return
	var built_center: Vector2i = result["center"]
	var built_radius: int = result["radius"]
	if int(result["id"]) == _request_id:
		var vertices: PackedVector3Array = result["vertices"]
		mesh_instance.mesh = _surface_from_vertices(vertices)
		mesh_instance.visible = not vertices.is_empty()
	# The centre may have moved while the scan was running; rebuild once for the
	# newest request instead of leaving a stale region installed.
	if _queued_radius > 0 and (_queued_center != built_center or _queued_radius != built_radius):
		_start_build()


func _scan_region(center: Vector2i, radius: int) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	var y := float(WATER_LEVEL + 1)
	for z in range(center.y * 16 - radius, center.y * 16 + radius):
		for x in range(center.x * 16 - radius, center.x * 16 + radius):
			if not BiomeManager.is_mire_water(x, z):
				continue
			var offset := Vector3(float(x), 0.0, float(z))
			var a := offset + Vector3(0.0, y, 0.0)
			var b := offset + Vector3(1.0, y, 0.0)
			var c := offset + Vector3(1.0, y, 1.0)
			var d := offset + Vector3(0.0, y, 1.0)
			for point in [a, b, c, a, c, d]:
				vertices.append(point)
	return vertices


func _surface_from_vertices(vertices: PackedVector3Array) -> ArrayMesh:
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Called before the world reseeds BiomeManager, so the scan cannot race a
# configure() on the main thread. Normally just waits for the in-flight scan.
func wait_for_pending() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_mutex.lock()
		_result = {}
		_mutex.unlock()


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
