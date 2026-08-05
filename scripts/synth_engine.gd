class_name SynthEngine
extends Node

## Lightweight polyphonic synth for Skullbeat
## Percussion + harmonic textures, driven by note + instrument number
## Uses a single AudioStreamGenerator and mixes voices in software

const SAMPLE_RATE := 44100.0
const MAX_VOICES := 12
const TWO_PI := PI * 2.0

enum VoiceType {
	KICK,
	SNARE,
	HAT,
	CLAP,
	BASS,       # saw + filter → harmonic body
	TEXTURE,    # detuned + slow filter for pads/textures
	FM_METAL,   # simple 2-op FM
	NOISE_SWEEP
}

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var voices: Array = []
var mix_buffer: PackedVector2Array

func _ready() -> void:
	player = AudioStreamPlayer.new()
	add_child(player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.1
	player.stream = gen
	player.play()
	playback = player.get_stream_playback()
	for i in range(MAX_VOICES):
		voices.append(_make_voice())

func _process(_delta: float) -> void:
	if playback == null:
		return
	var frames = playback.get_frames_available()
	if frames <= 0:
		return
	# Fill in chunks to keep it responsive
	while frames > 0:
		var n = mini(frames, 256)
		_render(n)
		frames -= n

func _make_voice() -> Dictionary:
	return {
		"active": false,
		"type": VoiceType.KICK,
		"phase": 0.0,
		"phase2": 0.0,
		"freq": 100.0,
		"freq2": 200.0,
		"amp": 0.0,
		"amp_env": 0.0,
		"pitch_env": 0.0,
		"filter": 0.0,
		"filter_env": 0.0,
		"noise_state": 0,
		"age": 0.0,
		"decay": 0.3,
		"vel": 1.0,
	}

func note_on(note: int, octave: int, instrument: int, velocity: float = 1.0) -> void:
	var freq = _note_to_freq(note, octave)
	var vtype = _instrument_to_type(instrument)
	var voice = _find_free_voice()
	if voice == null:
		return
	voice.active = true
	voice.type = vtype
	voice.phase = 0.0
	voice.phase2 = 0.0
	voice.freq = freq
	voice.freq2 = freq * 1.005  # slight detune for textures
	voice.amp = 0.0
	voice.amp_env = 1.0
	voice.pitch_env = 1.0
	voice.filter = 0.0
	voice.filter_env = 1.0
	voice.age = 0.0
	voice.vel = clampf(velocity, 0.1, 1.0)
	voice.noise_state = randi()
	match vtype:
		VoiceType.KICK:
			voice.freq = 180.0 + freq * 0.15  # start pitch
			voice.decay = 0.35 + (instrument % 4) * 0.08
		VoiceType.SNARE:
			voice.decay = 0.18 + (instrument % 3) * 0.04
		VoiceType.HAT:
			voice.decay = 0.04 + (instrument % 4) * 0.015
		VoiceType.CLAP:
			voice.decay = 0.22
		VoiceType.BASS:
			voice.decay = 0.6 + (instrument % 5) * 0.15
			voice.filter = 0.3
		VoiceType.TEXTURE:
			voice.decay = 1.2 + (instrument % 4) * 0.4
			voice.filter = 0.15
		VoiceType.FM_METAL:
			voice.decay = 0.5 + (instrument % 6) * 0.1
			voice.freq2 = freq * (2.0 + (instrument % 5) * 0.5)
		VoiceType.NOISE_SWEEP:
			voice.decay = 0.8
			voice.filter = 0.8

func _instrument_to_type(inst: int) -> int:
	var i = inst % 32
	if i <= 4:
		return VoiceType.KICK
	elif i <= 8:
		return VoiceType.SNARE
	elif i <= 11:
		return VoiceType.HAT
	elif i <= 13:
		return VoiceType.CLAP
	elif i <= 18:
		return VoiceType.BASS
	elif i <= 24:
		return VoiceType.TEXTURE
	elif i <= 28:
		return VoiceType.FM_METAL
	else:
		return VoiceType.NOISE_SWEEP

func _note_to_freq(note: int, octave: int) -> float:
	if note < 0:
		note = 0
	# MIDI-style: C4 = 60 ≈ 261.63
	var midi = (octave + 1) * 12 + note
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

func _find_free_voice() -> Dictionary:
	for v in voices:
		if not v.active:
			return v
	# steal oldest
	var oldest = voices[0]
	for v in voices:
		if v.age > oldest.age:
			oldest = v
	oldest.active = false
	return oldest

func _render(num_frames: int) -> void:
	var out := PackedVector2Array()
	out.resize(num_frames)
	var inv_sr = 1.0 / SAMPLE_RATE
	for i in range(num_frames):
		var sample := 0.0
		for v in voices:
			if not v.active:
				continue
			v.age += inv_sr
			var s = _render_voice(v, inv_sr)
			sample += s
			if v.amp_env < 0.001 and v.age > 0.02:
				v.active = false
		# soft clip
		sample = tanh(sample * 0.7)
		out[i] = Vector2(sample, sample)
	playback.push_buffer(out)

func _render_voice(v: Dictionary, dt: float) -> float:
	var s := 0.0
	match v.type:
		VoiceType.KICK:
			# exponential pitch drop + amp
			v.pitch_env = exp(-v.age * (12.0 / v.decay))
			var f = 45.0 + (v.freq - 45.0) * v.pitch_env
			v.phase = fmod(v.phase + f * dt, 1.0)
			s = sin(v.phase * TWO_PI)
			# click
			if v.age < 0.004:
				s += (randf() * 2.0 - 1.0) * 0.6 * (1.0 - v.age / 0.004)
			v.amp_env = exp(-v.age * (5.5 / v.decay))
			s *= v.amp_env * v.vel * 0.9

		VoiceType.SNARE:
			v.amp_env = exp(-v.age * (9.0 / v.decay))
			var body = sin(v.phase * TWO_PI) * 0.35
			v.phase = fmod(v.phase + 180.0 * dt, 1.0)
			var noise = _noise(v) * 0.7
			# simple high emphasis
			s = (body + noise) * v.amp_env * v.vel

		VoiceType.HAT:
			v.amp_env = exp(-v.age * (28.0 / v.decay))
			var n = _noise(v)
			# crude highpass
			v.filter = n - v.filter * 0.92
			s = v.filter * v.amp_env * v.vel * 0.55

		VoiceType.CLAP:
			# multi-burst noise
			var env = 0.0
			var t = v.age
			if t < 0.012:
				env = 1.0 - t / 0.012
			elif t < 0.025:
				env = 0.7 * (1.0 - (t - 0.012) / 0.013)
			elif t < 0.05:
				env = 0.4 * (1.0 - (t - 0.025) / 0.025)
			else:
				env = exp(-(t - 0.05) * 18.0)
			v.amp_env = env
			s = _noise(v) * env * v.vel * 0.7

		VoiceType.BASS:
			# band-limited-ish saw via polyBLEP approximation (simple)
			var f = v.freq
			v.phase = fmod(v.phase + f * dt, 1.0)
			var saw = v.phase * 2.0 - 1.0
			# one-pole lowpass controlled by filter_env
			v.filter_env = exp(-v.age * (3.5 / v.decay))
			var cutoff = 0.08 + 0.55 * v.filter_env
			v.filter += cutoff * (saw - v.filter)
			v.amp_env = exp(-v.age * (2.8 / v.decay))
			s = v.filter * v.amp_env * v.vel * 0.7

		VoiceType.TEXTURE:
			# dual detuned saw + slow filter for pads / harmonic wash
			v.phase = fmod(v.phase + v.freq * dt, 1.0)
			v.phase2 = fmod(v.phase2 + v.freq2 * dt, 1.0)
			var s1 = v.phase * 2.0 - 1.0
			var s2 = v.phase2 * 2.0 - 1.0
			var mixed = (s1 + s2) * 0.5
			v.filter_env = exp(-v.age * (1.2 / v.decay))
			var cutoff = 0.04 + 0.35 * v.filter_env
			v.filter += cutoff * (mixed - v.filter)
			v.amp_env = exp(-v.age * (1.6 / v.decay))
			s = v.filter * v.amp_env * v.vel * 0.55

		VoiceType.FM_METAL:
			# simple carrier + modulator
			var mod_idx = 3.5 * exp(-v.age * 4.0)
			v.phase2 = fmod(v.phase2 + v.freq2 * dt, 1.0)
			var mod = sin(v.phase2 * TWO_PI) * mod_idx
			v.phase = fmod(v.phase + (v.freq * (1.0 + mod * 0.15)) * dt, 1.0)
			s = sin(v.phase * TWO_PI)
			v.amp_env = exp(-v.age * (4.0 / v.decay))
			s *= v.amp_env * v.vel * 0.6

		VoiceType.NOISE_SWEEP:
			v.amp_env = exp(-v.age * (2.5 / v.decay))
			var n = _noise(v)
			var sweep = exp(-v.age * 3.0)
			v.filter += (0.1 + 0.7 * sweep) * (n - v.filter)
			s = v.filter * v.amp_env * v.vel * 0.5

	return s

func _noise(v: Dictionary) -> float:
	# xorshift-ish
	v.noise_state ^= v.noise_state << 13
	v.noise_state ^= v.noise_state >> 17
	v.noise_state ^= v.noise_state << 5
	return (v.noise_state % 10000) / 5000.0 - 1.0
