extends Node
class_name AmbienceManager

## Environmental audio bed: forest birds, wind, water, cave rumble and lava,
## selected from the same world state the music uses. All loops are synthesised
## here (no harvested audio), played on the separate "Ambience" bus so the bed
## can be mixed independently of both music and shot effects.

const RATE := 11025
const BUS := "Ambience"
const BASE_DB := -20.0
const FADE := 2.0
const LOOP_SECONDS := 4.0

const CATEGORIES := ["forest", "wind", "water", "cave", "lava"]

var world: VoxelWorld
var player: VoxelPlayer
var cycle: DayNightCycle

var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var active_index := 0
var fade_from := 0
var fade_to := 1
var fade_time := -1.0
var current := ""
var desired := ""
var hold := 0.0
var transitions := 0


func _ready() -> void:
	world = get_parent().get_node_or_null("VoxelWorld") as VoxelWorld
	player = get_parent().get_node_or_null("Player") as VoxelPlayer
	cycle = get_parent().get_node_or_null("DayNightCycle") as DayNightCycle
	for category in CATEGORIES:
		streams[category] = _build(category)
	for _i in range(2):
		var audio := AudioStreamPlayer.new()
		audio.bus = BUS
		audio.volume_db = -80.0
		add_child(audio)
		players.append(audio)


func _process(delta: float) -> void:
	if fade_time >= 0.0:
		fade_time += delta
		var k := clampf(fade_time / FADE, 0.0, 1.0)
		var curved := k * k * (3.0 - 2.0 * k)
		players[fade_from].volume_db = linear_to_db(maxf(1.0 - curved, 0.00001)) + BASE_DB
		players[fade_to].volume_db = linear_to_db(maxf(curved, 0.00001)) + BASE_DB
		if k >= 1.0:
			players[fade_from].stop()
			fade_time = -1.0
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	if not world.is_generated or not player.spawned:
		return
	var next := category_for(_state())
	if next == "":
		return
	if next != desired:
		desired = next
		hold = 0.0
	else:
		hold += minf(delta, 0.1)
	if desired == current or hold < 1.2:
		return
	_switch(desired)


func _state() -> Dictionary:
	var position := player.global_position
	var cell := Vector3i(floori(position.x), floori(position.y + 0.6), floori(position.z))
	var identity := GameplayBiome.identity_for(world.get_biome_at(cell))
	var surface := world.get_surface_height(cell.x, cell.z)
	return {"identity": identity, "depth": (surface - cell.y) if surface > 0 else 0}


func category_for(state: Dictionary) -> String:
	if int(state["depth"]) >= WorldLayers.UNDERWORLD_DEPTH:
		return "lava"
	if int(state["depth"]) >= 8:
		return "cave"
	match int(state["identity"]):
		GameplayBiome.Identity.OCEAN:
			return "water"
		GameplayBiome.Identity.SNOW:
			return "wind"
	return "forest"


func _switch(category: String) -> void:
	var stream: AudioStream = streams.get(category)
	if stream == null:
		return
	var state := _state()
	fade_from = active_index
	fade_to = 1 - active_index
	var incoming: AudioStreamPlayer = players[fade_to]
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	fade_time = 0.0
	active_index = fade_to
	current = category
	transitions += 1
	print("[Ambience] -> %s | depth=%d | %.0fs crossfade" % [category, int(state.get("depth", 0)), FADE])


func _loop(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in range(data.size()):
		var sample := int(clampf(data[i], -1.0, 1.0) * 32000.0)
		bytes[i * 2] = sample & 0xFF
		bytes[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = data.size()
	stream.data = bytes
	return stream


func _build(category: String) -> AudioStreamWAV:
	var total := int(LOOP_SECONDS * float(RATE))
	var samples := PackedFloat32Array()
	samples.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("terraria3d:ambience:" + category)
	var low := 0.0
	var brown := 0.0
	for i in range(total):
		var t := float(i) / float(RATE)
		var white := rng.randf() * 2.0 - 1.0
		var value := 0.0
		match category:
			"wind":
				low = lerpf(low, white, 0.06)
				var gust := 0.55 + 0.45 * sin(TAU * t / LOOP_SECONDS + sin(TAU * 2.0 * t / LOOP_SECONDS))
				value = low * 2.2 * gust
			"water":
				low = lerpf(low, white, 0.12)
				brown = lerpf(brown, low, 0.05)
				var swell := 0.6 + 0.4 * sin(TAU * t / LOOP_SECONDS)
				value = low * 0.5 * swell + brown * 3.0
			"cave":
				brown = lerpf(brown, white, 0.02)
				value = sin(TAU * 42.0 * t) * 0.18 + brown * 1.6
				# Occasional drips: short high pings at seeded moments.
				var drip_phase := fmod(t, 1.35)
				if drip_phase < 0.06:
					value += sin(TAU * 1400.0 * drip_phase) * exp(-drip_phase * 70.0) * 0.30
			"lava":
				brown = lerpf(brown, white, 0.035)
				low = lerpf(low, white, 0.25)
				var crackle := 0.0
				if rng.randf() < 0.0016:
					crackle = white * 0.9
				value = sin(TAU * 58.0 * t) * 0.14 + brown * 1.3 + crackle
			_:
				# Forest: soft air bed plus short bird chirps.
				low = lerpf(low, white, 0.10)
				value = low * 0.35
				var chirp := fmod(t * 0.37 + 0.11, 1.0)
				if chirp < 0.045:
					var sweep := 2100.0 + 1400.0 * sin(TAU * 9.0 * chirp)
					value += sin(TAU * sweep * chirp) * exp(-chirp * 60.0) * 0.18
		samples[i] = value * 0.5
	# Fade the edges so the loop seam is silent.
	var edge := int(float(RATE) * 0.1)
	for i in range(total):
		if i < edge:
			samples[i] *= float(i) / float(edge)
		elif i > total - edge:
			samples[i] *= float(total - i) / float(edge)
	return _loop(samples)
