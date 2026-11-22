extends SceneTree

# Visual evidence for the first-person held item. Boots the real game, switches
# to first person, selects each starter tool and writes one PNG per item, plus a
# mid-swing frame so the chop animation is documented too.
#   Godot --fixed-fps 60 --path . --script res://debug/capture_held_tool.gd

const SHOT_DIR := "res://debug/evidence"
const CYCLE: DayNightConfig = preload("res://data/world/day_night_config.tres")

var main: Node
var world: VoxelWorld
var player: VoxelPlayer


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("HELDCAP FAIL: main.tscn did not load")
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
	print("HELDCAP %s %s error=%d image=%s" % [shot_name, detail, error, path])


func _run() -> void:
	world = main.get_node("VoxelWorld")
	player = main.get_node("Player")
	var cycle: DayNightCycle = main.get_node("DayNightCycle")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 4000:
		await process_frame
		frames += 1
	print("HELDCAP world ready frames=%d" % frames)
	cycle.restore_time(cycle.CONFIG.day_seconds * 0.42)
	await _wait(2.0)
	for _i in range(150):
		var p := player.global_position
		var surface := world.get_surface_height(floori(p.x), floori(p.z))
		if surface > 0 and p.y < float(surface) - 25.0:
			player.global_position = Vector3(p.x, float(surface) + 2.0, p.z)
			player.velocity = Vector3.ZERO
		await process_frame
	await _wait(1.5)

	# First person, looking level, with the camera pitched down slightly so the
	# tool and the ground it is aimed at are both in frame.
	player.camera_mode = 0
	player.avatar.visible = false
	if player.viewmodel != null:
		player.viewmodel.set_first_person(true)
	player.camera.position = Vector3(0.0, 1.62, 0.0)
	player.camera.rotation.x = -0.18
	await _wait(0.4)

	if player.inventory != null:
		player.inventory.add_item(&"copper_pickaxe", 1)
		player.inventory.add_item(&"copper_axe", 1)
		player.inventory.add_item(&"wooden_sword", 1)
		player.inventory.add_item(&"torch", 40)
		player.inventory.add_item(&"dirt", 50)

	for entry in [[&"wooden_axe", "axe", "wooden axe in hand"], [&"copper_pickaxe", "pickaxe", "copper pickaxe in hand"], [&"wooden_sword", "sword", "sword in hand"], [&"torch", "torch", "torch in hand"], [&"dirt", "block", "dirt block card in hand"]]:
		var item_id: StringName = entry[0]
		var slot := -1
		for index in range(10):
			var stack: Dictionary = player.inventory.get_slot("hotbar", index)
			if not player.inventory.is_empty(stack) and StringName(stack.get("id", &"")) == item_id:
				slot = index
				break
		if slot < 0:
			print("HELDCAP skip %s (not in hotbar)" % String(item_id))
			continue
		player.inventory.select(slot)
		await _wait(0.4)
		await _capture("held_%s" % String(entry[1]), String(entry[2]))

	# Mid-swing frame: press the real attack action so the chop is driven by the
	# same input path a player uses, then catch it partway through the swing.
	player.inventory.select(0)
	await _wait(0.3)
	Input.action_press("break_block")
	await _wait(0.22)
	await _capture("held_swing", "axe partway through the chop swing")
	Input.action_release("break_block")
	print("HELDCAP viewmodel_visible=%s item=%s" % [str(player.viewmodel.visible if player.viewmodel != null else false), String(player.viewmodel.item_id if player.viewmodel != null else &"")])
	quit(0)
