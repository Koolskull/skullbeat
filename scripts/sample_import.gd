class_name SampleImport
extends RefCounted

## Sample import for Skullbeat on iPad / Xogot
##
## Primary path: native file dialog (Files app / AudioShare File Provider / iCloud)
## AudioShare: user can Open In → Skullbeat, or pick via Files from AudioShare provider
## Full AudioShare SDK (initiateSoundImport) needs a native iOS plugin — documented, not required
##
## Supported now: PCM WAV (8/16/24/32-bit, mono or stereo→mono mix)
## MP3/OGG can be added later via Godot AudioStream loaders when paths are available

signal import_finished(success: bool, message: String, inst_id: int)

var _target_inst: int = 1
var _engine: SynthEngine = null
var _host: Node = null

func setup(host: Node, engine: SynthEngine) -> void:
	_host = host
	_engine = engine

func set_target_instrument(id: int) -> void:
	_target_inst = clampi(id, 0, 63)

## Open system file picker filtered for audio
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
	# Native dialog on iOS when available
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show(
			"Import sample → INST %02X" % _target_inst,
			OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			filters,
			_on_native_dialog
		)
	else:
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.use_native_dialog = true
		dlg.filters = filters
		dlg.title = "Import sample"
		_host.add_child(dlg)
		dlg.file_selected.connect(func(path: String):
			_load_path(path)
			dlg.queue_free()
		)
		dlg.canceled.connect(func(): dlg.queue_free())
		dlg.popup_centered(Vector2i(700, 500))

func _on_native_dialog(status: bool, selected: PackedStringArray, _filter_idx: int) -> void:
	if not status or selected.is_empty():
		import_finished.emit(false, "Import cancelled", _target_inst)
		return
	_load_path(selected[0])

func _load_path(path: String) -> void:
	if _engine == null:
		import_finished.emit(false, "No engine", _target_inst)
		return
	var lower = path.to_lower()
	if lower.ends_with(".wav"):
		var ok = load_wav_into_instrument(path, _target_inst)
		if ok:
			import_finished.emit(true, "WAV → INST %02X  %s" % [_target_inst, path.get_file()], _target_inst)
		else:
			import_finished.emit(false, "WAV parse failed: %s" % path.get_file(), _target_inst)
	elif lower.ends_with(".mp3") or lower.ends_with(".ogg"):
		# Try Godot stream → rough decode via playback is complex; copy path note for now
		var ok2 = load_via_audiostream(path, _target_inst)
		if ok2:
			import_finished.emit(true, "Stream → INST %02X  %s" % [_target_inst, path.get_file()], _target_inst)
		else:
			import_finished.emit(false, "Need WAV for sample layer (convert in AudioShare)", _target_inst)
	else:
		# Attempt WAV-style parse anyway; many exports are RIFF
		var ok3 = load_wav_into_instrument(path, _target_inst)
		if ok3:
			import_finished.emit(true, "Loaded → INST %02X" % _target_inst, _target_inst)
		else:
			import_finished.emit(false, "Unsupported format — export WAV from AudioShare", _target_inst)

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
	var pcm: PackedFloat32Array = parsed["pcm"]
	var rate: float = parsed["rate"]
	_engine.get_instrument(inst_id).load_sample_mono(pcm, rate)
	# Prefer sample layer when user imports
	_engine.get_instrument(inst_id).sample_enabled = true
	_engine.get_instrument(inst_id).synth_enabled = true  # keep both unless user disables
	return true

## Parse RIFF/WAVE → mono float PCM
static func parse_wav(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 44:
		return {}
	# RIFF header
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
		var chunk_id = char(bytes[offset]) + char(bytes[offset + 1]) + char(bytes[offset + 2]) + char(bytes[offset + 3])
		var chunk_size = bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24)
		if chunk_size < 0:
			break
		offset += 8
		if chunk_id == "fmt ":
			if offset + 16 > bytes.size():
				return {}
			# audio format at 0, channels at 2, rate at 4, bits at 14
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
	if bits == 16:
		var frames = (end - data_off) / (2 * channels)
		pcm.resize(frames)
		for n in range(frames):
			var acc := 0.0
			for c in range(channels):
				var lo = bytes[i]
				var hi = bytes[i + 1]
				var sample = lo | (hi << 8)
				if sample >= 32768:
					sample -= 65536
				acc += float(sample) / 32768.0
				i += 2
			pcm[n] = acc / float(channels)
	elif bits == 8:
		var frames8 = (end - data_off) / channels
		pcm.resize(frames8)
		for n in range(frames8):
			var acc := 0.0
			for c in range(channels):
				acc += (float(bytes[i]) - 128.0) / 128.0
				i += 1
			pcm[n] = acc / float(channels)
	elif bits == 24:
		var frames24 = (end - data_off) / (3 * channels)
		pcm.resize(frames24)
		for n in range(frames24):
			var acc := 0.0
			for c in range(channels):
				var b0 = bytes[i]
				var b1 = bytes[i + 1]
				var b2 = bytes[i + 2]
				var sample = b0 | (b1 << 8) | (b2 << 16)
				if sample >= 0x800000:
					sample -= 0x1000000
				acc += float(sample) / 8388608.0
				i += 3
			pcm[n] = acc / float(channels)
	elif bits == 32:
		# assume 32-bit float
		var frames32 = (end - data_off) / (4 * channels)
		pcm.resize(frames32)
		for n in range(frames32):
			var acc := 0.0
			for c in range(channels):
				acc += bytes.decode_float(i)
				i += 4
			pcm[n] = acc / float(channels)
	else:
		return {}
	return {"pcm": pcm, "rate": float(rate), "channels": channels, "bits": bits}

## Best-effort for compressed formats — limited without decode pipeline
func load_via_audiostream(path: String, inst_id: int) -> bool:
	# Godot can load streams for playback but extracting PCM offline is non-trivial.
	# Prefer user exports WAV from AudioShare. Return false to push that message.
	return false

## Try to jump to AudioShare app (user then Open In / share back)
static func open_audioshare() -> void:
	# URL schemes used by AudioShare; may no-op if not installed
	var candidates = [
		"audioshare://",
		"audiosharecmd://",
		"audioshare.import://"
	]
	for u in candidates:
		if OS.has_feature("ios") or OS.has_feature("mobile"):
			OS.shell_open(u)
			return
	OS.shell_open("https://apps.apple.com/app/audioshare/id543859300")
