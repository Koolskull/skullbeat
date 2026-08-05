class_name SbClock
extends RefCounted

## Minimal transport / step clock.
## Owns: bpm, playing, current step, phase.
## Emits logical steps; UI and audio react separately.

signal stepped(step: int)

var bpm: float = 128.0
var steps: int = 16
var playing: bool = false
var step: int = 0
var phase: float = 0.0  # seconds into current step

func step_duration() -> float:
	return 60.0 / bpm / 4.0

func play() -> void:
	if playing:
		return
	playing = true
	step = -1
	phase = 0.0
	_fire()

func stop() -> void:
	playing = false
	step = 0
	phase = 0.0

func set_bpm(v: float) -> void:
	bpm = clampf(v, 40.0, 300.0)

func nudge_bpm(d: float) -> void:
	set_bpm(bpm + d)

## Call once per visual frame with frame delta.
## Advances at most max_steps to avoid note storms after hitches.
func tick(delta: float, max_steps: int = 2) -> void:
	if not playing:
		return
	var dur: float = step_duration()
	phase += minf(delta, dur * 2.0)
	var n := 0
	while phase >= dur and n < max_steps:
		phase -= dur
		_fire()
		n += 1
	if phase > dur * 2.0:
		phase = 0.0

func _fire() -> void:
	step = (step + 1) % steps
	stepped.emit(step)
