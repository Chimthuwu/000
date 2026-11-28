extends SceneTree

# Transition evidence pass for the todo's music verification item: teleports
# the real player across biome borders and down the depth ladder, then lets the
# live MusicManager._process drive real [Music] switches, and asserts
#   1. every reached category is a real file track (no procedural fallback),
#   2. a brief border crossing (< switch_hold_seconds) never switches the track,
#      so pacing across a border back and forth cannot restart the music,
#   3. holding on the far side past the hold window switches exactly once.
# Run with: Godot --headless --path . --script res://debug/music_transition_check.gd

const COMPLETE := "MUSIC TRANSITION CHECK PASS: border walk, depth ladder, hold debounce and no-restart"

var main: Node
var failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("MUSICTRANS PASS: %s %s" % [label, detail])
	else:
		failures += 1
		push_error("MUSICTRANS FAIL: %s %s" % [label, detail])


func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	main = packed.instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var world = main.world
	var player = main.player
	var music = main.get_node_or_null("MusicManager")
	if music == null:
		for child in main.get_children():
			if child.get_script() != null and String(child.get_script().resource_path).ends_with("music_manager.gd"):
				music = child
				break
	if music == null:
		print("MUSICTRANS FAIL: no MusicManager in main.tscn")
		quit(1)
		return
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 4000:
		await process_frame
		frames += 1
	for _i in range(8):
		await process_frame
	_check(music.tracks_ready() == 0 and music.is_prewarmed(), "map-backed manager ready (no synth tracks)", "procedural=%d" % music.tracks_ready())

	# --- 1. Walk across real biome borders ----------------------------------
	# Sample the category the manager would pick along the line from spawn to
	# each core biome centre, so every surface category is "reached" by a real
	# position like a walking player would reach it.
	var spawn: Vector2 = Vector2(world.spawn_origin.x, world.spawn_origin.z)
	var reached := {}
	# find_biome_center takes BiomeManager region ids (FROST is Snow, HUSH is
	# the Jungle regional variant); the identity mapping is only for the state.
	for identity in [BiomeManager.FROST, BiomeManager.HUSH,
			BiomeManager.DESERT, BiomeManager.MUSHROOM,
			BiomeManager.CRIMSON, BiomeManager.OCEAN]:
		var center_v := BiomeManager.find_biome_center(identity, world.world_seed, 64, 64)
		if center_v == Vector2i(-2147483648, -2147483648) or center_v == Vector2i.ZERO:
			continue
		var center: Vector2 = Vector2(center_v.x, center_v.y)
		var from: Vector2 = spawn
		for step in range(0, 41):
			var point: Vector2 = from.lerp(center, float(step) / 40.0)
			var surface = world.get_surface_height(int(point.x), int(point.y))
			var state := {
				"cell": Vector3i(int(point.x), surface, int(point.y)),
				"identity": GameplayBiome.identity_for(world.get_biome_at(Vector3i(int(point.x), surface, int(point.y)))),
				"identity_name": GameplayBiome.identity_name(GameplayBiome.identity_for(world.get_biome_at(Vector3i(int(point.x), surface, int(point.y))))),
				"surface": surface,
				"depth": 0,
				"night": false,
			}
			var category: String = music.category_for(state)
			reached[category] = true
	for category in reached.keys():
		var path: String = music.MAP.track_for(category)
		_check(path != "" and ResourceLoader.exists(path), "reached category maps to a real file track", "%s -> %s" % [category, path])
	_check(reached.has("surface_day") and reached.has("snow") and reached.has("jungle")
		and reached.has("desert") and reached.has("crimson"),
		"border walk reaches the surface categories",
		"reached=%s" % ", ".join(reached.keys()))

	# --- 2. Live border crossing: hold debounce, then one clean switch -------
	var snow_center_v := BiomeManager.find_biome_center(BiomeManager.FROST, world.world_seed, 64, 64)
	if snow_center_v != Vector2i(-2147483648, -2147483648) and snow_center_v != Vector2i.ZERO:
		var snow_center: Vector2 = Vector2(snow_center_v.x, snow_center_v.y)
		var surface_snow = world.get_surface_height(int(snow_center.x), int(snow_center.y))
		player.position = Vector3(snow_center.x + 0.5, float(surface_snow) + 2.0, snow_center.y + 0.5)
		await process_frame
		await _wait(2.5)
		var snow_state: Dictionary = music.world_state()
		_check(music.current_category == "snow", "holding inside Snow switches to snow", "category=%s" % music.current_category)
		var transitions_before: int = music.transitions
		# Pace across the border and back for under the hold window: the track
		# must not stutter-switch (and therefore not restart).
		var surface_spawn = world.spawn_height()
		for _i in range(8):
			player.position = Vector3(snow_center.x + 0.5, float(surface_snow) + 2.0, snow_center.y + 0.5)
			await process_frame
			player.position = Vector3(spawn.x + 0.5, float(surface_spawn) + 2.0, spawn.y + 0.5)
			await process_frame
		# Assert immediately: inside the hold window the crossing must not have
		# switched (so nothing restarted). Holding past the window is the next
		# assertion, and it is allowed to switch exactly once.
		_check(music.transitions == transitions_before,
			"rapid border crossing does not switch (no restart)", "transitions=%d -> %d" % [transitions_before, music.transitions])
		# Now hold on the far side; exactly one new switch must happen.
		player.position = Vector3(spawn.x + 0.5, float(surface_spawn) + 2.0, spawn.y + 0.5)
		await _wait(2.5)
		_check(music.current_category == "surface_day", "holding in Forest resolves the day surface track", "category=%s" % music.current_category)
		_check(music.transitions == transitions_before + 1,
			"a held crossing switches exactly once", "transitions=%d" % music.transitions)

	# --- 3. Depth ladder ------------------------------------------------------
	var base_x = world.spawn_origin.x
	var base_z = world.spawn_origin.z
	var surface = world.spawn_height()
	player.position = Vector3(base_x + 0.5, float(surface) - 12.0, base_z + 0.5)
	await _wait(2.0)
	_check(music.current_category == "underground", "shallow depth plays underground", "category=%s depth>=%d" % [music.current_category, 8])
	player.position = Vector3(base_x + 0.5, float(surface) - 80.0, base_z + 0.5)
	await _wait(2.0)
	_check(music.current_category == "cave", "deep depth plays cave", "category=%s" % music.current_category)
	player.position = Vector3(base_x + 0.5, float(WorldLayers.UNDERWORLD_DEPTH), base_z + 0.5)
	await _wait(2.0)
	var underworld_surface = world.get_surface_height(base_x, base_z)
	player.position = Vector3(base_x + 0.5, float(underworld_surface - WorldLayers.UNDERWORLD_DEPTH - 1.0), base_z + 0.5)
	await _wait(2.0)
	_check(music.current_category == "underworld", "underworld depth plays underworld", "category=%s" % music.current_category)
	for category in ["underground", "cave", "underworld"]:
		var path: String = music.MAP.track_for(category)
		_check(path != "" and ResourceLoader.exists(path), "depth category maps to a real file track", "%s -> %s" % [category, path])

	# --- 4. Boss takes over the mix ------------------------------------------
	# A live boss fight is out of scope here; the manager's own override hook
	# drives the same _switch_to path a spawned boss triggers via "bosses".
	music.force_category("boss")
	await _wait(2.0)
	_check(music.current_category == "boss", "boss presence switches to the boss track",
		"category=%s track=%s" % [music.current_category, music.current_track])
	var boss_path: String = music.MAP.track_for("boss")
	_check(boss_path != "" and ResourceLoader.exists(boss_path), "boss category maps to a real file track", "%s -> %s" % ["boss", boss_path])
	music.force_category("")
	await _wait(2.0)
	_check(music.current_category != "boss", "clearing the override returns to the world track", "category=%s" % music.current_category)

	if failures > 0:
		quit(1)
		return
	print(COMPLETE)
	quit(0)
