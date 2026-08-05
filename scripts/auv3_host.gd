class_name AUv3Host
extends Node

## AUv3 HOST — SHELVED (intention only)
## See docs/IOS_AUDIO.md for full rationale and phases.
## Pure GDScript cannot host AUs — needs native bridge later.

# units_changed reserved for when native host is linked
@warning_ignore("unused_signal")
signal units_changed
signal host_error(message: String)

var available: bool = false
var shelved_reason: String = "Needs native iOS AUv3 host plugin (see docs/IOS_AUDIO.md)"

func _ready() -> void:
	if Engine.has_singleton("SkullbeatAUv3"):
		available = true
	else:
		available = false

func is_available() -> bool:
	return available

func status_line() -> String:
	if available:
		return "AUv3 HOST READY"
	return "AUv3 SHELVED · " + shelved_reason

func list_available_units() -> Array:
	return []

func load_effect(_unit_id: String, _bus: String = "Master") -> bool:
	push_warning("[AUv3] shelved — " + shelved_reason)
	host_error.emit("AUv3 not linked")
	return false

func load_instrument(_unit_id: String, _inst_slot: int) -> bool:
	push_warning("[AUv3] shelved — " + shelved_reason)
	host_error.emit("AUv3 not linked")
	return false

func note_on_au(_inst_slot: int, _note: int, _velocity: float = 1.0) -> void:
	pass

func note_off_au(_inst_slot: int, _note: int) -> void:
	pass

func show_au_ui(_inst_slot: int) -> void:
	host_error.emit("AUv3 UI unavailable (shelved)")

func unload_all() -> void:
	pass
