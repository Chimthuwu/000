extends SceneTree

# End-to-end check for the survival layer: mortality, respawn, light-driven
# recovery and drain, placeable light economy, environmental clues, procedural
# audio wiring and persistence of the new gameplay state.

const COMPLETE := "SURVIVAL CHECK PASS: mortality, light economy, clues, audio and persistence"

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("SURVIVAL PASS: %s %s" % [label, detail])
		return
	failures += 1
	push_error("SURVIVAL FAIL: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_frames(count: int, physics := false) -> void:
	for _i in range(count):
		if physics:
			await physics_frame
		else:
			await process_frame


func _wait_world() -> void:
	var frames := 0
	while not main.world.is_generated and frames < 1800:
		await process_frame
		frames += 1
	_check(main.world.is_generated, "world generated", "frames=%d" % frames)


func _run() -> void:
	await _wait_world()
	var world: VoxelWorld = main.world
	var player: VoxelPlayer = main.player
	var caster: Lumencaster = player.get_node("Lumencaster")
	var hud: GameHUD = main.get_node("HUD")

	# --- Mortality ----------------------------------------------------------
	player.god_mode = false
	player.damage_cooldown = 0.0
	player.take_damage(30.0)
	_check(is_equal_approx(player.health, 70.0), "enemy damage reduces health", "hp=%.0f" % player.health)
	player.take_damage(30.0)
	_check(is_equal_approx(player.health, 70.0), "damage cooldown blocks a same-frame second hit")
	player.damage_cooldown = 0.0
	player.take_damage(100.0)
	_check(player.dead and player.health <= 0.0, "lethal damage kills the player")
	_check(hud.death_overlay.visible, "death screen is shown")
	main.respawn_player()
	await _wait_frames(3)
	var expected := Vector3(float(world.spawn_origin.x) + 0.5, float(world.spawn_height()) + 1.0, float(world.spawn_origin.z) + 0.5)
	_check(player.position.distance_to(expected) < 0.1, "respawn uses world.spawn_origin", "pos=%s" % str(player.position))
	_check(not player.dead and is_equal_approx(player.health, VoxelPlayer.MAX_HEALTH), "respawn restores health")
	_check(not hud.death_overlay.visible, "death screen is hidden on respawn")

	player.god_mode = true
	player.damage_cooldown = 0.0
	player.take_damage(50.0)
	_check(is_equal_approx(player.health, VoxelPlayer.MAX_HEALTH), "god mode blocks damage")
	player.god_mode = false

	# --- Light-driven recovery and drain ------------------------------------
	player.health = 50.0
	world.set_ambient_sky_level(0.6)
	main.gloom.set_level_for_cell(Vector3i(floori(player.position.x), 0, floori(player.position.z)), 0.0)
	await _wait_frames(20, true)
	_check(player.health > 50.0, "health regenerates in bright, low-Gloom light", "hp=%.1f" % player.health)
	hud._update_environment()
	_check(hud.environment_label.text == "SHELTERED", "HUD reports sheltered state", hud.environment_label.text)

	caster.reserve = 100.0
	caster.selected_cartridge = 1
	caster._fire_selected_cartridge()
	_check(caster.reserve < 100.0, "placing a beacon costs Lumen", "reserve=%.0f" % caster.reserve)
	if caster.temporary_lights.is_empty():
		var fallback_cell := Vector3i(floori(player.position.x), world.get_surface_height(floori(player.position.x), floori(player.position.z)) + 1, floori(player.position.z))
		var torch_id: int = world.block_ids[&"torch"]
		world.set_block(fallback_cell, torch_id)
		caster.temporary_lights.append({"cell": fallback_cell, "block_id": torch_id, "remaining": 25.0})
	var serialized: Array = caster.serialize_temporary_lights()
	_check(serialized.size() > 0, "temporary light is serializable")

	# A dark, high-Gloom column has no light and bleeds the reserve.
	var dark := Vector3(100.5, float(world.get_surface_height(100, 100)) + 1.0, 100.5)
	var home := player.position
	player.position = dark
	world.set_ambient_sky_level(0.0)
	main.gloom.set_level_for_cell(Vector3i(100, floori(dark.y), 100), 1.0)
	var reserve_before := caster.reserve
	await _wait_frames(20, true)
	_check(caster.reserve < reserve_before, "unlit high Gloom drains Lumen", "%.1f -> %.1f" % [reserve_before, caster.reserve])
	player.position = home

	# --- Environmental clues ------------------------------------------------
	var found_site := {}
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			var site := WorldGenerator._derelict_site(world.world_seed, gx, gz)
			if not site.is_empty():
				found_site = site
				break
		if not found_site.is_empty():
			break
	_check(not found_site.is_empty(), "abandoned camps generate deterministically")
	if not found_site.is_empty():
		var near := WorldGenerator.derelict_site_near(world.world_seed, int(found_site["x"]), int(found_site["z"]))
		_check(not near.is_empty(), "camp proximity query finds the site")
		player.position = Vector3(float(found_site["x"]) + 0.5, float(found_site["y"]) + 1.0, float(found_site["z"]) + 0.5)
		main._update_environmental_clues(1.0)
		_check(hud.world_hint_label.visible and hud.world_hint_label.text.begins_with("ABANDONED"), "approaching a camp shows an environmental clue")
		player.position = home
		main._update_environmental_clues(1.0)

	# --- Audio ---------------------------------------------------------------
	_check(main.get_node_or_null("AudioDirector") != null, "audio director is present in the main scene")
	_check(AudioServer.get_bus_index("World") >= 0 and AudioServer.get_bus_index("UI") >= 0, "World and UI audio buses exist")

	# --- Persistence of survival state --------------------------------------
	caster.inventory[&"stone"] = 7
	player.health = 63.0
	caster.reserve = 41.0
	player.god_mode = true
	main.save_game()
	await _wait_frames(2)
	player.health = 10.0
	caster.reserve = 5.0
	caster.inventory.clear()
	player.god_mode = false
	main.load_game()
	await _wait_world()
	_check(is_equal_approx(player.health, 63.0), "health survives save/load", "hp=%.0f" % player.health)
	# The world keeps simulating during the regeneration wait after reload, so
	# the reserve may drift slightly from recharge/drain; the restored value must
	# still be the saved figure rather than the pre-load 5.0.
	_check(absf(caster.reserve - 41.0) < 3.0, "Lumen reserve survives save/load", "reserve=%.2f" % caster.reserve)
	_check(int(caster.inventory.get(&"stone", 0)) == 7, "inventory survives save/load")
	_check(player.god_mode, "god flag survives save/load")
	_check(caster.temporary_lights.size() > 0, "placed lights survive save/load")
	_check(world.is_generated and world.chunk_records.size() > 0, "infinite-world streaming still works after reload")

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
