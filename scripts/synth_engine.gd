class_name SynthEngine
extends Node

## Polyphonic synth — parameters are meant to be driven by tracker FX columns.
## Supported FX (single letter + 2 hex digits, e.g. V80, D40, FA0):
##   Vxx  Volume / velocity          00–FF  (80 ≈ default)
##   Dxx  Decay scale                00=very short … FF=long
##   Fxx  Filter cutoff bias         00=dark … FF=open
##   Mxx  FM / metal / mod depth     00–FF
##   Pxx  Pitch offset (semitones)   00–7F up, 80–FF down (two’s-complement style)
##   Sxx  Kick/start pitch bias      higher = higher initial pitch drop start
##   Cxx  Note cut / max length      (future)

const SAMPLE_RATE := 44100.0
const MAX_VOICES := 12
const TWO_PI := PI * 2.0

enum VoiceType { KICK, SNARE, HAT, CLAP, BASS, TEXTURE, FM_METAL, NOISE_SWEEP }

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var voices: Array = []

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
		"base_freq": 100.0,
		"freq2": 200.0,
		"amp_env": 0.0,
		"pitch_env": 0.0,
		"filter": 0.0,
		"filter_env": 0.0,
		"noise_state": 0,
		"age": 0.0,
		"decay": 0.3,
		"vel": 1.0,
		"filter_bias": 0.5,   # 0–1 from F command
		"mod_depth": 1.0,     # from M command
		"start_pitch": 1.0,   # from S command (kicks)
	}

## Main entry — fx1 and fx2 are raw tracker strings like "V80", "D40", "----"
func note_on(note: int, octave: int, instrument: int, fx1: String = "----", fx2: String = "----", velocity: float = 1.0) -> void:
	var fx = _parse_fx_pair(fx1, fx2)
	var freq = _note_to_freq(note, octave)
	# P command = pitch offset in semitones
	if fx.has("P"):
		var p = fx["P"]
		var semis = p if p < 128 else p - 256   # 80–FF = negative
		freq *= pow(2.0, semis / 12.0)
	var vtype = _instrument_to_type(instrument)
	var voice = _find_free_voice()
	if voice == null:
		return

	voice.active = true
	voice.type = vtype
	voice.phase = 0.0
	voice.phase2 = 0.0
	voice.base_freq = freq
	voice.freq = freq
	voice.freq2 = freq * 1.005
	voice.amp_env = 1.0
	voice.pitch_env = 1.0
	voice.filter = 0.0
	voice.filter_env = 1.0
	voice.age = 0.0
	voice.noise_state = randi()
	voice.vel = clampf(velocity, 0.05, 1.0)
	voice.filter_bias = 0.5
	voice.mod_depth = 1.0
	voice.start_pitch = 1.0

	# Apply FX overrides
	if fx.has("V"):
		voice.vel = clampf(fx["V"] / 128.0, 0.05, 1.5)
	if fx.has("F"):
		voice.filter_bias = clampf(fx["F"] / 255.0, 0.0, 1.0)
	if fx.has("M"):
		voice.mod_depth = clampf(fx["M"] / 64.0, 0.1, 4.0)
	if fx.has("S"):
		voice.start_pitch = clampf(fx["S"] / 128.0, 0.3, 2.5)

	# Base decay by type, then scale by D command
	var base_decay := 0.3
	match vtype:
		VoiceType.KICK:
			voice.freq = (160.0 + freq * 0.2) * voice.start_pitch
			base_decay = 0.32 + (instrument % 4) * 0.07
		VoiceType.SNARE:
			base_decay = 0.16 + (instrument % 3) * 0.04
		VoiceType.HAT:
			base_decay = 0.035 + (instrument % 4) * 0.012
		VoiceType.CLAP:
			base_decay = 0.20
		VoiceType.BASS:
			base_decay = 0.55 + (instrument % 5) * 0.12
		VoiceType.TEXTURE:
			base_decay = 1.1 + (instrument % 4) * 0.35
		VoiceType.FM_METAL:
			base_decay = 0.45 + (instrument % 6) * 0.09
			voice.freq2 = freq * (2.0 + (instrument % 5) * 0.5) * voice.mod_depth
		VoiceType.NOISE_SWEEP:
			base_decay = 0.75

	if fx.has("D"):
		# 00 = ~0.25×, 80 = 1×, FF = ~3×
		var scale = 0.25 + (fx["D"] / 255.0) * 2.75
		voice.decay = base_decay * scale
	else:
		voice.decay = base_decay

func _parse_fx_pair(fx1: String, fx2: String) -> Dictionary:
	var out := {}
	_parse_one(fx1, out)
	_parse_one(fx2, out)
	return out

func _parse_one(fx: String, out: Dictionary) -> void:
	if fx == null or fx.length() < 3 or fx.begins_with("-"):
		return
	var cmd = fx.substr(0, 1).to_upper()
	var hex = fx.substr(1, 2)
	if not hex.is_valid_hex_number():
		return
	var val = hex.hex_to_int()
	out[cmd] = val

func _instrument_to_type(inst: int) -> int:
	var i = inst % 32
	if i <= 4: return VoiceType.KICK
	elif i <= 8: return VoiceType.SNARE
	elif i <= 11: return VoiceType.HAT
	elif i <= 13: return VoiceType.CLAP
	elif i <= 18: return VoiceType.BASS
	elif i <= 24: return VoiceType.TEXTURE
	elif i <= 28: return VoiceType.FM_METAL
	else: return VoiceType.NOISE_SWEEP

func _note_to_freq(note: int, octave: int) -> float:
	if note < 0: note = 0
	var midi = (octave + 1) * 12 + note
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

func _find_free_voice() -> Dictionary:
	for v in voices:
		if not v.active:
			return v
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
			if not v.active: continue
			v.age += inv_sr
			sample += _render_voice(v, inv_sr)
			if v.amp_env < 0.001 and v.age > 0.02:
				v.active = false
		sample = tanh(sample * 0.65)
		out[i] = Vector2(sample, sample)
	playback.push_buffer(out)

func _render_voice(v: Dictionary, dt: float) -> float:
	var s := 0.0
	match v.type:
		VoiceType.KICK:
			v.pitch_env = exp(-v.age * (11.0 / v.decay))
			var f = 42.0 + (v.freq - 42.0) * v.pitch_env
			v.phase = fmod(v.phase + f * dt, 1.0)
			s = sin(v.phase * TWO_PI)
			if v.age < 0.0035:
				s += (randf() * 2.0 - 1.0) * 0.55 * (1.0 - v.age / 0.0035)
			v.amp_env = exp(-v.age * (5.2 / v.decay))
			s *= v.amp_env * v.vel * 0.9

		VoiceType.SNARE:
			v.amp_env = exp(-v.age * (8.5 / v.decay))
			var body = sin(v.phase * TWO_PI) * 0.32
			v.phase = fmod(v.phase + 175.0 * dt, 1.0)
			s = (body + _noise(v) * 0.68) * v.amp_env * v.vel

		VoiceType.HAT:
			v.amp_env = exp(-v.age * (26.0 / v.decay))
			var n = _noise(v)
			v.filter = n - v.filter * (0.88 - v.filter_bias * 0.1)
			s = v.filter * v.amp_env * v.vel * 0.5

		VoiceType.CLAP:
			var t = v.age
			var env = 0.0
			if t < 0.011: env = 1.0 - t / 0.011
			elif t < 0.024: env = 0.65 * (1.0 - (t - 0.011) / 0.013)
			elif t < 0.048: env = 0.35 * (1.0 - (t - 0.024) / 0.024)
			else: env = exp(-(t - 0.048) * 16.0)
			v.amp_env = env
			s = _noise(v) * env * v.vel * 0.65

		VoiceType.BASS:
			v.phase = fmod(v.phase + v.freq * dt, 1.0)
			var saw = v.phase * 2.0 - 1.0
			v.filter_env = exp(-v.age * (3.2 / v.decay))
			var cutoff = 0.06 + (0.15 + 0.55 * v.filter_bias) * v.filter_env
			v.filter += cutoff * (saw - v.filter)
			v.amp_env = exp(-v.age * (2.6 / v.decay))
			s = v.filter * v.amp_env * v.vel * 0.7

		VoiceType.TEXTURE:
			v.phase = fmod(v.phase + v.freq * dt, 1.0)
			v.phase2 = fmod(v.phase2 + v.freq2 * dt, 1.0)
			var mixed = ((v.phase * 2.0 - 1.0) + (v.phase2 * 2.0 - 1.0)) * 0.5
			v.filter_env = exp(-v.age * (1.1 / v.decay))
			var cutoff = 0.03 + (0.08 + 0.4 * v.filter_bias) * v.filter_env
			v.filter += cutoff * (mixed - v.filter)
			v.amp_env = exp(-v.age * (1.5 / v.decay))
			s = v.filter * v.amp_env * v.vel * 0.52

		VoiceType.FM_METAL:
			var mod_idx = (2.5 * v.mod_depth) * exp(-v.age * 3.8)
			v.phase2 = fmod(v.phase2 + v.freq2 * dt, 1.0)
			var mod = sin(v.phase2 * TWO_PI) * mod_idx
			v.phase = fmod(v.phase + (v.freq * (1.0 + mod * 0.18)) * dt, 1.0)
			s = sin(v.phase * TWO_PI)
			v.amp_env = exp(-v.age * (3.8 / v.decay))
			s *= v.amp_env * v.vel * 0.58

		VoiceType.NOISE_SWEEP:
			v.amp_env = exp(-v.age * (2.3 / v.decay))
			var n = _noise(v)
			var sweep = exp(-v.age * 2.8)
			var open = 0.08 + 0.75 * v.filter_bias * sweep
			v.filter += open * (n - v.filter)
			s = v.filter * v.amp_env * v.vel * 0.48

	return s

func _noise(v: Dictionary) -> float:
	v.noise_state ^= v.noise_state << 13
	v.noise_state ^= v.noise_state >> 17
	v.noise_state ^= v.noise_state << 5
	return (v.noise_state % 10000) / 5000.0 - 1.0
