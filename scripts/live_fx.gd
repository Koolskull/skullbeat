class_name LiveFx
extends RefCounted

## Live performance + mixer levels. UI writes; engine reads.

signal changed

var glitch_on: bool = false
var retrig_on: bool = false
var stutter_on: bool = false
var kill_on: bool = false

var glitch_amt: float = 0.0
var stutter_rate: float = 0.25
var xy_a: Vector2 = Vector2(0.5, 0.5)
var xy_b: Vector2 = Vector2(0.0, 0.0)

var active_bank: int = 0
var muted: Array = [false, false, false, false]

# mixer — linear gains 0..1.5 (1.0 = unity)
var ch_level: Array = [1.0, 1.0, 1.0, 1.0]
var master_level: float = 1.0

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
	ch_level = [1.0, 1.0, 1.0, 1.0]
	master_level = 1.0
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

func set_ch_level(ch: int, v: float) -> void:
	if ch < 0 or ch >= ch_level.size():
		return
	ch_level[ch] = clampf(v, 0.0, 1.5)
	changed.emit()

func get_ch_level(ch: int) -> float:
	if ch < 0 or ch >= ch_level.size():
		return 1.0
	return float(ch_level[ch])

func set_master_level(v: float) -> void:
	master_level = clampf(v, 0.0, 1.5)
	changed.emit()

func level_for_channel(ch: int) -> float:
	if is_muted(ch):
		return 0.0
	return get_ch_level(ch) * master_level
