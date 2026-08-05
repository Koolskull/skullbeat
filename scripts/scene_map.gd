class_name SceneMap
extends PanelContainer

## Tiny window map — top-left, LGPT/LSDJ style.
## Shift+arrows move cursor (host). Touch taps cells.

signal scene_selected(id: int)

const COLS := 4
const ROWS := 2

## left→right, top→bottom
const LABELS := ["PHR", "LCH", "INS", "MIX", "TBL", "PRJ", "SET", "EXP"]
const IDS := ["phrase", "launch", "inst", "mixer", "table", "project", "settings", "export"]

const COL_BG := Color("#0a0a0a")
const COL_BORDER := Color("#333333")
const COL_TEXT := Color("#888888")
const COL_ACTIVE := Color("#ffff00")
const COL_HERE := Color("#ffffff")

var cursor: int = 0
var current: int = 0
var _cells: Array = []

func _ready() -> void:
	_build()

func _build() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(140, 48)

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)

	_cells.clear()
	for i in range(LABELS.size()):
		var b := Button.new()
		b.text = LABELS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(32, 18)
		b.add_theme_font_size_override("font_size", 10)
		_style_cell(b, false, false)
		var idx = i
		b.pressed.connect(func(): select(idx, true))
		grid.add_child(b)
		_cells.append(b)
	_repaint()

func id_name(i: int = -1) -> String:
	var n: int = current if i < 0 else i
	return IDS[clampi(n, 0, IDS.size() - 1)]

func select(i: int, emit_signal: bool = true) -> void:
	cursor = clampi(i, 0, IDS.size() - 1)
	current = cursor
	_repaint()
	if emit_signal:
		scene_selected.emit(current)

func move(dx: int, dy: int) -> void:
	var col: int = cursor % COLS
	var row: int = int(float(cursor) / float(COLS))
	col = clampi(col + dx, 0, COLS - 1)
	row = clampi(row + dy, 0, ROWS - 1)
	select(row * COLS + col, true)

func _repaint() -> void:
	for i in range(_cells.size()):
		_style_cell(_cells[i], i == current, i == cursor)

func _style_cell(b: Button, here: bool, cur: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	if here:
		sb.bg_color = COL_ACTIVE
		sb.border_color = COL_ACTIVE
		b.add_theme_color_override("font_color", Color("#000000"))
	elif cur:
		sb.bg_color = Color("#1a1a00")
		sb.border_color = COL_ACTIVE
		b.add_theme_color_override("font_color", COL_HERE)
	else:
		sb.bg_color = COL_BG
		sb.border_color = COL_BORDER
		b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
