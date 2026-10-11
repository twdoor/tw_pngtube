class_name TwberPerformanceRecorder extends VBoxContainer

signal state_changed

var selected_model: TwberRuntimeModel
var unavailable := false
var _target: TwberRuntimeModel
var _session: TwberModelTake
var _started_usec := 0
# The adapter owns time. Tests can inject a clock without sleeping.
var _clock: Callable = Time.get_ticks_usec
var _pending: TwberModelResource
var _last_model: TwberModelResource
var _last_animation_id := ""
var _last_path := ""
var _saving := false
var _record := Button.new()
var _cancel := Button.new()
var _retry := Button.new()
var _save_as := Button.new()
var _export := Button.new()
var _status := Label.new()
var _save_dialog := FileDialog.new()
var _export_dialog := TwberFrameExportDialog.new()


func _ready() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	_record.text = "Record performance"
	_record.tooltip_text = "Record the selected model's evaluated performance. Triggered clip results are captured; stage movement is not. Finished takes save as separate models."
	row.add_child(_record)
	_cancel.text = "Cancel"
	row.add_child(_cancel)
	_record.pressed.connect(func() -> void:
		if _session == null:
			start_recording(selected_model)
		else:
			finish_recording()
	)
	_cancel.pressed.connect(cancel_recording)
	var actions := HBoxContainer.new()
	add_child(actions)
	_retry.text = "Retry save"
	_retry.pressed.connect(save_pending)
	actions.add_child(_retry)
	_save_as.text = "Save elsewhere…"
	_save_as.pressed.connect(func() -> void: _save_dialog.popup_centered_ratio(0.7))
	actions.add_child(_save_as)
	_export.text = "Export last take PNGs…"
	_export.pressed.connect(func() -> void: _export_dialog.show_for(_last_model, _last_animation_id))
	actions.add_child(_export)
	_status.text = "Parameter takes save to Models/takes; open them in Editor to edit."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = PackedStringArray(["*.twber ; Twber model with recorded take"])
	_save_dialog.current_file = "recorded-take.twber"
	_save_dialog.file_selected.connect(save_pending)
	add_child(_save_dialog)
	add_child(_export_dialog)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()
	if _session != null:
		_status.text = "Recording %s · %.1f s" % [_target.name, _elapsed()]


func blocks_navigation() -> bool:
	return _session != null or _pending != null or _saving


func start_recording(target: TwberRuntimeModel) -> Error:
	if blocks_navigation() or unavailable:
		return ERR_BUSY
	if not is_instance_valid(target) or target.model == null:
		return ERR_UNCONFIGURED
	target.evaluate_parameters()
	var session := TwberModelTake.new()
	var error := session.start(target.model, target.get_parameter_values(), target.get_animation_playheads(), target.get_sprite_states())
	if error != OK:
		_status.text = "Cannot record: %s" % error_string(error)
		return error
	_target = target
	_session = session
	_started_usec = int(_clock.call())
	_target.performance_evaluated.connect(_on_performance_evaluated)
	_target.model_changing.connect(_on_target_replaced)
	_target.tree_exiting.connect(_on_target_removed)
	state_changed.emit()
	_refresh()
	return OK


func _on_performance_evaluated(values: Dictionary, playheads: Dictionary, sprites: Dictionary) -> void:
	var error := _session.sample(_elapsed(), values, playheads, sprites)
	if error != OK:
		# Preserve the valid prefix (including at the key limit) for saving.
		finish_recording()
		_status.text = "Recording stopped: %s. Saving captured input…" % error_string(error)


func _elapsed() -> float:
	return maxf(float(int(_clock.call()) - _started_usec) / 1000000.0, 0.0)


func finish_recording() -> Error:
	if _session == null:
		return ERR_UNCONFIGURED
	var result := _session.finish(_elapsed())
	var error: Error = result["error"]
	if error != OK:
		_status.text = "Cannot finish take: %s" % error_string(error)
		return error
	_disconnect_target()
	_session = null
	_pending = result["model"]
	_last_animation_id = result["animation_id"]
	state_changed.emit()
	_refresh()
	save_pending()
	return OK


func cancel_recording() -> void:
	if _session == null:
		return
	_disconnect_target()
	_session = null
	_status.text = "Recording canceled."
	state_changed.emit()
	_refresh()


func _on_target_replaced() -> void:
	cancel_recording()
	_status.text = "Recording canceled: its model was replaced."


func _on_target_removed() -> void:
	cancel_recording()
	_status.text = "Recording canceled: its model was removed."


func _disconnect_target() -> void:
	if is_instance_valid(_target):
		_target.performance_evaluated.disconnect(_on_performance_evaluated)
		_target.model_changing.disconnect(_on_target_replaced)
		_target.tree_exiting.disconnect(_on_target_removed)
	_target = null


func save_pending(path := "") -> void:
	if _pending == null or _saving:
		return
	var error := OK
	if path.is_empty():
		error = TwberAppSettings.ensure_directory("models/takes")
		var directory := TwberAppSettings.get_directory_path("models/takes")
		var stem := "take-%s-%s" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		path = directory.path_join(stem + ".twber")
		var index := 1
		while FileAccess.file_exists(path):
			path = directory.path_join("%s-%d.twber" % [stem, index])
			index += 1
	elif path.get_extension().to_lower() != "twber":
		path += ".twber"
	if error == OK and FileAccess.file_exists(path):
		error = ERR_ALREADY_EXISTS
	if error != OK:
		_save_failed(error)
		return
	_saving = true
	_status.text = "Saving take…"
	_refresh()
	var prepared := TwberModelCodec.prepare_twber_export(_pending)
	var task := TwberBackgroundTask.new()
	get_tree().root.add_child(task)
	error = task.start(TwberModelCodec.export_prepared_twber.bind(prepared, path))
	if error == OK:
		error = await task.completed
	else:
		task.queue_free()
	_saving = false
	if error != OK:
		_save_failed(error)
		return
	_last_model = _pending
	_pending = null
	_last_path = path
	_status.text = "Saved %s. Open this model in Editor to edit the take." % path.get_file()
	_status.tooltip_text = path
	state_changed.emit()
	_refresh()


func _save_failed(error: Error) -> void:
	_status.text = "Take kept in memory: %s. Retry or save to another folder before leaving." % error_string(error)
	state_changed.emit()
	_refresh()


func _refresh() -> void:
	_record.text = "Finish and save take" if _session != null else "Record performance"
	_record.disabled = unavailable or _pending != null or _saving or (_session == null and (
		not is_instance_valid(selected_model) or selected_model.model == null or (selected_model.model.parameters.is_empty() and selected_model.get_sprite_states().is_empty())))
	_cancel.visible = _session != null
	_retry.visible = _pending != null
	_save_as.visible = _pending != null
	_retry.disabled = _saving
	_save_as.disabled = _saving
	_export.visible = _last_model != null
	_export.disabled = blocks_navigation()
