extends Node
class_name AudioDirector

# Procedural, asset-free threat audio. Cues are generated once at startup as
# short AudioStreamWAV buffers and routed through the World bus, so terrain can
# muffle them with the existing lowpass plan. Loudness tracks Night and actual
# enemy proximity instead of playing a constant horror loop.

const MIX_RATE := 11025

var world: VoxelWorld
var player: VoxelPlayer
var drone: AudioStreamPlayer
var hum: AudioStreamPlayer
var skitters: Array[AudioStreamPlayer] = []
var skitter_index := 0
var skitter_cooldown := 0.0
var enemy_scan_cooldown := 0.0
var cached_nightlings: Array = []
var cached_lamp_eaters: Array = []


func _ready() -> void:
	_ensure_buses()
	world = get_parent().get_node("VoxelWorld") as VoxelWorld
	player = get_parent().get_node("Player") as VoxelPlayer

	drone = _make_player(_make_drone(), true)
	hum = _make_player(_make_hum(), true)
	for _i in range(3):
		skitters.append(_make_player(_make_skitter(), false))


func _ensure_buses() -> void:
	if AudioServer.get_bus_index("World") == -1:
		var index := AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, "World")
		AudioServer.set_bus_send(index, "Master")
	if AudioServer.get_bus_index("UI") == -1:
		var index := AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, "UI")
		AudioServer.set_bus_send(index, "Master")


func _make_player(stream: AudioStreamWAV, looping: bool) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.bus = "World"
	audio.volume_db = -60.0
	add_child(audio)
	if looping:
		audio.play()
	return audio


func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	if not world.is_generated or not player.spawned:
		return
	var cell := Vector3i(floori(player.position.x), floori(player.position.y + 0.5), floori(player.position.z))
	var night := world.get_night_level(cell)
	var target := 0.02 + 0.30 * night
	if player.dead:
		target += 0.10
	drone.volume_db = linear_to_db(clampf(target, 0.0001, 1.0))

	enemy_scan_cooldown -= delta
	if enemy_scan_cooldown <= 0.0:
		enemy_scan_cooldown = 0.4
		cached_nightlings = get_tree().get_nodes_in_group("enemies").filter(func(node): return node is Nightling and is_instance_valid(node))
		cached_lamp_eaters = get_tree().get_nodes_in_group("enemies").filter(func(node): return node is LampEater and is_instance_valid(node))

	skitter_cooldown -= delta
	var nearest_skitter := INF
	for enemy in cached_nightlings:
		if not is_instance_valid(enemy):
			continue
		var d := player.position.distance_to(enemy.global_position)
		if d < nearest_skitter:
			nearest_skitter = d
	if nearest_skitter < 14.0 and skitter_cooldown <= 0.0:
		skitter_cooldown = randf_range(1.6, 3.4)
		var audio := skitters[skitter_index]
		skitter_index = (skitter_index + 1) % skitters.size()
		audio.volume_db = linear_to_db(clampf(0.22 * (1.0 - nearest_skitter / 14.0), 0.0001, 1.0))
		audio.play()

	var nearest_hum := INF
	for enemy in cached_lamp_eaters:
		if not is_instance_valid(enemy):
			continue
		var d := player.position.distance_to(enemy.global_position)
		if d < nearest_hum:
			nearest_hum = d
	if nearest_hum < 18.0:
		hum.volume_db = linear_to_db(clampf(0.16 * (1.0 - nearest_hum / 18.0), 0.0001, 1.0))
	else:
		hum.volume_db = -60.0


# --- Procedural waveform generation -----------------------------------------

func _make_drone() -> AudioStreamWAV:
	var length := MIX_RATE * 2
	var samples := PackedFloat32Array()
	samples.resize(length)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8081
	for i in range(length):
		var t := float(i) / float(MIX_RATE)
		var swell := 0.65 + 0.35 * sin(TAU * 0.25 * t)
		var value := sin(TAU * 47.0 * t) * 0.55 + sin(TAU * 71.0 * t) * 0.28
		value += (rng.randf() * 2.0 - 1.0) * 0.07
		samples[i] = value * swell * 0.55
	return _to_wav(samples, AudioStreamWAV.LOOP_FORWARD)


func _make_hum() -> AudioStreamWAV:
	var length := int(MIX_RATE * 1.5)
	var samples := PackedFloat32Array()
	samples.resize(length)
	for i in range(length):
		var t := float(i) / float(MIX_RATE)
		var tremolo := 0.7 + 0.3 * sin(TAU * 5.0 * t)
		samples[i] = (sin(TAU * 119.0 * t) * 0.6 + sin(TAU * 123.0 * t) * 0.4) * tremolo * 0.5
	return _to_wav(samples, AudioStreamWAV.LOOP_FORWARD)


func _make_skitter() -> AudioStreamWAV:
	var length := int(MIX_RATE * 0.22)
	var samples := PackedFloat32Array()
	samples.resize(length)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	var previous := 0.0
	for i in range(length):
		var t := float(i) / float(MIX_RATE)
		var noise := rng.randf() * 2.0 - 1.0
		previous = lerpf(previous, noise, 0.35)
		var decay := exp(-t * 16.0)
		var chatter := sin(TAU * (900.0 + 500.0 * t) * t)
		samples[i] = (previous * 0.7 + chatter * 0.3) * decay * 0.7
	return _to_wav(samples, AudioStreamWAV.LOOP_DISABLED)


func _to_wav(samples: PackedFloat32Array, loop_mode: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var value := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = loop_mode
	stream.data = data
	return stream
