extends SceneTree

# Visual evidence for tree damage and felling. Boots the real game, stands the
# player in front of a real tree and writes PNGs of the upright tree, the scars
# and lean after two chops, the tumble, and the moment after it lands.
#   Godot --fixed-fps 60 --path . --script res://debug/capture_tree_fall.gd

const SHOT_DIR := "res://debug/evidence"
const CYCLE: DayNightConfig = preload("res://data/world/day_night_config.tres")

var main: Node
var world: VoxelWorld
var player: VoxelPlayer


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("FALLCAP FAIL: main.tscn did not load")
		quit(1)
		return
	main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _capture(shot_name: String, detail := "") -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, shot_name]
	var error := image.save_png(path)
	print("FALLCAP %s %s error=%d" % [shot_name, detail, error])


func _fall_angle(vegetation: WorldVegetation) -> float:
	if vegetation.tree_falls.is_empty():
		return 0.0
	return rad_to_deg(float(vegetation.tree_falls[0].get("angle", 0.0)))


## Waits until the tumble passes an angle, so the shot does not depend on the
## frame rate of the capturing machine.
func _wait_for_angle(vegetation: WorldVegetation, degrees: float) -> void:
	# Frames are slower than real time under --fixed-fps, so allow plenty.
	var deadline := Time.get_ticks_msec() + 20000
	while _fall_angle(vegetation) < degrees and not vegetation.tree_falls.is_empty() \
			and Time.get_ticks_msec() < deadline:
		await process_frame


## Points the player's own camera at `target`, which keeps the HUD and the
## first-person view in the shot.
func _look_at(target: Vector3) -> void:
	var from := player.global_position + Vector3(0.0, 1.62, 0.0)
	var to := target - from
	player.rotation.y = atan2(-to.x, -to.z)
	player.camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


func _run() -> void:
	world = main.get_node("VoxelWorld")
	player = main.get_node("Player")
	var cycle: DayNightCycle = main.get_node("DayNightCycle")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 4000:
		await process_frame
		frames += 1
	print("FALLCAP world ready frames=%d" % frames)
	cycle.restore_time(cycle.CONFIG.day_seconds * 0.42)
	await _wait(2.0)

	var vegetation: WorldVegetation = world.vegetation
	# A tree close to spawn, so the shot has the normal forest around it.
	var cell := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var best := INF
	for candidate in vegetation.site_slots.keys():
		var site: Vector3i = candidate
		var distance := Vector2(float(site.x) - player.global_position.x, float(site.z) - player.global_position.z).length()
		if distance < best:
			best = distance
			cell = site
	if cell.x == 1 << 30:
		print("FALLCAP FAIL: no tree near spawn")
		quit(1)
		return
	print("FALLCAP tree cell=%s distance=%.1f" % [str(cell), best])

	# Stand on the ground away from the trunk, facing it, in first person.
	var trunk := Vector3(float(cell.x) + 0.5, float(cell.y) + 1.0, float(cell.z) + 0.5)
	var stand := trunk + Vector3(-4.6, 0.0, 0.0)
	var surface := world.get_surface_height(floori(stand.x), floori(stand.z))
	if surface > 0:
		stand.y = float(surface) + 1.4
	player.global_position = stand
	player.velocity = Vector3.ZERO
	player.camera_mode = 0
	if player.avatar != null:
		player.avatar.visible = false
	if player.viewmodel != null:
		player.viewmodel.set_first_person(true)
	# Let streaming settle: a region rebuild during the fall would drop the tree
	# instantly instead of showing the tumble.
	await _wait(3.0)
	_look_at(trunk + Vector3(0.0, 2.2, 0.0))
	await _wait(0.8)
	_look_at(trunk + Vector3(0.0, 2.2, 0.0))
	await _capture("tree_upright", "tree before any chops")

	# Real chop: select the axe and hold the break action, so the damage, the
	# fall and the loot all come through the same path a player uses.
	var slot := -1
	for index in range(10):
		var stack: Dictionary = player.inventory.get_slot("hotbar", index)
		if not player.inventory.is_empty(stack) and StringName(stack.get("id", &"")) == &"wooden_axe":
			slot = index
			break
	if slot < 0:
		player.inventory.add_item(&"wooden_axe", 1)
		for index in range(10):
			var stack: Dictionary = player.inventory.get_slot("hotbar", index)
			if not player.inventory.is_empty(stack) and StringName(stack.get("id", &"")) == &"wooden_axe":
				slot = index
				break
	player.inventory.select(slot)
	await _wait(0.3)

	Input.action_press("break_block")
	var chopping := Time.get_ticks_msec() + 20000
	while player.mining_progress < 0.65 and Time.get_ticks_msec() < chopping:
		_look_at(trunk + Vector3(0.0, 2.2, 0.0))
		await process_frame
	await _capture("tree_damaged", "scarred, leaning trunk with chips, progress %.2f" % player.mining_progress)

	var felling := Time.get_ticks_msec() + 20000
	while vegetation.tree_falls.is_empty() and Time.get_ticks_msec() < felling:
		_look_at(trunk + Vector3(0.0, 2.2, 0.0))
		await process_frame
	Input.action_release("break_block")
	await _wait_for_angle(vegetation, 12.0)
	await _capture("tree_falling", "trunk partway through the fall angle=%.1f" % _fall_angle(vegetation))
	await _wait_for_angle(vegetation, 70.0)
	await _capture("tree_tumbling", "trunk near the ground angle=%.1f" % _fall_angle(vegetation))
	var landed := Time.get_ticks_msec() + 20000
	while not vegetation.tree_falls.is_empty() and Time.get_ticks_msec() < landed:
		await process_frame
	await _wait(0.5)
	var logs: Array = []
	for node in main.get_children():
		if node is ItemEntity and (node as ItemEntity).item_id == &"wood":
			logs.append(node)
	print("FALLCAP logs on the ground=%d" % logs.size())
	if not logs.is_empty():
		# Frame the logs rather than the empty stump.
		_look_at((logs[0] as ItemEntity).global_position + Vector3(0.0, 0.4, 0.0))
		await _wait(0.3)
	await _capture("tree_felled", "logs dropped where the trunk landed, stacks=%d" % logs.size())
	print("FALLCAP done cell=%s felled=%s" % [str(cell), str(vegetation.felled_sites.has(cell))])
	quit(0)
