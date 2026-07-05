extends Node

# Procedural technopop cover of "Eternal Chase" (bedbyeleven), used with the
# band's permission. Rebuilt from an automated analysis of the recording:
# 122 BPM, E minor; verses alternate Em/Bm, a G/A lift, and a D<->Em chorus
# carrying the E-E-D-F# / F#-A-F#-G lead hook. Synthesized sample-by-sample
# (pad + bass + arp + lead + drums), no audio assets needed.

const BPM := 122.0
const MIX_RATE := 44100.0

const STEP_DUR := 60.0 / BPM / 4.0   # 16th note
const BEAT_DUR := STEP_DUR * 4.0     # quarter note
const EIGHTH_DUR := STEP_DUR * 2.0
const BAR_DUR := STEP_DUR * 16.0
const SECTION_BARS := 4

# Section types: 0 = verse, 1 = lift, 2 = chorus. Loop: A A B C C (20 bars).
const SECTION_ORDER := [0, 0, 1, 2, 2]
const LOOP_DUR := BAR_DUR * SECTION_BARS * 5.0

# Triads per section (4 bars each).
const EM := [164.81, 196.00, 246.94]
const BM := [123.47, 146.83, 185.00]
const GM := [196.00, 246.94, 293.66]
const AM_MAJ := [220.00, 277.18, 329.63] # A major (dorian lift heard in the track)
const DM_MAJ := [146.83, 185.00, 220.00]

const SEC_CHORDS := [
	[EM, EM, BM, BM],           # verse: | Em | Em | Bm | Bm |
	[GM, GM, AM_MAJ, AM_MAJ],   # lift:  | G  | G  | A  | A  |
	[DM_MAJ, DM_MAJ, EM, EM],   # chorus:| D  | D  | Em | Em |
]
const SEC_BASS := [
	[82.41, 82.41, 123.47, 123.47],
	[98.00, 98.00, 110.00, 110.00],
	[73.42, 73.42, 82.41, 82.41],
]

# Lead melody per section: 32 eighth-note slots (4 bars x 8), 0.0 = rest.
# Contours transcribed from the recording's dominant line.
const SEC_MELODY := [
	[ # verse: E-G-E answer phrases, B-D-F# over Bm
		329.63, 0.0, 392.00, 329.63, 0.0, 329.63, 0.0, 0.0,
		329.63, 0.0, 392.00, 440.00, 0.0, 392.00, 329.63, 0.0,
		246.94, 0.0, 293.66, 369.99, 0.0, 369.99, 329.63, 293.66,
		246.94, 293.66, 246.94, 0.0, 0.0, 0.0, 0.0, 0.0,
	],
	[ # lift: climbing G-B-C then A-C#-E into the chorus
		392.00, 0.0, 493.88, 392.00, 0.0, 392.00, 0.0, 0.0,
		392.00, 0.0, 493.88, 523.25, 0.0, 493.88, 392.00, 0.0,
		440.00, 0.0, 554.37, 659.26, 0.0, 659.26, 554.37, 440.00,
		440.00, 493.88, 554.37, 659.26, 0.0, 0.0, 0.0, 0.0,
	],
	[ # chorus hook: E E D F# | F# A F# | G G F# | resolve to E
		329.63, 329.63, 293.66, 369.99, 369.99, 0.0, 440.00, 369.99,
		440.00, 440.00, 369.99, 392.00, 392.00, 369.99, 0.0, 0.0,
		329.63, 0.0, 329.63, 392.00, 0.0, 369.99, 329.63, 0.0,
		329.63, 0.0, 246.94, 293.66, 329.63, 0.0, 0.0, 0.0,
	],
]

const SEC_INTENSITY := [0.7, 0.85, 1.0]
const ARP_PATTERN := [0, 2, 1, 2]

var _playback: AudioStreamGeneratorPlayback
var _t := 0.0
var _sample_delta := 0.0
var _game_intensity := 0.6
var _target_intensity := 0.6

func _ready() -> void:
	# Keep playing while the game is paused (pause menu keeps its soundtrack).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sample_delta = 1.0 / MIX_RATE

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.3

	var player := AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = -8.0
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.play()
	_playback = player.get_stream_playback()

# Driven by the game (combo, buffs, difficulty): scales the energy layers
# on top of each section's own baseline.
func set_intensity(level: float) -> void:
	_target_intensity = clampf(level, 0.0, 1.0)

func _process(delta: float) -> void:
	if _playback == null:
		return
	_game_intensity = lerpf(_game_intensity, _target_intensity, minf(delta * 2.0, 1.0))
	var frames := _playback.get_frames_available()
	for _i in range(frames):
		var s := _sample(_t)
		_playback.push_frame(Vector2(s, s))
		_t += _sample_delta
		if _t >= LOOP_DUR:
			_t -= LOOP_DUR

func _sample(t: float) -> float:
	var global_bar: int = int(floor(t / BAR_DUR)) % (SECTION_BARS * SECTION_ORDER.size())
	@warning_ignore("integer_division")
	var sec: int = SECTION_ORDER[global_bar / SECTION_BARS]
	var bar_in_sec: int = global_bar % SECTION_BARS
	var t_in_bar := fmod(t, BAR_DUR)
	var step_index: int = int(floor(t_in_bar / STEP_DUR)) % 16
	var t_in_step := fmod(t_in_bar, STEP_DUR)
	var t_in_beat := fmod(t_in_bar, BEAT_DUR)
	var eighth_index: int = int(floor(t_in_bar / EIGHTH_DUR)) % 8
	var t_in_eighth := fmod(t_in_bar, EIGHTH_DUR)

	var chord: Array = SEC_CHORDS[sec][bar_in_sec]
	var bass_freq: float = SEC_BASS[sec][bar_in_sec]
	var intensity: float = SEC_INTENSITY[sec] * lerpf(0.6, 1.1, _game_intensity)

	var out := 0.0
	out += _pad(chord, t_in_bar) * 0.10
	out += _bass(bass_freq, t_in_beat) * 0.22 * intensity
	out += _arp(chord, step_index, t_in_step) * 0.13 * intensity

	var mel_freq: float = SEC_MELODY[sec][bar_in_sec * 8 + eighth_index]
	if mel_freq > 0.0:
		out += _lead(mel_freq, t_in_eighth, t) * (0.16 if sec == 2 else 0.12)

	if step_index % 4 == 0:
		out += _kick(t_in_beat) * 0.35
	if step_index % 4 == 2 or (_game_intensity > 0.8 and step_index % 2 == 1):
		out += _hihat(t_in_step) * (0.12 if sec == 2 else 0.08)
	if sec >= 1 and (step_index == 4 or step_index == 12):
		out += _clap(t_in_step) * 0.18

	return clamp(tanh(out * 1.4), -1.0, 1.0)

# Sustained triad (the "harmonic" layer) with a short fade at bar edges to avoid clicks.
func _pad(chord: Array, t_in_bar: float) -> float:
	var fade := 0.03 * BAR_DUR
	var env := 1.0
	if t_in_bar < fade:
		env = t_in_bar / fade
	elif t_in_bar > BAR_DUR - fade:
		env = (BAR_DUR - t_in_bar) / fade
	var v := 0.0
	for freq in chord:
		v += sin(TAU * freq * t_in_bar)
	return v / chord.size() * env

# Plucky square-wave bass retriggered every beat.
func _bass(freq: float, t_in_beat: float) -> float:
	var env: float = exp(-t_in_beat * 7.0)
	return sign(sin(TAU * freq * t_in_beat)) * env

# Bright staccato square-wave arpeggio, one octave above the pad.
func _arp(chord: Array, step_index: int, t_in_step: float) -> float:
	var idx: int = ARP_PATTERN[step_index % ARP_PATTERN.size()]
	var freq: float = chord[idx] * 2.0
	var env: float = exp(-t_in_step * 18.0)
	return sign(sin(TAU * freq * t_in_step)) * env

# Chiptune lead voice: pulse wave with light vibrato, one note per eighth.
func _lead(freq: float, t_in_eighth: float, t_abs: float) -> float:
	var attack: float = minf(t_in_eighth / 0.01, 1.0)
	var env: float = attack * exp(-t_in_eighth * 3.0)
	var vib := 1.0 + 0.004 * sin(TAU * 5.5 * t_abs)
	return sign(sin(TAU * freq * vib * t_in_eighth + 0.3)) * env

# Pitch-swept kick on every beat for the techno pulse.
func _kick(t_in_beat: float) -> float:
	var dur := 0.12
	if t_in_beat > dur:
		return 0.0
	var freq: float = lerp(150.0, 45.0, t_in_beat / dur)
	var env: float = exp(-t_in_beat * 28.0)
	return sin(TAU * freq * t_in_beat) * env

# Short noise burst on the off-beats.
func _hihat(t_in_step: float) -> float:
	var dur := 0.045
	if t_in_step > dur:
		return 0.0
	var env: float = exp(-t_in_step * 90.0)
	return (randf() * 2.0 - 1.0) * env

# Wider noise burst on beats 2 and 4 (lift/chorus only).
func _clap(t_in_step: float) -> float:
	var dur := 0.09
	if t_in_step > dur:
		return 0.0
	var env: float = exp(-t_in_step * 40.0)
	return (randf() * 2.0 - 1.0) * env
