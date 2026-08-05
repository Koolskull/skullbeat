class_name ProjectStore
extends RefCounted

## Project I/O only. No UI. No DSP.
## Format: JSON under user://projects/

const DIR := "user://projects"
const EXT := ".skull.json"
const VERSION := 1

signal saved(path: String)
signal loaded(path: String)
signal failed(msg: String)

var project_name: String = "UNTITLED"
var last_path: String = ""

func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)

func default_path(name: String = "") -> String:
	ensure_dir()
	var n := name if name != "" else project_name
	n = n.strip_edges().replace(" ", "_").to_upper()
	if n == "":
		n = "UNTITLED"
	return DIR.path_join(n + EXT)

func list_projects() -> PackedStringArray:
	ensure_dir()
	var out: PackedStringArray = PackedStringArray()
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(EXT):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

## Build serializable dict from app state
func pack(bpm: float, phrases: Array, tables: Array, banks: Array, settings: Dictionary) -> Dictionary:
	return {
		"v": VERSION,
		"name": project_name,
		"bpm": bpm,
		"phrases": phrases,
		"tables": tables,
		"banks": banks,
		"settings": settings,
	}

func save(data: Dictionary, path: String = "") -> bool:
	ensure_dir()
	if path == "":
		path = default_path(str(data.get("name", project_name)))
	var json := JSON.stringify(data, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		failed.emit("Save failed: %s" % path)
		return false
	f.store_string(json)
	f.close()
	last_path = path
	project_name = str(data.get("name", project_name))
	saved.emit(path)
	return true

func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		failed.emit("Missing: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		failed.emit("Open failed: %s" % path)
		return {}
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		failed.emit("Bad project JSON")
		return {}
	last_path = path
	project_name = str(data.get("name", "LOADED"))
	loaded.emit(path)
	return data

## Export song as compact pattern text (tracker dump) + JSON twin
func export_song(data: Dictionary, path: String = "") -> bool:
	ensure_dir()
	if path == "":
		path = DIR.path_join(str(data.get("name", project_name)) + ".export.txt")
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# SKULLBEAT EXPORT")
	lines.append("# name %s" % str(data.get("name", "")))
	lines.append("# bpm %s" % str(data.get("bpm", 128)))
	var phrases = data.get("phrases", [])
	for ch in range(phrases.size()):
		lines.append("")
		lines.append("# CH%d" % (ch + 1))
		var phrase = phrases[ch]
		for s in range(phrase.size()):
			var d = phrase[s]
			var note = int(d.get("note", -1))
			var nt := "---"
			if note >= 0:
				var names = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
				nt = names[note % 12]
			var oc := "%d" % int(d.get("oct", 4)) if note >= 0 else "-"
			var inst := "%02X" % int(d.get("inst", 0)) if note >= 0 else "--"
			lines.append("%02X %s %s %s %s %s" % [
				s, nt, oc, inst,
				str(d.get("fx1", "----")),
				str(d.get("fx2", "----"))
			])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		failed.emit("Export failed")
		return false
	f.store_string("\n".join(lines))
	f.close()
	# also write json sibling
	save(data, path.replace(".export.txt", ".export.json"))
	saved.emit(path)
	return true
