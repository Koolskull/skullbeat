extends Control

## ☦ SKULLBEAT — Super-instrument tracker
## Monophonic channels: each new row note chokes previous on same channel
## Chord column reserved for later (structure ready via channel voices)

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

var bpm: float = 128.0
var is_playing := false
var is_recording := false
var current_step := 0
var prev_play_step := -1
var step_timer := 0.0
var visible_rows := 16

var phrases: Array = []
var tables: Array = []
var channel_view_mode: Array = []

var selected_ch := 0
var selected_step := 0
var selected_col := 0
var drag_start_y := 0.0
var drag_start_value := 0
var is_dragging := false

var header_bar: HBoxContainer
var channel_containers: Array = []
var step_labels: Array = []
var status_label: Label
var rec_btn: Button
var play_btn: Button
var bpm_label: Label
var synth: SynthEngine
var sample_import: SampleImport
var auv3: AUv3Host

func _ready() -> void:
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
			# chord reserved for later multi-note per row; mono choke still applies per channel
			phrase.append({"note": -1, "oct": 4, "inst": 0, "fx1": "----", "fx2": "----", "chord": ""})
		phrases.append(phrase)
		var table: Array = []
		for r in range(TABLE_STEPS):
			table.append({"cmd1": "----", "val1": "00", "cmd2": "----", "val2": "00"})
		tables.append(table)
		channel_view_mode.append(0)

	phrases[0][0]  = {"note": 0, "oct": 2, "inst": 1, "fx1": "V90", "fx2": "D40", "chord": ""}
	phrases[0][8]  = {"note": 0, "oct": 2, "inst": 1, "fx1": "VA0", "fx2": "D90", "chord": ""}
	phrases[1][4]  = {"note": 0, "oct": 3, "inst": 6, "fx1": "V80", "fx2": "D50", "chord": ""}
	phrases[1][12] = {"note": 0, "oct": 3, "inst": 6, "fx1": "V60", "fx2": "D30", "chord": ""}
	phrases[2][0]  = {"note": 0, "oct": 5, "inst": 10, "fx1": "V70", "fx2": "D20", "chord": ""}
	phrases[2][2]  = {"note": 0, "oct": 5, "inst": 10, "fx1": "V50", "fx2": "D10", "chord": ""}
	phrases[2][4]  = {"note": 0, "oct": 5, "inst": 10, "fx1": "V70", "fx2": "D20", "chord": ""}
	phrases[2][6]  = {"note": 0, "oct": 5, "inst": 10, "fx1": "V40", "fx2": "D08", "chord": ""}
	phrases[2][8]  = {"note": 0, "oct": 5, "inst": 10, "fx1": "V70", "fx2": "D20", "chord": ""}
	phrases[2][10] = {"note": 0, "oct": 5, "inst": 10, "fx1": "V50", "fx2": "D10", "chord": ""}
	phrases[2][12] = {"note": 0, "oct": 5, "inst": 10, "fx1": "V70", "fx2": "D20", "chord": ""}
	phrases[2][14] = {"note": 0, "oct": 5, "inst": 10, "fx1": "V30", "fx2": "D05", "chord": ""}
	phrases[3][0]  = {"note": 0, "oct": 2, "inst": 16, "fx1": "V88", "fx2": "FA0", "chord": ""}
	phrases[3][8]  = {"note": 7, "oct": 2, "inst": 16, "fx1": "V70", "fx2": "F40", "chord": ""}

func _process(delta: float) -> void:
	if not is_playing:
		return
	var step_dur = 60.0 / bpm / 4.0
	step_timer += delta
	if step_timer >= step_dur:
		step_timer -= step_dur
		_advance_step()

func _advance_step() -> void:
	prev_play_step = current_step
	current_step = (current_step + 1) % STEPS
	for ch in range(CHANNELS):
		var d = phrases[ch][current_step]
		if d.note >= 0:
			# channel index => monophonic choke on that channel
			synth.note_on(d.note, d.oct, d.inst, d.fx1, d.fx2, 1.0, ch)
	_refresh_playhead()

func _import_target_inst() -> int:
	if channel_view_mode[selected_ch] == 0:
		var d = phrases[selected_ch][selected_step]
		if d.note >= 0 and d.inst > 0:
			return d.inst
	return clampi(selected_ch + 1, 1, 63)

func _do_import() -> void:
	var tid = _import_target_inst()
	sample_import.set_target_instrument(tid)
	status_label.text = "IMPORT -> INST %02X  (WAV via Files / AudioShare)" % tid
	sample_import.open_file_picker()

func _do_audioshare() -> void:
	status_label.text = "OPENING AUDIOSHARE · export WAV · then IMP"
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
		_on_pad_triggered(KOALA_PADS[key])
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_SPACE:
			if is_playing:
				_on_stop()
			else:
				_toggle_play()
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
			selected_step = max(0, selected_step - 1)
			_refresh_all_channels()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			selected_step = min(STEPS - 1, selected_step + 1)
			_refresh_all_channels()
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			if selected_col > 0:
				selected_col -= 1
			else:
				selected_ch = max(0, selected_ch - 1)
				selected_col = 4
			_refresh_all_channels()
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if selected_col < 4:
				selected_col += 1
			else:
				selected_ch = min(CHANNELS - 1, selected_ch + 1)
				selected_col = 0
			_refresh_all_channels()
			get_viewport().set_input_as_handled()
		KEY_BACKSPACE, KEY_DELETE:
			if channel_view_mode[selected_ch] == 0:
				phrases[selected_ch][selected_step] = {"note": -1, "oct": 4, "inst": 0, "fx1": "----", "fx2": "----", "chord": ""}
				_refresh_channel(selected_ch)
			get_viewport().set_input_as_handled()

func _on_pad_triggered(pad_idx: int) -> void:
	var inst = pad_idx + 1
	var note = pad_idx % 12
	var oct = 2 + int(pad_idx / 8)
	# live pads use free pool (channel -1), not tracker mono slots
	synth.note_on(note, oct, inst, "----", "----", 1.0, -1)
	status_label.text = "PAD %02d -> INST %02X  %s%d" % [pad_idx + 1, inst, NOTE_NAMES[note], oct]
	if is_recording and channel_view_mode[selected_ch] == 0:
		phrases[selected_ch][selected_step] = {
			"note": note, "oct": oct, "inst": inst,
			"fx1": "V80", "fx2": "----", "chord": ""
		}
		_refresh_channel(selected_ch)
		selected_step = (selected_step + 1) % STEPS
		_refresh_all_channels()

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
	title.text = "☦ SKULLBEAT"
	title.add_theme_color_override("font_color", COL_TEXT_BRIGHT)
	title.add_theme_font_size_override("font_size", 16)
	header_bar.add_child(title)
	var mode_lbl := Label.new()
	mode_lbl.text = "MONO CH · CHOKE"
	mode_lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
	mode_lbl.add_theme_font_size_override("font_size", 11)
	header_bar.add_child(mode_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(spacer)
	bpm_label = Label.new()
	bpm_label.text = "BPM %d" % int(bpm)
	bpm_label.add_theme_color_override("font_color", COL_ACTIVE)
	bpm_label.add_theme_font_size_override("font_size", 13)
	header_bar.add_child(bpm_label)
	var bpm_down := _make_console_btn("-")
	bpm_down.pressed.connect(func(): _change_bpm(-1))
	header_bar.add_child(bpm_down)
	var bpm_up := _make_console_btn("+")
	bpm_up.pressed.connect(func(): _change_bpm(1))
	header_bar.add_child(bpm_up)
	var imp_btn := _make_console_btn("IMP")
	imp_btn.pressed.connect(_do_import)
	header_bar.add_child(imp_btn)
	var as_btn := _make_console_btn("AS")
	as_btn.pressed.connect(_do_audioshare)
	header_bar.add_child(as_btn)
	rec_btn = _make_console_btn("REC")
	rec_btn.pressed.connect(_toggle_rec)
	header_bar.add_child(rec_btn)
	play_btn = _make_console_btn("PLAY")
	play_btn.pressed.connect(_toggle_play)
	header_bar.add_child(play_btn)
	var stop_btn := _make_console_btn("STOP")
	stop_btn.pressed.connect(_on_stop)
	header_bar.add_child(stop_btn)
	var channels_row := HBoxContainer.new()
	channels_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	channels_row.add_theme_constant_override("separation", 3)
	root.add_child(channels_row)
	channel_containers.clear()
	step_labels.clear()
	for ch in range(CHANNELS):
		var ch_panel := PanelContainer.new()
		ch_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_style_panel(ch_panel)
		channels_row.add_child(ch_panel)
		var ch_vbox := VBoxContainer.new()
		ch_vbox.add_theme_constant_override("separation", 0)
		ch_panel.add_child(ch_vbox)
		var ch_header := Button.new()
		ch_header.text = "CH%d  PHRASE" % (ch + 1)
		ch_header.focus_mode = Control.FOCUS_NONE
		ch_header.custom_minimum_size.y = 22
		_style_header_btn(ch_header)
		var ch_idx = ch
		ch_header.pressed.connect(func(): _toggle_channel_view(ch_idx))
		ch_vbox.add_child(ch_header)
		var col_hdr := HBoxContainer.new()
		col_hdr.add_theme_constant_override("separation", 0)
		ch_vbox.add_child(col_hdr)
		for col_name in ["NT", "OC", "IN", "FX1", "FX2"]:
			var l := Label.new()
			l.text = col_name
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_color_override("font_color", COL_TEXT_DIM)
			l.add_theme_font_size_override("font_size", 9)
			col_hdr.add_child(l)
		var steps_box := VBoxContainer.new()
		steps_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		steps_box.add_theme_constant_override("separation", 0)
		ch_vbox.add_child(steps_box)
		channel_containers.append({"panel": ch_panel, "header": ch_header, "steps_box": steps_box, "col_hdr": col_hdr})
		step_labels.append([])
	status_label = Label.new()
	status_label.text = "MONO: new note chokes channel · SPACE play · pads live"
	status_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	status_label.add_theme_font_size_override("font_size", 10)
	root.add_child(status_label)

func _recalc_layout() -> void:
	var avail_h = size.y - 80
	if avail_h < 100:
		avail_h = 400
	visible_rows = clamp(int(avail_h / 18), 8, STEPS)
	_rebuild_step_rows()

func _rebuild_step_rows() -> void:
	for ch in range(CHANNELS):
		var steps_box: VBoxContainer = channel_containers[ch]["steps_box"]
		for child in steps_box.get_children():
			child.queue_free()
		step_labels[ch].clear()
		for s in range(visible_rows):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			row.custom_minimum_size.y = 18
			var bg_rect := ColorRect.new()
			bg_rect.color = COL_ROW_ALT if s % 4 == 0 else COL_BG
			bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			row.add_child(bg_rect)
			row.move_child(bg_rect, 0)
			var cells: Array = []
			for col in range(5):
				var cell := Label.new()
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cell.add_theme_color_override("font_color", COL_TEXT)
				cell.add_theme_font_size_override("font_size", 12)
				cell.mouse_filter = Control.MOUSE_FILTER_STOP
				cell.gui_input.connect(_on_cell_input.bind(ch, s, col))
				row.add_child(cell)
				cells.append(cell)
			steps_box.add_child(row)
			step_labels[ch].append(cells)
	_refresh_all_channels()

func _refresh_all_channels() -> void:
	for ch in range(CHANNELS):
		_refresh_channel(ch)

## Only recolor playhead rows — avoids full UI rebuild every step (was a crash contributor)
func _refresh_playhead() -> void:
	for ch in range(CHANNELS):
		if channel_view_mode[ch] != 0:
			continue
		for s in range(min(visible_rows, STEPS)):
			var cells: Array = step_labels[ch][s]
			for c in range(5):
				var col_color = COL_TEXT
				if is_playing and s == current_step:
					col_color = COL_PLAYHEAD
				elif ch == selected_ch and s == selected_step and c == selected_col:
					col_color = COL_ACTIVE
				cells[c].add_theme_color_override("font_color", col_color)

func _refresh_channel(ch: int) -> void:
	var mode = channel_view_mode[ch]
	var header: Button = channel_containers[ch]["header"]
	header.text = "CH%d  %s" % [ch + 1, "TABLE" if mode == 1 else "PHRASE"]
	for s in range(min(visible_rows, STEPS)):
		var cells: Array = step_labels[ch][s]
		if mode == 0:
			var data = phrases[ch][s]
			cells[0].text = "---" if data.note < 0 else NOTE_NAMES[data.note]
			cells[1].text = "%d" % data.oct if data.note >= 0 else "-"
			cells[2].text = "%02X" % data.inst if data.note >= 0 else "--"
			cells[3].text = data.fx1
			cells[4].text = data.fx2
		else:
			var tdata = tables[ch][s]
			cells[0].text = tdata.cmd1
			cells[1].text = tdata.val1
			cells[2].text = tdata.cmd2
			cells[3].text = tdata.val2
			cells[4].text = ""
		for c in range(5):
			var col_color = COL_TEXT
			if is_playing and s == current_step and mode == 0:
				col_color = COL_PLAYHEAD
			elif ch == selected_ch and s == selected_step and c == selected_col:
				col_color = COL_ACTIVE
			cells[c].add_theme_color_override("font_color", col_color)

func _on_cell_input(event: InputEvent, ch: int, step: int, col: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_ch = ch
		selected_step = step
		selected_col = col
		if is_recording:
			is_dragging = true
			drag_start_y = event.position.y
			drag_start_value = _get_current_value(ch, step, col)
		_refresh_all_channels()
	elif event is InputEventMouseMotion and is_dragging and is_recording:
		var steps = int((drag_start_y - event.position.y) / 12.0)
		if steps != 0:
			_apply_drag_value(ch, step, col, drag_start_value + steps)
			_refresh_channel(ch)
	elif event is InputEventMouseButton and not event.pressed:
		is_dragging = false

func _get_current_value(ch: int, step: int, col: int) -> int:
	if channel_view_mode[ch] != 0:
		return 0
	var d = phrases[ch][step]
	match col:
		0:
			return d.note if d.note >= 0 else 0
		1:
			return d.oct
		2:
			return d.inst
		_:
			return 0

func _apply_drag_value(ch: int, step: int, col: int, val: int) -> void:
	if channel_view_mode[ch] != 0:
		return
	var d = phrases[ch][step]
	match col:
		0:
			d.note = clamp(val, -1, 11)
			if d.note < 0:
				d.note = -1
		1:
			d.oct = clamp(val, 0, 8)
		2:
			d.inst = clamp(val, 0, 63)
		3, 4:
			var presets = ["----", "V40", "V80", "VA0", "D20", "D50", "D90", "F20", "F80", "FA0", "M40", "M80", "S60", "SA0"]
			var idx = clamp(val, 0, presets.size() - 1)
			if col == 3:
				d.fx1 = presets[idx]
			else:
				d.fx2 = presets[idx]
	phrases[ch][step] = d

func _toggle_channel_view(ch: int) -> void:
	channel_view_mode[ch] = 1 - channel_view_mode[ch]
	_refresh_channel(ch)

func _toggle_rec() -> void:
	is_recording = not is_recording
	if is_recording:
		rec_btn.text = "REC*"
		_style_btn_active(rec_btn, true)
	else:
		rec_btn.text = "REC"
		_style_btn_active(rec_btn, false)
		is_dragging = false

func _toggle_play() -> void:
	if is_playing:
		return
	is_playing = true
	current_step = -1
	prev_play_step = -1
	step_timer = 0.0
	play_btn.text = "PLAY*"
	_advance_step()

func _on_stop() -> void:
	is_playing = false
	current_step = 0
	prev_play_step = -1
	play_btn.text = "PLAY"
	synth.stop_all()
	_refresh_all_channels()

func _change_bpm(d: int) -> void:
	bpm = clamp(bpm + d, 40.0, 300.0)
	bpm_label.text = "BPM %d" % int(bpm)

func _make_console_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 26)
	_style_btn_active(b, false)
	return b

func _style_btn_active(b: Button, active: bool) -> void:
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

func _style_header_btn(b: Button) -> void:
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
