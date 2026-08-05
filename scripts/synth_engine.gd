class_name SynthEngine
extends Node

## Thin audio mixer over Dsp + Instrument.
## Cost rules: sample XOR synth, master = gain+clip, hard frame cap.

const CH := 4
const PAD := 4
const VOICES := CH + PAD
const MAX_INST := 64
const MAX_FRAMES := 384

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var instruments: Array = []

var v_on: PackedByteArray
var v_algo: PackedByteArray
var v_src: PackedByteArray
var v_inst: PackedInt32Array
var v_noise: PackedInt32Array
var v_phase: PackedFloat32Array
var v_phase2: PackedFloat32Array
var v_freq: PackedFloat32Array
var v_freq2: PackedFloat32Array
var v_amp: PackedFloat32Array
var v_age: PackedFloat32Array
var v_decay: PackedFloat32Array
var v_vel: PackedFloat32Array
var v_filter: PackedFloat32Array
var v_fbias: PackedFloat32Array
var v_mod: PackedFloat32Array
var v_spitch: PackedFloat32Array
var v_spos: PackedFloat32Array
var v_sinc: PackedFloat32Array
var v_gain: PackedFloat32Array

var master_gain := 0.85
var master_lim := 0.0
var master_ceiling := 0.95
var bus_dist := 0.0
var bus_delay_wet := 0.0
var bus_delay_time := 0.28
var bus_delay_fb := 0.25
var delay_l: PackedFloat32Array
var delay_r: PackedFloat32Array
var delay_i := 0
var delay_n := 0

var _pad_rr := 0
var _out: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	_alloc_voices()
	_init_instruments()
	delay_n = int(Dsp.SR * 0.4)
	delay_l = PackedFloat32Array()
	delay_l.resize(delay_n)
	delay_r = PackedFloat32Array()
	delay_r.resize(delay_n)
	player = AudioStreamPlayer.new()
	add_child(player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = Dsp.SR
	gen.buffer_length = 0.1
	player.stream = gen
	player.volume_db = -3.0
	player.play()
	call_deferred("_grab")

func _grab() -> void:
	if player and player.playing:
		playback = player.get_stream_playback()

func _f32() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(VOICES)
	return a

func _alloc_voices() -> void:
	v_on = PackedByteArray()
	v_on.resize(VOICES)
	v_algo = PackedByteArray()
	v_algo.resize(VOICES)
	v_src = PackedByteArray()
	v_src.resize(VOICES)
	v_inst = PackedInt32Array()
	v_inst.resize(VOICES)
	v_noise = PackedInt32Array()
	v_noise.resize(VOICES)
	v_phase = _f32()
	v_phase2 = _f32()
	v_freq = _f32()
	v_freq2 = _f32()
	v_amp = _f32()
	v_age = _f32()
	v_decay = _f32()
	v_vel = _f32()
	v_filter = _f32()
	v_fbias = _f32()
	v_mod = _f32()
	v_spitch = _f32()
	v_spos = _f32()
	v_sinc = _f32()
	v_gain = _f32()
	for i in range(VOICES):
		v_noise[i] = 1 + i * 9973

func _init_instruments() -> void:
	instruments.clear()
	for i in range(MAX_INST):
		instruments.append(Instrument.new(i))

func get_instrument(id: int) -> Instrument:
	return instruments[id % MAX_INST]

func bake_procedural_sample(inst_id: int, kind: String = "kick") -> void:
	get_instrument(inst_id).load_sample_mono(Dsp.bake_oneshot(kind, 0.22), Dsp.SR)

func stop_all() -> void:
	for i in range(VOICES):
		v_on[i] = 0
		v_amp[i] = 0.0

func choke_channel(ch: int) -> void:
	if ch < 0 or ch >= CH:
		return
	v_on[ch] = 0
	v_amp[ch] = 0.0

func note_on(note: int, octave: int, instrument: int, fx1: String = "----", fx2: String = "----", velocity: float = 1.0, channel: int = -1) -> void:
	var vi: int = _alloc(channel)
	var inst: Instrument = get_instrument(instrument)
	var fx: Dictionary = Dsp.parse_fx_pair(fx1, fx2)
	var freq: float = Dsp.note_freq(note, octave)
	if fx.has("P"):
		var p: int = int(fx["P"])
		freq *= pow(2.0, float(p if p < 128 else p - 256) / 12.0)

	var use_samp: bool = inst.use_sample_source()
	v_on[vi] = 1
	v_inst[vi] = instrument % MAX_INST
	v_algo[vi] = inst.algo
	v_src[vi] = 1 if use_samp else 0
	v_phase[vi] = 0.0
	v_phase2[vi] = 0.0
	v_freq[vi] = freq
	v_freq2[vi] = freq * 1.005
	v_amp[vi] = 1.0
	v_age[vi] = 0.0
	v_filter[vi] = 0.0
	v_vel[vi] = clampf(velocity, 0.05, 1.0)
	v_fbias[vi] = 0.5
	v_mod[vi] = 1.0
	v_spitch[vi] = 1.0
	v_gain[vi] = inst.gain
	v_spos[vi] = 0.0
	v_sinc[vi] = 1.0
	v_noise[vi] = maxi(1, randi() % 2147483646)

	if fx.has("V"):
		v_vel[vi] = clampf(float(fx["V"]) / 128.0, 0.05, 1.5)
	if fx.has("F"):
		v_fbias[vi] = clampf(float(fx["F"]) / 255.0, 0.0, 1.0)
	if fx.has("M"):
		v_mod[vi] = clampf(float(fx["M"]) / 64.0, 0.1, 4.0)
	if fx.has("S"):
		v_spitch[vi] = clampf(float(fx["S"]) / 128.0, 0.3, 2.5)

	var base_decay := 0.3
	match int(v_algo[vi]):
		Instrument.Algo.KICK:
			v_freq[vi] = (160.0 + freq * 0.2) * v_spitch[vi]
			base_decay = 0.30
		Instrument.Algo.SNARE:
			base_decay = 0.16
		Instrument.Algo.HAT:
			base_decay = 0.045
		Instrument.Algo.CLAP:
			base_decay = 0.18
		Instrument.Algo.BASS:
			base_decay = 0.50
		Instrument.Algo.TEXTURE:
			base_decay = 0.90
		Instrument.Algo.FM:
			base_decay = 0.40
			v_freq2[vi] = freq * (2.0 + float(instrument % 5) * 0.5) * v_mod[vi]
		Instrument.Algo.NOISE:
			base_decay = 0.65
		_:
			base_decay = 0.35

	if fx.has("D"):
		v_decay[vi] = maxf(Dsp.MIN_DECAY, base_decay * (0.25 + float(fx["D"]) / 255.0 * 2.75))
	else:
		v_decay[vi] = maxf(Dsp.MIN_DECAY, base_decay)

	if use_samp and inst.pcm.size() > 0:
		var root_f: float = Dsp.midi_freq(inst.pcm_root)
		v_sinc[vi] = (freq / maxf(root_f, 1.0)) * (inst.pcm_rate / Dsp.SR)
		v_spos[vi] = float(maxi(0, inst.pcm_start))

func _alloc(channel: int) -> int:
	if channel >= 0 and channel < CH:
		v_on[channel] = 0
		return channel
	var idx: int = CH + (_pad_rr % PAD)
	_pad_rr = (_pad_rr + 1) % PAD
	v_on[idx] = 0
	return idx

func _process(_delta: float) -> void:
	if playback == null:
		_grab()
		return
	var need: int = playback.get_frames_available()
	if need <= 0:
		return
	_render(mini(need, MAX_FRAMES))

func _render(n: int) -> void:
	if n <= 0:
		return
	if _out.size() != n:
		_out.resize(n)
	var inv := Dsp.INV_SR
	var use_delay: bool = bus_delay_wet > 0.01 and delay_n > 1
	var use_dist: bool = bus_dist > 0.01
	var d_samp: int = 1
	if use_delay:
		d_samp = clampi(int(bus_delay_time * Dsp.SR), 1, delay_n - 1)

	for i in range(n):
		var mix := 0.0
		for vi in range(VOICES):
			if v_on[vi] == 0:
				continue
			v_age[vi] += inv
			var s: float
			if v_src[vi] == 1:
				s = _tick_sample(vi)
			else:
				s = _tick_synth(vi, inv)
			mix += s * v_gain[vi]

		if use_dist:
			mix = Dsp.soft_clip_drive(mix, bus_dist)
		if use_delay:
			var di: int = (delay_i - d_samp + delay_n) % delay_n
			var dl: float = delay_l[di]
			mix += dl * bus_delay_wet
			delay_l[delay_i] = clampf(mix + dl * bus_delay_fb, -1.2, 1.2)
			delay_r[delay_i] = delay_l[delay_i]
			delay_i = (delay_i + 1) % delay_n

		mix *= master_gain
		var peak: float = absf(mix)
		master_lim = maxf(peak, master_lim * 0.9993)
		if master_lim > master_ceiling:
			mix *= master_ceiling / master_lim
		_out[i] = Vector2(Dsp.soft_clip(mix), Dsp.soft_clip(mix))

	playback.push_buffer(_out)

func _tick_sample(vi: int) -> float:
	var inst: Instrument = instruments[v_inst[vi]]
	var data: PackedFloat32Array = inst.pcm
	var dsize: int = data.size()
	if dsize < 2:
		v_on[vi] = 0
		return 0.0
	var pos: int = int(v_spos[vi])
	var end_i: int = inst.pcm_end if inst.pcm_end > 0 else dsize
	end_i = mini(end_i, dsize)
	if pos < 0 or pos >= end_i:
		if inst.pcm_loop:
			v_spos[vi] = float(inst.pcm_start)
			return 0.0
		v_on[vi] = 0
		v_amp[vi] = 0.0
		return 0.0
	var s: float = data[pos] * v_vel[vi]
	v_spos[vi] += v_sinc[vi]
	v_amp[vi] = 1.0
	return s

func _tick_synth(vi: int, dt: float) -> float:
	var decay: float = maxf(v_decay[vi], Dsp.MIN_DECAY)
	var age: float = v_age[vi]
	var s := 0.0
	match int(v_algo[vi]):
		Instrument.Algo.KICK:
			var pe: float = Dsp.exp_env(age, 11.0 / decay)
			var f: float = 42.0 + (v_freq[vi] - 42.0) * pe
			v_phase[vi] = fmod(v_phase[vi] + f * dt, 1.0)
			s = sin(v_phase[vi] * Dsp.TWO_PI)
			if age < 0.0025:
				s += (randf() * 2.0 - 1.0) * 0.35 * (1.0 - age / 0.0025)
			v_amp[vi] = Dsp.exp_env(age, 5.2 / decay)
			s *= v_amp[vi] * v_vel[vi] * 0.9
		Instrument.Algo.SNARE:
			v_amp[vi] = Dsp.exp_env(age, 8.5 / decay)
			v_phase[vi] = fmod(v_phase[vi] + 175.0 * dt, 1.0)
			var nv: Vector2 = Dsp.noise(v_noise[vi])
			v_noise[vi] = int(nv.y)
			s = (sin(v_phase[vi] * Dsp.TWO_PI) * 0.28 + nv.x * 0.72) * v_amp[vi] * v_vel[vi]
		Instrument.Algo.HAT:
			v_amp[vi] = Dsp.exp_env(age, 28.0 / decay)
			var nh: Vector2 = Dsp.noise(v_noise[vi])
			v_noise[vi] = int(nh.y)
			v_filter[vi] = nh.x - v_filter[vi] * (0.88 - v_fbias[vi] * 0.1)
			s = v_filter[vi] * v_amp[vi] * v_vel[vi] * 0.48
		Instrument.Algo.CLAP:
			var env := 0.0
			if age < 0.01:
				env = 1.0 - age / 0.01
			elif age < 0.022:
				env = 0.6 * (1.0 - (age - 0.01) / 0.012)
			elif age < 0.045:
				env = 0.3 * (1.0 - (age - 0.022) / 0.023)
			else:
				env = exp(-(age - 0.045) * 18.0)
			v_amp[vi] = env
			var nc: Vector2 = Dsp.noise(v_noise[vi])
			v_noise[vi] = int(nc.y)
			s = nc.x * env * v_vel[vi] * 0.62
		Instrument.Algo.BASS:
			v_phase[vi] = fmod(v_phase[vi] + v_freq[vi] * dt, 1.0)
			var saw: float = v_phase[vi] * 2.0 - 1.0
			var fe: float = Dsp.exp_env(age, 3.2 / decay)
			var c: float = 0.06 + (0.12 + 0.5 * v_fbias[vi]) * fe
			v_filter[vi] = Dsp.lpf_step(v_filter[vi], saw, c)
			v_amp[vi] = Dsp.exp_env(age, 2.6 / decay)
			s = v_filter[vi] * v_amp[vi] * v_vel[vi] * 0.68
		Instrument.Algo.TEXTURE:
			v_phase[vi] = fmod(v_phase[vi] + v_freq[vi] * dt, 1.0)
			v_phase2[vi] = fmod(v_phase2[vi] + v_freq2[vi] * dt, 1.0)
			var m: float = v_phase[vi] + v_phase2[vi] - 1.0
			var fe2: float = Dsp.exp_env(age, 1.2 / decay)
			var c2: float = 0.03 + (0.08 + 0.35 * v_fbias[vi]) * fe2
			v_filter[vi] = Dsp.lpf_step(v_filter[vi], m, c2)
			v_amp[vi] = Dsp.exp_env(age, 1.6 / decay)
			s = v_filter[vi] * v_amp[vi] * v_vel[vi] * 0.5
		Instrument.Algo.FM:
			var mi: float = 2.4 * v_mod[vi] * Dsp.exp_env(age, 3.8)
			v_phase2[vi] = fmod(v_phase2[vi] + v_freq2[vi] * dt, 1.0)
			var mod: float = sin(v_phase2[vi] * Dsp.TWO_PI) * mi
			v_phase[vi] = fmod(v_phase[vi] + v_freq[vi] * (1.0 + mod * 0.16) * dt, 1.0)
			v_amp[vi] = Dsp.exp_env(age, 3.8 / decay)
			s = sin(v_phase[vi] * Dsp.TWO_PI) * v_amp[vi] * v_vel[vi] * 0.55
		Instrument.Algo.NOISE:
			v_amp[vi] = Dsp.exp_env(age, 2.4 / decay)
			var nn: Vector2 = Dsp.noise(v_noise[vi])
			v_noise[vi] = int(nn.y)
			var open: float = 0.08 + 0.7 * v_fbias[vi] * Dsp.exp_env(age, 2.8)
			v_filter[vi] = Dsp.lpf_step(v_filter[vi], nn.x, open)
			s = v_filter[vi] * v_amp[vi] * v_vel[vi] * 0.45
		_:
			v_amp[vi] = 0.0

	if v_amp[vi] < 0.001 and age > 0.02:
		v_on[vi] = 0
	return s
