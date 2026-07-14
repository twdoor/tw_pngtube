class_name TwberEnvironment extends Node

const PARAMETER_CONTROL_SCENE := preload("res://environment/parameter_control.tscn")
const PACKAGE_CARD_SCENE := preload("res://environment/package_card.tscn")
const MODEL_INPUT_PROFILE := preload("res://environment/core/twber_model_input_profile.gd")
const ENVIRONMENT_SETTINGS := preload("res://environment/core/twber_environment_settings.gd")
const MODEL_FILTERS := [
	"*.twber ; Twber model packages",
	"*.tres, *.res ; Editable model resources",
]

@onready var _runtime_model: TwberRuntimeModel = %RuntimeModel
@onready var _input_registry: TwberInputRegistry = %InputRegistry
@onready var _package_manager: TwberPackageManager = %PackageManager
@onready var _package_list: VBoxContainer = %PackageList
@onready var _preview_interaction: Control = %PreviewInteraction
@onready var _open_model_button: Button = %OpenModelButton
@onready var _reset_view_button: Button = %ResetViewButton
@onready var _model_name_label: Label = %ModelNameLabel
@onready var _status_label: Label = %StatusLabel
@onready var _empty_parameters_label: Label = %EmptyParametersLabel
@onready var _parameter_list: VBoxContainer = %ParameterList
@onready var _open_model_dialog: FileDialog = %OpenModelDialog
@onready var _error_dialog: AcceptDialog = %ErrorDialog

var _parameter_controls: Dictionary[String, TwberEnvironmentParameterControl] = {}
var _source_bindings: Dictionary[String, Dictionary] = {}
var _current_model_path := ""
var _view_zoom := 1.0
var _view_pan := Vector2.ZERO
var _panning := false
var _environment_settings


func _ready() -> void:
	get_viewport().gui_embed_subwindows = false
	_environment_settings = ENVIRONMENT_SETTINGS.new()
	_environment_settings.load()
	_open_model_dialog.filters = PackedStringArray(MODEL_FILTERS)
	_open_model_button.pressed.connect(_popup_open_model_dialog)
	_reset_view_button.pressed.connect(reset_model_view)
	_open_model_dialog.file_selected.connect(load_model)
	_input_registry.value_changed.connect(_on_input_value_changed)
	_preview_interaction.gui_input.connect(_on_preview_gui_input)
	_package_manager.package_loaded.connect(_on_package_loaded)
	_package_manager.package_failed.connect(_on_package_failed)
	_package_manager.discovery_finished.connect(_on_package_discovery_finished)
	get_viewport().size_changed.connect(_update_model_transform)
	_environment_settings.mark_all_packages_uninstalled()
	_package_manager.discover_packages()
	_update_model_transform.call_deferred()


func _popup_open_model_dialog() -> void:
	_open_model_dialog.show()


func load_model(path: String) -> Error:
	var error: Error = _runtime_model.load_model(path)
	if error != OK:
		_show_error("Could not load model", "The selected model could not be opened.\n%s" % error_string(error))
		return error
	_current_model_path = path
	_model_name_label.text = path.get_file()
	_status_label.text = "%d parameters" % _runtime_model.model.parameters.size()
	_rebuild_parameter_controls(MODEL_INPUT_PROFILE.load_bindings(path))
	reset_model_view()
	return OK


func reset_model_view() -> void:
	_view_zoom = 1.0
	_view_pan = Vector2.ZERO
	_update_model_transform()


func get_current_model_path() -> String:
	return _current_model_path


func get_package_provider(package_id: StringName) -> TwberInputProvider:
	return _input_registry.get_provider(package_id)


func _on_package_loaded(
		package_id: StringName,
		manifest: Dictionary,
		provider: TwberInputProvider,
) -> void:
	if not _input_registry.register_provider(provider):
		push_warning("Could not register package provider: %s" % package_id)
		return
	var state: Dictionary = _environment_settings.get_package_state(
			package_id,
			provider.get_default_enabled(),
	)
	var card := PACKAGE_CARD_SCENE.instantiate() as TwberPackageCard
	_package_list.add_child(card)
	card.configure(
			manifest,
			provider,
			bool(state.get("enabled", provider.get_default_enabled())),
			state.get("settings", {}) as Dictionary,
	)
	card.package_state_changed.connect(_on_package_state_changed)
	_environment_settings.set_package_state(
			package_id,
			provider.is_provider_enabled(),
			provider.get_package_settings(),
	)
	_save_environment_settings()


func _on_package_failed(path: String, reason: String) -> void:
	push_warning("Could not load package %s: %s" % [path, reason])


func _on_package_discovery_finished() -> void:
	_save_environment_settings()


func _on_package_state_changed(
		package_id: StringName,
		enabled: bool,
		settings: Dictionary,
) -> void:
	_environment_settings.set_package_state(package_id, enabled, settings)
	_save_environment_settings()


func _rebuild_parameter_controls(saved_bindings: Dictionary = {}) -> void:
	for child: Node in _parameter_list.get_children():
		_parameter_list.remove_child(child)
		child.queue_free()
	_parameter_controls.clear()
	_source_bindings.clear()
	if _runtime_model.model == null:
		_empty_parameters_label.visible = true
		return
	var parameters: Array[TwberParameterResource] = _runtime_model.model.parameters
	_empty_parameters_label.visible = parameters.is_empty()
	for parameter: TwberParameterResource in parameters:
		if parameter == null or parameter.id.is_empty():
			continue
		var control := PARAMETER_CONTROL_SCENE.instantiate() as TwberEnvironmentParameterControl
		_parameter_list.add_child(control)
		control.configure(parameter, _input_registry.get_compatible_sources(parameter))
		control.value_changed.connect(_on_parameter_value_changed)
		control.source_changed.connect(_on_parameter_source_changed)
		control.source_configuration_changed.connect(_on_parameter_source_configuration_changed)
		_parameter_controls[parameter.id] = control
		_restore_parameter_binding(parameter.id, control, saved_bindings.get(parameter.id))


func _restore_parameter_binding(
		parameter_id: String,
		control: TwberEnvironmentParameterControl,
		saved_binding: Variant,
) -> void:
	if saved_binding is not Dictionary:
		return
	var source_id := StringName(saved_binding.get("source_id", ""))
	var configuration: Variant = saved_binding.get("configuration", {})
	var safe_configuration: Dictionary = configuration if configuration is Dictionary else {}
	if not control.restore_source_binding(source_id, safe_configuration):
		return
	_source_bindings[parameter_id] = {
		"source_id": source_id,
		"configuration": safe_configuration.duplicate(true),
	}
	var latest_value: Variant = _input_registry.get_latest_value(source_id)
	if latest_value != null:
		_apply_source_value(parameter_id, latest_value)


func _on_parameter_value_changed(parameter_id: String, value: Variant) -> void:
	_runtime_model.set_parameter_value(parameter_id, value)


func _on_parameter_source_changed(parameter_id: String, source_id: StringName) -> void:
	if source_id.is_empty():
		_source_bindings.erase(parameter_id)
		_save_current_profile()
		return
	_source_bindings[parameter_id] = {"source_id": source_id, "configuration": {}}
	var latest_value: Variant = _input_registry.get_latest_value(source_id)
	if latest_value != null:
		_apply_source_value(parameter_id, latest_value)
	_save_current_profile()


func _on_parameter_source_configuration_changed(
		parameter_id: String,
		configuration: Dictionary,
) -> void:
	if not _source_bindings.has(parameter_id):
		return
	var binding: Dictionary = _source_bindings[parameter_id]
	binding["configuration"] = configuration.duplicate(true)
	_source_bindings[parameter_id] = binding
	_save_current_profile()


func _on_input_value_changed(source_id: StringName, value: Variant) -> void:
	for parameter_id: String in _source_bindings:
		var binding: Dictionary = _source_bindings[parameter_id]
		if StringName(binding.get("source_id", "")) == source_id:
			_apply_source_value(parameter_id, value)


func _apply_source_value(parameter_id: String, raw_value: Variant) -> void:
	var control := _parameter_controls.get(parameter_id) as TwberEnvironmentParameterControl
	if control == null:
		return
	var mapped_value: Variant = control.apply_source_value(raw_value)
	_runtime_model.set_parameter_value(parameter_id, mapped_value)
	var applied_value: Variant = _runtime_model.get_parameter_value(parameter_id)
	control.set_value(applied_value)
	control.set_source_preview(raw_value, applied_value)


func _save_current_profile() -> void:
	if _current_model_path.is_empty():
		return
	var error: Error = MODEL_INPUT_PROFILE.save_bindings(_current_model_path, _source_bindings)
	if error != OK:
		push_error("Could not save environment input profile: %s" % error_string(error))


func _save_environment_settings() -> void:
	var error: Error = _environment_settings.save()
	if error != OK:
		push_error("Could not save environment settings: %s" % error_string(error))


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_view_zoom = minf(_view_zoom * 1.1, 8.0)
			_update_model_transform()
			_preview_interaction.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_view_zoom = maxf(_view_zoom / 1.1, 0.05)
			_update_model_transform()
			_preview_interaction.accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_preview_interaction.accept_event()
	elif event is InputEventMouseMotion and _panning:
		if (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0:
			_panning = false
			return
		_view_pan += event.relative
		_update_model_transform()
		_preview_interaction.accept_event()


func _update_model_transform() -> void:
	if not is_instance_valid(_preview_interaction) or not is_instance_valid(_runtime_model):
		return
	_runtime_model.position = _preview_interaction.get_global_rect().get_center() + _view_pan
	_runtime_model.scale = Vector2.ONE * _view_zoom


func _show_error(title: String, message: String) -> void:
	_error_dialog.title = title
	_error_dialog.dialog_text = message
	_error_dialog.show()
