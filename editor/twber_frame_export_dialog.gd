class_name TwberFrameExportDialog extends ConfirmationDialog

var _model: TwberModelResource
var _animation_id := ""
var _exporter := TwberFrameExporter.new()
var _directory := LineEdit.new()
var _width := SpinBox.new()
var _height := SpinBox.new()
var _fps := SpinBox.new()
var _zoom := SpinBox.new()
var _center_x := SpinBox.new()
var _center_y := SpinBox.new()
var _status := Label.new()
var _picker := FileDialog.new()
var _inputs := VBoxContainer.new()


func _ready() -> void:
	title = "Export PNG frames"
	ok_button_text = "Export"
	dialog_hide_on_ok = false
	min_size = Vector2i(560, 420)
	add_child(_inputs)
	var description := Label.new()
	description.text = "Transparent frames from the committed clip.\nThe canvas is centered on the coordinates below."
	_inputs.add_child(description)
	var row := HBoxContainer.new()
	_inputs.add_child(row)
	_directory.placeholder_text = "Choose a parent folder"
	_directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_directory)
	var browse := Button.new()
	browse.text = "Browse…"
	row.add_child(browse)
	browse.pressed.connect(func() -> void: _picker.popup_centered_ratio(0.7))
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	add_child(_picker)
	_picker.dir_selected.connect(func(path: String) -> void: _directory.text = path)
	_add_setting("Width", _width, 1, 4096, 1, 512)
	_add_setting("Height", _height, 1, 4096, 1, 512)
	_add_setting("Frames per second", _fps, 1, 120, 1, 30)
	_add_setting("Scale", _zoom, 0.01, 100, 0.01, 1)
	_add_setting("Center X", _center_x, -100000, 100000, 1, 0)
	_add_setting("Center Y", _center_y, -100000, 100000, 1, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inputs.add_child(_status)
	confirmed.connect(_export)
	canceled.connect(_exporter.cancel)
	close_requested.connect(_exporter.cancel)
	_exporter.progress.connect(func(completed: int, total: int) -> void: _status.text = "Exporting frame %d of %d…" % [completed, total])


func _add_setting(label_text: String, input: SpinBox, minimum: float, maximum: float, step: float, value: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(input)
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = value
	_inputs.add_child(row)


func show_for(model: TwberModelResource, animation_id: String) -> void:
	if _exporter.running:
		return
	var clip := TwberEditTimeline.find(model, animation_id)
	if clip == null:
		return
	_model = model.duplicate(true)
	_animation_id = animation_id
	_fps.value = clip.fps
	_status.text = "A new folder will be created. Existing exports are kept."
	popup_centered()


func _export() -> void:
	if _exporter.running or _model == null:
		return
	var parent_path := _directory.text.strip_edges()
	if not DirAccess.dir_exists_absolute(parent_path):
		_status.text = "Choose an existing parent folder."
		return
	var name := _animation_id.validate_filename() + "_frames"
	var output := parent_path.path_join(name)
	var index := 2
	while DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		output = parent_path.path_join(name + "_%d" % index)
		index += 1
	get_ok_button().disabled = true
	var error := await _exporter.export_sequence(self, _model, _animation_id, output,
		Vector2i(int(_width.value), int(_height.value)), _fps.value, _zoom.value, Vector2(_center_x.value, _center_y.value))
	if not is_instance_valid(self) or not is_inside_tree():
		return
	get_ok_button().disabled = false
	if error == OK:
		_status.text = "Exported to " + output
	elif error == ERR_SKIP:
		_status.text = "Export cancelled. No output was kept."
	else:
		_status.text = "Export failed: " + error_string(error)


func _exit_tree() -> void:
	_exporter.cancel()
