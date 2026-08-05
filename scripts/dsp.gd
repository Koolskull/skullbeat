class_name Dsp
extends RefCounted

## Minimal pure DSP tools. No state. No nodes. Call from render path only.
## Layers above own state; this file only does math.

const SR := 22050.0
const INV_SR := 1.0 / 22050.0
const TWO_PI := PI * 2.0
const MIN_DECAY := 0.02

# --- pitch ---

static func note_freq(note: int, octave: int) -> float:
	note = clampi(note, 0, 11)
	octave = clampi(octave, 0, 8)
	return 440.0 * pow(2.0, float((octave + 1) * 12 + note - 69) / 12.0)

static func midi_freq(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)

# --- envelopes ---

static func exp_env(age: float, rate: float) -> float:
	return exp(-age * rate)

# --- noise (xorshift state in/out) ---

static func noise(state: int) -> Vector2:
	var ns: int = state
	ns ^= (ns << 13)
	ns ^= (ns >> 17)
	ns ^= (ns << 5)
	if ns == 0:
		ns = 1
	var sample: float = float(ns % 10000) / 5000.0 - 1.0
	return Vector2(sample, float(ns))

# --- soft clip (cheap, no tanh) ---

static func soft_clip(x: float) -> float:
	if x > 1.0:
		return 1.0
	if x < -1.0:
		return -1.0
	return x

static func soft_clip_drive(x: float, drive: float) -> float:
	x *= 1.0 + drive * 3.0
	if x > 1.0:
		return 1.0 - 0.5 / (x + 1.0)
	if x < -1.0:
		return -1.0 + 0.5 / (-x + 1.0)
	return x

# --- 1-pole LPF step: y += c * (x - y) ---

static func lpf_step(y: float, x: float, cutoff: float) -> float:
	return y + cutoff * (x - y)

# --- tracker FX parse (single letter + 2 hex) ---

static func parse_fx(fx: String, out: Dictionary) -> void:
	if fx.length() < 3 or fx.begins_with("-"):
		return
	var hex := fx.substr(1, 2)
	if not hex.is_valid_hex_number():
		return
	out[fx.substr(0, 1).to_upper()] = hex.hex_to_int()

static func parse_fx_pair(fx1: String, fx2: String) -> Dictionary:
	var out := {}
	parse_fx(fx1, out)
	parse_fx(fx2, out)
	return out

# --- bake short one-shot PCM (offline, not in render) ---

static func bake_oneshot(kind: String, seconds: float = 0.25) -> PackedFloat32Array:
	var n: int = int(SR * seconds)
	var data := PackedFloat32Array()
	data.resize(n)
	for i in range(n):
		var t: float = float(i) * INV_SR
		var s := 0.0
		match kind:
			"kick":
				var f: float = 150.0 * exp(-t * 20.0) + 40.0
				s = sin(TWO_PI * f * t) * exp(-t * 8.0)
			"snare":
				s = (sin(TWO_PI * 180.0 * t) * 0.3 + (randf() * 2.0 - 1.0) * 0.7) * exp(-t * 14.0)
			"hat":
				s = (randf() * 2.0 - 1.0) * exp(-t * 42.0)
			_:
				s = sin(TWO_PI * 220.0 * t) * exp(-t * 6.0)
		data[i] = s
	return data
