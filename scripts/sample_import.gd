class_name SampleImport
extends RefCounted

## WAV / AudioShare import — no DSP, only fills Instrument.pcm

signal import_finished(success: bool, message: String, inst_id: int)

var _target_inst: int = 1
var _engine = null
var _host: Node = null
var last_path: String = ""
var last_meta: Dictionary = {}

func setup(host: Node, engine) -> void:
	_host = host
	_engine = engine

func set_target_instrument(id: int) -> void:
	_target_inst = clampi(id, 0, 63)

func get_target_instrument() -> int:
	return _target_inst

func open_file_picker() -> void:
	if _host == null:
		return
	var filters := PackedStringArray([
		"*.wav ; WAV",
		"*.aif,*.aiff ; AIFF",
		"*.mp3 ; MP3",
		"*.ogg ; OGG",
		"*.caf ; CAF",
		"* ; All"
	])
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.filters = filters
	dlg.title = "Import sample -> INST %02X" % _target_inst
	_host.add_child(dlg)
	dlg.file_selected.connect(func(path: String):
		_load_path(path)
		dlg.queue_free()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
		import_finished.emit(false, "Import cancelled", _target_inst)
	)
	dlg.popup_centered(Vector2i(700, 500))

func _load_path(path: String) -> void:
	last_path = path
	if _engine == null:
		import_finished.emit(false, "No engine", _target_inst)
		return
	var lower = path.to_lower()
	if lower.ends_with(".wav"):
		var ok = load_wav_into_instrument(path, _target_inst)
		if ok:
			var m = last_meta
			var rate_f = float(m.get("rate", 44100))
			var frames_f = float(m.get("frames", 0))
			var ms = int(1000.0 * frames_f / maxf(rate_f, 1.0))
			var info = "%s  %dHz  %dms" % [path.get_file(), int(rate_f), ms]
			import_finished.emit(true, "WAV -> INST %02X  %s" % [_target_inst, info], _target_inst)
		else:
			import_finished.emit(false, "WAV parse failed: %s" % path.get_file(), _target_inst)
	elif lower.ends_with(".mp3") or lower.ends_with(".ogg"):
		import_finished.emit(false, "Export WAV from AudioShare for sample layer", _target_inst)
	else:
		var ok3 = load_wav_into_instrument(path, _target_inst)
		if ok3:
			import_finished.emit(true, "Loaded -> INST %02X  %s" % [_target_inst, path.get_file()], _target_inst)
		else:
			import_finished.emit(false, "Unsupported - export WAV from AudioShare", _target_inst)

func load_wav_into_instrument(path: String, inst_id: int) -> bool:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size = f.get_length()
	if size < 44:
		return false
	var data = f.get_buffer(size)
	f.close()
	var parsed = parse_wav(data)
	if parsed.is_empty():
		return false
	return inject_pcm(parsed["pcm"], parsed["rate"], inst_id, path.get_file())

func inject_pcm(pcm: PackedFloat32Array, rate: float, inst_id: int, label: String = "") -> bool:
	if _engine == null or pcm.size() < 16:
		return false
	var inst = _engine.get_instrument(inst_id)
	inst.load_sample_mono(pcm, rate)
	if label != "":
		inst.name = label.substr(0, mini(12, label.length()))
	last_meta = {
		"rate": rate,
		"frames": pcm.size(),
		"label": label,
		"inst": inst_id
	}
	return true

static func parse_wav(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 44:
		return {}
	if bytes[0] != 0x52 or bytes[1] != 0x49 or bytes[2] != 0x46 or bytes[3] != 0x46:
		return {}
	if bytes[8] != 0x57 or bytes[9] != 0x41 or bytes[10] != 0x56 or bytes[11] != 0x45:
		return {}
	var offset := 12
	var channels := 1
	var rate := 44100
	var bits := 16
	var data_off := -1
	var data_size := 0
	while offset + 8 <= bytes.size():
		var chunk_id := (
			String.chr(bytes[offset])
			+ String.chr(bytes[offset + 1])
			+ String.chr(bytes[offset + 2])
			+ String.chr(bytes[offset + 3])
		)
		var chunk_size: int = bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24)
		if chunk_size < 0:
			break
		offset += 8
		if chunk_id == "fmt ":
			if offset + 16 > bytes.size():
				return {}
			channels = bytes[offset + 2] | (bytes[offset + 3] << 8)
			rate = bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24)
			bits = bytes[offset + 14] | (bytes[offset + 15] << 8)
		elif chunk_id == "data":
			data_off = offset
			data_size = chunk_size
			break
		offset += chunk_size
		if chunk_size % 2 == 1:
			offset += 1
	if data_off < 0 or data_size <= 0:
		return {}
	var end = mini(data_off + data_size, bytes.size())
	var pcm := PackedFloat32Array()
	var i = data_off
	var ch_count = maxi(channels, 1)
	if bits == 16:
		var frames = int(float(end - data_off) / float(2 * ch_count))
		pcm.resize(frames)
		for n in range(frames):
			var acc := 0.0
			for c in range(ch_count):
				var lo = bytes[i]
				var hi = bytes[i + 1]
				var sample = lo | (hi << 8)
				if sample >= 32768:
					sample -= 65536
				acc += float(sample) / 32768.0
				i += 2
			pcm[n] = acc / float(ch_count)
	elif bits == 8:
		var frames8 = int(float(end - data_off) / float(ch_count))
		pcm.resize(frames8)
		for n in range(frames8):
			var acc8 := 0.0
			for c in range(ch_count):
				acc8 += (float(bytes[i]) - 128.0) / 128.0
				i += 1
			pcm[n] = acc8 / float(ch_count)
	elif bits == 24:
		var frames24 = int(float(end - data_off) / float(3 * ch_count))
		pcm.resize(frames24)
		for n in range(frames24):
			var acc24 := 0.0
			for c in range(ch_count):
				var b0 = bytes[i]
				var b1 = bytes[i + 1]
				var b2 = bytes[i + 2]
				var sample24 = b0 | (b1 << 8) | (b2 << 16)
				if sample24 >= 0x800000:
					sample24 -= 0x1000000
				acc24 += float(sample24) / 8388608.0
				i += 3
			pcm[n] = acc24 / float(ch_count)
	elif bits == 32:
		var frames32 = int(float(end - data_off) / float(4 * ch_count))
		pcm.resize(frames32)
		for n in range(frames32):
			var acc32 := 0.0
			for c in range(ch_count):
				acc32 += bytes.decode_float(i)
				i += 4
			pcm[n] = acc32 / float(ch_count)
	else:
		return {}
	return {
		"pcm": pcm,
		"rate": float(rate),
		"channels": channels,
		"bits": bits,
		"frames": pcm.size()
	}

static func open_audioshare() -> void:
	if OS.has_feature("ios") or OS.has_feature("mobile"):
		OS.shell_open("audioshare://")
		return
	OS.shell_open("https://apps.apple.com/app/audioshare/id543859300")
