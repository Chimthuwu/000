extends SceneTree

# Feeds real input events into the booted world and checks that the scroll wheel
# and number keys move the hotbar selection (and change the held item) instead of
# being swallowed by another node on the way through.

var _failures: Array[String] = []

func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s (%s)" % [name, detail])
	else:
		_failures.append(name)
		print("FAIL %s (%s)" % [name, detail])


func _wheel(up: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	root.push_input(event)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	root.push_input(event)


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var world = scene.get_node_or_null("VoxelWorld")
	var player = scene.get_node_or_null("Player")
	var caster = scene.get_node_or_null("Player/ArcaneCaster")
	if world == null or player == null:
		print("HOTBAR WHEEL CHECK FAIL: missing world or player")
		quit(1)
		return
	var frames := 0
	while (not bool(world.is_generated) or not bool(player.spawned)) and frames < 900:
		await process_frame
		frames += 1
	for _settle in range(4):
		await process_frame

	var inventory = player.inventory
	inventory.select(0)
	await process_frame

	var cartridge_before: int = int(caster.selected_cartridge) if caster != null else -1

	# Terraria convention: scrolling up walks back through the bar, down walks forward.
	_wheel(true)
	await process_frame
	_check("wheel up walks back and wraps", int(inventory.selected) == inventory.HOTBAR_SIZE - 1,
		"selected=%d" % int(inventory.selected))
	_check("the held item follows the wheel",
		String(inventory.held_item()) == String(inventory.hotbar[inventory.selected]["id"]),
		"held=%s" % String(inventory.held_item()))

	_wheel(true)
	await process_frame
	_check("wheel up continues backwards", int(inventory.selected) == inventory.HOTBAR_SIZE - 2,
		"selected=%d" % int(inventory.selected))

	_wheel(false)
	await process_frame
	_check("wheel down steps forward", int(inventory.selected) == inventory.HOTBAR_SIZE - 1,
		"selected=%d" % int(inventory.selected))

	inventory.select(0)
	await process_frame
	_wheel(false)
	await process_frame
	_check("wheel down advances from the first slot", int(inventory.selected) == 1,
		"selected=%d" % int(inventory.selected))

	if caster != null:
		_check("the wheel no longer drives the legacy cartridges",
			int(caster.selected_cartridge) == cartridge_before,
			"cartridge %d -> %d" % [cartridge_before, int(caster.selected_cartridge)])

	_key(KEY_3)
	await process_frame
	_check("number keys still select slots", int(inventory.selected) == 2, "selected=%d" % int(inventory.selected))

	_key(KEY_1)
	await process_frame
	_check("key 1 selects the first slot", int(inventory.selected) == 0, "selected=%d" % int(inventory.selected))

	# Selection must reach the hand, not just the model.
	var viewmodel = player.get_node_or_null("Camera3D/Viewmodel")
	if viewmodel != null:
		var expected := String(inventory.hotbar[inventory.selected]["id"])
		_check("the held item updates with the wheel", String(viewmodel.item_id) == expected,
			"viewmodel=%s expected=%s" % [String(viewmodel.item_id), expected])

	if _failures.is_empty():
		print("HOTBAR WHEEL CHECK PASS")
		quit(0)
	else:
		print("HOTBAR WHEEL CHECK FAIL: %s" % ", ".join(_failures))
		quit(1)
