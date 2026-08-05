extends Control

## ☦ SKULLBEAT
## K-OS III aligned drum machine + step sequencer + scene launcher
## Pixel aesthetic · no rounded corners · sharp borders · yellow accents

const TRACKS := 8
const STEPS := 16
const SCENES := 8

const TRACK_NAMES := ["KICK", "SNR", "CHH", "OHH", "CLP", "TOM", "RIM", "PRC"]

# Colors matching K-OS III
const COL_BG := Color("#000000")
const COL_PANEL := Color("#0a0a0a")
const COL_BORDER := Color("#333333")
const COL_INACTIVE := Color("#1a1a1a")
const COL_ACTIVE := Color("#ffff00")
const COL_PLAYHEAD := Color("#ff3333")
const COL_TEXT := Color("#aaaaaa")
const COL_TEXT_DIM := Color("#555555")
const COL_TEXT_BRIGHT := Color("#ffffff")

var bpm: float = 128.0
var is_playing: bool = false
var current_step: int = 0
var step_timer: float = 0.0

# pattern[track][step] = bool
var pattern: Array = []
# scenes[scene_idx] = deep copy of pattern
var scenes: Array = []
var active_scene: int = 0

# UI refs
var step_buttons: Array = []  # [track][step] -> Button
var pad_buttons: Array = []
var scene_buttons: Array = []
var play_btn: Button
var bpm_label: Label
var status_label: Label

# Audio players (one per track)
var players: Array = []

func _ready() -> void:
	# Init data
	for t in range(TRACKS):
		var row: Array = []
		for s in range(STEPS):
			row.append(false)
		pattern.append(row)
	
	for sc in range(SCENES):
		var copy: Array = []
		for t in range(TRACKS):
			var row: Array = []
			for s in range(STEPS):
				row.append(false)
			copy.append(row)
		scenes.append(copy)
	
	# Seed a basic kick/snare/hat pattern
	pattern[0][0] = true
	pattern[0][8] = true
	pattern[1][4] = true
	pattern[1][12] = true
	pattern[2][0] = true
	pattern[2][2] = true
	pattern[2][4] = true
	pattern[2][6] = true
	pattern[2][8] = true
	pattern[2][10] = true
	pattern[2][12] = true
	pattern[2][14] = true
	
	# Store seed into scene 0
	_store_to_scene(0)
	
	_build_ui()
	_setup_audio()
	_apply_pattern_to_ui()
	_highlight_active_scene()

func _process(delta: float) -> void:
	if not is_playing:
		return
	var step_duration = 60.0 / bpm / 4.0  # 16th notes
	step_timer += delta
	if step_timer >= step_duration:
		step_timer -= step_duration
		_advance_step()

func _advance_step() -> void:
	_update_playhead_visual(current_step, false)
	current_step = (current_step + 1) % STEPS
	_update_playhead_visual(current_step, true)
	for t in range(TRACKS):
		if pattern[t][current_step]:
			_play_track(t)

func _play_track(track: int) -> void:
	if track < players.size() and players[track]:
		# Will be silent until streams are assigned.
		# Next pass: procedural generators or sample bank.
		players[track].play()

func _setup_audio() -> void:
	for t in range(TRACKS):
		var p := AudioStreamPlayer.new()
		p.name = "Player_%d" % t
		add_child(p)
		players.append(p)
		# TODO: assign AudioStreamWAV or use AudioStreamGenerator for basic synth drums

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)
	
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)
	
	# === HEADER ===
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	
	var title := Label.new()
	title.text = "☦ SKULLBEAT"
	title.add_theme_color_override("font_color", COL_TEXT_BRIGHT)
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	
	var subtitle := Label.new()
	subtitle.text = "· K-OS III"
	subtitle.add_theme_color_override("font_color", COL_TEXT_DIM)
	subtitle.add_theme_font_size_override("font_size", 12)
	header.add_child(subtitle)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	bpm_label = Label.new()
	bpm_label.text = "BPM %d" % int(bpm)
	bpm_label.add_theme_color_override("font_color", COL_ACTIVE)
	bpm_label.add_theme_font_size_override("font_size", 14)
	header.add_child(bpm_label)
	
	play_btn = _make_button("PLAY", 70)
	play_btn.pressed.connect(_on_play_pressed)
	header.add_child(play_btn)
	
	var stop_btn := _make_button("STOP", 60)
	stop_btn.pressed.connect(_on_stop_pressed)
	header.add_child(stop_btn)
	
	var clear_btn := _make_button("CLEAR", 60)
	clear_btn.pressed.connect(_on_clear_pressed)
	header.add_child(clear_btn)
	
	var bpm_down := _make_button("-", 36)
	bpm_down.pressed.connect(func(): _change_bpm(-1))
	header.add_child(bpm_down)
	var bpm_up := _make_button("+", 36)
	bpm_up.pressed.connect(func(): _change_bpm(1))
	header.add_child(bpm_up)
	
	# === MAIN AREA ===
	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 8)
	root.add_child(main_row)
	
	# LEFT: Live Pads
	var pads_col := VBoxContainer.new()
	pads_col.custom_minimum_size.x = 110
	pads_col.add_theme_constant_override("separation", 4)
	main_row.add_child(pads_col)
	
	var pads_label := Label.new()
	pads_label.text = "PADS"
	pads_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	pads_label.add_theme_font_size_override("font_size", 10)
	pads_col.add_child(pads_label)
	
	for t in range(TRACKS):
		var pad := _make_button(TRACK_NAMES[t], 100)
		pad.custom_minimum_size.y = 36
		var track_idx = t
		pad.pressed.connect(func(): _on_pad_pressed(track_idx))
		pads_col.add_child(pad)
		pad_buttons.append(pad)
	
	# CENTER: Sequencer grid
	var seq_panel := PanelContainer.new()
	seq_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seq_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_panel(seq_panel)
	main_row.add_child(seq_panel)
	
	var seq_inner := VBoxContainer.new()
	seq_inner.add_theme_constant_override("separation", 2)
	seq_panel.add_child(seq_inner)
	
	var seq_header := Label.new()
	seq_header.text = "SEQUENCER  ·  16 STEPS"
	seq_header.add_theme_color_override("font_color", COL_TEXT_DIM)
	seq_header.add_theme_font_size_override("font_size", 10)
	seq_inner.add_child(seq_header)
	
	var grid := GridContainer.new()
	grid.columns = STEPS + 1
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	seq_inner.add_child(grid)
	
	var empty := Label.new()
	empty.custom_minimum_size = Vector2(48, 20)
	grid.add_child(empty)
	for s in range(STEPS):
		var num := Label.new()
		num.text = str(s + 1)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_color_override("font_color", COL_TEXT_DIM)
		num.add_theme_font_size_override("font_size", 9)
		num.custom_minimum_size = Vector2(28, 20)
		grid.add_child(num)
	
	step_buttons.clear()
	for t in range(TRACKS):
		var name_lbl := Label.new()
		name_lbl.text = TRACK_NAMES[t]
		name_lbl.add_theme_color_override("font_color", COL_TEXT)
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.custom_minimum_size = Vector2(48, 28)
		grid.add_child(name_lbl)
		
		var row_btns: Array = []
		for s in range(STEPS):
			var btn := Button.new()
			btn.toggle_mode = true
			btn.custom_minimum_size = Vector2(28, 28)
			btn.focus_mode = Control.FOCUS_NONE
			_style_step_button(btn, false)
			var tt = t
			var ss = s
			btn.toggled.connect(func(pressed: bool): _on_step_toggled(tt, ss, pressed))
			grid.add_child(btn)
			row_btns.append(btn)
		step_buttons.append(row_btns)
	
	# RIGHT: Scene launcher
	var scenes_col := VBoxContainer.new()
	scenes_col.custom_minimum_size.x = 100
	scenes_col.add_theme_constant_override("separation", 4)
	main_row.add_child(scenes_col)
	
	var scenes_label := Label.new()
	scenes_label.text = "SCENES"
	scenes_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	scenes_label.add_theme_font_size_override("font_size", 10)
	scenes_col.add_child(scenes_label)
	
	for sc in range(SCENES):
		var btn := _make_button("S%d" % (sc + 1), 90)
		btn.custom_minimum_size.y = 32
		var sc_idx = sc
		btn.pressed.connect(func(): _on_scene_pressed(sc_idx))
		scenes_col.add_child(btn)
		scene_buttons.append(btn)
	
	var store_btn := _make_button("STORE", 90)
	store_btn.pressed.connect(_on_store_pressed)
	scenes_col.add_child(store_btn)
	
	# Status bar
	status_label = Label.new()
	status_label.text = "READY · TAP STEPS · PADS LIVE · STORE → ACTIVE SCENE · TAP SCENE TO LOAD"
	status_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	status_label.add_theme_font_size_override("font_size", 11)
	root.add_child(status_label)

func _make_button(text: String, min_w: float = 60) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 32)
	b.focus_mode = Control.FOCUS_NONE
	_style_button(b)
	return b

func _style_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_INACTIVE
	normal.border_color = COL_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	
	var hover := normal.duplicate()
	hover.bg_color = Color("#222222")
	
	var pressed := normal.duplicate()
	pressed.bg_color = COL_ACTIVE
	pressed.border_color = COL_ACTIVE
	
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_TEXT_BRIGHT)
	b.add_theme_color_override("font_pressed_color", Color("#000000"))
	b.add_theme_font_size_override("font_size", 11)

func _style_step_button(b: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	if active:
		sb.bg_color = COL_ACTIVE
		sb.border_color = COL_ACTIVE
	else:
		sb.bg_color = COL_INACTIVE
		sb.border_color = COL_BORDER
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)

func _style_panel(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)

func _apply_pattern_to_ui() -> void:
	for t in range(TRACKS):
		for s in range(STEPS):
			var btn: Button = step_buttons[t][s]
			btn.set_pressed_no_signal(pattern[t][s])
			_style_step_button(btn, pattern[t][s])

func _update_playhead_visual(step: int, on: bool) -> void:
	for t in range(TRACKS):
		var btn: Button = step_buttons[t][step]
		if on:
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(0)
			sb.set_border_width_all(2)
			sb.border_color = COL_PLAYHEAD
			if pattern[t][step]:
				sb.bg_color = COL_ACTIVE
			else:
				sb.bg_color = Color("#331111")
			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)
		else:
			_style_step_button(btn, pattern[t][step])

func _highlight_active_scene() -> void:
	for i in range(SCENES):
		var b: Button = scene_buttons[i]
		if i == active_scene:
			var sb := StyleBoxFlat.new()
			sb.bg_color = COL_ACTIVE
			sb.border_color = COL_ACTIVE
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(0)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_color_override("font_color", Color("#000000"))
		else:
			_style_button(b)

func _on_step_toggled(track: int, step: int, pressed: bool) -> void:
	pattern[track][step] = pressed
	_style_step_button(step_buttons[track][step], pressed)
	status_label.text = "T%d S%d %s" % [track + 1, step + 1, "ON" if pressed else "OFF"]

func _on_pad_pressed(track: int) -> void:
	_play_track(track)
	status_label.text = "PAD %s" % TRACK_NAMES[track]
	var btn: Button = pad_buttons[track]
	var flash := StyleBoxFlat.new()
	flash.bg_color = COL_ACTIVE
	flash.border_color = COL_ACTIVE
	flash.set_border_width_all(1)
	flash.set_corner_radius_all(0)
	btn.add_theme_stylebox_override("normal", flash)
	await get_tree().create_timer(0.08).timeout
	_style_button(btn)

func _on_scene_pressed(sc: int) -> void:
	active_scene = sc
	for t in range(TRACKS):
		for s in range(STEPS):
			pattern[t][s] = scenes[sc][t][s]
	_apply_pattern_to_ui()
	_highlight_active_scene()
	status_label.text = "LOADED SCENE %d" % (sc + 1)

func _on_store_pressed() -> void:
	_store_to_scene(active_scene)
	status_label.text = "STORED → SCENE %d" % (active_scene + 1)

func _store_to_scene(sc: int) -> void:
	if sc < 0 or sc >= SCENES:
		return
	for t in range(TRACKS):
		for s in range(STEPS):
			scenes[sc][t][s] = pattern[t][s]

func _on_play_pressed() -> void:
	if is_playing:
		return
	is_playing = true
	current_step = -1
	step_timer = 0.0
	play_btn.text = "PLAYING"
	status_label.text = "PLAYING @ %d BPM" % int(bpm)
	_advance_step()

func _on_stop_pressed() -> void:
	is_playing = false
	_update_playhead_visual(current_step, false)
	current_step = 0
	play_btn.text = "PLAY"
	status_label.text = "STOPPED"

func _on_clear_pressed() -> void:
	for t in range(TRACKS):
		for s in range(STEPS):
			pattern[t][s] = false
	_apply_pattern_to_ui()
	status_label.text = "CLEARED"

func _change_bpm(delta: int) -> void:
	bpm = clamp(bpm + delta, 40.0, 300.0)
	bpm_label.text = "BPM %d" % int(bpm)
	if is_playing:
		status_label.text = "PLAYING @ %d BPM" % int(bpm)
