class_name Instrument
extends RefCounted

## Data-only super-instrument.
## Render policy lives in SynthEngine — this never does DSP.
##
## Layers (compose, don't stack cost unless enabled):
##   sample  — optional PCM one-shot / loop
##   synth   — optional algo (only if sample off or forced)
##   fx[3]   — rack slots (OFF = free)
##   gain    — single output scale

enum Algo {
	NONE,
	KICK,
	SNARE,
	HAT,
	CLAP,
	BASS,
	TEXTURE,
	FM,
	NOISE
}

enum Fx {
	OFF,
	DIST,
	CHORUS,
	DELAY,
	REVERB
}

var id: int = 0
var name: String = "00"

# source select: sample wins if present + enabled
var synth_on: bool = true
var sample_on: bool = false
var algo: int = Algo.KICK
var gain: float = 1.0

# sample layer
var pcm: PackedFloat32Array = PackedFloat32Array()
var pcm_rate: float = 44100.0
var pcm_root: int = 60
var pcm_start: int = 0
var pcm_end: int = 0
var pcm_loop: bool = false

# 3-slot FX rack (wet==0 or type OFF → skipped in engine)
var fx_type: Array = [Fx.OFF, Fx.OFF, Fx.OFF]
var fx_wet: Array = [0.0, 0.0, 0.0]
var fx_a: Array = [0.5, 0.5, 0.5]
var fx_b: Array = [0.5, 0.5, 0.5]

func _init(p_id: int = 0) -> void:
	id = p_id
	name = "%02X" % p_id
	algo = _default_algo(p_id)

func _default_algo(i: int) -> int:
	var n: int = i % 32
	if n <= 4:
		return Algo.KICK
	if n <= 8:
		return Algo.SNARE
	if n <= 11:
		return Algo.HAT
	if n <= 13:
		return Algo.CLAP
	if n <= 18:
		return Algo.BASS
	if n <= 24:
		return Algo.TEXTURE
	if n <= 28:
		return Algo.FM
	return Algo.NOISE

func has_sample() -> bool:
	return sample_on and pcm.size() > 16

## Prefer sample when loaded — engine uses one source only
func use_sample_source() -> bool:
	return has_sample()

func use_synth_source() -> bool:
	return synth_on and not use_sample_source()

func load_sample_mono(data: PackedFloat32Array, rate: float = 44100.0) -> void:
	pcm = data
	pcm_rate = rate
	pcm_start = 0
	pcm_end = data.size()
	sample_on = true
	synth_on = false

func set_fx(slot: int, type: int, wet: float = 0.3, a: float = 0.5, b: float = 0.5) -> void:
	if slot < 0 or slot > 2:
		return
	fx_type[slot] = type
	fx_wet[slot] = clampf(wet, 0.0, 1.0)
	fx_a[slot] = a
	fx_b[slot] = b

# aliases so sample_import / older code still works
var sample_enabled: bool:
	get:
		return sample_on
	set(v):
		sample_on = v

var synth_enabled: bool:
	get:
		return synth_on
	set(v):
		synth_on = v
var sample_data: PackedFloat32Array:
	get:
		return pcm
	set(v):
		pcm = v
var sample_rate: float:
	get:
		return pcm_rate
	set(v):
		pcm_rate = v
var sample_root_note: int:
	get:
		return pcm_root
	set(v):
		pcm_root = v
var sample_start: int:
	get:
		return pcm_start
	set(v):
		pcm_start = v
var sample_end: int:
	get:
		return pcm_end
	set(v):
		pcm_end = v
var sample_loop: bool:
	get:
		return pcm_loop
	set(v):
		pcm_loop = v
var sample_gain: float:
	get:
		return gain
	set(v):
		gain = v
var synth_gain: float:
	get:
		return gain
	set(v):
		gain = v
var synth_algo: int:
	get:
		return algo
	set(v):
		algo = v
