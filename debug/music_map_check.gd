extends SceneTree

# Checks that the biome music map points at real, loadable tracks and that the
# manager actually switches a player onto them (Underground and Crimson were the
# two folders the soundtrack was imported from).

var _failures: Array[String] = []


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("PASS %s (%s)" % [name, detail])
	else:
		_failures.append(name)
		print("FAIL %s (%s)" % [name, detail])


func _initialize() -> void:
	var map: MusicMap = load("res://data/audio/music_map.tres")
	_check("the music map loads", map != null, "tracks=%d" % (map.tracks.size() if map else 0))
	if map == null:
		print("MUSIC MAP CHECK FAIL")
		quit(1)
		return

	var missing_categories: Array[String] = []
	for category in MusicSynth.CATEGORIES:
		if map.track_for(String(category)) == "":
			missing_categories.append(String(category))
	_check("every music category is mapped, so the synth is unused",
		missing_categories.is_empty(), "missing=%s" % str(missing_categories))

	for category in ["underground", "crimson", "surface_day", "surface_night", "cave",
			"jungle", "corruption", "hallow", "underground_corruption", "underground_crimson",
			"underground_hallow", "desert", "underworld",
			"snow", "ocean", "mushroom", "space", "boss"]:
		var path := map.track_for(category)
		var ok := path != "" and ResourceLoader.exists(path)
		var detail := path if path != "" else "(none)"
		if ok:
			var stream: AudioStream = load(path) as AudioStream
			ok = stream != null
			detail = "%s %.1fs" % [path.get_file(), stream.get_length() if stream else 0.0]
		_check("category %s has a real track" % category, ok, detail)

	# Boot the world and let the manager pick a category on its own.
	var scene: Node = (load("res://scenes/world/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var world = scene.get_node("VoxelWorld")
	var player = scene.get_node("Player")
	var music: MusicManager = scene.get_node("MusicManager") as MusicManager
	var booted := Time.get_ticks_msec()
	while (not bool(world.is_generated) or not bool(player.spawned)) and Time.get_ticks_msec() - booted < 30000:
		await process_frame
	# The manager needs switch_hold_seconds of world time before it commits to a
	# track, and headless frames run far faster than real time.
	var started := Time.get_ticks_msec()
	while music.current_category == "" and Time.get_ticks_msec() - started < 15000:
		await process_frame
	_check("surface music starts on the overworld track",
		music.current_track == "surface_day.mp3" or music.current_track == "surface_night.mp3",
		"category=%s track=%s" % [music.current_category, music.current_track])

	# Force the two categories from the imported folders and confirm the player
	# is really holding the file, looping, and fading in.
	for entry in [["underground", "underground.mp3"], ["crimson", "crimson.mp3"],
			["underground_corruption", "underground_corruption.mp3"],
			["underground_crimson", "underground_crimson.mp3"],
			["underground_hallow", "underground_hallow.mp3"],
			["desert", "surface_day.mp3"], ["underworld", "underworld.mp3"]]:
		music.force_category(entry[0])
		for _settle in range(120):
			await process_frame
		var active: AudioStreamPlayer = music.players[music.active_index]
		var looped := false
		if active.stream != null and "loop" in active.stream:
			looped = bool(active.stream.get("loop"))
		_check("forcing %s fades in its file" % entry[0],
			music.current_category == entry[0] and music.current_track == entry[1],
			"track=%s" % music.current_track)
		_check("%s loops instead of stopping" % entry[0], looped and active.playing,
			"playing=%s loop=%s" % [str(active.playing), str(looped)])
		# A real audio driver is the only way to prove the file decodes; with the
		# dummy driver there is no playback clock to read.
		if AudioServer.get_driver_name() != "Dummy":
			var clock := Time.get_ticks_msec()
			while Time.get_ticks_msec() - clock < 800:
				await process_frame
			_check("%s actually plays the mp3" % entry[0],
				active.get_playback_position() > 0.2,
				"pos=%.2fs driver=%s" % [active.get_playback_position(), AudioServer.get_driver_name()])

	# World-driven selection: standing underground in crimson soil must resolve to
	# the crimson track without a forced override.
	music.force_category("")
	var cell := Vector3i(floori(player.global_position.x), floori(player.global_position.y), floori(player.global_position.z))
	var deep_state := {
		"cell": cell, "biome": 0, "identity": GameplayBiome.Identity.CRIMSON,
		"identity_name": "Crimson", "surface": cell.y + 120, "depth": 120, "night": false,
	}
	_check("deep crimson resolves to its own underground track",
		music.category_for(deep_state) == "underground_crimson", music.category_for(deep_state))
	var surface_crimson := deep_state.duplicate()
	surface_crimson["depth"] = 0
	surface_crimson["surface"] = cell.y
	_check("surface crimson keeps the surface track",
		music.category_for(surface_crimson) == "crimson", music.category_for(surface_crimson))
	var corruption_state := deep_state.duplicate()
	corruption_state["identity"] = GameplayBiome.Identity.CORRUPTION
	corruption_state["identity_name"] = "Corruption"
	_check("deep corruption resolves to its own underground track",
		music.category_for(corruption_state) == "underground_corruption", music.category_for(corruption_state))
	var hallow_state := deep_state.duplicate()
	hallow_state["identity"] = GameplayBiome.Identity.HALLOW
	hallow_state["identity_name"] = "Hallow"
	_check("deep hallow resolves to its own underground track",
		music.category_for(hallow_state) == "underground_hallow", music.category_for(hallow_state))
	var surface_corruption := corruption_state.duplicate()
	surface_corruption["depth"] = 0
	surface_corruption["surface"] = cell.y
	_check("surface corruption keeps the surface track",
		music.category_for(surface_corruption) == "corruption", music.category_for(surface_corruption))
	var underground_state := deep_state.duplicate()
	underground_state["identity"] = GameplayBiome.Identity.FOREST
	underground_state["identity_name"] = "Forest"
	underground_state["depth"] = 12
	_check("a shallow cave resolves to the underground track",
		music.category_for(underground_state) == "underground", music.category_for(underground_state))

	if _failures.is_empty():
		print("MUSIC MAP CHECK PASS")
		quit(0)
	else:
		print("MUSIC MAP CHECK FAIL: %s" % ", ".join(_failures))
		quit(1)
