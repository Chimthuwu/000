extends SceneTree

# Visual evidence for the Terraria HUD/inventory recreation. Boots the real game,
# fills a plausible early-game hotbar, winds time to daylight and writes two PNGs:
# the normal gameplay HUD and the ESC expanded inventory.
#   Godot --fixed-fps 60 --path . --script res://debug/capture_terraria_ui.gd

const SHOT_DIR := "res://debug/evidence"
const CYCLE: DayNightConfig = preload("res://data/world/day_night_config.tres")

var main: Node
var world: VoxelWorld
var player: VoxelPlayer
var hud: GameHUD


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	if packed == null:
		print("TERRARIAUICAP FAIL: main.tscn did not load")
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
	print("TERRARIAUICAP %s %s error=%d image=%s" % [shot_name, detail, error, path])


func _run() -> void:
	world = main.get_node("VoxelWorld")
	player = main.get_node("Player")
	hud = main.get_node("HUD")
	var cycle: DayNightCycle = main.get_node("DayNightCycle")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 4000:
		await process_frame
		frames += 1
	print("TERRARIAUICAP world ready frames=%d" % frames)
	cycle.restore_time(cycle.CONFIG.day_seconds * 0.42)
	await _wait(2.0)

	# Streaming can still be catching up right after spawn; lift the player back
	# onto the surface if they fell through a chunk that was not collidable yet.
	for _i in range(150):
		var p := player.global_position
		var surface := world.get_surface_height(floori(p.x), floori(p.z))
		if surface > 0 and p.y < float(surface) - 25.0:
			player.global_position = Vector3(p.x, float(surface) + 2.0, p.z)
			player.velocity = Vector3.ZERO
		await process_frame
	await _wait(1.5)
	var settled := player.global_position
	var settled_surface := world.get_surface_height(floori(settled.x), floori(settled.z))
	print("TERRARIAUICAP settle y=%.1f surface=%d depth=%d" % [settled.y, settled_surface, settled_surface - floori(settled.y)])

	# A believable early hotbar: pickaxe, axe, sword, torches, building blocks.
	if player.inventory != null:
		player.inventory.add_item(&"copper_pickaxe", 1)
		player.inventory.add_item(&"copper_axe", 1)
		player.inventory.add_item(&"wooden_sword", 1)
		player.inventory.add_item(&"torch", 40)
		player.inventory.add_item(&"wood", 120)
		player.inventory.add_item(&"stone", 74)
		player.inventory.add_item(&"healing_salve", 3)
		player.inventory.add_item(&"copper_helmet", 1)
		player.inventory.add_item(&"copper_chestplate", 1)
		player.inventory.select(3)
	# Partial health and mana so the heart/star states are visible, not a full row.
	player.health = player.max_health * 0.62
	if player.get("weapons") != null:
		player.weapons.mana = 47.0
	hud._update_health()
	hud._update_mana()
	await _wait(0.6)
	await _capture("hud_gameplay", "top-left hotbar, top-right hearts and mana stars")

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud._toggle_inventory()
	await _wait(0.5)
	await _capture("hud_inventory", "ESC expanded inventory over the running world")
	print("TERRARIAUICAP inventory_visible=%s paused=%s hotbar_visible=%s" % [str(hud.inventory_visible), str(hud.paused), str(hud.hotbar_panel.visible)])

	# Same inventory with an armour item equipped, to show real equipment state.
	if player.inventory != null:
		player.inventory.equip("head", "main", 0)
		hud._refresh_inventory_panel()
		await _wait(0.3)
		await _capture("hud_inventory_equipped", "copper helmet equipped in the armour column")

	hud._toggle_inventory()
	await _wait(0.2)
	quit(0)
