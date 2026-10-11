class_name TwberModelDocument extends RefCounted

signal changed(change: TwberDocumentChange)
signal dirty_changed(dirty: bool)

# First document boundary uses the existing resource schema as a compatibility
# DTO. All scene/UI access belongs to adapters, never to this owner.
const MAX_UNDO_STEPS := 64

var _model := TwberModelResource.new()
var _owner := RefCounted.new()
var _state := RefCounted.new()
var _saved_state: RefCounted = _state
var _revision := 0
var _history: Array[Dictionary] = []
var _cursor := 0
var _publishing := false
var _diagnostics: Array[String] = []


func replace_model(value: TwberModelResource) -> Error:
	if _publishing:
		return ERR_BUSY
	_diagnostics = TwberDocumentValidator.validate(value)
	if not _diagnostics.is_empty():
		return ERR_INVALID_DATA
	var was_dirty := is_dirty()
	_model = value.duplicate(true)
	_owner = RefCounted.new()
	_state = RefCounted.new()
	_saved_state = _state
	_history.clear()
	_cursor = 0
	_revision += 1
	_publish("Open model", TwberDocumentChange.Kind.STRUCTURE, [], was_dirty)
	return OK


func execute(command: TwberDocumentCommand) -> Error:
	if _publishing:
		return ERR_BUSY
	if command == null:
		return ERR_INVALID_PARAMETER
	var candidate := _model.duplicate(true) as TwberModelResource
	command.error_message = ""
	var error := command.apply(candidate)
	if error != OK:
		_diagnostics = [command.error_message if not command.error_message.is_empty() else error_string(error)]
		return error
	_diagnostics = TwberDocumentValidator.validate(candidate)
	if not _diagnostics.is_empty():
		return ERR_INVALID_DATA
	if not command.did_change:
		return OK
	var was_dirty := is_dirty()
	_history.resize(_cursor)
	var next_state := RefCounted.new()
	# Snapshots prioritize isolation for the initial slice. A bounded history
	# limits retained versions; compact inverse patches can replace this backend.
	var entry := {
		"before": _model,
		"after": candidate.duplicate(true),
		"before_state": _state,
		"after_state": next_state,
		"label": command.label,
		"kinds": command.kinds,
		"ids": command.layer_ids.duplicate(),
	}
	_history.append(entry)
	if _history.size() > MAX_UNDO_STEPS:
		_history.pop_front()
	_cursor = _history.size()
	_model = entry["after"]
	_state = next_state
	_revision += 1
	_publish(command.label, command.kinds, command.layer_ids, was_dirty)
	return OK


func undo() -> bool:
	if _publishing or _cursor == 0:
		return false
	var was_dirty := is_dirty()
	_cursor -= 1
	var entry := _history[_cursor]
	_model = entry["before"]
	_state = entry["before_state"]
	_revision += 1
	_publish("Undo " + entry["label"], entry["kinds"], entry["ids"], was_dirty)
	return true


func redo() -> bool:
	if _publishing or _cursor >= _history.size():
		return false
	var was_dirty := is_dirty()
	var entry := _history[_cursor]
	_cursor += 1
	_model = entry["after"]
	_state = entry["after_state"]
	_revision += 1
	_publish("Redo " + entry["label"], entry["kinds"], entry["ids"], was_dirty)
	return true


func snapshot() -> TwberDocumentSnapshot:
	return TwberDocumentSnapshot.new(_model, _owner, _state, _revision)


func mark_saved(saved: TwberDocumentSnapshot) -> bool:
	if _publishing or saved == null or not saved.belongs_to(_owner):
		return false
	var was_dirty := is_dirty()
	_saved_state = saved.get_state_token()
	if was_dirty != is_dirty():
		_publishing = true
		dirty_changed.emit(is_dirty())
		_publishing = false
	return true


func is_dirty() -> bool:
	return _state != _saved_state


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _history.size()


func get_undo_label() -> String:
	return String(_history[_cursor - 1]["label"]) if can_undo() else ""


func get_redo_label() -> String:
	return String(_history[_cursor]["label"]) if can_redo() else ""


func invalidate_saved_state() -> void:
	if _publishing:
		return
	var was_dirty := is_dirty()
	_saved_state = null
	if not was_dirty:
		_publishing = true
		dirty_changed.emit(true)
		_publishing = false


func get_revision() -> int:
	return _revision


func get_diagnostics() -> Array[String]:
	return _diagnostics.duplicate()


func _publish(label: String, kinds: int, ids: Array[String], was_dirty: bool) -> void:
	_publishing = true
	changed.emit(TwberDocumentChange.new(_revision, label, kinds, ids))
	if was_dirty != is_dirty():
		dirty_changed.emit(is_dirty())
	_publishing = false
