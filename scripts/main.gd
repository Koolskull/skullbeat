extends Control

## SKULLBEAT UI shell
## Owns: pattern data, tracker view, input
## Does NOT own: DSP, clock math, sample parse
## Layers: SbClock → note events → SynthEngine → Dsp

const CHANNELS := 4
const STEPS := 16
const TABLE_STEPS := 16
const NOTE_NAMES := ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]

const KOALA_PADS := {
	KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3,
	KEY_Q: 4, KEY_W: 5, KEY_E: 6, KEY_R: 7,
	KEY_A: 8, KEY_S: 9, KEY_D: 10, KEY_F: 11,
	KEY_Z: 12, KEY_X: 13, KEY_C: 14, KEY_V: 15
}

const COL_BG := Color("#000000")
const COL_PANEL := Color("#0a0a0a")
const COL_BORDER := Color("#333333")
const COL_ROW_ALT := Color("#0f0f0f")
const COL_ACTIVE := Color("#ffff00")
const COL_PLAYHEAD := Color("#ff3333")
const COL_TEXT := Color("#cccccc")
const COL_TEXT_DIM := Color("#666666")
const COL_TEXT_BRIGHT := Color("#ffffff")
const COL_REC := Color("#ff2222")

var clock: SbClock
var synth: SynthEngine
var sample_import: SampleImport
var auv3: AUv3Host

var phrases: Array = []
var tables: Array = []
var channel_view_mode: Array = []

var is_recording := false
var selected_ch := 0
var selected_step := 0
var selected_col := 0
var drag_start_y := 0.0
var drag_start_value := 0
var is_dragging := false
var visible_rows := 16
var prev_step := -1

var header_bar: HBoxContainer
var channel_containers: Array = []
var step_labels: Array = []
var status_label: Label
var rec_btn: Button
var play_btn: Button
var bpm_label: Label

func _ready() -> void:
	clock = SbClock.new()
	clock.steps = STEPS
	clock.stepped.connect(_on_clock_step)

	synth = SynthEngine.new()
	add_child(synth)
	auv3 = AUv3Host.new()
	add_child(auv3)
	sample_import = SampleImport.new()
	sample_import.setup(self, synth)
	sample_import.import_finished.connect(_on_import_finished)

	synth.bake_procedural_sample(1, "kick")
	synth.bake_procedural_sample(6, "snare")
	synth.bake_procedural_sample(10, "hat")

	_init_data()
	_build_ui()
	_recalc_layout()
	get_viewport().size_changed.connect(_recalc_layout)

func _init_data() -> void:
	for ch in range(CHANNELS):
		var phrase: Array = []
		for s in range(STEPS):
			phrase.append(_empty_step())
		phrases.append(phrase)
		var table: Array = []
		for r in range(TABLE_STEPS):
			table.append({"cmd1": "----", "val1": "00", "cmd2": "----", "val2": "00"})
		tables.append(table)
		channel_view_mode.append(0)

	# demo groove — short samples + one synth line
	phrases[0][0]  = _step(0, 2, 1, "V90", "D40")
	phrases[0][8]  = _step(0, 2, 1, "VA0", "D90")
	phrases[1][4]  = _step(0, 3, 6, "V80", "D50")
	phrases[1][12] = _step(0, 3, 6, "V60", "D30")
	phrases[2][0]  = _step(0, 5, 10, "V70", "D20")
	phrases[2][2]  = _step(0, 5, 10, "V50", "D10")
	phrases[2][4]  = _step(0, 5, 10, "V70", "D20")
	phrases[2][6]  = _step(0, 5, 10, "V40", "D08")
	phrases[2][8]  = _step(0, 5, 10, "V70", "D20")
	phrases[2][10] = _step(0, 5, 10, "V50", "D10")
	phrases[2][12] = _step(0, 5, 10, "V70", "D20")
	phrases[2][14] = _step(0, 5, 10, "V30", "D05")
	phrases[3][0]  = _step(0, 2, 16, "V88", "FA0")
	phrases[3][8]  = _step(7, 2, 16, "V70", "F40")

func _empty_step() -> Dictionary:
	return {"note": -1, "oct": 4, "inst": 0, "fx1": "----", "fx2": "----"}

func _step(note: int, oct: int, inst: int, fx1: String, fx2: String) -> Dictionary:
	return {"note": note, "oct": oct, "inst": inst, "fx1": fx1, "fx2": fx2}

func _process(delta: float) -> void:
	clock.tick(delta, 2)

func _on_clock_step(step: int) -> void:
	var old: int = prev_step
	prev_step = step
	for ch in range(CHANNELS):
		var d = phrases[ch][step]
		if d.note >= 0:
			synth.note_on(d.note, d.oct, d.inst, d.fx1, d.fx2, 1.0, ch)
	_paint_playhead(old, step)

func _import_target_inst() -> int:
	if channel_view_mode[selected_ch] == 0:
		var d = phrases[selected_ch][selected_step]
		if d.note >= 0 and d.inst > 0:
			return d.inst
	return clampi(selected_ch + 1, 1, 63)

func _do_import() -> void:
	var tid = _import_target_inst()
	sample_import.set_target_instrument(tid)
	status_label.text = "IMPORT -> INST %02X" % tid
	sample_import.open_file_picker()

func _do_audioshare() -> void:
	status_label.text = "AUDIOSHARE → export WAV → IMP"
	SampleImport.open_audioshare()

func _on_import_finished(success: bool, message: String, inst_id: int) -> void:
	status_label.text = message
	if success:
		synth.note_on(0, 4, inst_id, "V90", "----", 1.0, -1)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key = event.keycode
	if KOALA_PADS.has(key):
		_on_pad(KOALA_PADS[key])
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_SPACE:
			if clock.playing:
				_stop()
			else:
				_play()
			get_viewport().set_input_as_handled()
		KEY_0:
			_toggle_rec()
			get_viewport().set_input_as_handled()
		KEY_I:
			_do_import()
			get_viewport().set_input_as_handled()
		KEY_U:
			_do_audioshare()
			get_viewport().set_input_as_handled()
		KEY_EQUAL, KEY_KP_ADD:
			_change_bpm(1)
			get_viewport().set_input_as_handled()
		KEY_MINUS, KEY_KP_SUBTRACT:
			_change_bpm(-1)
			get_viewport().set_input_as_handled()
		KEY_UP:
			selected_step = maxi(0, selected_step - 1)
			_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			selected_step = mini(STEPS - 1, selected_step + 1)
			_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			if selected_col > 0:
				selected_col -= 1
			else:
				selected_ch = maxi(0, selected_ch - 1)
				selected_col = 4
			_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if selected_col < 4:
				selected_col += 1
			else:
				selected_ch = mini(CHANNELS - 1, selected_ch + 1)
				selected_col = 0
			_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_BACKSPACE, KEY_DELETE:
			if channel_view_mode[selected_ch] == 0:
				phrases[selected_ch][selected_step] = _empty_step()
				_refresh_ch(selected_ch)
			get_viewport().set_input_as_handled()

func _on_pad(pad_idx: int) -> void:
	var inst: int = pad_idx + 1
	var note: int = pad_idx % 12
	var oct: int = 2 + int(float(pad_idx) / 8.0)
	synth.note_on(note, oct, inst, "----", "----", 1.0, -1)
	status_label.text = "PAD %02d → INST %02X" % [pad_idx + 1, inst]
	if is_recording and channel_view_mode[selected_ch] == 0:
		phrases[selected_ch][selected_step] = _step(note, oct, inst, "V80", "----")
		_refresh_ch(selected_ch)
		selected_step = (selected_step + 1) % STEPS
		_refresh_all()

func _play() -> void:
	prev_step = -1
	play_btn.text = "PLAY*"
	clock.play()

func _stop() -> void:
	clock.stop()
	play_btn.text = "PLAY"
	synth.stop_all()
	prev_step = -1
	_refresh_all()

func _toggle_rec() -> void:
	is_recording = not is_recording
	if is_recording:
		rec_btn.text = "REC*"
		_style_btn(rec_btn, true)
	else:
		rec_btn.text = "REC"
		_style_btn(rec_btn, false)
		is_dragging = false

func _change_bpm(d: int) -> void:
	clock.nudge_bpm(float(d))
	bpm_label.text = "BPM %d" % int(clock.bpm)

# ─── UI ───────────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	root.offset_left = 4
	root.offset_top = 4
	root.offset_right = -4
	root.offset_bottom = -4
	add_child(root)

	header_bar = HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", 6)
	root.add_child(header_bar)

	var title := Label.new()
	title.text = "SKULLBEAT"
	title.add_theme_color_override("font_color", COL_TEXT_BRIGHT)
	title.add_theme_font_size_override("font_size", 16)
	header_bar.add_child(title)

	var mode := Label.new()
	mode.text = "MODULAR · MIN"
	mode.add_theme_color_override("font_color", COL_TEXT_DIM)
	mode.add_theme_font_size_override("font_size", 11)
	header_bar.add_child(mode)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(spacer)

	bpm_label = Label.new()
	bpm_label.text = "BPM %d" % int(clock.bpm)
	bpm_label.add_theme_color_override("font_color", COL_ACTIVE)
	bpm_label.add_theme_font_size_override("font_size", 13)
	header_bar.add_child(bpm_label)

	var bd := _btn("-")
	bd.pressed.connect(func(): _change_bpm(-1))
	header_bar.add_child(bd)
	var bu := _btn("+")
	bu.pressed.connect(func(): _change_bpm(1))
	header_bar.add_child(bu)
	var imp := _btn("IMP")
	imp.pressed.connect(_do_import)
	header_bar.add_child(imp)
	var ash := _btn("AS")
	ash.pressed.connect(_do_audioshare)
	header_bar.add_child(ash)
	rec_btn = _btn("REC")
	rec_btn.pressed.connect(_toggle_rec)
	header_bar.add_child(rec_btn)
	play_btn = _btn("PLAY")
	play_btn.pressed.connect(func():
		if clock.playing:
			_stop()
		else:
			_play()
	)
	header_bar.add_child(play_btn)
	var st := _btn("STOP")
	st.pressed.connect(_stop)
	header_bar.add_child(st)

	var channels_row := HBoxContainer.new()
	channels_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	channels_row.add_theme_constant_override("separation", 3)
	root.add_child(channels_row)

	channel_containers.clear()
	step_labels.clear()
	for ch in range(CHANNELS):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_style_panel(panel)
		channels_row.add_child(panel)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 0)
		panel.add_child(vbox)
		var hdr := Button.new()
		hdr.text = "CH%d  PHRASE" % (ch + 1)
		hdr.focus_mode = Control.FOCUS_NONE
		hdr.custom_minimum_size.y = 22
		_style_hdr(hdr)
		var ch_i = ch
		hdr.pressed.connect(func(): _toggle_view(ch_i))
		vbox.add_child(hdr)
		var col_hdr := HBoxContainer.new()
		col_hdr.add_theme_constant_override("separation", 0)
		vbox.add_child(col_hdr)
		for name in ["NT", "OC", "IN", "FX1", "FX2"]:
			var l := Label.new()
			l.text = name
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_color_override("font_color", COL_TEXT_DIM)
			l.add_theme_font_size_override("font_size", 9)
			col_hdr.add_child(l)
		var steps_box := VBoxContainer.new()
		steps_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		steps_box.add_theme_constant_override("separation", 0)
		vbox.add_child(steps_box)
		channel_containers.append({"header": hdr, "steps_box": steps_box})
		step_labels.append([])

	status_label = Label.new()
	status_label.text = "SPACE play · pads live · IMP sample · REC drag-edit"
	status_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	status_label.add_theme_font_size_override("font_size", 10)
	root.add_child(status_label)

func _recalc_layout() -> void:
	var h: float = size.y - 80.0
	if h < 100.0:
		h = 400.0
	visible_rows = clampi(int(h / 18.0), 8, STEPS)
	_rebuild_rows()

func _rebuild_rows() -> void:
	for ch in range(CHANNELS):
		var box: VBoxContainer = channel_containers[ch]["steps_box"]
		for c in box.get_children():
			c.queue_free()
		step_labels[ch].clear()
		for s in range(visible_rows):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			row.custom_minimum_size.y = 18
			var bg := ColorRect.new()
			bg.color = COL_ROW_ALT if (s % 4) == 0 else COL_BG
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(bg)
			row.move_child(bg, 0)
			var cells: Array = []
			for col in range(5):
				var cell := Label.new()
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cell.add_theme_color_override("font_color", COL_TEXT)
				cell.add_theme_font_size_override("font_size", 12)
				cell.mouse_filter = Control.MOUSE_FILTER_STOP
				cell.gui_input.connect(_on_cell.bind(ch, s, col))
				row.add_child(cell)
				cells.append(cell)
			box.add_child(row)
			step_labels[ch].append(cells)
	_refresh_all()

func _paint_playhead(old_s: int, new_s: int) -> void:
	for ch in range(CHANNELS):
		if channel_view_mode[ch] != 0:
			continue
		if old_s >= 0 and old_s < step_labels[ch].size():
			_color_row(ch, old_s, false)
		if new_s >= 0 and new_s < step_labels[ch].size():
			_color_row(ch, new_s, true)

func _color_row(ch: int, s: int, playhead: bool) -> void:
	var cells: Array = step_labels[ch][s]
	for c in range(5):
		var col := COL_TEXT
		if playhead and clock.playing:
			col = COL_PLAYHEAD
		elif ch == selected_ch and s == selected_step and c == selected_col:
			col = COL_ACTIVE
		cells[c].add_theme_color_override("font_color", col)

func _refresh_all() -> void:
	for ch in range(CHANNELS):
		_refresh_ch(ch)

func _refresh_ch(ch: int) -> void:
	var mode: int = channel_view_mode[ch]
	channel_containers[ch]["header"].text = "CH%d  %s" % [ch + 1, "TABLE" if mode == 1 else "PHRASE"]
	for s in range(mini(visible_rows, STEPS)):
		var cells: Array = step_labels[ch][s]
		if mode == 0:
			var d = phrases[ch][s]
			cells[0].text = "---" if d.note < 0 else NOTE_NAMES[d.note]
			cells[1].text = "%d" % d.oct if d.note >= 0 else "-"
			cells[2].text = "%02X" % d.inst if d.note >= 0 else "--"
			cells[3].text = d.fx1
			cells[4].text = d.fx2
		else:
			var t = tables[ch][s]
			cells[0].text = t.cmd1
			cells[1].text = t.val1
			cells[2].text = t.cmd2
			cells[3].text = t.val2
			cells[4].text = ""
		for c in range(5):
			var col := COL_TEXT
			if clock.playing and s == clock.step and mode == 0:
				col = COL_PLAYHEAD
			elif ch == selected_ch and s == selected_step and c == selected_col:
				col = COL_ACTIVE
			cells[c].add_theme_color_override("font_color", col)

func _on_cell(event: InputEvent, ch: int, step: int, col: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_ch = ch
		selected_step = step
		selected_col = col
		if is_recording:
			is_dragging = true
			drag_start_y = event.position.y
			drag_start_value = _cell_val(ch, step, col)
		_refresh_all()
	elif event is InputEventMouseMotion and is_dragging and is_recording:
		var dsteps = int((drag_start_y - event.position.y) / 12.0)
		if dsteps != 0:
			_apply_drag(ch, step, col, drag_start_value + dsteps)
			_refresh_ch(ch)
	elif event is InputEventMouseButton and not event.pressed:
		is_dragging = false

func _cell_val(ch: int, step: int, col: int) -> int:
	if channel_view_mode[ch] != 0:
		return 0
	var d = phrases[ch][step]
	match col:
		0: return d.note if d.note >= 0 else 0
		1: return d.oct
		2: return d.inst
		_: return 0

func _apply_drag(ch: int, step: int, col: int, val: int) -> void:
	if channel_view_mode[ch] != 0:
		return
	var d = phrases[ch][step]
	match col:
		0:
			d.note = clampi(val, -1, 11)
		1:
			d.oct = clampi(val, 0, 8)
		2:
			d.inst = clampi(val, 0, 63)
		3, 4:
			var presets = ["----", "V40", "V80", "VA0", "D20", "D50", "D90", "F20", "F80", "FA0", "M40", "M80", "S60", "SA0"]
			var idx = clampi(val, 0, presets.size() - 1)
			if col == 3:
				d.fx1 = presets[idx]
			else:
				d.fx2 = presets[idx]
	phrases[ch][step] = d

func _toggle_view(ch: int) -> void:
	channel_view_mode[ch] = 1 - channel_view_mode[ch]
	_refresh_ch(ch)

func _btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 26)
	_style_btn(b, false)
	return b

func _style_btn(b: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	if active:
		sb.bg_color = COL_REC if b.text.begins_with("REC") else COL_ACTIVE
		sb.border_color = sb.bg_color
		b.add_theme_color_override("font_color", Color("#000000"))
	else:
		sb.bg_color = COL_PANEL
		sb.border_color = COL_BORDER
		b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_font_size_override("font_size", 11)

func _style_hdr(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#111111")
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_font_size_override("font_size", 11)

func _style_panel(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
