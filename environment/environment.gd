class_name TwberEnvironment extends Node

const PARAMETER_CONTROL_SCENE := preload("res://environment/parameter_control.tscn")
const PACKAGE_CARD_SCENE := preload("res://environment/package_card.tscn")
const MODEL_INSTANCE_SCENE := preload("res://environment/environment_model.tscn")
const MODEL_INPUT_PROFILE := preload("res://environment/core/twber_model_input_profile.gd")
const ENVIRONMENT_SETTINGS := preload("res://environment/core/twber_environment_settings.gd")
const MODEL_SOURCE_KIND := "model"
const IMAGE_SOURCE_KIND := "image"
const MAX_WORKSPACE_ITEMS := 64

@onready var _performance_recorder: TwberPerformanceRecorder = %PerformanceRecorder
@onready var _model_stage: Node2D = %ModelStage
@onready var _background_color: ColorRect = %BackgroundColor
@onready var _background_image: TextureRect = %BackgroundImage
@onready var _input_registry: TwberInputRegistry = %InputRegistry
@onready var _package_manager: TwberPackageManager = %PackageManager
@onready var _workspace_save_timer: Timer = %WorkspaceSaveTimer
@onready var _package_list: VBoxContainer = %PackageList
@onready var _install_package_button: Button = %InstallPackageButton
@onready var _open_package_directory_button: Button = %OpenPackageDirectoryButton
@onready var _package_status_label: Label = %PackageStatusLabel
@onready var _preview_interaction: Control = %PreviewInteraction
@onready var _preview_help: Label = %Help
@onready var _embedded_dock: PanelContainer = %EmbeddedDock
@onready var _control_dock: VBoxContainer = %ControlDock
@onready var _detach_controls_button: Button = %DetachControlsButton
@onready var _detached_controls_window: Window = %DetachedControlsWindow
@onready var _detached_dock_margin: MarginContainer = %DetachedDockMargin
@onready var _open_model_button: Button = %OpenModelButton
@onready var _remove_model_button: Button = %RemoveModelButton
@onready var _reset_view_button: Button = %ResetViewButton
@onready var _home_button: Button = %HomeButton
@onready var _model_selector: OptionButton = %ModelSelector
@onready var _status_label: Label = %StatusLabel
@onready var _operation_status_label: Label = %OperationStatusLabel
@onready var _empty_parameters_label: Label = %EmptyParametersLabel
@onready var _parameter_list: VBoxContainer = %ParameterList
@onready var _model_control_storage: VBoxContainer = %ModelControlStorage
@onready var _open_model_dialog: FileDialog = %OpenModelDialog
@onready var _error_dialog: AcceptDialog = %ErrorDialog
@onready var _install_package_dialog: FileDialog = %InstallPackageDialog
@onready var _remove_package_dialog: ConfirmationDialog = %RemovePackageDialog

var _parameter_controls: Dictionary[String, TwberEnvironmentParameterControl] = {}
var _model_entries: Array[Dictionary] = []
var _package_cards: Dictionary[StringName, TwberPackageCard] = {}
var _selected_model: TwberRuntimeModel
var _dragging_model := false
var _environment_settings
var _busy := false
var _restoring_workspace := false
var _pending_package_removal := StringName()
var _stage_api := TwberStageApi.new()


func _ready() -> void:
	get_viewport().gui_embed_subwindows = false
	_performance_recorder.state_changed.connect(func() -> void:
		_home_button.disabled = _busy or _performance_recorder.blocks_navigation()
	)
	_environment_settings = ENVIRONMENT_SETTINGS.new()
	_environment_settings.load()
	_home_button.pressed.connect(func() -> void:
		if _busy or _performance_recorder.blocks_navigation():
			return
		_save_workspace()
		get_tree().change_scene_to_file("res://launcher/launcher.tscn")
	)
	_workspace_save_timer.timeout.connect(_save_workspace)
	_stage_api.configure(
		_get_stage_items,
		_get_model_global_bounds,
		_get_stage_item_source_path,
		add_image_asset_async,
		_get_model_attachment_anchor,
		_bring_stage_item_to_front,
		_set_stage_background_color,
		_set_stage_background_image,
		_clear_stage_background,
	)
	_stage_api.item_drag_ended.connect(_on_stage_item_drag_ended)
	_prepare_model_directory()
	_open_model_button.pressed.connect(_popup_open_model_dialog)
	_install_package_button.pressed.connect(_popup_install_package_dialog)
	_open_package_directory_button.pressed.connect(_open_package_directory)
	_install_package_dialog.file_selected.connect(_install_package)
	_remove_package_dialog.confirmed.connect(_remove_pending_package)
	_remove_package_dialog.canceled.connect(func() -> void:
		_pending_package_removal = StringName()
	)
	_remove_model_button.pressed.connect(remove_selected_model)
	_reset_view_button.pressed.connect(reset_selected_model_transform)
	_detach_controls_button.pressed.connect(_toggle_controls_detached)
	_detached_controls_window.close_requested.connect(_embed_controls)
	_model_selector.item_selected.connect(_on_model_selector_item_selected)
	_open_model_dialog.files_selected.connect(_add_selected_model_files)
	_input_registry.value_changed.connect(_on_input_value_changed)
	_preview_interaction.gui_input.connect(_on_preview_gui_input)
	_package_manager.package_loaded.connect(_on_package_loaded)
	_package_manager.package_failed.connect(_on_package_failed)
	_package_manager.discovery_finished.connect(_on_package_discovery_finished)
	_environment_settings.mark_all_packages_uninstalled()
	_package_manager.discover_packages()
	_restore_workspace_async.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_workspace_save_timer) and not _restoring_workspace:
		_save_workspace()


func _popup_open_model_dialog() -> void:
	_prepare_model_directory()
	_open_model_dialog.show()


func _popup_install_package_dialog() -> void:
	var error := TwberAppSettings.ensure_directory(
		TwberAppSettings.PACKAGES_DIRECTORY_NAME
	)
	if error != OK:
		_show_error("Package Folder Unavailable", error_string(error))
		return
	_install_package_dialog.current_dir = _package_manager.get_package_directory_path()
	_install_package_dialog.show()


func _install_package(path: String) -> void:
	var result := _package_manager.install_package(path)
	if not bool(result.get("success", false)):
		var message := str(result.get("error", "The package could not be installed."))
		_package_status_label.text = message
		_show_error("Package Installation Failed", message)
		return
	var message := str(result.get("message", "Package installed."))
	if bool(result.get("restart_required", false)):
		message += " Restart Twber to finish applying this change."
	_package_status_label.text = message


func _open_package_directory() -> void:
	var error := _package_manager.open_package_directory()
	if error != OK:
		_show_error("Package Folder Unavailable", error_string(error))


func _request_package_removal(package_id: StringName) -> void:
	_pending_package_removal = package_id
	_remove_package_dialog.dialog_text = (
		"Remove %s.pck? The package will be disabled now and unloaded after Twber restarts."
		% package_id
	)
	_remove_package_dialog.popup_centered()


func _remove_pending_package() -> void:
	var package_id := _pending_package_removal
	_pending_package_removal = StringName()
	if package_id.is_empty():
		return
	var result := _package_manager.remove_package(package_id)
	if not bool(result.get("success", false)):
		var error_message := str(result.get("error", "The package could not be removed."))
		_package_status_label.text = error_message
		_show_error("Package Removal Failed", error_message)
		return
	var card := _package_cards.get(package_id) as TwberPackageCard
	if card != null:
		card.mark_removal_pending()
	var package_record: Dictionary = _package_manager.get_packages().get(package_id, {})
	var package := package_record.get("package") as TwberEnvironmentPackage
	if package != null:
		_environment_settings.set_package_state(
			package_id,
			false,
			package.get_package_settings(),
		)
		_save_environment_settings()
	var message := str(result.get("message", "Package removed."))
	if bool(result.get("restart_required", false)):
		message += " Restart Twber to finish unloading it."
	_package_status_label.text = message


func _prepare_model_directory() -> void:
	var error := TwberAppSettings.ensure_directory(
		TwberAppSettings.MODELS_DIRECTORY_NAME
	)
	if error != OK:
		push_warning("Could not create Twber model library: %s" % error_string(error))
		return
	_open_model_dialog.current_dir = TwberAppSettings.get_directory_path(
		TwberAppSettings.MODELS_DIRECTORY_NAME
	)


func _restore_workspace_async() -> void:
	_restoring_workspace = true
	var workspace: Dictionary = _environment_settings.get_workspace()
	var saved_entries: Variant = workspace.get("entries", [])
	var selected_index := int(workspace.get("selected", -1))
	var selected_model: TwberRuntimeModel
	if saved_entries is Array:
		var restore_count := mini((saved_entries as Array).size(), MAX_WORKSPACE_ITEMS)
		for index: int in restore_count:
			var saved_entry: Variant = (saved_entries as Array)[index]
			if saved_entry is not Dictionary:
				continue
			var entry := saved_entry as Dictionary
			var path := str(entry.get("path", ""))
			if path.is_empty() or not FileAccess.file_exists(path):
				continue
			var source_kind := str(entry.get("kind", MODEL_SOURCE_KIND))
			var error := await _load_workspace_source(path, source_kind)
			if error != OK or _selected_model == null:
				continue
			var saved_position: Variant = entry.get("position")
			if saved_position is Vector2 and (saved_position as Vector2).is_finite():
				_selected_model.position = saved_position as Vector2
			var saved_scale: Variant = entry.get("scale")
			if (
				saved_scale is Vector2
				and (saved_scale as Vector2).is_finite()
				and not (saved_scale as Vector2).is_zero_approx()
			):
				_selected_model.scale = saved_scale as Vector2
			if index == selected_index:
				selected_model = _selected_model
	if selected_model != null:
		_select_model(selected_model)
	_restoring_workspace = false
	_save_workspace()
	if not _model_entries.is_empty():
		_set_operation_status("Workspace restored")


func _load_workspace_source(path: String, source_kind: String) -> Error:
	if source_kind == IMAGE_SOURCE_KIND:
		return await add_image_asset_async(path)
	return await load_model_async(path)


func _toggle_controls_detached() -> void:
	if _control_dock.get_parent() == _detached_dock_margin:
		_embed_controls()
	else:
		_detach_controls()


func _detach_controls() -> void:
	if _control_dock.get_parent() == _detached_dock_margin:
		return
	_control_dock.reparent(_detached_dock_margin)
	_embedded_dock.visible = false
	_preview_help.visible = false
	_detach_controls_button.text = "↙"
	_detach_controls_button.tooltip_text = "Return controls to the environment window"
	_detached_controls_window.show()


func _embed_controls() -> void:
	if _control_dock.get_parent() != _embedded_dock.get_node("DockMargin"):
		_control_dock.reparent(_embedded_dock.get_node("DockMargin"))
	_detached_controls_window.hide()
	_embedded_dock.visible = true
	_preview_help.visible = true
	_detach_controls_button.text = "↗"
	_detach_controls_button.tooltip_text = "Move controls to a separate window"


func _set_stage_background_color(color: Color) -> void:
	_background_color.color = color
	_background_image.visible = false


func _set_stage_background_image(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_warning("Could not load background image: %s" % path)
		return
	_background_image.texture = ImageTexture.create_from_image(image)
	_background_image.visible = true


func _clear_stage_background() -> void:
	_background_color.color = Color.TRANSPARENT
	_background_image.texture = null
	_background_image.visible = false


func load_model(path: String) -> Error:
	var model := TwberModelCodec.load_model(path)
	if model == null:
		_show_error("Could not load model", "The selected model could not be opened.")
		return ERR_FILE_CORRUPT
	_add_model_instance(model, path)
	return OK


func load_model_async(path: String) -> Error:
	if _busy:
		return ERR_BUSY
	_set_busy(true, "Loading %s…" % path.get_file())
	var result: Variant = await _run_background(TwberModelCodec.load_model.bind(path))
	if result is not TwberModelResource:
		_set_busy(false, "Load failed")
		_show_error("Could not load model", "The selected model could not be opened.")
		return ERR_FILE_CORRUPT
	_set_operation_status("Preparing model…")
	await get_tree().process_frame
	_add_model_instance(result as TwberModelResource, path)
	_set_busy(false, "Loaded %s" % path.get_file())
	return OK


func _add_selected_model_files(paths: PackedStringArray) -> void:
	for path: String in paths:
		var error := await load_model_async(path)
		if error != OK:
			break


func _add_model_instance(
	model: TwberModelResource,
	path: String,
	source_kind := MODEL_SOURCE_KIND,
) -> TwberRuntimeModel:
	var runtime_model := MODEL_INSTANCE_SCENE.instantiate() as TwberRuntimeModel
	runtime_model.name = _make_unique_model_node_name(path)
	_model_stage.add_child(runtime_model)
	runtime_model.set_model(model)
	var offset_index := _model_entries.size()
	runtime_model.position = _preview_interaction.get_global_rect().get_center() + Vector2(offset_index * 36.0, 0.0)
	runtime_model.scale = Vector2.ONE
	var entry := {
		"model": runtime_model,
		"path": path,
		"kind": source_kind,
		"bindings": MODEL_INPUT_PROFILE.load_bindings(path),
		"controls": {},
		"source_targets": {},
	}
	_model_entries.append(entry)
	_create_parameter_controls(entry)
	_refresh_model_selector()
	_select_model(runtime_model)
	_stage_api.item_added.emit(runtime_model)
	_schedule_workspace_save()
	return runtime_model


func remove_selected_model() -> void:
	if _selected_model == null:
		return
	var removed_index := _find_model_entry_index(_selected_model)
	if removed_index < 0:
		return
	_store_visible_parameter_controls()
	var removed_entry := _model_entries[removed_index]
	_stage_api.item_removed.emit(_selected_model)
	for control_value: Variant in (removed_entry["controls"] as Dictionary).values():
		if control_value is Node:
			(control_value as Node).queue_free()
	_selected_model.queue_free()
	_model_entries.remove_at(removed_index)
	_selected_model = null
	_refresh_model_selector()
	if not _model_entries.is_empty():
		var next_index := mini(removed_index, _model_entries.size() - 1)
		_select_model(_model_entries[next_index]["model"] as TwberRuntimeModel)
	else:
		_show_selected_model_controls()
	_schedule_workspace_save()


func reset_selected_model_transform() -> void:
	if _selected_model == null:
		return
	_selected_model.position = _preview_interaction.get_global_rect().get_center()
	_selected_model.scale = Vector2.ONE
	_schedule_workspace_save()


func get_current_model_path() -> String:
	var entry := _get_selected_entry()
	return String(entry.get("path", ""))


func get_model_count() -> int:
	return _model_entries.size()


func get_selected_model() -> TwberRuntimeModel:
	return _selected_model


func _get_stage_items() -> Array[Node2D]:
	var output: Array[Node2D] = []
	for child: Node in _model_stage.get_children():
		if child is TwberRuntimeModel:
			output.append(child as Node2D)
	return output


func _get_stage_item_source_path(item: Node2D) -> String:
	if item is not TwberRuntimeModel:
		return ""
	return String(_get_model_entry(item as TwberRuntimeModel).get("path", ""))


func add_image_asset_async(path: String) -> Error:
	if _busy:
		return ERR_BUSY
	_set_busy(true, "Loading %s…" % path.get_file())
	var result: Variant = await _run_background(_load_image_file.bind(path))
	if result is not Image or (result as Image).is_empty():
		_set_busy(false, "Asset load failed")
		return ERR_FILE_CORRUPT
	var model := TwberModelResource.new()
	var texture_id := "asset_texture"
	model.textures[texture_id] = ImageTexture.create_from_image(result as Image)
	model.texture_sources[texture_id] = path
	var layer := TwberLayerResource.new()
	layer.id = "asset"
	layer.name = path.get_file().get_basename()
	layer.type = TwberLayerResource.LayerType.SPRITE
	layer.texture_id = texture_id
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)
	_add_model_instance(model, path, IMAGE_SOURCE_KIND)
	_set_busy(false, "Loaded %s" % path.get_file())
	return OK


static func _load_image_file(path: String) -> Image:
	return Image.load_from_file(path)


func _make_unique_model_node_name(path: String) -> String:
	var base_name := path.get_file().get_basename().to_pascal_case()
	for invalid_character: String in [".", ":", "@", "/", '"', "%"]:
		base_name = base_name.replace(invalid_character, "")
	if base_name.is_empty():
		base_name = "Model"
	var candidate := base_name
	var suffix := 2
	while _model_stage_has_child_named(candidate):
		candidate = "%s%d" % [base_name, suffix]
		suffix += 1
	return candidate


func _model_stage_has_child_named(node_name: String) -> bool:
	for child: Node in _model_stage.get_children():
		if child.name == node_name:
			return true
	return false


func _refresh_model_selector() -> void:
	_model_selector.clear()
	for entry: Dictionary in _model_entries:
		var path := String(entry.get("path", ""))
		var runtime_model := entry.get("model") as TwberRuntimeModel
		_model_selector.add_item(runtime_model.name)
		_model_selector.set_item_metadata(
			_model_selector.item_count - 1,
			runtime_model.get_instance_id(),
		)
		_model_selector.set_item_tooltip(_model_selector.item_count - 1, path)
	_model_selector.disabled = _model_entries.is_empty()


func _on_model_selector_item_selected(index: int) -> void:
	if index < 0 or index >= _model_selector.item_count:
		return
	var instance_id := int(_model_selector.get_item_metadata(index))
	for entry: Dictionary in _model_entries:
		var runtime_model := entry.get("model") as TwberRuntimeModel
		if runtime_model != null and runtime_model.get_instance_id() == instance_id:
			_select_model(runtime_model)
			return


func _select_model(runtime_model: TwberRuntimeModel) -> void:
	if runtime_model == null:
		return
	_bring_model_forward(runtime_model)
	_stage_api.item_selected.emit(runtime_model)
	if runtime_model == _selected_model:
		return
	_store_visible_parameter_controls()
	_selected_model = runtime_model
	var selected_index := _find_model_entry_index(runtime_model)
	if selected_index >= 0:
		_model_selector.select(selected_index)
	_show_selected_model_controls()
	_schedule_workspace_save()


func _bring_model_forward(runtime_model: TwberRuntimeModel) -> void:
	if runtime_model.get_parent() != _model_stage:
		return
	_model_stage.move_child(runtime_model, _model_stage.get_child_count() - 1)


func _bring_stage_item_to_front(item: Node2D) -> void:
	if item is TwberRuntimeModel:
		_bring_model_forward(item as TwberRuntimeModel)


func _store_visible_parameter_controls() -> void:
	for child: Node in _parameter_list.get_children():
		_parameter_list.remove_child(child)
		_model_control_storage.add_child(child)
	_parameter_controls.clear()


func _show_selected_model_controls() -> void:
	_performance_recorder.selected_model = _selected_model
	_store_visible_parameter_controls()
	var entry := _get_selected_entry()
	if entry.is_empty():
		_empty_parameters_label.visible = true
		_status_label.text = "%d models" % _model_entries.size()
		_remove_model_button.disabled = true
		_reset_view_button.disabled = true
		return
	var controls := entry.get("controls") as Dictionary
	for parameter_id: String in controls:
		var control := controls[parameter_id] as TwberEnvironmentParameterControl
		if control == null:
			continue
		_model_control_storage.remove_child(control)
		_parameter_list.add_child(control)
		_parameter_controls[parameter_id] = control
	_empty_parameters_label.visible = controls.is_empty()
	var runtime_model := entry.get("model") as TwberRuntimeModel
	var parameter_count := runtime_model.model.parameters.size() if runtime_model.model != null else 0
	_status_label.text = "%d models · %d parameters" % [_model_entries.size(), parameter_count]
	_remove_model_button.disabled = false
	_reset_view_button.disabled = false


func _get_selected_entry() -> Dictionary:
	return _get_model_entry(_selected_model)


func _get_model_entry(runtime_model: TwberRuntimeModel) -> Dictionary:
	if runtime_model == null:
		return {}
	for entry: Dictionary in _model_entries:
		if entry.get("model") == runtime_model:
			return entry
	return {}


func _find_model_entry_index(runtime_model: TwberRuntimeModel) -> int:
	for index: int in _model_entries.size():
		if _model_entries[index].get("model") == runtime_model:
			return index
	return -1


func is_busy() -> bool:
	return _busy


func get_package_provider(package_id: StringName) -> TwberInputProvider:
	return _input_registry.get_provider(package_id)


func _on_package_loaded(
		package_id: StringName,
		manifest: Dictionary,
		package: TwberEnvironmentPackage,
) -> void:
	package.set_stage_api(_stage_api)
	if package is TwberInputProvider:
		if not _input_registry.register_provider(package as TwberInputProvider):
			push_warning("Could not register package provider: %s" % package_id)
			return
	var state: Dictionary = _environment_settings.get_package_state(
			package_id,
			package.get_default_enabled(),
	)
	var card := PACKAGE_CARD_SCENE.instantiate() as TwberPackageCard
	_package_list.add_child(card)
	card.configure(
		manifest,
		package,
		bool(state.get("enabled", package.get_default_enabled())),
		state.get("settings", {}) as Dictionary,
		bool(_package_manager.get_packages().get(package_id, {}).get("bundled", false)),
	)
	card.package_state_changed.connect(_on_package_state_changed)
	card.removal_requested.connect(_request_package_removal)
	_package_cards[package_id] = card
	_environment_settings.set_package_state(
			package_id,
			package.is_package_enabled(),
			package.get_package_settings(),
	)
	_save_environment_settings()


func _on_package_failed(path: String, reason: String) -> void:
	push_warning("Could not load package %s: %s" % [path, reason])
	_package_status_label.text = "Could not load %s: %s" % [path.get_file(), reason]


func _on_package_discovery_finished() -> void:
	_save_environment_settings()
	_package_status_label.text = "%d packages loaded" % _package_manager.get_packages().size()


func _on_package_state_changed(
		package_id: StringName,
		enabled: bool,
		settings: Dictionary,
) -> void:
	_environment_settings.set_package_state(package_id, enabled, settings)
	_save_environment_settings()


func _create_parameter_controls(entry: Dictionary) -> void:
	var runtime_model := entry.get("model") as TwberRuntimeModel
	if runtime_model == null or runtime_model.model == null:
		return
	var controls := entry.get("controls") as Dictionary
	var saved_bindings := entry.get("bindings") as Dictionary
	var parameters: Array[TwberParameterResource] = runtime_model.model.parameters
	for parameter: TwberParameterResource in parameters:
		if parameter == null or parameter.id.is_empty():
			continue
		var control := PARAMETER_CONTROL_SCENE.instantiate() as TwberEnvironmentParameterControl
		_model_control_storage.add_child(control)
		control.configure(parameter, _input_registry.get_compatible_sources(parameter))
		control.value_changed.connect(_on_parameter_value_changed.bind(runtime_model))
		control.source_changed.connect(_on_parameter_source_changed.bind(runtime_model))
		control.source_configuration_changed.connect(
			_on_parameter_source_configuration_changed.bind(runtime_model),
		)
		controls[parameter.id] = control
		_restore_parameter_binding(entry, parameter.id, control, saved_bindings.get(parameter.id))


func _restore_parameter_binding(
		entry: Dictionary,
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
	var bindings := entry.get("bindings") as Dictionary
	bindings[parameter_id] = {
		"source_id": source_id,
		"configuration": safe_configuration.duplicate(true),
	}
	var latest_value: Variant = _input_registry.get_latest_value(source_id)
	if latest_value != null:
		_apply_source_value(entry, parameter_id, latest_value, false)


func _on_parameter_value_changed(
		parameter_id: String,
		value: Variant,
		runtime_model: TwberRuntimeModel,
) -> void:
	var entry := _get_model_entry(runtime_model)
	var source_targets := entry.get("source_targets") as Dictionary
	if source_targets != null:
		source_targets.erase(parameter_id)
	runtime_model.set_parameter_value(parameter_id, value)


func _on_parameter_source_changed(
		parameter_id: String,
		source_id: StringName,
		runtime_model: TwberRuntimeModel,
) -> void:
	var entry := _get_model_entry(runtime_model)
	var bindings := entry.get("bindings") as Dictionary
	if source_id.is_empty():
		bindings.erase(parameter_id)
		(entry.get("source_targets") as Dictionary).erase(parameter_id)
		_save_model_profile(entry)
		return
	bindings[parameter_id] = {"source_id": source_id, "configuration": {}}
	var latest_value: Variant = _input_registry.get_latest_value(source_id)
	if latest_value != null:
		_apply_source_value(entry, parameter_id, latest_value, runtime_model == _selected_model)
	_save_model_profile(entry)


func _on_parameter_source_configuration_changed(
		parameter_id: String,
		configuration: Dictionary,
		runtime_model: TwberRuntimeModel,
) -> void:
	var entry := _get_model_entry(runtime_model)
	var bindings := entry.get("bindings") as Dictionary
	if not bindings.has(parameter_id):
		return
	var binding: Dictionary = bindings[parameter_id]
	binding["configuration"] = configuration.duplicate(true)
	bindings[parameter_id] = binding
	_save_model_profile(entry)


func _on_input_value_changed(source_id: StringName, value: Variant) -> void:
	for entry: Dictionary in _model_entries:
		var bindings := entry.get("bindings") as Dictionary
		for parameter_id: String in bindings:
			var binding: Dictionary = bindings[parameter_id]
			if StringName(binding.get("source_id", "")) == source_id:
				_apply_source_value(
					entry,
					parameter_id,
					value,
					entry.get("model") == _selected_model,
					true,
				)


func _apply_source_value(
		entry: Dictionary,
		parameter_id: String,
		raw_value: Variant,
		update_preview: bool,
		smooth := false,
) -> void:
	var runtime_model := entry.get("model") as TwberRuntimeModel
	var controls := entry.get("controls") as Dictionary
	var control := controls.get(parameter_id) as TwberEnvironmentParameterControl
	if control == null or runtime_model == null:
		return
	var binding: Dictionary = (entry["bindings"] as Dictionary).get(parameter_id, {})
	var mapper := _input_registry.get_mapping(StringName(binding.get("source_id", "")))
	var mapped_value: Variant
	if mapper != null:
		var parameter := TwberEditParameter.find(runtime_model.model, parameter_id)
		mapped_value = mapper.map_value(parameter, binding.get("configuration", {}), raw_value, TwberInputContext.capture_displays())
	else:
		# Older third-party packages can still supply their mapping via a widget.
		mapped_value = control.apply_source_value(raw_value)
	var source_targets := entry.get("source_targets") as Dictionary
	if smooth and (mapped_value is float or mapped_value is int or mapped_value is Vector2):
		var state: Dictionary = source_targets.get(parameter_id, {})
		if state.is_empty():
			state["current"] = runtime_model.get_parameter_value(parameter_id)
		state["target"] = mapped_value
		state["raw"] = raw_value
		source_targets[parameter_id] = state
		return
	source_targets.erase(parameter_id)
	runtime_model.set_parameter_value(parameter_id, mapped_value)
	if update_preview:
		var applied_value: Variant = runtime_model.get_parameter_value(parameter_id)
		control.set_value(applied_value)
		control.set_source_preview(raw_value, applied_value)


func _process(delta: float) -> void:
	for entry: Dictionary in _model_entries:
		var runtime_model := entry.get("model") as TwberRuntimeModel
		var source_targets := entry.get("source_targets") as Dictionary
		var controls := entry.get("controls") as Dictionary
		if runtime_model == null or source_targets == null or source_targets.is_empty():
			continue
		for parameter_key: Variant in source_targets.keys():
			var parameter_id := String(parameter_key)
			var state: Dictionary = source_targets.get(parameter_id, {})
			var current: Variant = state.get("current")
			var target: Variant = state.get("target")
			var next_value: Variant = TwberInputSmoothing.advance(current, target, delta)
			if TwberInputSmoothing.settled(next_value, target):
				next_value = target
				source_targets.erase(parameter_id)
			else:
				state["current"] = next_value
				source_targets[parameter_id] = state
			runtime_model.set_parameter_value(parameter_id, next_value)
			if runtime_model == _selected_model:
				var control := controls.get(parameter_id) as TwberEnvironmentParameterControl
				if control != null:
					var applied_value: Variant = runtime_model.get_parameter_value(parameter_id)
					control.set_value(applied_value)
					control.set_source_preview(state.get("raw"), applied_value)


func _save_model_profile(entry: Dictionary) -> void:
	var path := String(entry.get("path", ""))
	if path.is_empty():
		return
	var bindings := entry.get("bindings") as Dictionary
	var error: Error = MODEL_INPUT_PROFILE.save_bindings(path, bindings)
	if error != OK:
		push_error("Could not save environment input profile: %s" % error_string(error))
	else:
		_set_operation_status("Profile saved")


func _save_environment_settings() -> void:
	var error: Error = _environment_settings.save()
	if error != OK:
		push_error("Could not save environment settings: %s" % error_string(error))
	else:
		_set_operation_status("Settings saved")


func _schedule_workspace_save() -> void:
	if _restoring_workspace or not is_instance_valid(_workspace_save_timer):
		return
	_workspace_save_timer.start()


func _save_workspace() -> void:
	if _restoring_workspace or _environment_settings == null:
		return
	var entries: Array[Dictionary] = []
	var selected_index := -1
	for child: Node in _model_stage.get_children():
		if child is not TwberRuntimeModel:
			continue
		var runtime_model := child as TwberRuntimeModel
		var model_entry := _get_model_entry(runtime_model)
		var path := str(model_entry.get("path", ""))
		if path.is_empty():
			continue
		if runtime_model == _selected_model:
			selected_index = entries.size()
		entries.append({
			"path": path,
			"kind": str(model_entry.get("kind", MODEL_SOURCE_KIND)),
			"position": runtime_model.position,
			"scale": runtime_model.scale,
		})
	_environment_settings.set_workspace(entries, selected_index)
	var error: Error = _environment_settings.save()
	if error != OK:
		push_error("Could not save environment workspace: %s" % error_string(error))


func _on_stage_item_drag_ended(_item: Node2D) -> void:
	_schedule_workspace_save()


func _set_busy(busy: bool, status: String) -> void:
	_busy = busy
	_performance_recorder.unavailable = busy
	_home_button.disabled = busy or _performance_recorder.blocks_navigation()
	_open_model_button.disabled = busy
	_model_selector.disabled = busy or _model_entries.is_empty()
	_remove_model_button.disabled = busy or _selected_model == null
	_reset_view_button.disabled = busy or _selected_model == null
	_set_operation_status(status)


func _set_operation_status(status: String) -> void:
	if _operation_status_label != null:
		_operation_status_label.text = status


func _run_background(callable: Callable) -> Variant:
	var task := TwberBackgroundTask.new()
	get_tree().root.add_child(task)
	var error := task.start(callable)
	if error != OK:
		task.queue_free()
		return error
	return await task.completed


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and _selected_model != null:
			var next_scale := minf(_selected_model.scale.x * 1.1, 8.0)
			_selected_model.scale = Vector2.ONE * next_scale
			_schedule_workspace_save()
			_preview_interaction.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and _selected_model != null:
			var next_scale := maxf(_selected_model.scale.x / 1.1, 0.05)
			_selected_model.scale = Vector2.ONE * next_scale
			_schedule_workspace_save()
			_preview_interaction.accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var picked_model := _pick_model_at(event.global_position)
				if picked_model != null:
					_select_model(picked_model)
					_dragging_model = true
					_stage_api.item_drag_started.emit(picked_model)
			else:
				if _dragging_model and _selected_model != null:
					_stage_api.item_drag_ended.emit(_selected_model)
				_dragging_model = false
			_preview_interaction.accept_event()
	elif event is InputEventMouseMotion and _dragging_model and _selected_model != null:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_stage_api.item_drag_ended.emit(_selected_model)
			_dragging_model = false
			return
		_selected_model.position += event.relative
		_preview_interaction.accept_event()


func _pick_model_at(global_position: Vector2) -> TwberRuntimeModel:
	var stage_children := _model_stage.get_children()
	for index: int in range(stage_children.size() - 1, -1, -1):
		var runtime_model := stage_children[index] as TwberRuntimeModel
		if runtime_model == null:
			continue
		var bounds := _get_model_global_bounds(runtime_model)
		if bounds.has_area() and bounds.grow(12.0).has_point(global_position):
			return runtime_model
		if runtime_model.global_position.distance_to(global_position) <= 80.0:
			return runtime_model
	return null


func _get_model_global_bounds(runtime_model: TwberRuntimeModel) -> Rect2:
	var state := {"has_bounds": false, "bounds": Rect2()}
	_collect_model_visual_bounds(runtime_model, state)
	return state["bounds"] as Rect2


func _collect_model_visual_bounds(node: Node, state: Dictionary) -> void:
	var visual_rect: Variant = _get_visual_local_rect(node)
	if visual_rect is Rect2:
		_expand_transformed_rect(visual_rect as Rect2, node as Node2D, state)
	for child: Node in node.get_children():
		_collect_model_visual_bounds(child, state)


func _get_model_attachment_anchor(runtime_model: Node2D, global_point: Vector2) -> Node2D:
	return _find_attachment_anchor(runtime_model, global_point)


func _find_attachment_anchor(node: Node, global_point: Vector2) -> Node2D:
	var children := node.get_children()
	for index: int in range(children.size() - 1, -1, -1):
		var anchor := _find_attachment_anchor(children[index], global_point)
		if anchor != null:
			return anchor
	if node is not Node2D:
		return null
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		if not canvas_item.is_visible_in_tree() or canvas_item.modulate.a * canvas_item.self_modulate.a <= 0.001:
			return null
	var visual_rect: Variant = _get_visual_local_rect(node)
	var local_point := (node as Node2D).to_local(global_point)
	if (
		visual_rect is Rect2
		and (visual_rect as Rect2).has_point(local_point)
		and _is_visual_point_opaque(node, local_point)
	):
		return node as Node2D
	return null


func _is_visual_point_opaque(node: Node, local_point: Vector2) -> bool:
	if node is Sprite2D:
		return (node as Sprite2D).is_pixel_opaque(local_point)
	if node is AnimatedSprite2D:
		return _is_animated_sprite_point_opaque(node as AnimatedSprite2D, local_point)
	if node is TwberMeshSprite2D:
		return _is_mesh_point_opaque(node as TwberMeshSprite2D, local_point)
	return false


func _is_animated_sprite_point_opaque(
		animated_sprite: AnimatedSprite2D,
		local_point: Vector2,
) -> bool:
	var frame_texture := _get_animated_sprite_texture(animated_sprite)
	if frame_texture == null:
		return false
	var image := TwberTextureUtils.get_authoring_image(frame_texture)
	if image == null or image.is_empty():
		return true
	var frame_size := frame_texture.get_size()
	var frame_position := animated_sprite.offset
	if animated_sprite.centered:
		frame_position -= frame_size * 0.5
	var pixel := Vector2i(floor(local_point - frame_position))
	if animated_sprite.flip_h:
		pixel.x = image.get_width() - 1 - pixel.x
	if animated_sprite.flip_v:
		pixel.y = image.get_height() - 1 - pixel.y
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
		return false
	return image.get_pixelv(pixel).a > 0.001


func _is_mesh_point_opaque(mesh_sprite: TwberMeshSprite2D, local_point: Vector2) -> bool:
	var mesh := mesh_sprite.mesh_data
	if mesh == null or mesh.vertices.size() < 3 or mesh.triangles.size() < 3:
		return false
	var uvs := mesh.uvs
	var has_uvs := uvs.size() == mesh.vertices.size()
	var image := TwberTextureUtils.get_authoring_image(mesh_sprite.texture)
	for triangle_index: int in range(0, mesh.triangles.size() - 2, 3):
		var first := mesh.triangles[triangle_index]
		var second := mesh.triangles[triangle_index + 1]
		var third := mesh.triangles[triangle_index + 2]
		if first < 0 or second < 0 or third < 0:
			continue
		if first >= mesh.vertices.size() or second >= mesh.vertices.size() or third >= mesh.vertices.size():
			continue
		var weights := _triangle_weights(
			local_point,
			mesh.vertices[first],
			mesh.vertices[second],
			mesh.vertices[third],
		)
		if weights.x < -0.0001 or weights.y < -0.0001 or weights.z < -0.0001:
			continue
		if image == null or image.is_empty():
			return true
		var first_uv := uvs[first] if has_uvs else mesh.vertices[first] - mesh_sprite.get_texture_origin()
		var second_uv := uvs[second] if has_uvs else mesh.vertices[second] - mesh_sprite.get_texture_origin()
		var third_uv := uvs[third] if has_uvs else mesh.vertices[third] - mesh_sprite.get_texture_origin()
		var uv: Vector2 = first_uv * weights.x + second_uv * weights.y + third_uv * weights.z
		var pixel := Vector2i(floori(uv.x), floori(uv.y))
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
			return false
		return image.get_pixelv(pixel).a > 0.001
	return false


func _triangle_weights(point: Vector2, first: Vector2, second: Vector2, third: Vector2) -> Vector3:
	var denominator := (second.y - third.y) * (first.x - third.x) + (third.x - second.x) * (first.y - third.y)
	if is_zero_approx(denominator):
		return Vector3(-1.0, -1.0, -1.0)
	var first_weight := (
		(second.y - third.y) * (point.x - third.x)
		+ (third.x - second.x) * (point.y - third.y)
	) / denominator
	var second_weight := (
		(third.y - first.y) * (point.x - third.x)
		+ (first.x - third.x) * (point.y - third.y)
	) / denominator
	return Vector3(first_weight, second_weight, 1.0 - first_weight - second_weight)


func _get_visual_local_rect(node: Node) -> Variant:
	if node is Sprite2D:
		return (node as Sprite2D).get_rect()
	if node is AnimatedSprite2D:
		var animated_sprite := node as AnimatedSprite2D
		var frame_texture := _get_animated_sprite_texture(animated_sprite)
		if frame_texture == null:
			return null
		var frame_size := frame_texture.get_size()
		var frame_position := animated_sprite.offset
		if animated_sprite.centered:
			frame_position -= frame_size * 0.5
		return Rect2(frame_position, frame_size)
	if node is TwberMeshSprite2D:
		var mesh_sprite := node as TwberMeshSprite2D
		if mesh_sprite.mesh_data == null or mesh_sprite.mesh_data.vertices.is_empty():
			return null
		var mesh_bounds := Rect2(mesh_sprite.mesh_data.vertices[0], Vector2.ZERO)
		for vertex: Vector2 in mesh_sprite.mesh_data.vertices:
			mesh_bounds = mesh_bounds.expand(vertex)
		return mesh_bounds
	return null


func _get_animated_sprite_texture(animated_sprite: AnimatedSprite2D) -> Texture2D:
	if animated_sprite.sprite_frames == null:
		return null
	var animation := animated_sprite.animation
	if not animated_sprite.sprite_frames.has_animation(animation):
		return null
	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation)
	if frame_count <= 0:
		return null
	return animated_sprite.sprite_frames.get_frame_texture(
		animation,
		clampi(animated_sprite.frame, 0, frame_count - 1),
	)


func _expand_transformed_rect(local_rect: Rect2, node: Node2D, state: Dictionary) -> void:
	for corner: Vector2 in [
		local_rect.position,
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y),
	]:
		var point := node.to_global(corner)
		if bool(state["has_bounds"]):
			state["bounds"] = (state["bounds"] as Rect2).expand(point)
		else:
			state["bounds"] = Rect2(point, Vector2.ZERO)
			state["has_bounds"] = true


func _show_error(title: String, message: String) -> void:
	_error_dialog.title = title
	_error_dialog.dialog_text = message
	_error_dialog.show()
