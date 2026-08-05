class_name Instrument
extends RefCounted

## Super-instrument for Skullbeat
## - Synthesis layer (existing algorithms)
## - Waveform sample player layer
## - 3-slot stereo FX rack (distortion, chorus, plate reverb, delay)
## - Mandatory EQ + compressor/limiter per instrument
## Master bus also has dedicated EQ + limiter (handled in AudioEngine)

enum SynthAlgo {
	NONE,
	KICK,
	SNARE,
	HAT,
	CLAP,
	BASS,
	TEXTURE,
	FM_METAL,
	NOISE_SWEEP
}

enum FxType {
	OFF,
	DISTORTION,
	CHORUS,
	PLATE_REVERB,
	DELAY
}

var id: int = 0
var name: String = "INST"

# --- Synth layer ---
var synth_enabled: bool = true
var synth_algo: int = SynthAlgo.KICK
var synth_gain: float = 1.0

# --- Sample layer ---
var sample_enabled: bool = false
var sample_data: PackedFloat32Array = PackedFloat32Array()  # mono -1..1
var sample_rate: float = 44100.0
var sample_root_note: int = 60          # MIDI note that plays at original rate
var sample_start: int = 0
var sample_end: int = 0                 # exclusive
var sample_loop: bool = false
var sample_gain: float = 1.0

# --- 3-slot FX rack (stereo) ---
# Each slot: { type: FxType, wet: 0-1, param_a, param_b }
var fx_slots: Array = [
	{"type": FxType.OFF, "wet": 0.0, "a": 0.5, "b": 0.5},
	{"type": FxType.OFF, "wet": 0.0, "a": 0.5, "b": 0.5},
	{"type": FxType.OFF, "wet": 0.0, "a": 0.5, "b": 0.5}
]

# --- Mandatory EQ (3-band for speed) ---
var eq_low_gain: float = 1.0    # ~0.25–4.0 linear
var eq_mid_gain: float = 1.0
var eq_high_gain: float = 1.0
var eq_low_freq: float = 120.0
var eq_high_freq: float = 4000.0

# --- Mandatory compressor / limiter ---
var comp_threshold: float = 0.7   # 0-1
var comp_ratio: float = 4.0
var comp_attack: float = 0.005
var comp_release: float = 0.08
var limiter_ceiling: float = 0.95

func _init(p_id: int = 0) -> void:
	id = p_id
	name = "%02X" % p_id
	synth_algo = _default_algo_for_id(p_id)

func _default_algo_for_id(i: int) -> int:
	var n = i % 32
	if n <= 4: return SynthAlgo.KICK
	elif n <= 8: return SynthAlgo.SNARE
	elif n <= 11: return SynthAlgo.HAT
	elif n <= 13: return SynthAlgo.CLAP
	elif n <= 18: return SynthAlgo.BASS
	elif n <= 24: return SynthAlgo.TEXTURE
	elif n <= 28: return SynthAlgo.FM_METAL
	else: return SynthAlgo.NOISE_SWEEP

func set_fx_slot(slot: int, type: int, wet: float = 0.4, a: float = 0.5, b: float = 0.5) -> void:
	if slot < 0 or slot > 2: return
	fx_slots[slot] = {"type": type, "wet": clampf(wet, 0.0, 1.0), "a": a, "b": b}

func has_sample() -> bool:
	return sample_enabled and sample_data.size() > 16

func load_sample_mono(data: PackedFloat32Array, rate: float = 44100.0) -> void:
	sample_data = data
	sample_rate = rate
	sample_start = 0
	sample_end = data.size()
	sample_enabled = true
