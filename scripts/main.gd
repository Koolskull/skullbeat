extends Control

## SKULLBEAT UI shell — multi-window host
## Scene map (top-left): PHR LCH SET / TBL PRJ EXP
## Shift+arrows navigate map · tap map cells · SPACE transport

const CHANNELS := 4
const STEPS := 16
const TABLE_STEPS := 16
const BANKS := 4
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
var live: LiveFx
var store: ProjectStore
var sample_import: SampleImport
var auv3: AUv3Host
var scene_map: SceneMap

# pattern data — banks[bank][ch][step]
var banks: Array = []
var phrases: Array = []
var tables: Array = []
var channel_view_mode: Array = []
var swing: float = 0.0
var project_name: String = "UNTITLED"

var is_recording := false
var selected_ch := 0
var selected_step := 0
var selected_col := 0
var drag_start_y := 0.0
var drag_start_value := 0
var is_dragging := false
var visible_rows := 16
var prev_step := -1
var current_scene := "phrase"

# UI roots
var root: VBoxContainer
var header_bar: HBoxContainer
var body: Control
var status_label: Label
var rec_btn: Button
var play_btn: Button
var bpm_label: Label
var scene_title: Label

# phrase view
var channel_containers: Array = []
var step_labels: Array = []
var phrase_host: Control

# launch view
var launch_host: Control
var clip_btns: Array = []
var fx_btns: Dictionary = {}
var xy_a_panel: ColorRect
var xy_b_panel: ColorRect
var xy_a_dot: ColorRect
var xy_b_dot: ColorRect
var mute_btns: Array = []

# settings / project / export
var settings_host: Control
var project_host: Control
var export_host: Control
var name_edit: LineEdit
var bpm_edit_label: Label
var project_list: VBoxContainer

func _ready() -> void:
	live = LiveFx.new()
	store = ProjectStore.new()
	store.saved.connect(func(p): status_label.text = "SAVED  %s" % p.get_file() if status_label else print(p))
	store.loaded.connect(func(p): status_label.text = "LOADED  %s" % p.get_file() if status_label else print(p))
	store.failed.connect(func(m): status_label.text = m if status_label else print(m))

	clock = SbClock.new()
	clock.steps = STEPS
	clock.stepped.connect(_on_clock_step)

	synth = SynthEngine.new()
	add_child(synth)
	synth.bind_live(live)

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
	_show_scene("phrase")
	_recalc_layout()
	get_viewport().size_changed.connect(_recalc_layout)

func _init_data() -> void:
	banks.clear()
	for b in range(BANKS):
		var bank: Array = []
		for ch in range(CHANNELS):
			var phrase: Array = []
			for s in range(STEPS):
				phrase.append(_empty_step())
			bank.append(phrase)
		banks.append(bank)
	phrases = banks[0]
	tables.clear()
	channel_view_mode.clear()
	for ch in range(CHANNELS):
		var table: Array = []
		for r in range(TABLE_STEPS):
			table.append({"cmd1": "----", "val1": "00", "cmd2": "----", "val2": "00"})
		tables.append(table)
		channel_view_mode.append(0)
	_seed_demo(0)

func _seed_demo(bank: int) -> void:
	var p = banks[bank]
	p[0][0]  = _step(0, 2, 1, "V90", "D40")
	p[0][8]  = _step(0, 2, 1, "VA0", "D90")
	p[1][4]  = _step(0, 3, 6, "V80", "D50")
	p[1][12] = _step(0, 3, 6, "V60", "D30")
	p[2][0]  = _step(0, 5, 10, "V70", "D20")
	p[2][2]  = _step(0, 5, 10, "V50", "D10")
	p[2][4]  = _step(0, 5, 10, "V70", "D20")
	p[2][6]  = _step(0, 5, 10, "V40", "D08")
	p[2][8]  = _step(0, 5, 10, "V70", "D20")
	p[2][10] = _step(0, 5, 10, "V50", "D10")
	p[2][12] = _step(0, 5, 10, "V70", "D20")
	p[2][14] = _step(0, 5, 10, "V30", "D05")
	p[3][0]  = _step(0, 2, 16, "V88", "FA0")
	p[3][8]  = _step(7, 2, 16, "V70", "F40")
	# light variations on other banks
	if bank == 0:
		for b in range(1, BANKS):
			_seed_demo(b)
			if b == 1:
				banks[b][0][4] = _step(0, 2, 1, "V70", "D30")
			elif b == 2:
				banks[b][1][0] = _step(0, 3, 6, "VA0", "D40")
			elif b == 3:
				banks[b][3][4] = _step(5, 3, 16, "V60", "F80")

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
		if live.is_muted(ch):
			continue
		var d = phrases[ch][step]
		if d.note >= 0:
			synth.note_on(d.note, d.oct, d.inst, d.fx1, d.fx2, 1.0, ch)
	if current_scene == "phrase" or current_scene == "table":
		_paint_playhead(old, step)

# ─── scenes ───────────────────────────────────────────

func _show_scene(name: String) -> void:
	current_scene = name
	for h in [phrase_host, launch_host, settings_host, project_host, export_host]:
		if h:
			h.visible = false
	match name:
		"phrase", "table":
			if phrase_host:
				phrase_host.visible = true
			if name == "table":
				for ch in range(CHANNELS):
					channel_view_mode[ch] = 1
			else:
				for ch in range(CHANNELS):
					channel_view_mode[ch] = 0
			_refresh_all()
		"launch":
			if launch_host:
				launch_host.visible = true
			_refresh_launch()
		"settings":
			if settings_host:
				settings_host.visible = true
			_refresh_settings()
		"project":
			if project_host:
				project_host.visible = true
			_refresh_project_list()
		"export":
			if export_host:
				export_host.visible = true
	if scene_title:
		scene_title.text = name.to_upper()
	if status_label:
		status_label.text = "MAP  Shift+↑↓←→ · tap cells · SPACE play · scene %s" % name.to_upper()

func _on_map_scene(i: int) -> void:
	_show_scene(scene_map.id_name(i))

# ─── input ────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key = event.keycode
	var shift: bool = event.shift_pressed

	# Scene map navigation — hold Shift + arrows (LGPT/LSDJ)
	if shift and key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		match key:
			KEY_UP: scene_map.move(0, -1)
			KEY_DOWN: scene_map.move(0, 1)
			KEY_LEFT: scene_map.move(-1, 0)
			KEY_RIGHT: scene_map.move(1, 0)
		get_viewport().set_input_as_handled()
		return

	if KOALA_PADS.has(key) and not shift and not event.ctrl_pressed and not event.meta_pressed:
		_on_pad(KOALA_PADS[key])
		get_viewport().set_input_as_handled()
		return

	match key:
		KEY_SPACE:
			if clock.playing: _stop()
			else: _play()
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
		KEY_G:
			live.toggle_glitch()
			_refresh_launch()
			get_viewport().set_input_as_handled()
		KEY_T:
			live.toggle_retrig()
			_refresh_launch()
			get_viewport().set_input_as_handled()
		KEY_Y:
			live.toggle_stutter()
			_refresh_launch()
			get_viewport().set_input_as_handled()
		KEY_K:
			live.pulse_kill()
			get_viewport().set_input_as_handled()
		KEY_S:
			if event.ctrl_pressed or event.meta_pressed:
				_save_project()
				get_viewport().set_input_as_handled()
		KEY_UP:
			if current_scene in ["phrase", "table"]:
				selected_step = maxi(0, selected_step - 1)
				_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			if current_scene in ["phrase", "table"]:
				selected_step = mini(STEPS - 1, selected_step + 1)
				_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			if current_scene in ["phrase", "table"]:
				if selected_col > 0: selected_col -= 1
				else:
					selected_ch = maxi(0, selected_ch - 1)
					selected_col = 4
				_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if current_scene in ["phrase", "table"]:
				if selected_col < 4: selected_col += 1
				else:
					selected_ch = mini(CHANNELS - 1, selected_ch + 1)
					selected_col = 0
				_refresh_all()
			get_viewport().set_input_as_handled()
		KEY_BACKSPACE, KEY_DELETE:
			if current_scene == "phrase" and channel_view_mode[selected_ch] == 0:
				phrases[selected_ch][selected_step] = _empty_step()
				_refresh_ch(selected_ch)
			get_viewport().set_input_as_handled()

func _on_pad(pad_idx: int) -> void:
	var inst: int = pad_idx + 1
	var note: int = pad_idx % 12
	var oct: int = 2 + int(float(pad_idx) / 8.0)
	synth.note_on(note, oct, inst, "----", "----", 1.0, -1)
	if status_label:
		status_label.text = "PAD %02d → INST %02X" % [pad_idx + 1, inst]
	if is_recording and current_scene == "phrase" and channel_view_mode[selected_ch] == 0:
		phrases[selected_ch][selected_step] = _step(note, oct, inst, "V80", "----")
		_refresh_ch(selected_ch)
		selected_step = (selected_step + 1) % STEPS
		_refresh_all()

func _play() -> void:
	prev_step = -1
	if play_btn: play_btn.text = "PLAY*"
	clock.play()

func _stop() -> void:
	clock.stop()
	if play_btn: play_btn.text = "PLAY"
	synth.stop_all()
	prev_step = -1
	if current_scene in ["phrase", "table"]:
		_refresh_all()

func _toggle_rec() -> void:
	is_recording = not is_recording
	if is_recording:
		if rec_btn: rec_btn.text = "REC*"
		_style_btn(rec_btn, true)
	else:
		if rec_btn: rec_btn.text = "REC"
		_style_btn(rec_btn, false)
		is_dragging = false

func _change_bpm(d: int) -> void:
	clock.nudge_bpm(float(d))
	if bpm_label: bpm_label.text = "BPM %d" % int(clock.bpm)
	if bpm_edit_label: bpm_edit_label.text = "%d" % int(clock.bpm)

func _switch_bank(b: int) -> void:
	b = clampi(b, 0, BANKS - 1)
	# write-back current phrases into bank slot (phrases is reference to banks[active])
	live.set_bank(b)
	phrases = banks[b]
	if current_scene in ["phrase", "table"]:
		_refresh_all()
	_refresh_launch()
	if status_label:
		status_label.text = "CLIP BANK %c" % (65 + b)

# ─── project I/O ──────────────────────────────────────

func _pack_data() -> Dictionary:
	store.project_name = project_name
	return store.pack(clock.bpm, phrases, tables, banks, {
		"swing": swing,
		"bank": live.active_bank
	})

func _save_project() -> void:
	store.project_name = project_name
	var ok = store.save(_pack_data())
	if ok and status_label:
		status_label.text = "SAVED  %s" % store.last_path.get_file()
	_refresh_project_list()

func _load_project(path: String) -> void:
	var data = store.load_file(path)
	if data.is_empty():
		return
	project_name = str(data.get("name", "LOADED"))
	clock.set_bpm(float(data.get("bpm", 128)))
	if bpm_label: bpm_label.text = "BPM %d" % int(clock.bpm)
	var loaded_banks = data.get("banks", [])
	if loaded_banks is Array and loaded_banks.size() > 0:
		banks = loaded_banks
		while banks.size() < BANKS:
			var bank: Array = []
			for ch in range(CHANNELS):
				var phrase: Array = []
				for s in range(STEPS):
					phrase.append(_empty_step())
				bank.append(phrase)
			banks.append(bank)
	elif data.has("phrases"):
		banks[0] = data["phrases"]
	var settings = data.get("settings", {})
	swing = float(settings.get("swing", 0.0))
	var b = int(settings.get("bank", 0))
	phrases = banks[clampi(b, 0, banks.size() - 1)]
	live.set_bank(b)
	if data.has("tables"):
		tables = data["tables"]
	_refresh_all()
	_refresh_launch()
	_refresh_settings()
	if name_edit: name_edit.text = project_name

func _export_song() -> void:
	store.project_name = project_name
	var ok = store.export_song(_pack_data())
	if ok and status_label:
		status_label.text = "EXPORTED  %s" % store.last_path.get_file()

func _do_import() -> void:
	var tid = clampi(selected_ch + 1, 1, 63)
	if current_scene == "phrase":
		var d = phrases[selected_ch][selected_step]
		if d.note >= 0 and d.inst > 0:
			tid = d.inst
	sample_import.set_target_instrument(tid)
	sample_import.open_file_picker()

func _do_audioshare() -> void:
	SampleImport.open_audioshare()

func _on_import_finished(success: bool, message: String, inst_id: int) -> void:
	if status_label: status_label.text = message
	if success:
		synth.note_on(0, 4, inst_id, "V90", "----", 1.0, -1)

# ─── UI build ─────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)

	root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	root.offset_left = 4
	root.offset_top = 4
	root.offset_right = -4
	root.offset_bottom = -4
	add_child(root)

	# header: scene map | title | transport
	header_bar = HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", 6)
	root.add_child(header_bar)

	scene_map = SceneMap.new()
	scene_map.scene_selected.connect(_on_map_scene)
	header_bar.add_child(scene_map)

	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 0)
	header_bar.add_child(title_col)
	var title := Label.new()
	title.text = "SKULLBEAT"
	title.add_theme_color_override("font_color", COL_TEXT_BRIGHT)
	title.add_theme_font_size_override("font_size", 14)
	title_col.add_child(title)
	scene_title = Label.new()
	scene_title.text = "PHRASE"
	scene_title.add_theme_color_override("font_color", COL_ACTIVE)
	scene_title.add_theme_font_size_override("font_size", 10)
	title_col.add_child(scene_title)

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
	rec_btn = _btn("REC")
	rec_btn.pressed.connect(_toggle_rec)
	header_bar.add_child(rec_btn)
	play_btn = _btn("PLAY")
	play_btn.pressed.connect(func():
		if clock.playing: _stop()
		else: _play()
	)
	header_bar.add_child(play_btn)
	var st := _btn("STOP")
	st.pressed.connect(_stop)
	header_bar.add_child(st)

	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_build_phrase_view()
	_build_launch_view()
	_build_settings_view()
	_build_project_view()
	_build_export_view()

	status_label = Label.new()
	status_label.text = "Shift+arrows = scene map · LCH = clips+FX · PRJ save"
	status_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	status_label.add_theme_font_size_override("font_size", 10)
	root.add_child(status_label)

func _host() -> Control:
	var h := Control.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.visible = false
	body.add_child(h)
	return h

func _build_phrase_view() -> void:
	phrase_host = _host()
	var channels_row := HBoxContainer.new()
	channels_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	channels_row.add_theme_constant_override("separation", 3)
	phrase_host.add_child(channels_row)
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
		hdr.pressed.connect(func():
			channel_view_mode[ch_i] = 1 - channel_view_mode[ch_i]
			_refresh_ch(ch_i)
		)
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

func _build_launch_view() -> void:
	launch_host = _host()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	launch_host.add_child(v)

	var clips_lbl := Label.new()
	clips_lbl.text = "CLIP LAUNCH  A–D banks · mute CH · live FX"
	clips_lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
	clips_lbl.add_theme_font_size_override("font_size", 11)
	v.add_child(clips_lbl)

	var clips_row := HBoxContainer.new()
	clips_row.add_theme_constant_override("separation", 4)
	v.add_child(clips_row)
	clip_btns.clear()
	for i in range(BANKS):
		var b := _btn("  %c  " % (65 + i))
		b.custom_minimum_size = Vector2(64, 48)
		var bi = i
		b.pressed.connect(func(): _switch_bank(bi))
		clips_row.add_child(b)
		clip_btns.append(b)

	var mute_row := HBoxContainer.new()
	mute_row.add_theme_constant_override("separation", 4)
	v.add_child(mute_row)
	mute_btns.clear()
	for ch in range(CHANNELS):
		var m := _btn("CH%d" % (ch + 1))
		var ci = ch
		m.pressed.connect(func():
			live.toggle_mute(ci)
			_refresh_launch()
		)
		mute_row.add_child(m)
		mute_btns.append(m)

	var fx_lbl := Label.new()
	fx_lbl.text = "LIVE FX  G glitch · T retrig · Y stutter · K kill"
	fx_lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
	fx_lbl.add_theme_font_size_override("font_size", 11)
	v.add_child(fx_lbl)

	var fx_row := HBoxContainer.new()
	fx_row.add_theme_constant_override("separation", 4)
	v.add_child(fx_row)
	fx_btns.clear()
	for item in [["GLITCH", "glitch"], ["RTRG", "retrig"], ["STUT", "stutter"], ["KILL", "kill"]]:
		var fb := _btn(item[0])
		fb.custom_minimum_size = Vector2(72, 40)
		var id = item[1]
		fb.pressed.connect(func():
			match id:
				"glitch": live.toggle_glitch()
				"retrig": live.toggle_retrig()
				"stutter": live.toggle_stutter()
				"kill": live.pulse_kill()
			_refresh_launch()
		)
		fx_row.add_child(fb)
		fx_btns[id] = fb

	var xy_row := HBoxContainer.new()
	xy_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	xy_row.add_theme_constant_override("separation", 8)
	v.add_child(xy_row)

	xy_a_panel = _make_xy_pad("XY A  X=filter  Y=drive", true)
	xy_b_panel = _make_xy_pad("XY B  X=delay  Y=time", false)
	xy_row.add_child(xy_a_panel.get_meta("wrap"))
	xy_row.add_child(xy_b_panel.get_meta("wrap"))

func _make_xy_pad(label: String, is_a: bool) -> ColorRect:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", COL_TEXT_DIM)
	l.add_theme_font_size_override("font_size", 10)
	wrap.add_child(l)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(panel)
	wrap.add_child(panel)
	var area := ColorRect.new()
	area.color = Color("#111111")
	area.custom_minimum_size = Vector2(120, 120)
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(area)
	var dot := ColorRect.new()
	dot.color = COL_ACTIVE
	dot.size = Vector2(10, 10)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(dot)
	if is_a:
		xy_a_dot = dot
	else:
		xy_b_dot = dot
	area.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton or ev is InputEventMouseMotion:
			if ev is InputEventMouseMotion and not (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
				return
			if ev is InputEventMouseButton and not ev.pressed and ev.button_index != MOUSE_BUTTON_LEFT:
				return
			var p: Vector2 = ev.position
			var sz: Vector2 = area.size
			if sz.x < 1.0 or sz.y < 1.0:
				return
			var nx = clampf(p.x / sz.x, 0.0, 1.0)
			var ny = clampf(1.0 - p.y / sz.y, 0.0, 1.0)
			if is_a:
				live.set_xy_a(Vector2(nx, ny))
			else:
				live.set_xy_b(Vector2(nx, ny))
			_place_xy_dot(dot, area, Vector2(nx, ny))
	)
	# store wrap as child of caller's parent later — return area for ref, attach wrap via meta
	area.set_meta("wrap", wrap)
	# reparent trick: caller adds wrap
	# We'll return area but caller should add wrap — fix by returning wrap's area after attaching
	return area

func _place_xy_dot(dot: ColorRect, area: ColorRect, v: Vector2) -> void:
	var sz = area.size
	if sz.x < 1.0:
		sz = Vector2(120, 120)
	dot.position = Vector2(v.x * sz.x - 5.0, (1.0 - v.y) * sz.y - 5.0)

func _build_settings_view() -> void:
	settings_host = _host()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	settings_host.add_child(v)
	var h := Label.new()
	h.text = "PROJECT SETTINGS"
	h.add_theme_color_override("font_color", COL_ACTIVE)
	v.add_child(h)

	var row_name := HBoxContainer.new()
	v.add_child(row_name)
	var nl := Label.new()
	nl.text = "NAME  "
	nl.add_theme_color_override("font_color", COL_TEXT)
	row_name.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.text = project_name
	name_edit.custom_minimum_size.x = 200
	name_edit.add_theme_color_override("font_color", COL_TEXT_BRIGHT)
	name_edit.text_changed.connect(func(t): project_name = t.to_upper())
	row_name.add_child(name_edit)

	var row_bpm := HBoxContainer.new()
	v.add_child(row_bpm)
	var bl := Label.new()
	bl.text = "BPM   "
	bl.add_theme_color_override("font_color", COL_TEXT)
	row_bpm.add_child(bl)
	bpm_edit_label = Label.new()
	bpm_edit_label.text = "%d" % int(clock.bpm)
	bpm_edit_label.add_theme_color_override("font_color", COL_ACTIVE)
	row_bpm.add_child(bpm_edit_label)
	var b1 := _btn("-5")
	b1.pressed.connect(func(): _change_bpm(-5))
	row_bpm.add_child(b1)
	var b2 := _btn("+5")
	b2.pressed.connect(func(): _change_bpm(5))
	row_bpm.add_child(b2)

	var row_swing := HBoxContainer.new()
	v.add_child(row_swing)
	var sl := Label.new()
	sl.text = "SWING (reserved)"
	sl.add_theme_color_override("font_color", COL_TEXT_DIM)
	row_swing.add_child(sl)

	var note := Label.new()
	note.text = "Master FX wet defaults 0 — use LCH XY pads live.\nAUv3 shelved — see docs/IOS_AUDIO.md"
	note.add_theme_color_override("font_color", COL_TEXT_DIM)
	note.add_theme_font_size_override("font_size", 11)
	v.add_child(note)

func _build_project_view() -> void:
	project_host = _host()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	project_host.add_child(v)
	var h := Label.new()
	h.text = "PROJECT  save / load  (user://projects)"
	h.add_theme_color_override("font_color", COL_ACTIVE)
	v.add_child(h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var save_b := _btn("SAVE")
	save_b.pressed.connect(_save_project)
	row.add_child(save_b)
	var reload_b := _btn("REFRESH")
	reload_b.pressed.connect(_refresh_project_list)
	row.add_child(reload_b)
	project_list = VBoxContainer.new()
	project_list.add_theme_constant_override("separation", 2)
	v.add_child(project_list)

func _build_export_view() -> void:
	export_host = _host()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	export_host.add_child(v)
	var h := Label.new()
	h.text = "EXPORT SONG"
	h.add_theme_color_override("font_color", COL_ACTIVE)
	v.add_child(h)
	var d := Label.new()
	d.text = "Writes tracker text dump + JSON twin to user://projects/\nShare via Files / AudioShare from there on device."
	d.add_theme_color_override("font_color", COL_TEXT_DIM)
	v.add_child(d)
	var ex := _btn("EXPORT NOW")
	ex.custom_minimum_size = Vector2(140, 40)
	ex.pressed.connect(_export_song)
	v.add_child(ex)
	var imp := _btn("IMPORT SAMPLE")
	imp.pressed.connect(_do_import)
	v.add_child(imp)

func _refresh_launch() -> void:
	if clip_btns.is_empty():
		return
	for i in range(clip_btns.size()):
		_style_btn(clip_btns[i], i == live.active_bank)
	for ch in range(mute_btns.size()):
		_style_btn(mute_btns[ch], live.is_muted(ch))
		mute_btns[ch].text = "CH%d%s" % [ch + 1, " M" if live.is_muted(ch) else ""]
	if fx_btns.has("glitch"):
		_style_btn(fx_btns["glitch"], live.glitch_on)
	if fx_btns.has("retrig"):
		_style_btn(fx_btns["retrig"], live.retrig_on)
	if fx_btns.has("stutter"):
		_style_btn(fx_btns["stutter"], live.stutter_on)
	if xy_a_panel and xy_a_dot:
		_place_xy_dot(xy_a_dot, xy_a_panel, live.xy_a)
	if xy_b_panel and xy_b_dot:
		_place_xy_dot(xy_b_dot, xy_b_panel, live.xy_b)

func _refresh_settings() -> void:
	if name_edit: name_edit.text = project_name
	if bpm_edit_label: bpm_edit_label.text = "%d" % int(clock.bpm)

func _refresh_project_list() -> void:
	if project_list == null:
		return
	for c in project_list.get_children():
		c.queue_free()
	var files = store.list_projects()
	if files.is_empty():
		var empty := Label.new()
		empty.text = "(no projects yet — hit SAVE)"
		empty.add_theme_color_override("font_color", COL_TEXT_DIM)
		project_list.add_child(empty)
		return
	for f in files:
		var row := HBoxContainer.new()
		var b := _btn(f)
		b.custom_minimum_size.x = 220
		var path = store.DIR.path_join(f)
		b.pressed.connect(func(): _load_project(path))
		row.add_child(b)
		project_list.add_child(row)

func _recalc_layout() -> void:
	var h: float = size.y - 90.0
	if h < 100.0: h = 400.0
	visible_rows = clampi(int(h / 18.0), 8, STEPS)
	if not channel_containers.is_empty():
		_rebuild_rows()

func _rebuild_rows() -> void:
	if channel_containers.is_empty():
		return
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
	if ch >= step_labels.size() or s >= step_labels[ch].size():
		return
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
	if ch >= channel_containers.size():
		return
	var mode: int = channel_view_mode[ch]
	channel_containers[ch]["header"].text = "CH%d  %s" % [ch + 1, "TABLE" if mode == 1 else "PHRASE"]
	for s in range(mini(visible_rows, STEPS)):
		if s >= step_labels[ch].size():
			break
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
	if channel_view_mode[ch] != 0: return 0
	var d = phrases[ch][step]
	match col:
		0: return d.note if d.note >= 0 else 0
		1: return d.oct
		2: return d.inst
		_: return 0

func _apply_drag(ch: int, step: int, col: int, val: int) -> void:
	if channel_view_mode[ch] != 0: return
	var d = phrases[ch][step]
	match col:
		0: d.note = clampi(val, -1, 11)
		1: d.oct = clampi(val, 0, 8)
		2: d.inst = clampi(val, 0, 63)
		3, 4:
			var presets = ["----", "V40", "V80", "VA0", "D20", "D50", "D90", "F20", "F80", "FA0", "M40", "M80", "S60", "SA0"]
			var idx = clampi(val, 0, presets.size() - 1)
			if col == 3: d.fx1 = presets[idx]
			else: d.fx2 = presets[idx]
	phrases[ch][step] = d

func _btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 26)
	_style_btn(b, false)
	return b

func _style_btn(b: Button, active: bool) -> void:
	if b == null: return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	if active:
		sb.bg_color = COL_REC if b.text.begins_with("REC") or b.text.begins_with("KILL") else COL_ACTIVE
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
