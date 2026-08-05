class_name LiveFx
extends RefCounted

## Live performance bus state. Cheap flags the engine samples each block.
## UI only writes; SynthEngine only reads.

signal changed

# momentary / toggles
var glitch_on: bool = false
var retrig_on: bool = false
var stutter_on: bool = false
var kill_on: bool = false

# continuous 0..1
var glitch_amt: float = 0.0     # bitcrush / rate reduce
var stutter_rate: float = 0.25  # restarts per step fraction
var xy_a: Vector2 = Vector2(0.5, 0.5)  # pad A: X=filter bias, Y=drive
var xy_b: Vector2 = Vector2(0.0, 0.0)  # pad B: X=delay wet, Y=delay time

# clip launcher
var active_bank: int = 0
var muted: Array = [false, false, false, false]  # per channel mute

func reset() -> void:
	glitch_on = false
	retrig_on = false
	stutter_on = false
	kill_on = false
	glitch_amt = 0.0
	stutter_rate = 0.25
	xy_a = Vector2(0.5, 0.5)
	xy_b = Vector2(0.0, 0.0)
	active_bank = 0
	muted = [false, false, false, false]
	changed.emit()

func toggle_glitch() -> void:
	glitch_on = not glitch_on
	if glitch_on and glitch_amt < 0.2:
		glitch_amt = 0.55
	changed.emit()

func toggle_retrig() -> void:
	retrig_on = not retrig_on
	changed.emit()

func toggle_stutter() -> void:
	stutter_on = not stutter_on
	changed.emit()

func pulse_kill() -> void:
	kill_on = true
	changed.emit()

func clear_kill() -> void:
	kill_on = false

func set_xy_a(v: Vector2) -> void:
	xy_a = v.clamp(Vector2.ZERO, Vector2.ONE)
	changed.emit()

func set_xy_b(v: Vector2) -> void:
	xy_b = v.clamp(Vector2.ZERO, Vector2.ONE)
	changed.emit()

func set_bank(i: int) -> void:
	active_bank = clampi(i, 0, 7)
	changed.emit()

func toggle_mute(ch: int) -> void:
	if ch < 0 or ch >= muted.size():
		return
	muted[ch] = not muted[ch]
	changed.emit()

func is_muted(ch: int) -> bool:
	if ch < 0 or ch >= muted.size():
		return false
	return muted[ch]
