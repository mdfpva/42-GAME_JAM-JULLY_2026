extends Node

# Procedurally generated sound effects: short PCM samples are synthesized once
# at startup into AudioStreamWAV resources, then played through a small pool
# of AudioStreamPlayers so overlapping sounds don't cut each other off.

const SAMPLE_RATE := 22050
const POOL_SIZE := 8

var sounds: Dictionary = {}
var pool: Array[AudioStreamPlayer] = []
var next_player := 0

func _ready() -> void:
	sounds["jump"] = _build(_gen_sweep(280.0, 560.0, 0.15, 0.35, "sine"))
	sounds["land"] = _build(_gen_noise(0.06, 0.2))
	sounds["coin"] = _build(_gen_tone_seq([900.0, 1350.0], 0.06, 0.35))
	sounds["shoot"] = _build(_gen_sweep(900.0, 300.0, 0.08, 0.25, "square"))
	sounds["kill"] = _build(_gen_sweep(520.0, 90.0, 0.22, 0.4, "square"))
	sounds["death"] = _build(_gen_sweep(400.0, 45.0, 0.7, 0.5, "saw"))
	sounds["buff"] = _build(_gen_tone_seq([440.0, 554.0, 659.0, 880.0], 0.08, 0.4))
	sounds["mission"] = _build(_gen_tone_seq([660.0, 880.0, 990.0], 0.1, 0.4))
	sounds["crumble"] = _build(_gen_noise(0.25, 0.3))
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)

func play(sound_name: String, volume_db := -6.0) -> void:
	if not sounds.has(sound_name):
		return
	var p := pool[next_player]
	next_player = (next_player + 1) % POOL_SIZE
	p.stream = sounds[sound_name]
	p.volume_db = volume_db
	p.play()

func _build(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav

func _gen_sweep(f0: float, f1: float, dur: float, amp: float, shape: String) -> PackedFloat32Array:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / SAMPLE_RATE
		var s: float
		match shape:
			"square":
				s = 1.0 if fmod(phase, TAU) < PI else -1.0
			"saw":
				s = 2.0 * fmod(phase, TAU) / TAU - 1.0
			_:
				s = sin(phase)
		out[i] = s * amp * (1.0 - t)
	return out

func _gen_tone_seq(freqs: Array, note_dur: float, amp: float) -> PackedFloat32Array:
	var n_note := int(note_dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n_note * freqs.size())
	var idx := 0
	for f in freqs:
		var phase := 0.0
		for i in n_note:
			var t := float(i) / n_note
			phase += TAU * f / SAMPLE_RATE
			out[idx] = sin(phase) * amp * (1.0 - t * 0.7)
			idx += 1
	return out

func _gen_noise(dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / n
		# Cheap lowpass so the burst sounds like rubble, not hiss.
		prev = prev * 0.7 + (randf() * 2.0 - 1.0) * 0.3
		out[i] = prev * amp * (1.0 - t)
	return out
