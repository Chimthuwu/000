extends Node
class_name MusicManager

## Terraria-style environmental music. The category is resolved from real world
## state (surface biome, depth, day/night, boss presence), never from trigger
## volumes, and every change is a crossfade between two AudioStreamPlayers so a
## track is never cut and never restarted by walking along a border.
##
## Tracks come either from `data/audio/music_map.tres` (point an entry at a
## licensed/original file) or from the built-in procedural synthesis in
## `MusicSynth`. Synthesis runs on a worker thread and the finished loops are
## installed on the main thread, so no biome change hitches the game.

const MAP: MusicMap = preload("res://data/audio/music_map.tres")
const BASE_DB := -4.0

var world: VoxelWorld
var player: VoxelPlayer
var cycle: DayNightCycle
var blood_moon: BloodMoonDirector

var players: Array[AudioStreamPlayer] = []
var active_index := 0
var fade_from := 0
var fade_to := 1
var fade_time := -1.0
var fade_duration := 1.5

var current_category := ""
var current_track := ""
var desired_category := ""
var switch_hold := 0.0
var transitions := 0
var last_reason := ""
var override_category := ""

var _streams: Dictionary = {}
var _thread: Thread
var _mutex := Mutex.new()
var _ready_tracks: Array = []
var _building := true
var _abort := false
var _pending_logged := ""


func _ready() -> void:
	world = get_parent().get_node_or_null("VoxelWorld") as VoxelWorld
	player = get_parent().get_node_or_null("Player") as VoxelPlayer
	cycle = get_parent().get_node_or_null("DayNightCycle") as DayNightCycle
	blood_moon = get_parent().get_node_or_null("BloodMoonDirector") as BloodMoonDirector
	_ensure_buses()
	fade_duration = maxf(MAP.fade_seconds, 0.1)
	for _i in range(2):
		var audio := AudioStreamPlayer.new()
		audio.bus = "Music"
		audio.volume_db = -80.0
		add_child(audio)
		players.append(audio)
	_thread = Thread.new()
	_thread.start(_prewarm)


func _ensure_buses() -> void:
	for bus_name in ["Music", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var index := AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _exit_tree() -> void:
	_abort = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _prewarm() -> void:
	for category in MusicSynth.CATEGORIES:
		if _abort:
			return
		# Categories that already have a real track in the map never need a
		# synthesised fallback, so skip the work and keep boot fast.
		if MAP.track_for(category) != "":
			continue
		var bytes := MusicSynth.build_bytes(category)
		_mutex.lock()
		_ready_tracks.append([category, bytes])
		_mutex.unlock()
	_mutex.lock()
	_building = false
	_mutex.unlock()


func _drain_worker() -> void:
	if _ready_tracks.is_empty():
		return
	_mutex.lock()
	var batch := _ready_tracks.duplicate()
	_ready_tracks.clear()
	_mutex.unlock()
	for entry in batch:
		var category: String = entry[0]
		_streams[category] = MusicSynth.stream_from_bytes(entry[1])


func _process(delta: float) -> void:
	_drain_worker()
	_update_fade(delta)
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	if not world.is_generated or not player.spawned:
		return
	var state := world_state()
	var category := override_category if override_category != "" else category_for(state)
	if category == "":
		return
	if category != desired_category:
		desired_category = category
		switch_hold = 0.0
	else:
		switch_hold += minf(delta, 0.1)
	if desired_category == current_category:
		return
	# A brief crossing never reaches switch_hold, so biome borders cannot make
	# the music stutter back and forth.
	if switch_hold < maxf(MAP.switch_hold_seconds, 0.0):
		return
	_switch_to(desired_category, state)


## Everything music needs, read from the live world.
func world_state() -> Dictionary:
	var position := player.global_position
	var cell := Vector3i(floori(position.x), floori(position.y + 0.6), floori(position.z))
	var biome := world.get_biome_at(cell)
	var identity := GameplayBiome.identity_for(biome)
	var surface := world.get_surface_height(cell.x, cell.z)
	var depth := 0
	if surface > 0:
		depth = surface - cell.y
	var night := false
	if cycle != null:
		night = cycle.daylight < 0.30
	elif world.has_method("get_night_level"):
		night = world.get_night_level(cell) > 0.5
	return {
		"cell": cell,
		"biome": biome,
		"identity": identity,
		"identity_name": GameplayBiome.identity_name(identity),
		"surface": surface,
		"depth": depth,
		"night": night,
	}


func category_for(state: Dictionary) -> String:
	if _boss_present():
		last_reason = "boss alive"
		return "boss"
	if blood_moon != null and blood_moon.is_active and state.get("night", false):
		last_reason = "blood moon"
		return "blood_moon"
	var depth: int = int(state["depth"])
	var identity: int = int(state["identity"])
	if depth >= WorldLayers.UNDERWORLD_DEPTH:
		last_reason = "underworld depth %d" % depth
		return "underworld"
	if state["surface"] > 0 and int(state["cell"].y) > int(state["surface"]) + 70:
		last_reason = "above the cloud line"
		return "space"
	if depth >= WorldLayers.UNDERGROUND_DEPTH:
		last_reason = "deep underground %d" % depth
		match identity:
			GameplayBiome.Identity.JUNGLE:
				return "underground_jungle"
			GameplayBiome.Identity.CORRUPTION:
				return "underground_corruption"
			GameplayBiome.Identity.CRIMSON:
				return "underground_crimson"
			GameplayBiome.Identity.HALLOW:
				return "underground_hallow"
			_:
				return "cave"
	if depth >= 8:
		last_reason = "underground %d" % depth
		if identity == GameplayBiome.Identity.JUNGLE:
			return "underground_jungle"
		if identity == GameplayBiome.Identity.CORRUPTION:
			return "underground_corruption"
		if identity == GameplayBiome.Identity.CRIMSON:
			return "underground_crimson"
		if identity == GameplayBiome.Identity.HALLOW:
			return "underground_hallow"
		return "underground"
	last_reason = "%s %s" % [state.get("identity_name", "?"), "night" if state.get("night", false) else "day"]
	if identity == GameplayBiome.Identity.FOREST:
		return "surface_night" if state["night"] else "surface_day"
	match identity:
		GameplayBiome.Identity.DESERT:
			return "desert"
		GameplayBiome.Identity.JUNGLE:
			return "jungle"
		GameplayBiome.Identity.CORRUPTION:
			return "corruption"
		GameplayBiome.Identity.CRIMSON:
			return "crimson"
		GameplayBiome.Identity.HALLOW:
			return "hallow"
		GameplayBiome.Identity.SNOW:
			return "snow"
		GameplayBiome.Identity.OCEAN:
			return "ocean"
		GameplayBiome.Identity.MUSHROOM:
			return "mushroom"
	return "surface_night" if state["night"] else "surface_day"


func _boss_present() -> bool:
	for boss in get_tree().get_nodes_in_group("bosses"):
		if is_instance_valid(boss) and not boss.is_queued_for_deletion():
			return true
	return false


func _switch_to(category: String, state: Dictionary) -> void:
	var path := MAP.track_for(category)
	var stream: AudioStream = null
	var track_id := ""
	if path != "" and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
		track_id = path.get_file()
	if stream == null:
		stream = _streams.get(category) as AudioStream
		track_id = "procedural:%s" % category
	if stream != null and "loop" in stream and not bool(stream.get("loop")):
		# File tracks ship with looping off; the manager is the only thing that
		# plays them, so turning it on here keeps every biome track seamless.
		stream.set("loop", true)
	if stream == null:
		# The worker has not finished this category yet. Keep the current track
		# running rather than fading into silence, and retry next frame.
		if _pending_logged != category:
			_pending_logged = category
			print("[Music] pending %s (still synthesising; keeping %s)" % [category, current_category])
		return

	fade_from = active_index
	fade_to = 1 - active_index
	var incoming: AudioStreamPlayer = players[fade_to]
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	var outgoing: AudioStreamPlayer = players[fade_from]
	var was_playing := outgoing.playing
	fade_time = 0.0
	current_category = category
	current_track = track_id
	active_index = fade_to
	transitions += 1
	print("[Music] -> %s | track=%s | biome=%s depth=%d %s | fade=%.1fs%s" % [
		category, track_id, state.get("identity_name", "?"), int(state.get("depth", 0)),
		"night" if state.get("night", false) else (state.get("reason", "day")),
		fade_duration, "" if was_playing else " (first track)"])
	_pending_logged = ""


func _update_fade(delta: float) -> void:
	if fade_time < 0.0 or players.size() < 2:
		return
	fade_time += delta
	var k := clampf(fade_time / fade_duration, 0.0, 1.0)
	# Smoothstep keeps the perceptual loudness steady through the middle of the
	# crossfade; the two ramps sum to roughly constant amplitude.
	var curved := k * k * (3.0 - 2.0 * k)
	var out_db := linear_to_db(maxf(1.0 - curved, 0.00001)) + BASE_DB
	var in_db := linear_to_db(maxf(curved, 0.00001)) + BASE_DB
	players[fade_from].volume_db = out_db
	players[fade_to].volume_db = in_db
	if k >= 1.0:
		players[fade_from].stop()
		players[fade_from].volume_db = -80.0
		fade_time = -1.0


## Debug/test hook: force a category ("" returns to world-driven selection).
func force_category(category: String) -> void:
	override_category = category
	desired_category = ""
	switch_hold = 999.0
	if category != "" and category != current_category:
		var state := {"identity_name": "forced", "depth": 0, "night": false, "reason": "override"}
		_switch_to(category, state)


func tracks_ready() -> int:
	return _streams.size()


func is_prewarmed() -> bool:
	_mutex.lock()
	var done := not _building
	_mutex.unlock()
	return done
