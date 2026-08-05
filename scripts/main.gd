extends Control

## ☦ SKULLBEAT — Tracker Mode
## 4 channels · note | octave | instrument | fx1 | fx2
## Per-channel Tables (subroutine style like LittleGPTracker / LSDJ)
## Console font · dynamic screen fill · REC + tap-drag edit
## K-OS III visual rules: no rounded corners, sharp, black, yellow accents

const CHANNELS := 4
const STEPS := 16          # phrase length (classic)
const TABLE_STEPS := 16   # table length
const NOTE_NAMES := ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]

# Visual
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
const COL_SELECTED := Color("#224422")

var bpm: float = 128.0
var is_playing := false
var is_recording := false          # REC mode: drag-to-edit enabled
var current_step := 0
var step_timer := 0.0
var visible_rows := 16             # calculated dynamically

# Data model
# phrases[ch][step] = {note:int (-1 empty), oct:int, inst:int, fx1:String, fx2:String}
var phrases: Array = []
# tables[ch][row] = {cmd1:String, val1:String, cmd2:String, val2:String, hop:int}  (simplified)
var tables: Array = []
var channel_view_mode: Array = []  # 0 = phrase, 1 = table for that channel

# UI state
var selected_ch := 0
var selected_step := 0
var selected_col := 0              # 0=note 1=oct 2=inst 3=fx1 4=fx2
var drag_start_y := 0.0
var drag_start_value := 0
var is_dragging := false

# UI refs
var header_bar: HBoxContainer
var channel_containers: Array = []
var step_labels: Array = []        # [ch][step] -> various Labels for the columns
var status_label: Label
var rec_btn: Button
var play_btn: Button
var bpm_label: Label

func _ready() -> void:
	_init_data()
	_build_ui()
	_recalc_layout()
	get_viewport().size_changed.connect(_recalc_layout)

func _init_data() -> void:
	for ch in range(CHANNELS):
		var phrase: Array = []
		for s in range(STEPS):
			phrase.append({"note": -1, "oct": 4, "inst": 0, "fx1": "----", "fx2": "----"})
		phrases.append(phrase)
		
		var table: Array = []
		for r in range(TABLE_STEPS):
			table.append({"cmd1": "----", "val1": "00", "cmd2": "----", "val2": "00"})
		tables.append(table)
		channel_view_mode.append(0)  # start in phrase view
	
	# Seed a simple pattern so something is visible
	phrases[0][0] = {"note": 0, "oct": 3, "inst": 1, "fx1": "----", "fx2": "----"}  # C-3
	phrases[0][4] = {"note": 0, "oct": 3, "inst": 1, "fx1": "----", "fx2": "----"}
	phrases[0][8] = {"note": 0, "oct": 3, "inst": 1, "fx1": "----", "fx2": "----"}
	phrases[0][12] = {"note": 0, "oct": 3, "inst": 1, "fx1": "----", "fx2": "----"}
	phrases[1][4] = {"note": 7, "oct": 4, "inst": 2, "fx1": "----", "fx2": "----"}  # G-4
	phrases[1][12] = {"note": 7, "oct": 4, "inst": 2, "fx1": "----", "fx2": "----"}
	phrases[2][0] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}
	phrases[2][2] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}
	phrases[2][4] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}
	phrases[2][6] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}
	phrases[2][8] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}
	phrases[2][10] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}
	phrases[2][12] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}
	phrases[2][14] = {"note": 0, "oct": 5, "inst": 3, "fx1": "----", "fx2": "----"}

func _process(delta: float) -> void:
	if not is_playing:
		return
	var step_dur = 60.0 / bpm / 4.0
	step_timer += delta
	if step_timer >= step_dur:
		step_timer -= step_dur
		_advance_step()

func _advance_step() -> void:
	current_step = (current_step + 1) % STEPS
	_refresh_all_channels()
	# TODO: actual note triggering + table execution

func _build_ui() -> void:
	# Background
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
	
	# === HEADER ===
	header_bar = HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", 8)
	root.add_child(header_bar)
	
	var title := Label.new()
	title.text = "☦ SKULLBEAT"
	title.add_theme_color_override("font_color", COL_TEXT_BRIGHT)
	title.add_theme_font_size_override("font_size", 16)
	header_bar.add_child(title)
	
	var mode_lbl := Label.new()
	mode_lbl.text = "TRACKER · 4CH"
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
	
	rec_btn = _make_console_btn("REC")
	rec_btn.pressed.connect(_toggle_rec)
	header_bar.add_child(rec_btn)
	
	play_btn = _make_console_btn("PLAY")
	play_btn.pressed.connect(_toggle_play)
	header_bar.add_child(play_btn)
	
	var stop_btn := _make_console_btn("STOP")
	stop_btn.pressed.connect(_on_stop)
	header_bar.add_child(stop_btn)
	
	# === CHANNELS ROW ===
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
		
		# Channel header (click to switch phrase/table view)
		var ch_header := Button.new()
		ch_header.text = "CH%d  PHRASE" % (ch + 1)
		ch_header.focus_mode = Control.FOCUS_NONE
		ch_header.custom_minimum_size.y = 22
		_style_header_btn(ch_header)
		var ch_idx = ch
		ch_header.pressed.connect(func(): _toggle_channel_view(ch_idx))
		ch_vbox.add_child(ch_header)
		
		# Column headers
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
		
		# Steps container (will be filled dynamically)
		var steps_box := VBoxContainer.new()
		steps_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		steps_box.add_theme_constant_override("separation", 0)
		ch_vbox.add_child(steps_box)
		
		channel_containers.append({
			"panel": ch_panel,
			"header": ch_header,
			"steps_box": steps_box,
			"col_hdr": col_hdr
		})
		step_labels.append([])
	
	# Status
	status_label = Label.new()
	status_label.text = "REC OFF · TAP CELL + DRAG TO EDIT WHEN REC ON · TAP CH HEADER TO TOGGLE TABLE"
	status_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	status_label.add_theme_font_size_override("font_size", 10)
	root.add_child(status_label)

func _recalc_layout() -> void:
	# Dynamically decide how many rows we can show based on available height
	var avail_h = size.y - 80  # header + status approx
	if avail_h < 100:
		avail_h = 400
	var row_h = 18
	visible_rows = clamp(int(avail_h / row_h), 8, STEPS)
	_rebuild_step_rows()

func _rebuild_step_rows() -> void:
	for ch in range(CHANNELS):
		var steps_box: VBoxContainer = channel_containers[ch]["steps_box"]
		# Clear old
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

func _refresh_channel(ch: int) -> void:
	var mode = channel_view_mode[ch]
	var header: Button = channel_containers[ch]["header"]
	if mode == 0:
		header.text = "CH%d  PHRASE" % (ch + 1)
	else:
		header.text = "CH%d  TABLE" % (ch + 1)
	
	for s in range(min(visible_rows, STEPS)):
		var cells: Array = step_labels[ch][s]
		if mode == 0:
			# Phrase view
			var data = phrases[ch][s]
			var note_str = "---" if data.note < 0 else NOTE_NAMES[data.note]
			cells[0].text = note_str
			cells[1].text = "%d" % data.oct if data.note >= 0 else "-"
			cells[2].text = "%02X" % data.inst if data.note >= 0 else "--"
			cells[3].text = data.fx1
			cells[4].text = data.fx2
		else:
			# Table view (simplified 4 columns for now)
			var tdata = tables[ch][s]
			cells[0].text = tdata.cmd1
			cells[1].text = tdata.val1
			cells[2].text = tdata.cmd2
			cells[3].text = tdata.val2
			cells[4].text = ""
		
		# Playhead + selection highlighting
		for c in range(5):
			var col_color = COL_TEXT
			if is_playing and s == current_step and mode == 0:
				col_color = COL_PLAYHEAD
			elif is_recording and ch == selected_ch and s == selected_step and c == selected_col:
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
			status_label.text = "EDIT CH%d STEP%02d COL%d" % [ch+1, step, col]
		_refresh_all_channels()
	elif event is InputEventMouseMotion and is_dragging and is_recording:
		var delta_y = drag_start_y - event.position.y  # up = increase
		var steps = int(delta_y / 12.0)  # sensitivity
		if steps != 0:
			_apply_drag_value(ch, step, col, drag_start_value + steps)
			_refresh_channel(ch)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging = false

func _get_current_value(ch: int, step: int, col: int) -> int:
	if channel_view_mode[ch] == 0:
		var d = phrases[ch][step]
		match col:
			0: return d.note if d.note >= 0 else 0
			1: return d.oct
			2: return d.inst
			_: return 0
	else:
		return 0  # tables later

func _apply_drag_value(ch: int, step: int, col: int, val: int) -> void:
	if channel_view_mode[ch] != 0:
		return  # table editing later
	var d = phrases[ch][step]
	match col:
		0:  # note
			d.note = clamp(val, -1, 11)
			if d.note < 0:
				d.note = -1
		1:  # octave
			d.oct = clamp(val, 0, 8)
		2:  # instrument
			d.inst = clamp(val, 0, 63)
		3, 4:
			pass  # FX text editing later (need hex or command list)
	phrases[ch][step] = d

func _toggle_channel_view(ch: int) -> void:
	channel_view_mode[ch] = 1 - channel_view_mode[ch]
	_refresh_channel(ch)
	status_label.text = "CH%d now showing %s" % [ch+1, "TABLE" if channel_view_mode[ch] == 1 else "PHRASE"]

func _toggle_rec() -> void:
	is_recording = not is_recording
	if is_recording:
		rec_btn.text = "REC*"
		_style_btn_active(rec_btn, true)
		status_label.text = "REC ON · TAP + DRAG CELLS TO EDIT VALUES"
	else:
		rec_btn.text = "REC"
		_style_btn_active(rec_btn, false)
		is_dragging = false
		status_label.text = "REC OFF"

func _toggle_play() -> void:
	if is_playing:
		return
	is_playing = true
	current_step = -1
	step_timer = 0.0
	play_btn.text = "PLAY*"
	_advance_step()

func _on_stop() -> void:
	is_playing = false
	current_step = 0
	play_btn.text = "PLAY"
	_refresh_all_channels()
	status_label.text = "STOPPED"

func _change_bpm(d: int) -> void:
	bpm = clamp(bpm + d, 40.0, 300.0)
	bpm_label.text = "BPM %d" % int(bpm)

func _make_console_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 26)
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
