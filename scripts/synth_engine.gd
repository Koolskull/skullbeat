class_name SynthEngine
extends Node

## Lightweight monophonic-per-channel audio engine for iPad/Xogot
## Designed so main-thread GDScript DSP never starves the sequencer.

const SAMPLE_RATE := 44100.0
const TRACKER_CHANNELS := 4
const PAD_VOICES := 4
const TOTAL_VOICES := TRACKER_CHANNELS + PAD_VOICES
const TWO_PI := PI * 2.0
const MAX_INST := 64
const MIN_DECAY := 0.02
## Cap frames filled per visual frame so UI/sequencer keep running (~11ms)
const MAX_FRAMES_PER_TICK := 512

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var voices: Array = []
var instruments: Array = []

# Master EQ / limiter (always cheap)
var master_eq_gain := 1.0
var master_lim_ceiling := 0.95
var master_lim_env := 0.0

# Master FX — OFF by default (expensive in GDScript). Toggle from INST later.
var master_dist_drive := 0.0
var master_chorus_wet := 0.0
var master_delay_wet := 0.0
var master_delay_time := 0.28
var master_delay_fb := 0.28
var master_reverb_wet := 0.0

var delay_l: PackedFloat32Array
var delay_r: PackedFloat32Array
var delay_idx := 0
var delay_len := 0
var chorus_phase := 0.0
var reverb_buf: PackedFloat32Array
var reverb_idx := 0

var _pad_rr := 0
var _out_buf: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	_init_instruments()
	_init_fx_buffers()
	voices.clear()
	for i in range(TOTAL_VOICES):
		voices.append(_make_voice())
	player = AudioStreamPlayer.new()
	add_child(player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	# Slightly larger buffer = more headroom when a frame is late
	gen.buffer_length = 0.12
	player.stream = gen
	player.volume_db = -4.0
	player.play()
	call_deferred("_grab_playback")

func _grab_playback() -> void:
	if player and player.playing:
		playback = player.get_stream_playback()

func _init_instruments() -> void:
	instruments.clear()
	for i in range(MAX_INST):
		instruments.append(Instrument.new(i))

func _init_fx_buffers() -> void:
	# Smaller delay/reverb so enabling FX later is cheaper
	delay_len = int(SAMPLE_RATE * 0.5)
	delay_l = PackedFloat32Array()
	delay_l.resize(delay_len)
	delay_r = PackedFloat32Array()
	delay_r.resize(delay_len)
	reverb_buf = PackedFloat32Array()
	reverb_buf.resize(int(SAMPLE_RATE * 0.18))

func _process(_delta: float) -> void:
	if playback == null:
		_grab_playback()
		return
	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return
	# Never fill more than MAX_FRAMES_PER_TICK in one visual frame
	var n: int = mini(frames, MAX_FRAMES_PER_TICK)
	_render(n)

func get_instrument(id: int) -> Instrument:
	return instruments[id % MAX_INST]

func _make_voice() -> Dictionary:
	return {
		"active": false,
		"channel": -1,
		"inst_id": 0,
		"algo": Instrument.SynthAlgo.KICK,
		"phase": 0.0,
		"phase2": 0.0,
		"freq": 100.0,
		"freq2": 200.0,
		"amp_env": 0.0,
		"pitch_env": 0.0,
		"filter": 0.0,
		"filter_env": 0.0,
		"noise_state": 1,
		"age": 0.0,
		"decay": 0.3,
		"vel": 1.0,
		"filter_bias": 0.5,
		"mod_depth": 1.0,
		"start_pitch": 1.0,
		"use_synth": true,
		"use_sample": false,
		"sample_pos": 0.0,
		"sample_inc": 1.0,
		"sample_gain": 1.0,
		"synth_gain": 1.0,
	}

## channel: 0..3 tracker (mono choke). -1 = live pad pool.
func note_on(note: int, octave: int, instrument: int, fx1: String = "----", fx2: String = "----", velocity: float = 1.0, channel: int = -1) -> void:
	var inst: Instrument = get_instrument(instrument)
	var fx = _parse_fx_pair(fx1, fx2)
	var freq = _note_to_freq(note, octave)
	if fx.has("P"):
		var p: int = int(fx["P"])
		var semis: int = p if p < 128 else p - 256
		freq *= pow(2.0, float(semis) / 12.0)

	var voice = _allocate_voice(channel)
	if voice == null:
		return

	voice.active = true
	voice.channel = channel
	voice.inst_id = instrument % MAX_INST
	voice.algo = inst.synth_algo
	voice.phase = 0.0
	voice.phase2 = 0.0
	voice.freq = freq
	voice.freq2 = freq * 1.005
	voice.amp_env = 1.0
	voice.pitch_env = 1.0
	voice.filter = 0.0
	voice.filter_env = 1.0
	voice.age = 0.0
	voice.noise_state = maxi(1, randi() % 2147483646)
	voice.vel = clampf(velocity, 0.05, 1.0)
	voice.filter_bias = 0.5
	voice.mod_depth = 1.0
	voice.start_pitch = 1.0
	voice.synth_gain = inst.synth_gain
	voice.sample_gain = inst.sample_gain
	voice.sample_pos = 0.0
	voice.sample_inc = 1.0

	# Prefer sample OR synth, not both — double render was killing performance
	var has_samp: bool = inst.has_sample()
	voice.use_sample = has_samp and inst.sample_enabled
	voice.use_synth = inst.synth_enabled and not voice.use_sample
	if not voice.use_sample and not voice.use_synth:
		# fall back to synth so something always sounds
		voice.use_synth = true

	if fx.has("V"):
		voice.vel = clampf(float(fx["V"]) / 128.0, 0.05, 1.5)
	if fx.has("F"):
		voice.filter_bias = clampf(float(fx["F"]) / 255.0, 0.0, 1.0)
	if fx.has("M"):
		voice.mod_depth = clampf(float(fx["M"]) / 64.0, 0.1, 4.0)
	if fx.has("S"):
		voice.start_pitch = clampf(float(fx["S"]) / 128.0, 0.3, 2.5)

	if voice.use_sample and inst.sample_data.size() > 0:
		var root_freq = 440.0 * pow(2.0, float(inst.sample_root_note - 69) / 12.0)
		voice.sample_inc = (freq / maxf(root_freq, 1.0)) * (inst.sample_rate / SAMPLE_RATE)
		voice.sample_pos = float(maxi(0, inst.sample_start))

	var base_decay := 0.3
	match voice.algo:
		Instrument.SynthAlgo.KICK:
			voice.freq = (160.0 + freq * 0.2) * voice.start_pitch
			base_decay = 0.32
		Instrument.SynthAlgo.SNARE:
			base_decay = 0.17
		Instrument.SynthAlgo.HAT:
			base_decay = 0.05
		Instrument.SynthAlgo.CLAP:
			base_decay = 0.20
		Instrument.SynthAlgo.BASS:
			base_decay = 0.55
		Instrument.SynthAlgo.TEXTURE:
			base_decay = 1.0
		Instrument.SynthAlgo.FM_METAL:
			base_decay = 0.45
			voice.freq2 = freq * (2.0 + float(instrument % 5) * 0.5) * voice.mod_depth
		Instrument.SynthAlgo.NOISE_SWEEP:
			base_decay = 0.7
		_:
			base_decay = 0.4

	if fx.has("D"):
		voice.decay = maxf(MIN_DECAY, base_decay * (0.25 + (float(fx["D"]) / 255.0) * 2.75))
	else:
		voice.decay = maxf(MIN_DECAY, base_decay)

func choke_channel(channel: int) -> void:
	if channel < 0 or channel >= TRACKER_CHANNELS:
		return
	var v = voices[channel]
	v.active = false
	v.amp_env = 0.0
	v.use_sample = false

func stop_all() -> void:
	for v in voices:
		v.active = false
		v.amp_env = 0.0
		v.use_sample = false

func _allocate_voice(channel: int) -> Dictionary:
	if channel >= 0 and channel < TRACKER_CHANNELS:
		var v = voices[channel]
		v.active = false
		return v
	var idx = TRACKER_CHANNELS + (_pad_rr % PAD_VOICES)
	_pad_rr = (_pad_rr + 1) % PAD_VOICES
	var pv = voices[idx]
	pv.active = false
	return pv

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
	out[cmd] = hex.hex_to_int()

func _note_to_freq(note: int, octave: int) -> float:
	note = clampi(note, 0, 11)
	octave = clampi(octave, 0, 8)
	return 440.0 * pow(2.0, float((octave + 1) * 12 + note - 69) / 12.0)

func _render(num_frames: int) -> void:
	if playback == null or num_frames <= 0:
		return
	if _out_buf.size() != num_frames:
		_out_buf.resize(num_frames)
	var inv_sr := 1.0 / SAMPLE_RATE
	var use_delay := master_delay_wet > 0.01 and delay_len > 1
	var use_chorus := master_chorus_wet > 0.01 and delay_len > 1
	var use_reverb := master_reverb_wet > 0.01 and reverb_buf.size() > 1
	var use_dist := master_dist_drive > 0.01
	var delay_samples := 1
	if use_delay or use_chorus:
		delay_samples = clampi(int(master_delay_time * SAMPLE_RATE), 1, delay_len - 1)
	var rlen: int = reverb_buf.size()
	var reverb_off: int = int(SAMPLE_RATE * 0.037) if use_reverb else 0

	for i in range(num_frames):
		var mix := 0.0
		for vi in range(TOTAL_VOICES):
			var v = voices[vi]
			if not v.active:
				continue
			v.age += inv_sr
			var s: float = _render_voice(v, inv_sr)
			mix += s
			if v.amp_env < 0.001 and v.age > 0.015 and not v.use_sample:
				v.active = false

		# Master FX only when wet > 0
		if use_dist:
			var d = 1.0 + master_dist_drive * 3.0
			mix = clampf(mix * d, -1.5, 1.5)
			# soft clip without tanh (faster)
			if mix > 1.0:
				mix = 1.0 - 1.0 / (mix + 1.0) * 0.5
			elif mix < -1.0:
				mix = -1.0 + 1.0 / (-mix + 1.0) * 0.5

		if use_chorus:
			chorus_phase = fmod(chorus_phase + 0.8 * inv_sr, 1.0)
			var mod = sin(chorus_phase * TWO_PI) * 0.0025
			var c_samp = clampi(int((0.012 + mod) * SAMPLE_RATE), 1, delay_len - 1)
			var c_idx = (delay_idx - c_samp + delay_len) % delay_len
			mix = lerpf(mix, delay_l[c_idx], master_chorus_wet)

		var dl := 0.0
		var dr := 0.0
		if use_delay or use_chorus:
			var d_idx = (delay_idx - delay_samples + delay_len) % delay_len
			dl = delay_l[d_idx]
			dr = delay_r[d_idx]
			if use_delay:
				mix += dl * master_delay_wet
			delay_l[delay_idx] = clampf(mix + dl * master_delay_fb, -1.5, 1.5)
			delay_r[delay_idx] = clampf(mix * 0.97 + dr * master_delay_fb, -1.5, 1.5)
			delay_idx = (delay_idx + 1) % delay_len

		if use_reverb:
			var r_read = (reverb_idx - reverb_off + rlen) % rlen
			var rv = reverb_buf[r_read]
			reverb_buf[reverb_idx] = clampf(mix * 0.25 + rv * 0.72, -1.5, 1.5)
			reverb_idx = (reverb_idx + 1) % rlen
			mix += rv * master_reverb_wet

		mix *= master_eq_gain

		var peak = absf(mix)
		master_lim_env = maxf(peak, master_lim_env * 0.9992)
		if master_lim_env > master_lim_ceiling:
			mix *= master_lim_ceiling / master_lim_env
		mix = clampf(mix, -1.0, 1.0)
		_out_buf[i] = Vector2(mix, mix)

	playback.push_buffer(_out_buf)

func _render_voice(v: Dictionary, dt: float) -> float:
	var s := 0.0
	var inst: Instrument = instruments[v.inst_id % MAX_INST]

	if v.use_sample:
		var data: PackedFloat32Array = inst.sample_data
		var dsize: int = data.size()
		if dsize <= 0:
			v.use_sample = false
		else:
			var pos: int = int(v.sample_pos)
			var s_end: int = mini(inst.sample_end if inst.sample_end > 0 else dsize, dsize)
			if pos >= 0 and pos < s_end:
				s = data[pos] * v.sample_gain * v.vel
				v.sample_pos += v.sample_inc
				# simple amp envelope for samples so they don't click forever
				v.amp_env = 1.0
				if v.sample_pos >= float(s_end):
					if inst.sample_loop:
						v.sample_pos = float(inst.sample_start)
					else:
						v.use_sample = false
						v.amp_env = 0.0
			else:
				v.use_sample = false
				v.amp_env = 0.0
		return s

	if v.use_synth and v.algo != Instrument.SynthAlgo.NONE:
		s = _render_synth(v, dt, maxf(v.decay, MIN_DECAY)) * v.synth_gain
	return s

func _render_synth(v: Dictionary, dt: float, decay: float) -> float:
	var s := 0.0
	match v.algo:
		Instrument.SynthAlgo.KICK:
			v.pitch_env = exp(-v.age * (11.0 / decay))
			var f = 42.0 + (v.freq - 42.0) * v.pitch_env
			v.phase = fmod(v.phase + f * dt, 1.0)
			s = sin(v.phase * TWO_PI)
			if v.age < 0.003:
				s += (randf() * 2.0 - 1.0) * 0.4 * (1.0 - v.age / 0.003)
			v.amp_env = exp(-v.age * (5.2 / decay))
			s *= v.amp_env * v.vel * 0.9
		Instrument.SynthAlgo.SNARE:
			v.amp_env = exp(-v.age * (8.5 / decay))
			v.phase = fmod(v.phase + 175.0 * dt, 1.0)
			s = (sin(v.phase * TWO_PI) * 0.3 + _noise(v) * 0.7) * v.amp_env * v.vel
		Instrument.SynthAlgo.HAT:
			v.amp_env = exp(-v.age * (26.0 / decay))
			var n = _noise(v)
			v.filter = n - v.filter * (0.88 - v.filter_bias * 0.1)
			s = v.filter * v.amp_env * v.vel * 0.5
		Instrument.SynthAlgo.CLAP:
			var t = v.age
			var env = 0.0
			if t < 0.011:
				env = 1.0 - t / 0.011
			elif t < 0.024:
				env = 0.65 * (1.0 - (t - 0.011) / 0.013)
			elif t < 0.048:
				env = 0.35 * (1.0 - (t - 0.024) / 0.024)
			else:
				env = exp(-(t - 0.048) * 16.0)
			v.amp_env = env
			s = _noise(v) * env * v.vel * 0.65
		Instrument.SynthAlgo.BASS:
			v.phase = fmod(v.phase + v.freq * dt, 1.0)
			var saw = v.phase * 2.0 - 1.0
			v.filter_env = exp(-v.age * (3.2 / decay))
			var cutoff = 0.06 + (0.15 + 0.55 * v.filter_bias) * v.filter_env
			v.filter += cutoff * (saw - v.filter)
			v.amp_env = exp(-v.age * (2.6 / decay))
			s = v.filter * v.amp_env * v.vel * 0.7
		Instrument.SynthAlgo.TEXTURE:
			v.phase = fmod(v.phase + v.freq * dt, 1.0)
			v.phase2 = fmod(v.phase2 + v.freq2 * dt, 1.0)
			var mixed = ((v.phase * 2.0 - 1.0) + (v.phase2 * 2.0 - 1.0)) * 0.5
			v.filter_env = exp(-v.age * (1.1 / decay))
			var cutoff2 = 0.03 + (0.08 + 0.4 * v.filter_bias) * v.filter_env
			v.filter += cutoff2 * (mixed - v.filter)
			v.amp_env = exp(-v.age * (1.5 / decay))
			s = v.filter * v.amp_env * v.vel * 0.52
		Instrument.SynthAlgo.FM_METAL:
			var mod_idx = (2.5 * v.mod_depth) * exp(-v.age * 3.8)
			v.phase2 = fmod(v.phase2 + v.freq2 * dt, 1.0)
			var mod = sin(v.phase2 * TWO_PI) * mod_idx
			v.phase = fmod(v.phase + (v.freq * (1.0 + mod * 0.18)) * dt, 1.0)
			s = sin(v.phase * TWO_PI)
			v.amp_env = exp(-v.age * (3.8 / decay))
			s *= v.amp_env * v.vel * 0.58
		Instrument.SynthAlgo.NOISE_SWEEP:
			v.amp_env = exp(-v.age * (2.3 / decay))
			var n2 = _noise(v)
			var sweep = exp(-v.age * 2.8)
			var open = 0.08 + 0.75 * v.filter_bias * sweep
			v.filter += open * (n2 - v.filter)
			s = v.filter * v.amp_env * v.vel * 0.48
	return s

func _noise(v: Dictionary) -> float:
	var ns: int = int(v.noise_state)
	ns ^= (ns << 13)
	ns ^= (ns >> 17)
	ns ^= (ns << 5)
	v.noise_state = ns
	return float(ns % 10000) / 5000.0 - 1.0

func bake_procedural_sample(inst_id: int, kind: String = "kick") -> void:
	var inst: Instrument = get_instrument(inst_id)
	var n: int = int(SAMPLE_RATE * 0.28)
	var data := PackedFloat32Array()
	data.resize(n)
	for i in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var s := 0.0
		match kind:
			"kick":
				var f = 150.0 * exp(-t * 20.0) + 40.0
				s = sin(TWO_PI * f * t) * exp(-t * 8.0)
			"snare":
				s = (sin(TWO_PI * 180.0 * t) * 0.3 + (randf() * 2.0 - 1.0) * 0.7) * exp(-t * 14.0)
			"hat":
				s = (randf() * 2.0 - 1.0) * exp(-t * 40.0)
			_:
				s = sin(TWO_PI * 220.0 * t) * exp(-t * 6.0)
		data[i] = s
	inst.load_sample_mono(data, SAMPLE_RATE)
	# sample layer only — avoid double render with synth
	inst.sample_enabled = true
	inst.synth_enabled = false
