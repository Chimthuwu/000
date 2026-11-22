extends SceneTree

## Headless check for the biome music + ambience systems.
## Asserts the mapping file loads, the procedural bank synthesises every
## category, category resolution follows biome/depth/day-night, crossfades ramp
## both players and never restart the track that is already playing.
##   Godot --headless --path . --script res://debug/music_check.gd

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String, detail := "") -> void:
	checks += 1
	if condition:
		print("MUSIC PASS: %s %s" % [label, detail])
	else:
		failures += 1
		print("MUSIC FAIL: %s %s" % [label, detail])


func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _run() -> void:
	var packed: PackedScene = load("res://scenes/world/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	var world: VoxelWorld = main.get_node("VoxelWorld")
	var player: VoxelPlayer = main.get_node("Player")
	var frames := 0
	while (not world.is_generated or not player.spawned) and frames < 4000:
		await process_frame
		frames += 1

	var music: MusicManager = main.get_node_or_null("MusicManager") as MusicManager
	var ambience: AmbienceManager = main.get_node_or_null("AmbienceManager") as AmbienceManager
	_check(music != null, "MusicManager is part of the world scene")
	_check(ambience != null, "AmbienceManager is part of the world scene")
	if music == null or ambience == null:
		quit(1)
		return

	var map: MusicMap = MusicManager.MAP
	_check(map != null, "music map resource loads")
	var missing := []
	var categories: Array = MusicSynth.CATEGORIES
	for category in categories:
		var path := map.track_for(category)
		if path == "" or not ResourceLoader.exists(path):
			missing.append(category)
	_check(missing.is_empty(), "every mapped biome points at a real track file", "missing=%s" % str(missing))
	_check(missing.is_empty() and map.tracks.size() >= categories.size(),
		"every music category is mapped to a file, so the synth is never used",
		"mapped=%d/%d" % [map.tracks.size(), categories.size()])
	_check(map.fade_seconds >= 1.0 and map.switch_hold_seconds > 0.0, "map defines crossfade and hold times", "fade=%.1fs hold=%.1fs" % [map.fade_seconds, map.switch_hold_seconds])

	# The worker synthesises the whole bank; wait for it like a slow disk would.
	var waited := 0.0
	while not music.is_prewarmed() and waited < 45.0:
		await process_frame
		waited += 1.0 / 60.0
	await _wait(0.2)
	_check(music.is_prewarmed(), "music bank finishes synthesising", "waited=%.1fs" % waited)
	var unmapped := 0
	for category in MusicSynth.CATEGORIES:
		if map.track_for(category) == "":
			unmapped += 1
	_check(music.tracks_ready() == unmapped, "every unmapped category still has a synth stream", "%d/%d" % [music.tracks_ready(), unmapped])

	# Category resolution against synthetic world states.
	var day := {"identity": GameplayBiome.Identity.FOREST, "depth": 0, "surface": 120, "cell": Vector3i(0, 120, 0), "night": false}
	var night := day.duplicate()
	night["night"] = true
	_check(music.category_for(day) == "surface_day", "forest daytime resolves to the overworld day track")
	_check(music.category_for(night) == "surface_night", "forest night resolves to the night track")
	var underground := day.duplicate()
	underground["depth"] = 70
	_check(music.category_for(underground) == "cave", "deep forest resolves to cave music")
	var shallow := day.duplicate()
	shallow["depth"] = 20
	_check(music.category_for(shallow) == "underground", "shallow forest resolves to underground music")
	var hell := day.duplicate()
	hell["depth"] = WorldLayers.UNDERWORLD_DEPTH + 4
	_check(music.category_for(hell) == "underworld", "underworld depth resolves to the underworld track")
	var sky := day.duplicate()
	sky["cell"] = Vector3i(0, 210, 0)
	_check(music.category_for(sky) == "space", "above the cloud line resolves to space")
	var desert := day.duplicate()
	desert["identity"] = GameplayBiome.Identity.DESERT
	_check(music.category_for(desert) == "desert", "desert resolves to its own track")
	var jungle := day.duplicate()
	jungle["identity"] = GameplayBiome.Identity.JUNGLE
	_check(music.category_for(jungle) == "jungle", "jungle resolves to its own track")
	var crimson := day.duplicate()
	crimson["identity"] = GameplayBiome.Identity.CRIMSON
	_check(music.category_for(crimson) == "crimson", "crimson resolves to its own track")
	var snowy := day.duplicate()
	snowy["identity"] = GameplayBiome.Identity.SNOW
	_check(music.category_for(snowy) == "snow", "snow resolves to its own track")
	var ocean := day.duplicate()
	ocean["identity"] = GameplayBiome.Identity.OCEAN
	_check(music.category_for(ocean) == "ocean", "ocean resolves to its own track")

	# Crossfade behaviour.
	music.force_category("surface_day")
	await _wait(0.2)
	var first_transitions := music.transitions
	_check(music.current_category == "surface_day" and music.current_track == "surface_day.mp3", "day track is playing", music.current_track)
	_check(music.players[0].playing or music.players[1].playing, "a music player is running")
	music.force_category("surface_day")
	await _wait(0.1)
	_check(music.transitions == first_transitions, "re-selecting the same category does not restart the track")

	var active_before := music.active_index
	music.force_category("underground")
	await _wait(0.35)
	var both := music.players[0].playing and music.players[1].playing
	var split := absf(music.players[0].volume_db - music.players[1].volume_db)
	_check(both, "both players run during the crossfade")
	_check(split > 1.0 and split < 79.0, "crossfade ramps the two players, no full-volume overlap", "gap=%.1fdB" % split)
	await _wait(1.8)
	_check(music.active_index != active_before, "the new track became the active player")
	_check(not music.players[active_before].playing, "the previous track is stopped once faded out")
	_check(music.current_category == "underground", "underground music is current")

	# Distinct audio per category: compare waveform fingerprints.
	var day_bytes := MusicSynth.build_bytes("surface_day")
	var cave_bytes := MusicSynth.build_bytes("underground")
	_check(day_bytes.size() > 100000, "synthesised tracks are several seconds long", "%d bytes" % day_bytes.size())
	_check(day_bytes != cave_bytes, "different categories produce different audio")
	var nonzero := 0
	for i in range(0, mini(day_bytes.size(), 4000), 2):
		var value := day_bytes.decode_s16(i)
		if absi(value) > 200:
			nonzero += 1
	_check(nonzero > 50, "the day track is not silence", "%d loud samples in 2s" % nonzero)

	# Ambience bed.
	_check(ambience.streams.size() == AmbienceManager.CATEGORIES.size(), "ambience bank is built", "%d loops" % ambience.streams.size())
	await _wait(1.6)
	_check(ambience.current != "", "ambience selects a bed for the spawn biome", ambience.current)
	_check(ambience.players[ambience.active_index].playing, "the ambience bed is audible")

	if failures > 0:
		print("MUSIC CHECK FAIL: %d/%d assertions failed" % [failures, checks])
		quit(1)
		return
	print("MUSIC CHECK PASS: %d assertions over mapping, synthesis, crossfade and ambience" % checks)
	quit(0)
