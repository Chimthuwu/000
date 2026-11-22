extends SceneTree

# Gameplay-side integration check: biome spawn tables, new enemy variants,
# HUD biome indicator, HUD visibility regressions, and save policy.

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if not condition:
		failures += 1
		push_error("GAMEPLAY CHECK FAIL: %s %s" % [label, detail])
		return
	print("GAMEPLAY PASS: %s %s" % [label, detail])


func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _run() -> void:
	var world: VoxelWorld = main.world
	var frames := 0
	while not world.is_generated and frames < 1800:
		await process_frame
		frames += 1
	_check(world.is_generated, "world ready", "frames=%d" % frames)
	if not world.is_generated:
		quit(1)
		return

	# --- Biome spawn tables (pure config) ---
	var config: EnemyConfig = preload("res://data/world/enemy_config.tres")
	var allowed := [
		[EnemyConfig.KIND_NIGHTLING, EnemyConfig.KIND_LAMP_EATER],
		[EnemyConfig.KIND_NIGHTLING, EnemyConfig.KIND_HOLLOW],
		[EnemyConfig.KIND_NIGHTLING, EnemyConfig.KIND_FROST_STALKER],
		[EnemyConfig.KIND_LAMP_EATER, EnemyConfig.KIND_BOG_CRAWLER],
	]
	for biome in range(4):
		var rolled := {}
		for step in range(100):
			rolled[config.roll_kind(biome, float(step) / 100.0)] = true
		var only_table := true
		for key in rolled.keys():
			if not allowed[biome].has(key):
				only_table = false
		_check(only_table and rolled.size() == allowed[biome].size(), "biome %d rolls exactly its table" % biome, str(rolled.keys()))

	# --- Enemy variants ---
	var director: EnemyDirector = main.enemy_director
	var stalker: NightEnemy = director._make_enemy(EnemyConfig.KIND_FROST_STALKER)
	main.add_child(stalker)
	_check(stalker is Nightling, "Frost Stalker reuses Nightling logic")
	_check(is_equal_approx(stalker.move_speed, config.frost_stalker_speed) and stalker.move_speed > config.nightling_speed, "Frost Stalker is faster", "speed=%.1f" % stalker.move_speed)
	var icy := false
	for child in stalker.visual_root.get_children():
		var material := child.material_override as StandardMaterial3D
		if material != null and material.emission_energy_multiplier >= 6.0 and material.emission.b > material.emission.r:
			icy = true
	_check(icy, "Frost Stalker glow parts are blue-tinted")
	stalker.queue_free()

	var crawler: NightEnemy = director._make_enemy(EnemyConfig.KIND_BOG_CRAWLER)
	main.add_child(crawler)
	_check(crawler is LampEater, "Bog Crawler reuses Lamp Eater logic")
	_check(crawler.body_half_extents.y < 0.35, "Bog Crawler is low-slung (crawls)", "half_y=%.2f" % crawler.body_half_extents.y)
	crawler.queue_free()
	await _wait_frames(3)

	# --- Sandbox HUD / vehicle removal ---
	var hud: GameHUD = main.get_node("HUD")
	await _wait_frames(2)
	_check(main.get_node_or_null("Buggy") == null, "dune buggy is no longer spawned in the world")
	_check(not main.player.driving, "player starts on foot, not in a vehicle")
	_check(not hud.dialogue_footer.is_visible_in_tree(), "dialogue footer stays hidden with no dialogue open")
	_check(not hud.boss_panel.visible and not hud.boss_health_fill.visible, "boss bar stays hidden with no boss")
	_check(hud.heart_icons.size() == 20 and hud.heart_icons[0].visible and hud.heart_icons[0].position.y < 40.0, "hearts use the top-right Terraria row", "visible=%d y=%.0f" % [hud.heart_icons.filter(func(h): return h.visible).size(), hud.heart_icons[0].position.y])
	_check(hud.heart_icons[9].position.x > 1000.0, "hearts are right-aligned against the screen edge", "x=%.0f" % hud.heart_icons[9].position.x)
	_check(hud.mana_stars.size() == 10 and hud.mana_stars[0].visible and hud.mana_stars[0].position.y > hud.heart_icons[0].position.y, "mana stars sit under the hearts")
	_check(hud.hotbar_panel.position.x < 20.0 and hud.hotbar_panel.position.y < 20.0, "hotbar is anchored at the top left", "pos=%s" % hud.hotbar_panel.position)

	# --- HUD biome indicator ---
	hud._update_biome(0.016)
	_check(hud.last_biome >= 0 and hud.biome_label.text != "", "HUD shows the persistent biome tag", hud.biome_label.text)
	_check(not hud.biome_intro_label.visible, "no crossing banner on first read")
	var player_home: Vector3 = main.player.position
	var home_biome := world.get_biome_at(Vector3i(floori(player_home.x), 0, floori(player_home.z)))
	var found := false
	var away := Vector3.ZERO
	for step in range(1, 60):
		for eighths in range(8):
			var angle := TAU * float(eighths) / 8.0
			var x := floori(player_home.x + cos(angle) * float(step) * 40.0)
			var z := floori(player_home.z + sin(angle) * float(step) * 40.0)
			if world.get_biome_at(Vector3i(x, 0, z)) != home_biome:
				away = Vector3(float(x) + 0.5, 40.0, float(z) + 0.5)
				found = true
				break
		if found:
			break
	_check(found, "a neighbouring biome column exists for the crossing test")
	main.player.position = away
	hud._update_biome(0.016)
	_check(hud.biome_intro_label.visible and hud.biome_intro_label.text.begins_with("ENTERING:"), "crossing shows ENTERING banner", hud.biome_intro_label.text)
	main.player.position = player_home
	hud.last_biome = world.get_biome_at(Vector3i(floori(player_home.x), 0, floori(player_home.z)))
	hud.biome_intro_time = 0.0

	# --- Save policy ---
	_check(WorldSave.SAVE_VERSION == 4 and WorldSave.FORMAT_CHANGED_MESSAGE == "World format changed — starting fresh", "save format v4 with the approved rejection message")
	var legacy_dir := "user://worlds/991"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(legacy_dir))
	var legacy := FileAccess.open(legacy_dir.path_join("metadata.json"), FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"save_version": 1, "seed": 991}))
	legacy.close()
	_check(WorldSave.load_world(991, world).is_empty(), "v1 saves are rejected outright")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_dir))

	if failures > 0:
		quit(1)
		return
	print("GAMEPLAY INTEGRATION CHECK PASS: biomes, enemies, governor, HUD and saves integrated")
	quit(0)
