extends SceneTree

# Verifies the Terraria presentation pass: starter kit, no Lumencaster weapon,
# and a HUD laid out for the real viewport.

var failures := 0
var checks := 0


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PRESENTATION FAIL: %s %s" % [label, detail])
		return
	print("PRESENTATION PASS: %s %s" % [label, detail])


func _initialize() -> void:
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	var world: VoxelWorld = main.get_node("VoxelWorld") as VoxelWorld
	var player: VoxelPlayer = main.get_node("Player") as VoxelPlayer
	var frames := 0
	while not world.is_generated and frames < 6000:
		await process_frame
		frames += 1
	_check(world.is_generated, "world ready", "frames=%d" % frames)
	await process_frame

	_check(player.inventory.count(&"wooden_pickaxe") == 1, "starter pickaxe in inventory")
	_check(player.inventory.count(&"wooden_axe") == 1, "starter axe in inventory")
	_check(player.inventory.count(&"wooden_sword") == 1, "starter sword in inventory")
	_check(player.inventory.count(&"torch") >= 10, "starter torches in inventory")
	_check(player.inventory.held_item() == &"wooden_pickaxe", "pickaxe selected on spawn")
	_check(player.mining_tier == 1, "starter pickaxe sets mining tier", "tier=%d" % player.mining_tier)

	var viewmodel := player.camera.get_node_or_null("Viewmodel")
	_check(viewmodel == null or not viewmodel.visible, "legacy gun viewmodel is hidden")
	var legacy := player.get_node_or_null("Lumencaster")
	_check(legacy == null or bool(legacy.get("disabled")), "legacy Lumencaster is disabled")

	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var vp: Vector2 = hud.get_viewport().size
	var crosshair := hud.get_node_or_null("Crosshair") as Control
	_check(crosshair != null and absf(crosshair.position.x - (vp.x * 0.5 - 6.0)) < 1.0,
		"crosshair centred", str(crosshair.position if crosshair != null else Vector2.ZERO))
	var hotbar: Panel = hud.get_node_or_null("HotbarPanel") as Panel
	_check(hotbar != null and hotbar.position.y > vp.y - 80.0, "hotbar anchored to bottom", str(hotbar.position if hotbar != null else Vector2.ZERO))
	var loadout: Panel = hud.get_node_or_null("LoadoutPanel") as Panel
	_check(loadout == null or not loadout.visible, "legacy loadout card hidden")
	var labels: Array[String] = []
	for child in hud.get_children():
		var lbl := child as Label
		if lbl != null and lbl.visible and lbl.text.contains("LUMENCASTER"):
			labels.append(lbl.text)
	_check(labels.is_empty(), "no Lumencaster label rendered", str(labels))

	if failures > 0:
		print("PRESENTATION RESULT: %d/%d failed" % [failures, checks])
		quit(1)
		return
	print("PRESENTATION PASS: %d checks" % checks)
	quit(0)
