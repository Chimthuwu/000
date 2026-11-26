extends RefCounted
class_name Sfx

## Short, procedural one-shot sound effects for player actions (chop, mine,
## fell, place, pick up), generated the same asset-free way AudioDirector and
## MusicSynth build their audio, so no external sound files are needed.
## Each buffer is synthesised once and cached; `play()` drops a transient
## AudioStreamPlayer3D under the given parent and frees itself when done.

const MIX_RATE := 11025

static var _cache: Dictionary = {}


static func play(parent: Node, at: Vector3, name: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var stream := _get(name)
	if stream == null:
		return
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.bus = "World"
	audio.volume_db = volume_db
	audio.pitch_scale = pitch
	audio.max_distance = 24.0
	parent.add_child(audio)
	audio.global_position = at
	audio.play()
	audio.finished.connect(audio.queue_free)


static func chop(parent: Node, at: Vector3) -> void:
	play(parent, at, &"chop", -4.0, randf_range(0.92, 1.1))


static func mine(parent: Node, at: Vector3) -> void:
	play(parent, at, &"mine", -4.0, randf_range(0.92, 1.1))


static func fell(parent: Node, at: Vector3) -> void:
	play(parent, at, &"fell", -2.0)


static func place(parent: Node, at: Vector3) -> void:
	play(parent, at, &"place", -6.0, randf_range(0.95, 1.05))


static func pickup(parent: Node, at: Vector3) -> void:
	play(parent, at, &"pickup", -8.0, randf_range(0.97, 1.08))


static func swing(parent: Node, at: Vector3) -> void:
	play(parent, at, &"swing", -10.0, randf_range(0.95, 1.1))


# --- Synthesis ---------------------------------------------------------------

static func _get(name: StringName) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var stream: AudioStreamWAV = null
	match name:
		&"chop":
			stream = _knock(0.11, 420.0, 180.0, 0.55)
		&"mine":
			stream = _knock(0.08, 820.0, 260.0, 0.40)
		&"fell":
			stream = _crash()
		&"place":
			stream = _knock(0.07, 260.0, 120.0, 0.30)
		&"pickup":
			stream = _chirp()
		&"swing":
			stream = _whoosh()
	_cache[name] = stream
	return stream


## A short pitched thud with a noisy transient: the shared shape behind chop,
## mine and place, parameterised by length, tone frequency and noise amount.
static func _knock(length: float, tone_hz: float, noise_hz: float, noise_mix: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(tone_hz * 97.0 + length * 1000.0)
	var previous := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var decay := exp(-t / (length * 0.32))
		var tone := sin(TAU * tone_hz * t) * (1.0 - noise_mix)
		var noise := rng.randf() * 2.0 - 1.0
		previous = lerpf(previous, noise, 0.5)
		tone += previous * noise_mix
		samples[i] = clampf(tone * decay, -1.0, 1.0) * 0.9
	return _to_wav(samples)


## A tree hitting the ground: a falling-pitch rumble plus a noisy crack.
static func _crash() -> AudioStreamWAV:
	var length := 0.55
	var count := int(MIX_RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var previous := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var progress := t / length
		var rumble_hz := lerpf(150.0, 55.0, progress)
		var decay := exp(-t * 3.2)
		var crack_decay := exp(-t * 26.0)
		var noise := rng.randf() * 2.0 - 1.0
		previous = lerpf(previous, noise, 0.4)
		var value := sin(TAU * rumble_hz * t) * decay * 0.7
		value += previous * crack_decay * 0.9
		value += previous * decay * 0.25
		samples[i] = clampf(value, -1.0, 1.0) * 0.95
	return _to_wav(samples)


## A bright, quick upward chirp: picking something up off the ground.
static func _chirp() -> AudioStreamWAV:
	var length := 0.14
	var count := int(MIX_RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var progress := t / length
		var hz := lerpf(540.0, 1080.0, progress)
		var decay := exp(-t / (length * 0.45))
		samples[i] = sin(TAU * hz * t) * decay * 0.6
	return _to_wav(samples)


## A quick breathy noise sweep for a weapon swing that doesn't land.
static func _whoosh() -> AudioStreamWAV:
	var length := 0.16
	var count := int(MIX_RATE * length)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7373
	var previous := 0.0
	for i in range(count):
		var t := float(i) / float(MIX_RATE)
		var progress := t / length
		var envelope := sin(PI * progress) * (1.0 - progress * 0.3)
		var noise := rng.randf() * 2.0 - 1.0
		previous = lerpf(previous, noise, 0.6)
		samples[i] = previous * envelope * 0.5
	return _to_wav(samples)


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
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
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
