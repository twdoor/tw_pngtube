class_name TwberEnvironmentParameterControl extends PanelContainer

signal value_changed(parameter_id: String, value: Variant)
signal source_changed(parameter_id: String, source_id: StringName)
signal source_configuration_changed(parameter_id: String, configuration: Dictionary)

@onready var _name_label: Label = %NameLabel
@onready var _type_label: Label = %TypeLabel
@onready var _source_option: OptionButton = %SourceOption
@onready var _binding_host: VBoxContainer = %BindingHost
@onready var _bool_editor: CheckButton = %BoolEditor
@onready var _scalar_editor: HBoxContainer = %ScalarEditor
@onready var _scalar_slider: HSlider = %ScalarSlider
@onready var _scalar_value: SpinBox = %ScalarValue
@onready var _vector_editor: TwberVectorPlane = %VectorPlane
@onready var _reset_button: Button = %ResetButton

var _parameter: TwberParameterResource
var _sources_by_id: Dictionary[StringName, Dictionary] = {}
var _selected_source := StringName()
var _binding_control: TwberInputBindingControl
var _updating := false


func _ready() -> void:
	_source_option.item_selected.connect(_on_source_selected)
	_bool_editor.toggled.connect(_on_bool_changed)
	_scalar_slider.value_changed.connect(_on_scalar_slider_changed)
	_scalar_value.value_changed.connect(_on_scalar_spin_changed)
	_vector_editor.value_changed.connect(_on_vector_changed)
	_reset_button.pressed.connect(_on_reset_pressed)


func configure(parameter: TwberParameterResource, input_sources: Array[Dictionary]) -> void:
	_parameter = parameter
	if _parameter == null:
		return
	_name_label.text = _parameter.name if not _parameter.name.is_empty() else _parameter.id
	_type_label.text = _get_type_name(_parameter.value_type)
	_configure_source_options(input_sources)
	_configure_value_editor()
	_binding_host.visible = false
	set_value(_parameter.get_default_value())


func restore_source_binding(source_id: StringName, configuration: Dictionary) -> bool:
	if not _sources_by_id.has(source_id):
		return false
	for option_index: int in _source_option.item_count:
		if StringName(_source_option.get_item_metadata(option_index)) == source_id:
			_source_option.select(option_index)
			break
	_activate_source(source_id, configuration)
	return true


func get_source_configuration() -> Dictionary:
	return _binding_control.get_configuration() if _binding_control != null else {}


func apply_source_value(value: Variant) -> Variant:
	return _binding_control.apply_source_value(value) if _binding_control != null else value


func set_source_preview(raw_value: Variant, mapped_value: Variant) -> void:
	if _binding_control != null:
		_binding_control.set_preview(raw_value, mapped_value)


func set_value(value: Variant) -> void:
	if _parameter == null:
		return
	var normalized: Variant = _parameter.value_from_coordinate(_parameter.coordinate_from_value(value))
	_updating = true
	match _parameter.value_type:
		TwberParameterResource.ValueType.BOOL:
			_bool_editor.button_pressed = bool(normalized)
		TwberParameterResource.ValueType.VECTOR2:
			_vector_editor.set_value(normalized)
		_:
			_scalar_slider.value = float(normalized)
			_scalar_value.value = float(normalized)
	_updating = false


func _configure_source_options(input_sources: Array[Dictionary]) -> void:
	_sources_by_id.clear()
	_source_option.clear()
	_source_option.add_item("Manual")
	_source_option.set_item_metadata(0, StringName())
	for descriptor: Dictionary in input_sources:
		var source_id := StringName(descriptor.get("source_id", ""))
		if source_id.is_empty():
			continue
		_sources_by_id[source_id] = descriptor
		var provider_name := String(descriptor.get("provider_name", "Input"))
		var source_name := String(descriptor.get("name", source_id))
		_source_option.add_item("%s · %s" % [provider_name, source_name])
		_source_option.set_item_metadata(_source_option.item_count - 1, source_id)


func _activate_source(source_id: StringName, configuration: Dictionary = {}) -> void:
	_clear_binding_control()
	_selected_source = source_id
	_set_manual_editor_enabled(source_id.is_empty())
	if source_id.is_empty():
		return
	var descriptor: Dictionary = _sources_by_id.get(source_id, {})
	var binding_scene_path := String(descriptor.get("binding_scene", ""))
	if binding_scene_path.is_empty():
		return
	var binding_scene := load(binding_scene_path) as PackedScene
	if binding_scene == null:
		push_warning("Could not load input binding UI: %s" % binding_scene_path)
		return
	var instance := binding_scene.instantiate()
	if instance is not TwberInputBindingControl:
		instance.free()
		push_warning("Input binding UI must extend TwberInputBindingControl.")
		return
	_binding_control = instance as TwberInputBindingControl
	_binding_host.add_child(_binding_control)
	_binding_host.visible = true
	_binding_control.configure(_parameter, configuration)
	_binding_control.configuration_changed.connect(_on_binding_configuration_changed)


func _clear_binding_control() -> void:
	if _binding_control == null:
		return
	_binding_host.remove_child(_binding_control)
	_binding_control.queue_free()
	_binding_control = null
	_binding_host.visible = false


func _configure_value_editor() -> void:
	var is_bool := _parameter.value_type == TwberParameterResource.ValueType.BOOL
	var is_vector := _parameter.value_type == TwberParameterResource.ValueType.VECTOR2
	_bool_editor.visible = is_bool
	_scalar_editor.visible = not is_bool and not is_vector
	_vector_editor.visible = is_vector
	if is_vector:
		_vector_editor.configure(
			_parameter.get_vector_min(),
			_parameter.get_vector_max(),
			maxf(_parameter.step, 0.0001),
		)
	elif not is_bool:
		var minimum := _parameter.get_scalar_min()
		var maximum := _parameter.get_scalar_max()
		var value_step := maxf(_parameter.step, 0.0001)
		_scalar_slider.min_value = minimum
		_scalar_slider.max_value = maximum
		_scalar_slider.step = value_step
		_scalar_value.min_value = minimum
		_scalar_value.max_value = maximum
		_scalar_value.step = value_step


func _on_source_selected(index: int) -> void:
	if _parameter == null:
		return
	var source_id := StringName(_source_option.get_item_metadata(index))
	_activate_source(source_id)
	source_changed.emit(_parameter.id, source_id)
	if not source_id.is_empty():
		source_configuration_changed.emit(_parameter.id, get_source_configuration())


func _on_binding_configuration_changed(configuration: Dictionary) -> void:
	if _parameter != null:
		source_configuration_changed.emit(_parameter.id, configuration)


func _set_manual_editor_enabled(enabled: bool) -> void:
	if _parameter == null:
		return
	var is_bool := _parameter.value_type == TwberParameterResource.ValueType.BOOL
	var is_vector := _parameter.value_type == TwberParameterResource.ValueType.VECTOR2
	_bool_editor.visible = enabled and is_bool
	_scalar_editor.visible = enabled and not is_bool and not is_vector
	_bool_editor.disabled = not enabled
	_scalar_slider.editable = enabled
	_scalar_value.editable = enabled
	_vector_editor.set_editable(enabled)


func _on_bool_changed(value: bool) -> void:
	_emit_value(value)


func _on_scalar_slider_changed(value: float) -> void:
	if _updating:
		return
	_updating = true
	_scalar_value.value = value
	_updating = false
	_emit_value(value)


func _on_scalar_spin_changed(value: float) -> void:
	if _updating:
		return
	_updating = true
	_scalar_slider.value = value
	_updating = false
	_emit_value(value)


func _on_vector_changed(value: Vector2) -> void:
	_emit_value(value)


func _on_reset_pressed() -> void:
	if _parameter == null:
		return
	set_value(_parameter.get_default_value())
	value_changed.emit(_parameter.id, _parameter.get_default_value())


func _emit_value(value: Variant) -> void:
	if not _updating and _parameter != null:
		value_changed.emit(_parameter.id, value)


func _get_type_name(value_type: int) -> String:
	match value_type:
		TwberParameterResource.ValueType.BOOL:
			return "BOOL"
		TwberParameterResource.ValueType.INT:
			return "INT"
		TwberParameterResource.ValueType.VECTOR2:
			return "VECTOR2"
		_:
			return "FLOAT"
