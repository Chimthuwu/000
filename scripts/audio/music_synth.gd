extends RefCounted
class_name MusicSynth

## Original, generated music. Nothing here is a copy of the Terraria
## soundtrack: each category is a short chiptune loop synthesised from a
## different scale, tempo, waveform and arrangement, so every environment has
## its own recognisable mood while remaining license-clean placeholder audio.
##
## Building happens on a worker thread (`build_bytes` touches no engine
## resources), and `stream_from_bytes` turns the result into an AudioStreamWAV
## on the main thread.

const RATE := 11025

## Categories resolved by MusicManager. Every one has a distinct profile below.
const CATEGORIES := [
	"surface_day", "surface_night", "underground", "cave", "jungle",
	"underground_jungle", "desert", "snow", "ocean", "mushroom", "hallow",
	"corruption", "crimson", "underground_corruption", "underground_crimson",
	"underground_hallow", "underworld", "space", "boss", "blood_moon",
]

# Waveforms for _osc(): 0 sine, 1 square, 2 triangle, 3 saw.
const SINE := 0
const SQUARE := 1
const TRIANGLE := 2
const SAW := 3

## Natural minor, major, pentatonic, phrygian and harmonic-minor spellings.
const MINOR := [0, 2, 3, 5, 7, 8, 10]
const MAJOR := [0, 2, 4, 5, 7, 9, 11]
const PENTATONIC := [0, 2, 4, 7, 9]
const PHRYGIAN := [0, 1, 3, 5, 7, 8, 10]
const HARMONIC := [0, 2, 3, 5, 7, 8, 11]


static func profile_for(category: String) -> Dictionary:
	# root is a MIDI note; progression is one chord root per bar, as scale
	# degrees; gains are mixed per voice.
	match category:
		"surface_night":
			return _profile(66.0, 60, MINOR, [0, 5, 3, 4], SINE, 0.34, 0.45, 0.16, 0.14, 0.03)
		"underground":
			return _profile(58.0, 45, MINOR, [0, 0, 5, 3], TRIANGLE, 0.26, 0.55, 0.13, 0.20, 0.05)
		"cave":
			return _profile(50.0, 38, MINOR, [0, 3, 0, 4], SINE, 0.22, 0.60, 0.10, 0.24, 0.02)
		"jungle":
			return _profile(112.0, 62, PENTATONIC, [0, 0, 3, 2], SINE, 0.36, 0.40, 0.20, 0.12, 0.28)
		"underground_jungle":
			return _profile(96.0, 50, PENTATONIC, [0, 2, 1, 3], TRIANGLE, 0.30, 0.45, 0.16, 0.16, 0.20)
		"desert":
			return _profile(96.0, 57, PHRYGIAN, [0, 1, 0, 4], SQUARE, 0.30, 0.38, 0.18, 0.14, 0.16)
		"snow":
			return _profile(84.0, 67, MAJOR, [0, 4, 5, 3], SINE, 0.30, 0.50, 0.12, 0.20, 0.02)
		"ocean":
			return _profile(62.0, 55, MAJOR, [0, 5, 3, 4], SINE, 0.26, 0.45, 0.18, 0.22, 0.00)
		"mushroom":
			return _profile(104.0, 64, PENTATONIC, [0, 3, 2, 4], TRIANGLE, 0.34, 0.34, 0.20, 0.12, 0.10)
		"hallow":
			return _profile(124.0, 69, MAJOR, [0, 4, 5, 3], SQUARE, 0.32, 0.36, 0.16, 0.14, 0.22)
		"corruption":
			return _profile(88.0, 52, MINOR, [0, 4, 1, 4], SAW, 0.24, 0.42, 0.18, 0.20, 0.12)
		"crimson":
			return _profile(92.0, 54, HARMONIC, [0, 3, 4, 5], SAW, 0.28, 0.46, 0.20, 0.16, 0.18)
		"underground_corruption":
			return _profile(76.0, 45, MINOR, [0, 4, 1, 3], SAW, 0.22, 0.50, 0.16, 0.26, 0.10)
		"underground_crimson":
			return _profile(84.0, 48, HARMONIC, [0, 3, 4, 1], SAW, 0.24, 0.48, 0.18, 0.24, 0.14)
		"underground_hallow":
			return _profile(104.0, 57, MAJOR, [0, 5, 4, 2], SINE, 0.26, 0.48, 0.14, 0.24, 0.06)
		"underworld":
			return _profile(136.0, 40, MINOR, [0, 0, 1, 0], SQUARE, 0.30, 0.55, 0.24, 0.10, 0.30)
		"space":
			return _profile(54.0, 72, PENTATONIC, [0, 2, 3, 1], SINE, 0.20, 0.35, 0.10, 0.30, 0.00)
		"boss":
			return _profile(150.0, 46, HARMONIC, [0, 1, 0, 4], SQUARE, 0.34, 0.50, 0.26, 0.14, 0.40)
		"blood_moon":
			return _profile(138.0, 43, HARMONIC, [0, 4, 1, 5], SAW, 0.30, 0.52, 0.28, 0.12, 0.42)
		_:
			return _profile(100.0, 60, MAJOR, [0, 5, 3, 4], SQUARE, 0.32, 0.40, 0.18, 0.16, 0.12)


static func _profile(bpm: float, root: int, scale: Array, progression: Array, lead_wave: int,
		melody_gain: float, lead_gain: float, bass_gain: float, pad_gain: float, perc_gain: float) -> Dictionary:
	return {
		"bpm": bpm,
		"bars": 2,
		"root": root,
		"scale": scale,
		"progression": progression,
		"lead_wave": lead_wave,
		"melody": melody_gain,
		"lead": lead_gain,
		"bass": bass_gain,
		"pad": pad_gain,
		"perc": perc_gain,
	}


static func _midi_freq(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)


static var _sine_table: PackedFloat32Array = PackedFloat32Array()
static var _tri_table: PackedFloat32Array = PackedFloat32Array()
static var _exp_table: PackedFloat32Array = PackedFloat32Array()
const TABLE_BITS := 11
const TABLE_SIZE := 1 << TABLE_BITS
const TABLE_MASK := TABLE_SIZE - 1


## Wave and envelope tables. A per-sample sin()/exp() call dominated the
## synthesis cost (~21 s for the whole bank); tables bring that down by an
## order of magnitude and cost 12 kB of memory.
static func _ensure_tables() -> void:
	if not _sine_table.is_empty():
		return
	_sine_table.resize(TABLE_SIZE)
	_tri_table.resize(TABLE_SIZE)
	for i in range(TABLE_SIZE):
		var phase := float(i) / float(TABLE_SIZE)
		_sine_table[i] = sin(TAU * phase)
		_tri_table[i] = 4.0 * absf(phase - 0.5) - 1.0
	_exp_table.resize(1024)
	for i in range(1024):
		_exp_table[i] = exp(-float(i) / 64.0)


static func _osc(wave: int, phase: float) -> float:
	var index := int(phase * float(TABLE_SIZE)) & TABLE_MASK
	match wave:
		SQUARE:
			return 1.0 if _sine_table[index] >= 0.0 else -1.0
		TRIANGLE:
			return _tri_table[index]
		SAW:
			return 2.0 * (float(index) / float(TABLE_SIZE)) - 1.0
		_:
			return _sine_table[index]


## exp(-x) for x in [0, 16) through a 1024-entry table.
static func _fast_exp(x: float) -> float:
	var index := int(x * 64.0)
	if index < 0:
		return 1.0
	if index >= 1024:
		return 0.0
	return _exp_table[index]


static func _note_env(local: float, length: float, attack: float, decay: float) -> float:
	var a := minf(1.0, local / maxf(attack, 0.0001))
	var release := clampf((length - local) / 0.03, 0.0, 1.0)
	return a * _fast_exp(decay * local) * release


## Pure synthesis, safe on a worker thread. Returns 16-bit mono PCM.
static func build_bytes(category: String) -> PackedByteArray:
	_ensure_tables()
	var profile := profile_for(category)
	var bpm: float = float(profile["bpm"])
	var bars: int = int(profile["bars"])
	var beat_len := 60.0 / bpm
	var bar_len := beat_len * 4.0
	var length := bar_len * float(bars)
	var total := int(length * float(RATE))
	var scale: Array = profile["scale"]
	var progression: Array = profile["progression"]
	var root: int = int(profile["root"])
	var lead_wave: int = int(profile["lead_wave"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("terraria3d:music:" + category)
	var melody: Array = []
	for _i in range(bars * 8):
		melody.append(-1 if rng.randf() < 0.28 else rng.randi_range(0, scale.size() + 2))
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in range(total):
		var t := float(i) / float(RATE)
		var bar_index := int(t / bar_len)
		var bar := bar_index % progression.size()
		var in_bar := t - float(bar_index) * bar_len
		var chord: int = int(progression[bar])
		var value := 0.0
		var bass_gain: float = float(profile["bass"])
		var lead_gain: float = float(profile["lead"])
		var melody_gain: float = float(profile["melody"])
		var pad_gain: float = float(profile["pad"])
		var perc_gain: float = float(profile["perc"])

		# Bass: chord root an octave and a half down, one note per beat.
		var beat_index := int(in_bar / beat_len)
		var bass_local := in_bar - float(beat_index) * beat_len
		var bass_note := root - 24 + int(scale[chord % scale.size()])
		value += _osc(TRIANGLE, _midi_freq(bass_note) * bass_local) * _note_env(bass_local, beat_len, 0.008, 3.0) * bass_gain

		# Arpeggio: chord tones on eighth notes.
		var eighth_len := beat_len * 0.5
		var eighth := int(in_bar / eighth_len)
		var arp_local := in_bar - float(eighth) * eighth_len
		var arp_offsets := [0, 2, 4, 2]
		var arp_degree := int(scale[(chord + int(arp_offsets[eighth % 4])) % scale.size()]) + 12
		value += _osc(lead_wave, _midi_freq(root + arp_degree) * arp_local) * _note_env(arp_local, eighth_len, 0.004, 10.0) * lead_gain

		# Melody: a seeded line one octave above the arpeggio.
		var mel_index := (eighth + 2) % melody.size()
		var mel: int = int(melody[mel_index])
		if mel >= 0:
			var mel_note := root + 12 + int(scale[mel % scale.size()]) + 12 * int(mel / scale.size())
			value += _osc(SINE, _midi_freq(mel_note) * arp_local) * _note_env(arp_local, eighth_len, 0.006, 8.0) * melody_gain

		# Pad: slow triad swell so the loop has body between notes.
		if pad_gain > 0.001:
			var swell := 0.55 + 0.45 * sin(TAU * 0.08 * t)
			for k in range(3):
				var pad_note := root + int(scale[(chord + k * 2) % scale.size()])
				value += _osc(SINE, _midi_freq(pad_note) * t) * swell * pad_gain / 3.0

		# Percussion: kick on beats 1 and 3, noise hat on the off-beats.
		if perc_gain > 0.001:
			if beat_index % 4 == 0 or beat_index % 4 == 2:
				var kick_local := bass_local
				if kick_local < 0.14:
					var sweep := 110.0 - 70.0 * (kick_local / 0.14)
					value += _osc(SINE, sweep * kick_local) * _fast_exp(kick_local * 26.0) * perc_gain
			var hat_local := in_bar - float(int(in_bar / eighth_len)) * eighth_len
			if hat_local < 0.05:
				var noise := rng.randf() * 2.0 - 1.0
				value += noise * _fast_exp(hat_local * 110.0) * perc_gain * 0.35

		# Soft clip keeps the mix glued and avoids square-wave harshness.
		var shaped := value / (1.0 + absf(value) * 0.55)
		# Fade the loop edges so a repeat does not click.
		var edge := int(float(RATE) * 0.015)
		if i < edge:
			shaped *= float(i) / float(edge)
		elif i > total - edge:
			shaped *= float(total - i) / float(edge)
		var sample := int(clampf(shaped * 1.35, -1.0, 1.0) * 32000.0)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	return data


static func stream_from_bytes(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = data.size() / 2
	stream.data = data
	return stream
