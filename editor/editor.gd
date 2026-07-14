class_name TwberEditor extends CanvasLayer

const MENU_NEW := 4
const MENU_OPEN := 1
const MENU_SAVE := 2
const MENU_EXPORT := 3
const MENU_SETTINGS := 5
const MENU_PERFORMANCE := 6
const MENU_SAVE_AS := 7
const MODEL_RESOURCE_FILTER := "*.tres, *.res ; Legacy editable model resources"
const EXPORTED_MODEL_FILTER := "*.twber ; Twber models"
const SETTINGS_DIALOG_SCENE := preload("res://editor/editor_settings_dialog.tscn")

@onready var _file_menu_button: MenuButton = %FileMenuButton
@onready var _current_model_label: Label = %CurrentModelLabel
@onready var _editor_status_label: Label = %EditorStatusLabel
@onready var _model_root: Node2D = $ModelPreview/Textures
@onready var _model_preview: ModelPreview = $ModelPreview
@onready var _editor_placer: EditorPlacer = $PanelContainer/MarginContainer/VBoxContainer/Menus/EditorPlacer
@onready var _editor_mesher: EditorMesher = $PanelContainer/MarginContainer/VBoxContainer/Menus/EditorMesher
@onready var _editor_rigger: EditorRigger = $PanelContainer/MarginContainer/VBoxContainer/Menus/EditorRigger
@onready var _menus: TabContainer = $PanelContainer/MarginContainer/VBoxContainer/Menus

var _current_model_path := ""
var _default_model_root_position := Vector2.ZERO
var _default_model_root_scale := Vector2.ONE
var _default_model_root_rotation := 0.0
var _editor_settings: TwberEditorSettings
var _batch_renderer: TwberModelBatchRenderer2D
var _clip_controller: TwberAlphaClipController
var _busy := false


func _ready() -> void:
	_remember_default_model_root_transform()
	_editor_settings = TwberEditorSettings.load_settings()
	_batch_renderer = TwberModelBatchRenderer2D.attach_to(_model_root)
	_clip_controller = TwberAlphaClipController.attach_to(_model_root)
	_apply_editor_settings()
	_set_current_model_path("")

	var popup := _file_menu_button.get_popup()
	popup.id_pressed.connect(_on_file_menu_id_pressed)
	_menus.tab_changed.connect(_on_tab_changed)
	_editor_mesher.model_tree_changed.connect(_on_mesher_model_tree_changed)
	_editor_placer.model_render_changed.connect(_on_placer_model_render_changed)
	_model_preview.view_changed.connect(_on_model_preview_view_changed)


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		MENU_NEW:
			_new_model()
		MENU_OPEN:
			_open_model_dialog()
		MENU_SAVE:
			_save_model()
		MENU_SAVE_AS:
			_save_model_as_dialog()
		MENU_EXPORT:
			_export_model_dialog()
		MENU_SETTINGS:
			_open_settings_dialog()
		MENU_PERFORMANCE:
			_show_performance_report()


func _new_model() -> void:
	if _busy:
		return
	if _clip_controller != null:
		_clip_controller.clear()
	for child: Node in _model_root.get_children():
		_model_root.remove_child(child)
		child.queue_free()

	_model_root.position = _default_model_root_position
	_model_root.scale = _default_model_root_scale
	_model_root.rotation = _default_model_root_rotation
	TwberModelCodec.clear_model_root_metadata(_model_root)
	_set_current_model_path("")
	_set_editor_status("Ready")

	_reload_editors_from_preview()
	_menus.current_tab = _editor_placer.get_index()


func _open_model_dialog() -> void:
	var dialog := _create_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Open model")
	dialog.filters = PackedStringArray([MODEL_RESOURCE_FILTER, EXPORTED_MODEL_FILTER])
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		_open_model_async(path)
	)
	dialog.popup_centered_ratio(0.7)


func _save_model() -> void:
	if _current_model_path.is_empty():
		_save_model_as_dialog()
		return

	_save_model_to_path_async(_current_model_path, true)


func _save_model_as_dialog() -> void:
	var dialog := _create_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save model as")
	dialog.filters = PackedStringArray([EXPORTED_MODEL_FILTER, MODEL_RESOURCE_FILTER])
	dialog.current_file = _get_save_as_file_name()
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		_save_model_to_path_async(_normalize_model_path(path), true)
	)
	dialog.popup_centered_ratio(0.7)


func _export_model_dialog() -> void:
	var dialog := _create_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Export Twber copy")
	dialog.filters = PackedStringArray([EXPORTED_MODEL_FILTER])
	dialog.current_file = _get_export_file_name()
	dialog.file_selected.connect(func(path: String) -> void:
		dialog.queue_free()
		_save_model_to_path_async(_normalize_export_path(path), false)
	)
	dialog.popup_centered_ratio(0.7)


func _open_model(path: String) -> void:
	var model = TwberModelCodec.load_model(path)
	if model == null:
		return
	_apply_opened_model(model, path)
	_set_editor_status("Loaded %s" % path.get_file())


func _open_model_async(path: String) -> Error:
	if _busy:
		return ERR_BUSY
	_set_busy(true, "Loading %s…" % path.get_file())
	var result: Variant = await _run_background(TwberModelCodec.load_model.bind(path))
	if result is not TwberModelResource:
		_set_busy(false, "Load failed")
		push_error("Could not load model: %s" % path)
		return ERR_FILE_CORRUPT
	_set_editor_status("Preparing editor…")
	await get_tree().process_frame
	_apply_opened_model(result as TwberModelResource, path)
	_set_busy(false, "Loaded %s" % path.get_file())
	return OK


func _apply_opened_model(model: TwberModelResource, path: String) -> void:

	if _clip_controller != null:
		_clip_controller.clear()
	TwberModelCodec.apply_to_model_root(model, _model_root)
	_optimize_editor_rendering(
			path.get_extension().to_lower() != TwberModelCodec.TWBER_EXTENSION,
	)
	_reload_editors_from_preview()

	_set_current_model_path(path)


func _save_model_to_path(path: String, make_current: bool) -> Error:
	var normalized_path := _normalize_model_path(path)
	if normalized_path.get_extension().to_lower() == TwberModelCodec.TWBER_EXTENSION:
		return _export_model(normalized_path, make_current)
	return _save_model_resource(normalized_path, make_current)


func _save_model_to_path_async(path: String, make_current: bool) -> Error:
	if _busy:
		return ERR_BUSY
	var normalized_path := _normalize_model_path(path)
	_set_busy(true, "Saving %s…" % normalized_path.get_file())
	await get_tree().process_frame
	var model := _create_model_resource_from_base_state()
	var save_callable: Callable
	if normalized_path.get_extension().to_lower() == TwberModelCodec.TWBER_EXTENSION:
		save_callable = TwberModelCodec.export_twber.bind(model, normalized_path)
	else:
		save_callable = TwberModelCodec.save_resource.bind(model, normalized_path)
	var result: Variant = await _run_background(save_callable)
	var error := int(result) as Error
	if error != OK:
		_set_busy(false, "Save failed")
		push_error("Could not save model: %s" % error_string(error))
		return error
	if make_current:
		_set_current_model_path(normalized_path)
	_set_busy(false, "Saved %s" % normalized_path.get_file())
	return OK


func _save_model_resource(path: String, make_current := true) -> Error:
	var model := _create_model_resource_from_base_state()
	var error: Error = TwberModelCodec.save_resource(model, path)
	if error != OK:
		push_error("Could not save model resource: %s" % error_string(error))
		return error

	if make_current:
		_set_current_model_path(path)
	return OK


func _export_model(path: String, make_current := false) -> Error:
	var model := _create_model_resource_from_base_state()
	var error: Error = TwberModelCodec.export_twber(model, path)
	if error != OK:
		push_error("Could not export Twber model: %s" % error_string(error))
		return error
	if make_current:
		_set_current_model_path(path)
	return OK


func _open_settings_dialog() -> void:
	var dialog: EditorSettingsDialog = SETTINGS_DIALOG_SCENE.instantiate()
	dialog.set_editor_settings(_editor_settings)
	dialog.settings_applied.connect(func(settings: TwberEditorSettings) -> void:
		_editor_settings = settings
		_apply_editor_settings()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 340))


func _show_performance_report() -> void:
	var model := _create_model_resource_from_base_state()
	var summary := TwberModelCodec.get_model_performance_summary(model)
	if _batch_renderer != null and _batch_renderer.is_batching_active():
		summary["estimated_draw_calls"] = _batch_renderer.get_batch_count()
	var warnings := TwberPerformanceBudget.get_warnings(summary)
	var report_lines := PackedStringArray([
		"Layers: %d (%d drawable)" % [summary.get("layers", 0), summary.get("drawable_layers", 0)],
		"Estimated draw calls: %d" % summary.get("estimated_draw_calls", 0),
		"Meshes: %d | Vertices: %d | Triangles: %d" % [
			summary.get("meshes", 0),
			summary.get("vertices", 0),
			summary.get("triangles", 0),
		],
		"Textures: %d | Estimated VRAM: %s" % [
			summary.get("textures", 0),
			TwberPerformanceBudget.format_bytes(summary.get("estimated_texture_vram_bytes", 0)),
		],
		"Transparent pixels trimmed: %d" % summary.get("trimmed_pixels_saved", 0),
		"Animation frames: %d" % summary.get("animation_frames", 0),
		"Parameters: %d | Positions: %d | States: %d" % [
			summary.get("parameters", 0),
			summary.get("parameter_positions", 0),
			summary.get("parameter_states", 0),
		],
	])
	if warnings.is_empty():
		report_lines.append("\nNo recommended performance budgets exceeded.")
	else:
		report_lines.append("\nRecommendations:")
		for warning: String in warnings:
			report_lines.append("• %s" % warning)

	var dialog := AcceptDialog.new()
	dialog.title = "Model Performance"
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	var label := Label.new()
	label.custom_minimum_size = Vector2(560, 260)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "\n".join(report_lines)
	dialog.add_child(label)
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 340))


func _apply_editor_settings() -> void:
	_editor_placer.set_editor_settings(_editor_settings)
	_editor_mesher.set_editor_settings(_editor_settings)
	_editor_rigger.set_editor_settings(_editor_settings)
	_optimize_editor_rendering(false)
	if _editor_rigger.visible:
		_editor_rigger.preview_parameters()


func _on_tab_changed(tab_index: int) -> void:
	var tab := _menus.get_child(tab_index)
	if tab != _editor_rigger:
		_editor_rigger.restore_parameter_preview_base()

	if tab == _editor_placer:
		_editor_placer.reload_from_preview()
	elif tab == _editor_mesher:
		_editor_mesher.reload_from_preview()
	elif tab == _editor_rigger:
		_editor_rigger.reload_from_preview()


func _on_mesher_model_tree_changed() -> void:
	_optimize_editor_rendering(false)
	_editor_placer.reload_from_preview()
	_editor_rigger.reload_from_preview()


func _on_model_preview_view_changed() -> void:
	_editor_mesher.refresh_overlay()
	_editor_rigger.refresh_overlay()


func _on_placer_model_render_changed(
		rebuild_atlases: bool,
		reconfigure_batching: bool,
) -> void:
	if rebuild_atlases or reconfigure_batching:
		_optimize_editor_rendering(rebuild_atlases)
	elif _batch_renderer != null:
		_batch_renderer.update_dynamic_geometry()


func _optimize_editor_rendering(rebuild_atlases: bool) -> void:
	if _clip_controller == null:
		_clip_controller = TwberAlphaClipController.attach_to(_model_root)
	_clip_controller.clear()
	if rebuild_atlases and _editor_settings != null:
		TwberTextureAtlasBuilder.optimize_model_root(
				_model_root,
				_editor_settings.large_texture_vram_threshold_px,
		)
	if _batch_renderer == null:
		_batch_renderer = TwberModelBatchRenderer2D.attach_to(_model_root)
	_clip_controller.configure(_model_root)
	_batch_renderer.configure(_model_root)


func _reload_editors_from_preview() -> void:
	_optimize_editor_rendering(false)
	_editor_placer.reload_from_preview()
	_editor_mesher.reload_from_preview()
	_editor_rigger.reload_from_preview()


func _create_model_resource_from_base_state() -> TwberModelResource:
	var should_restore_preview := _editor_rigger.visible
	_editor_rigger.restore_parameter_preview_base()
	if _clip_controller != null:
		_clip_controller.clear()
	var model := TwberModelCodec.from_model_root(_model_root)
	_optimize_editor_rendering(false)
	if should_restore_preview:
		_editor_rigger.preview_parameters()
	return model


func _create_file_dialog(file_mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = file_mode
	dialog.use_native_dialog = false
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	return dialog


func _remember_default_model_root_transform() -> void:
	_default_model_root_position = _model_root.position
	_default_model_root_scale = _model_root.scale
	_default_model_root_rotation = _model_root.rotation


func _normalize_model_path(path: String) -> String:
	return _normalize_path_extension(
		path,
		PackedStringArray(["tres", "res", TwberModelCodec.TWBER_EXTENSION]),
		TwberModelCodec.TWBER_EXTENSION,
	)


func _normalize_export_path(path: String) -> String:
	return _normalize_path_extension(
		path,
		PackedStringArray([TwberModelCodec.TWBER_EXTENSION]),
		TwberModelCodec.TWBER_EXTENSION
	)


func _get_save_as_file_name() -> String:
	return _current_model_path.get_file() if not _current_model_path.is_empty() else "model.twber"


func _get_export_file_name() -> String:
	if _current_model_path.is_empty():
		return "model.twber"
	return "%s.twber" % _current_model_path.get_file().get_basename()


func _set_current_model_path(path: String) -> void:
	_current_model_path = path
	if _current_model_label == null:
		return
	_current_model_label.text = path.get_file() if not path.is_empty() else "Untitled"
	_current_model_label.tooltip_text = path if not path.is_empty() else "This model has not been saved yet."


func get_current_model_path() -> String:
	return _current_model_path


func is_busy() -> bool:
	return _busy


func _set_busy(busy: bool, status: String) -> void:
	_busy = busy
	_file_menu_button.disabled = busy
	_menus.mouse_behavior_recursive = (
		Control.MOUSE_BEHAVIOR_DISABLED if busy else Control.MOUSE_BEHAVIOR_ENABLED
	)
	_menus.modulate.a = 0.65 if busy else 1.0
	_set_editor_status(status)


func _set_editor_status(status: String) -> void:
	if _editor_status_label != null:
		_editor_status_label.text = status


func _run_background(callable: Callable) -> Variant:
	var task := TwberBackgroundTask.new()
	get_tree().root.add_child(task)
	var error := task.start(callable)
	if error != OK:
		task.queue_free()
		return error
	return await task.completed


func _normalize_path_extension(
		path: String,
		valid_extensions: PackedStringArray,
		default_extension: String,
) -> String:
	var extension := path.get_extension().to_lower()
	if valid_extensions.has(extension):
		return path

	var base_path := path if extension.is_empty() else path.get_basename()
	return "%s.%s" % [base_path, default_extension]
