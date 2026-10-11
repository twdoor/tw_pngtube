class_name TwberEditor extends CanvasLayer

const MENU_NEW := 4
const MENU_OPEN := 1
const MENU_SAVE := 2
const MENU_EXPORT := 3
const MENU_SETTINGS := 5
const MENU_PERFORMANCE := 6
const MENU_SAVE_AS := 7
const MENU_HOME := 8
const HOME_SCENE := "res://launcher/launcher.tscn"
const RECOVERY_MODEL_FILE := "recovery.twber"
const RECOVERY_METADATA_FILE := "recovery.cfg"
const SETTINGS_DIALOG_SCENE := preload("res://editor/editor_settings_dialog.tscn")

enum PendingAction {
	NONE,
	NEW_MODEL,
	OPEN_MODEL,
	HOME,
	QUIT,
}

@onready var _file_menu_button: MenuButton = %FileMenuButton
@onready var _edit_menu_button: MenuButton = %EditMenuButton
@onready var _current_model_label: Label = %CurrentModelLabel
@onready var _editor_status_label: Label = %EditorStatusLabel
@onready var _model_root: Node2D = %Workspace.canvas.get_node("Textures")
@onready var _model_preview: ModelPreview = $ModelPreview
@onready var _preview_background: ColorRect = %Workspace.canvas.get_node("Background")
@onready var _editor_placer: EditorPlacer = %EditorPlacer
@onready var _editor_mesher: EditorMesher = %EditorMesher
@onready var _editor_rigger: EditorRigger = %EditorRigger
@onready var _editor_animator: EditorAnimator = %EditorAnimator
@onready var _mode_bar: TabBar = %ModeBar
@onready var _controllers: Node = $Controllers
@onready var _open_model_file_dialog: FileDialog = %OpenModelDialog
@onready var _save_model_file_dialog: FileDialog = %SaveModelDialog
@onready var _export_model_file_dialog: FileDialog = %ExportModelDialog
@onready var _autosave_timer: Timer = %AutosaveTimer
@onready var _unsaved_changes_dialog: Window = %UnsavedChangesDialog
@onready var _unsaved_changes_label: Label = %UnsavedChangesLabel
@onready var _cancel_changes_button: Button = %CancelChangesButton
@onready var _discard_changes_button: Button = %DiscardChangesButton
@onready var _save_changes_button: Button = %SaveChangesButton
@onready var _recovery_dialog: ConfirmationDialog = %RecoveryDialog

var _current_model_path := ""
var _default_model_root_position := Vector2.ZERO
var _default_model_root_scale := Vector2.ONE
var _default_model_root_rotation := 0.0
var _editor_settings: TwberEditorSettings
var _batch_renderer: TwberModelBatchRenderer2D
var _clip_controller: TwberAlphaClipController
var _pose_name_change := false
var _parameter_take: TwberParameterTake
var _take_started_usec := 0
var _frame_export_dialog: TwberFrameExportDialog
var _busy := false
var _dirty := false
var _suppress_dirty_tracking := false
var _autosave_active := false
var _owns_recovery := false
var _pending_action := PendingAction.NONE
var _continue_pending_after_save := false
var _document := TwberModelDocument.new()
var _mesh_edit_session: TwberDocumentEditSession
var _mesh_edit_layer_id := ""
var _active_tab := 0
var _recovery_generation := 0
var _workspace_binding: TwberWorkspaceBinding
var _previous_window_minimum := Vector2i.ZERO
var _selected_document_layer_id := ""
var _changing_mode := false
var _focus_check_pending := false
var _record_take_button: Button
var _cancel_take_button: Button


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_remember_default_model_root_transform()
	_editor_settings = TwberEditorSettings.load_settings()
	_batch_renderer = TwberModelBatchRenderer2D.attach_to(_model_root)
	_clip_controller = TwberAlphaClipController.attach_to(_model_root)
	_apply_editor_settings()
	_set_current_model_path("")
	_active_tab = _mode_bar.current_tab
	_document.replace_model(TwberModelCodec.from_model_root(_model_root))
	_document.changed.connect(_on_committed_document_changed)
	_document.dirty_changed.connect(_on_document_dirty_changed)
	_editor_placer.prepare_transform = _finish_pending_authoring
	_editor_rigger.pose_draft = TwberPoseDraftController.new(_document, _model_root)
	_editor_animator.pose_draft = TwberPoseDraftController.new(_document, _model_root)
	_editor_rigger.pose_draft.changed.connect(_on_pose_draft_changed)
	_editor_animator.pose_draft.changed.connect(_on_pose_draft_changed)
	_editor_rigger.execute_parameter_command = _execute_parameter_command
	_record_take_button = _editor_rigger.get_panel_control("RecordTake") as Button
	_cancel_take_button = _editor_rigger.get_panel_control("CancelTake") as Button
	_record_take_button.pressed.connect(_toggle_parameter_recording)
	_cancel_take_button.pressed.connect(_cancel_parameter_recording)
	_editor_rigger.parameter_values_previewed.connect(_sample_parameter_recording)
	_frame_export_dialog = TwberFrameExportDialog.new()
	add_child(_frame_export_dialog)
	_editor_animator.export_frames_requested.connect(_show_frame_export)
	_editor_animator.get_document_model = func() -> TwberModelResource: return _document.snapshot().to_model_resource()
	_editor_animator._capture_base_pose()
	_editor_animator.execute_timeline_command = _execute_timeline_command
	_editor_placer.execute_hierarchy_command = _execute_hierarchy_command
	_editor_placer.execute_layer_command = _execute_layer_command
	_editor_rigger.execute_layer_command = _execute_layer_command
	_editor_animator.execute_layer_command = _execute_layer_command
	_editor_placer.transform_committed.connect(_on_transform_committed)
	_editor_placer.transform_cancelled.connect(_on_transform_cancelled)
	_edit_menu_button.get_popup().id_pressed.connect(_on_edit_menu_id_pressed)
	_refresh_history_menu()

	var popup := _file_menu_button.get_popup()
	popup.id_pressed.connect(_on_file_menu_id_pressed)
	_mode_bar.tab_changed.connect(_on_tab_changed)
	_editor_mesher.execute_mesh_command = _execute_mesh_command
	_editor_mesher.begin_mesh_gesture = _begin_mesh_gesture
	_editor_mesher.end_mesh_gesture = _finish_mesh_gesture
	_editor_placer.model_render_changed.connect(_on_placer_model_render_changed)
	_model_preview.view_changed.connect(_on_model_preview_view_changed)
	_open_model_file_dialog.file_selected.connect(_on_open_model_file_selected)
	_save_model_file_dialog.file_selected.connect(_on_save_model_file_selected)
	_save_model_file_dialog.canceled.connect(_on_save_model_file_dialog_cancelled)
	_export_model_file_dialog.file_selected.connect(_on_export_model_file_selected)
	_autosave_timer.timeout.connect(_on_autosave_timer_timeout)
	_unsaved_changes_dialog.close_requested.connect(_cancel_pending_action)
	_cancel_changes_button.pressed.connect(_cancel_pending_action)
	_discard_changes_button.pressed.connect(_discard_changes_and_continue)
	_save_changes_button.pressed.connect(_save_changes_and_continue)
	_recovery_dialog.confirmed.connect(_recover_autosave)
	_prepare_model_dialog(_open_model_file_dialog)
	_prepare_model_dialog(_save_model_file_dialog)
	_prepare_model_dialog(_export_model_file_dialog)
	_previous_window_minimum = get_window().min_size
	($PanelContainer as Control).minimum_size_changed.connect(_sync_workspace_minimum_size)
	_workspace_binding = TwberWorkspaceBinding.new()
	_workspace_binding.setup(self)
	_sync_workspace_minimum_size.call_deferred()
	_check_for_recovery.call_deferred()


func _exit_tree() -> void:
	if _workspace_binding != null and is_instance_valid(_workspace_binding.workspace):
		_workspace_binding.workspace.save_layout()
		get_window().min_size = _previous_window_minimum
	var tree := get_tree()
	if tree != null:
		tree.auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready():
		_schedule_workspace_focus_check()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		_request_action(PendingAction.QUIT)


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		MENU_NEW:
			_request_action(PendingAction.NEW_MODEL)
		MENU_OPEN:
			_request_action(PendingAction.OPEN_MODEL)
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
		MENU_HOME:
			_request_action(PendingAction.HOME)


func _new_model() -> void:
	if _busy:
		return
	_suppress_dirty_tracking = true
	_editor_placer.cancel_transform_drag()
	_cancel_mesh_gesture(false)
	_editor_rigger.restore_parameter_preview_base()
	_editor_animator.stop_and_restore()
	if _clip_controller != null:
		_clip_controller.clear()
	for child: Node in _model_root.get_children():
		_model_root.remove_child(child)
		child.queue_free()

	_model_root.position = _default_model_root_position
	_model_root.scale = _default_model_root_scale
	_model_root.rotation = _default_model_root_rotation
	TwberModelCodec.clear_model_root_metadata(_model_root)
	_document.replace_model(TwberModelCodec.from_model_root(_model_root))
	_set_current_model_path("")
	_set_editor_status("Ready")

	_reload_editors_from_preview()
	_mode_bar.current_tab = _editor_placer.get_index()
	_suppress_dirty_tracking = false
	_set_dirty(false)
	_clear_recovery()


func _open_model_dialog() -> void:
	_prepare_model_dialog(_open_model_file_dialog)
	_open_model_file_dialog.popup_centered_ratio(0.7)


func _on_open_model_file_selected(path: String) -> void:
	_open_model_async(path)


func _save_model() -> void:
	if _current_model_path.is_empty():
		_save_model_as_dialog()
		return

	_save_model_to_path_async(_current_model_path, true)


func _save_model_as_dialog(continue_pending_action := false) -> void:
	_continue_pending_after_save = continue_pending_action
	_prepare_model_dialog(_save_model_file_dialog)
	_save_model_file_dialog.current_file = _get_save_as_file_name()
	_save_model_file_dialog.popup_centered_ratio(0.7)


func _on_save_model_file_selected(path: String) -> void:
	var continue_after_save := _continue_pending_after_save
	_continue_pending_after_save = false
	var error := await _save_model_to_path_async(_normalize_model_path(path), true)
	if continue_after_save and error == OK:
		_execute_pending_action()
	elif continue_after_save:
		_pending_action = PendingAction.NONE


func _on_save_model_file_dialog_cancelled() -> void:
	if not _continue_pending_after_save:
		return
	_continue_pending_after_save = false
	_pending_action = PendingAction.NONE


func _export_model_dialog() -> void:
	_prepare_model_dialog(_export_model_file_dialog)
	_export_model_file_dialog.current_file = _get_export_file_name()
	_export_model_file_dialog.popup_centered_ratio(0.7)


func _on_export_model_file_selected(path: String) -> void:
	_save_model_to_path_async(_normalize_export_path(path), false)


func _request_action(action: PendingAction) -> void:
	if _busy or _unsaved_changes_dialog.visible:
		return
	_editor_placer.finish_transform_drag()
	_finish_mesh_gesture()
	_finish_pending_authoring()
	_pending_action = action
	if not _dirty:
		_execute_pending_action()
		return
	var model_name := (
		_current_model_path.get_file()
		if not _current_model_path.is_empty()
		else "Untitled"
	)
	_unsaved_changes_label.text = (
		"%s has unsaved changes. Save them before continuing?" % model_name
	)
	_unsaved_changes_dialog.popup_centered()


func _execute_pending_action() -> void:
	var action := _pending_action
	_pending_action = PendingAction.NONE
	match action:
		PendingAction.NEW_MODEL:
			_new_model()
		PendingAction.OPEN_MODEL:
			_open_model_dialog()
		PendingAction.HOME:
			get_tree().change_scene_to_file(HOME_SCENE)
		PendingAction.QUIT:
			get_tree().quit()


func _cancel_pending_action() -> void:
	_unsaved_changes_dialog.hide()
	_pending_action = PendingAction.NONE
	_continue_pending_after_save = false


func _discard_changes_and_continue() -> void:
	_unsaved_changes_dialog.hide()
	_clear_recovery()
	_execute_pending_action()


func _save_changes_and_continue() -> void:
	_unsaved_changes_dialog.hide()
	if _current_model_path.is_empty():
		_save_model_as_dialog(true)
		return
	var error := await _save_model_to_path_async(_current_model_path, true)
	if error == OK:
		_execute_pending_action()
	else:
		_pending_action = PendingAction.NONE


func _open_model(path: String) -> void:
	var model = TwberModelCodec.load_model(path)
	if model == null:
		return
	if _apply_opened_model(model, path) == OK:
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
	var error := _apply_opened_model(result as TwberModelResource, path)
	_set_busy(false, "Loaded %s" % path.get_file() if error == OK else "Load failed: invalid model")
	return error


func _apply_opened_model(
	model: TwberModelResource,
	path: String,
	clear_recovery := true,
) -> Error:
	var error := _document.replace_model(model)
	if error != OK:
		_set_editor_status("Invalid model: %s" % "; ".join(_document.get_diagnostics()))
		return error
	_suppress_dirty_tracking = true
	_editor_placer.cancel_transform_drag()
	_cancel_mesh_gesture(false)
	_editor_rigger.restore_parameter_preview_base()
	_editor_animator.stop_and_restore()
	if _clip_controller != null:
		_clip_controller.clear()
	TwberModelCodec.apply_to_model_root(model, _model_root)
	_center_workspace_canvas()
	_selected_document_layer_id = ""
	_optimize_editor_rendering(
			path.get_extension().to_lower() != TwberModelCodec.TWBER_EXTENSION,
	)
	_reload_editors_from_preview()

	_set_current_model_path(path)
	_suppress_dirty_tracking = false
	_set_dirty(false)
	if clear_recovery:
		_clear_recovery()
	return OK


func _save_model_to_path(path: String, make_current: bool) -> Error:
	var normalized_path := _normalize_model_path(path)
	if normalized_path.get_extension().to_lower() == TwberModelCodec.TWBER_EXTENSION:
		return _export_model(normalized_path, make_current)
	return _save_model_resource(normalized_path, make_current)


func _save_model_to_path_async(path: String, make_current: bool) -> Error:
	if _busy:
		return ERR_BUSY
	var normalized_path := _normalize_model_path(path)
	var snapshot := _prepare_document_snapshot()
	if snapshot == null:
		_set_editor_status("Save failed: an edit could not be committed")
		return ERR_INVALID_DATA
	_set_busy(true, "Saving %s…" % normalized_path.get_file())
	while _autosave_active:
		await get_tree().process_frame
	var model := snapshot.to_model_resource()
	var save_callable: Callable
	if normalized_path.get_extension().to_lower() == TwberModelCodec.TWBER_EXTENSION:
		save_callable = TwberModelCodec.export_prepared_twber.bind(
			TwberModelCodec.prepare_twber_export(model), normalized_path
		)
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
		_document.mark_saved(snapshot)
		_refresh_document_dirty()
		_clear_recovery()
	_set_busy(false, "Saved %s" % normalized_path.get_file())
	return OK


func _save_model_resource(path: String, make_current := true) -> Error:
	if _autosave_active:
		return ERR_BUSY
	var snapshot := _prepare_document_snapshot()
	if snapshot == null:
		return ERR_INVALID_DATA
	var error: Error = TwberModelCodec.save_resource(snapshot.to_model_resource(), path)
	if error != OK:
		push_error("Could not save model resource: %s" % error_string(error))
		return error

	if make_current:
		_set_current_model_path(path)
		_document.mark_saved(snapshot)
		_refresh_document_dirty()
		_clear_recovery()
	return OK


func _export_model(path: String, make_current := false) -> Error:
	if _autosave_active:
		return ERR_BUSY
	var snapshot := _prepare_document_snapshot()
	if snapshot == null:
		return ERR_INVALID_DATA
	var error: Error = TwberModelCodec.export_twber(snapshot.to_model_resource(), path)
	if error != OK:
		push_error("Could not export Twber model: %s" % error_string(error))
		return error
	if make_current:
		_set_current_model_path(path)
		_document.mark_saved(snapshot)
		_refresh_document_dirty()
		_clear_recovery()
	return OK


func _open_settings_dialog() -> void:
	var dialog: EditorSettingsDialog = SETTINGS_DIALOG_SCENE.instantiate()
	dialog.set_editor_settings(_editor_settings)
	dialog.settings_applied.connect(func(settings: TwberEditorSettings) -> void:
		_editor_settings = settings
		_apply_editor_settings()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 390))


func _show_performance_report() -> void:
	var model := _create_model_resource_from_base_state()
	if model == null:
		return
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
	_preview_background.color = _editor_settings.background_color
	_editor_placer.set_editor_settings(_editor_settings)
	_editor_mesher.set_editor_settings(_editor_settings)
	_editor_rigger.set_editor_settings(_editor_settings)
	_editor_animator.set_editor_settings(_editor_settings)
	_optimize_editor_rendering(false)
	if _editor_rigger.tool_active:
		_editor_rigger.preview_parameters()


func _on_tab_changed(tab_index: int) -> void:
	if _busy:
		_mode_bar.set_block_signals(true)
		_mode_bar.current_tab = _active_tab
		_mode_bar.set_block_signals(false)
		return
	var shared_selection := _active_selection_id()
	_changing_mode = true
	_cancel_parameter_recording()
	_cancel_pose_drafts()
	_finish_mesh_gesture()
	_editor_placer.finish_transform_drag()
	if _finish_pending_authoring() != OK:
		_mode_bar.set_block_signals(true)
		_mode_bar.current_tab = _active_tab
		_mode_bar.set_block_signals(false)
		_changing_mode = false
		return
	_active_tab = tab_index
	for tool: TwberEditorTool in [_editor_placer, _editor_mesher, _editor_rigger, _editor_animator]:
		tool.set_tool_active(tool.get_index() == tab_index)
	var tab := _controllers.get_child(tab_index)
	if tab != _editor_rigger:
		_editor_rigger.restore_parameter_preview_base()
	if tab != _editor_animator:
		_editor_animator.stop_and_restore()

	if tab == _editor_placer:
		_editor_placer.reload_from_preview()
	elif tab == _editor_mesher:
		_editor_mesher.reload_from_preview()
	elif tab == _editor_rigger:
		_editor_rigger.reload_from_preview()
	elif tab == _editor_animator:
		_editor_animator.reload_from_preview()
	_select_workspace_layer(shared_selection)
	_changing_mode = false
	if _workspace_binding != null:
		_workspace_binding.set_mode(tab_index)


func _on_model_preview_view_changed() -> void:
	_editor_placer.refresh_overlay()
	_editor_mesher.refresh_overlay()
	_editor_rigger.refresh_overlay()
	_editor_animator.refresh_overlay()


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
	_editor_animator.reload_from_preview()


func _create_model_resource_from_base_state() -> TwberModelResource:
	var snapshot := _prepare_document_snapshot()
	return snapshot.to_model_resource() if snapshot != null else null


# Saves only flush explicit authoring events. Displayed poses are never a save source.
func _prepare_document_snapshot() -> TwberDocumentSnapshot:
	if _finish_mesh_gesture() != OK:
		return null
	_editor_placer.finish_transform_drag()
	if _finish_pending_authoring() != OK:
		return null
	return _document.snapshot()


func _finish_pending_authoring() -> Error:
	if _suppress_dirty_tracking:
		return OK
	var error := _editor_rigger.finish_parameter_edits()
	if error != OK:
		return error
	return _editor_animator.finish_animation_edits()


func _begin_mesh_gesture(label: String, layer_id: String) -> Error:
	if _busy or _mesh_edit_session != null:
		return ERR_BUSY
	var error := _finish_pending_authoring()
	if error != OK:
		return error
	_mesh_edit_session = TwberDocumentEditSession.new(_document, label)
	_mesh_edit_layer_id = layer_id
	return OK


func _execute_mesh_command(command: TwberEditMesh, replace_draft: bool) -> Error:
	if _busy or _suppress_dirty_tracking:
		return ERR_BUSY
	var error: Error
	if _mesh_edit_session != null:
		error = _mesh_edit_session.update(command, replace_draft)
		if error == OK:
			_project_mesh(_mesh_edit_session.to_model_resource(), _mesh_edit_layer_id)
		else:
			_set_editor_status("Mesh preview failed: %s" % "; ".join(_mesh_edit_session.diagnostics))
		return error
	error = _finish_pending_authoring()
	if error != OK:
		return error
	error = _document.execute(command)
	if error == OK and command.did_change:
		_project_mesh(_document.snapshot().to_model_resource(), command.layer_ids[0])
	elif error != OK:
		_set_editor_status("Mesh edit failed: %s" % "; ".join(_document.get_diagnostics()))
	return error


func _finish_mesh_gesture() -> Error:
	if _mesh_edit_session == null:
		return OK
	var session := _mesh_edit_session
	var id := _mesh_edit_layer_id
	_mesh_edit_session = null
	_mesh_edit_layer_id = ""
	_editor_mesher.clear_gesture_state()
	var error := session.commit()
	_project_mesh(_document.snapshot().to_model_resource(), id)
	if error != OK:
		_set_editor_status("Mesh gesture cancelled because the document changed")
	return error


func _cancel_mesh_gesture(restore := true) -> void:
	if _mesh_edit_session == null:
		return
	var id := _mesh_edit_layer_id
	_mesh_edit_session.cancel()
	_mesh_edit_session = null
	_mesh_edit_layer_id = ""
	_editor_mesher.clear_gesture_state()
	_editor_mesher._selected_vertex_indices.clear()
	if restore:
		_project_mesh(_document.snapshot().to_model_resource(), id)


func _project_mesh(model: TwberModelResource, id: String) -> void:
	_clip_controller.clear()
	var node := TwberMeshProjection.apply(model, _model_root, id)
	if node == null:
		return
	var replaced := node != _editor_mesher._selected_node
	_editor_mesher.refresh_mesh_projection(node)
	if replaced:
		_editor_placer.reload_from_preview()
	_optimize_editor_rendering(false)


func _execute_layer_command(command: TwberDocumentCommand) -> Error:
	if _busy or _suppress_dirty_tracking:
		return ERR_BUSY
	if _finish_mesh_gesture() != OK:
		return ERR_INVALID_DATA
	_editor_placer.finish_transform_drag()
	var error := _finish_pending_authoring()
	if error != OK:
		return error
	error = _document.execute(command)
	if error != OK:
		_set_editor_status("%s failed: %s" % [command.label, "; ".join(_document.get_diagnostics())])
		_editor_placer._refresh_inspector()
		return error
	if not command.did_change:
		return OK
	var selected := _editor_placer.get_selected_document_layer_id()
	var rig_values := _editor_rigger._parameter_preview_values.duplicate()
	var rig_selection := _editor_rigger._selected_parameter_id
	_suppress_dirty_tracking = true
	_editor_rigger.restore_parameter_preview_base()
	_editor_animator.stop_and_restore()
	_clip_controller.clear()
	var assets := (command.kinds & TwberDocumentChange.Kind.ASSETS) != 0
	TwberLayerProjection.apply(_document.snapshot().to_model_resource(), _model_root, command.layer_ids, assets)
	if assets:
		_optimize_editor_rendering(true)
	_reload_editors_from_preview()
	_editor_placer.select_document_layer(selected)
	_editor_rigger._parameter_preview_values = rig_values
	_editor_rigger._selected_parameter_id = rig_selection
	_editor_rigger._refresh_parameter_panel()
	_editor_rigger.preview_parameters()
	_suppress_dirty_tracking = false
	_set_editor_status(command.label)
	return OK


func _execute_timeline_command(command: TwberEditTimeline) -> Error:
	if _busy or _suppress_dirty_tracking:
		return ERR_BUSY
	var error := _finish_pending_authoring()
	if error != OK:
		return error
	_pose_name_change = command.is_name_only()
	error = _document.execute(command)
	_pose_name_change = false
	if error == OK:
		var model := _document.snapshot().to_model_resource()
		_editor_animator.project_animations(model, command)
		if command.operation == TwberEditTimeline.Operation.DELETE:
			_editor_rigger.sync_parameters(model)
			_editor_rigger._refresh_parameter_panel()
	else:
		_editor_animator._refresh_animation_list()
		_set_editor_status("%s failed: %s" % [command.label, "; ".join(_document.get_diagnostics())])
	return error


func _execute_parameter_command(command: TwberEditParameter) -> Error:
	if _busy or _suppress_dirty_tracking:
		return ERR_BUSY
	var error := _finish_pending_authoring()
	if error != OK:
		return error
	_pose_name_change = command.is_name_only()
	error = _document.execute(command)
	_pose_name_change = false
	if error == OK and (command.did_change or command.operation == TwberEditParameter.Operation.BIND_POSE):
		var model := _document.snapshot().to_model_resource()
		_editor_animator.sync_document(model)
		_editor_rigger.project_parameters(model, command)
	elif error != OK:
		_set_editor_status("%s failed: %s" % [command.label, "; ".join(_document.get_diagnostics())])
	return error


func _execute_hierarchy_command(command: TwberDocumentCommand) -> Error:
	if _busy or _suppress_dirty_tracking:
		return ERR_BUSY
	_finish_mesh_gesture()
	_editor_placer.finish_transform_drag()
	var error := _finish_pending_authoring()
	if error != OK:
		return error
	error = _document.execute(command)
	if error != OK:
		_set_editor_status("%s failed: %s. The hierarchy was left unchanged." % [command.label, "; ".join(_document.get_diagnostics())])
		return error
	if not command.did_change:
		return OK
	_suppress_dirty_tracking = true
	_clip_controller.clear()
	TwberHierarchyProjection.apply(_document.snapshot().to_model_resource(), _model_root)
	if command is TwberCreateLayer or command is TwberDuplicateLayers:
		_optimize_editor_rendering(true)
	_reload_editors_from_preview()
	var selection: Array[String] = []
	if command is TwberCreateLayer:
		selection = [command.created_layer_id]
	elif command is TwberDeleteLayers:
		selection = [command.selection_after]
	elif command is TwberDuplicateLayers:
		selection = command.duplicated_root_ids
	elif command is TwberReparentLayers:
		selection = command.moved_ids
	_editor_placer.select_document_layers(selection)
	_suppress_dirty_tracking = false
	_set_editor_status(command.label)
	return OK


func _on_transform_committed(node: Node2D) -> void:
	if _suppress_dirty_tracking:
		return
	var id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	var error := _document.execute(TwberSetRestTransform.new(id, node.position, node.rotation, node.scale))
	if error != OK:
		_project_document()
		_set_editor_status("Transform could not be committed: %s" % error_string(error))
		return
	var model := _document.snapshot().to_model_resource()
	TwberModelCodec._set_model_parameters_on_root(_model_root, model)
	TwberModelCodec._set_model_timeline_animations_on_root(_model_root, model)
	_refresh_document_dirty()


func _on_transform_cancelled() -> void:
	if _batch_renderer != null:
		_batch_renderer.update_dynamic_geometry()
	_refresh_document_dirty()


func _on_committed_document_changed(_change: TwberDocumentChange) -> void:
	_cancel_parameter_recording()
	if _pose_name_change:
		_editor_rigger.pose_draft.accept_name_revision()
		_editor_animator.pose_draft.accept_name_revision()
	else:
		_cancel_pose_drafts()
	_refresh_history_menu()
	_refresh_document_dirty()


func _on_document_dirty_changed(_value: bool) -> void:
	_refresh_document_dirty()


func _refresh_document_dirty() -> void:
	_set_dirty(_document.is_dirty())


func _refresh_history_menu() -> void:
	var popup := _edit_menu_button.get_popup()
	popup.set_item_text(0, "Discard recording" if _parameter_take != null else "Discard pose draft" if _has_pose_draft() else ("Undo " + _document.get_undo_label() if _document.can_undo() else "Undo"))
	popup.set_item_text(1, "Redo " + _document.get_redo_label() if _document.can_redo() else "Redo")
	popup.set_item_disabled(0, not _document.can_undo() and not _has_pose_draft() and _parameter_take == null)
	popup.set_item_disabled(1, not _document.can_redo() or _has_pose_draft() or _parameter_take != null)


func _on_edit_menu_id_pressed(id: int) -> void:
	if id == 0:
		undo_document()
	elif id == 1:
		redo_document()


func _unhandled_key_input(event: InputEvent) -> void:
	if _busy or event is not InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _parameter_take != null:
		_cancel_parameter_recording()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _has_pose_draft():
		_cancel_pose_drafts()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _mesh_edit_session != null:
		_cancel_mesh_gesture()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _editor_placer.is_transform_dragging():
		_editor_placer.cancel_transform_drag()
		get_viewport().set_input_as_handled()
	elif event.is_command_or_control_pressed() and not event.alt_pressed:
		if event.keycode == KEY_Z:
			if event.shift_pressed:
				redo_document()
			else:
				undo_document()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y:
			redo_document()
			get_viewport().set_input_as_handled()


func undo_document() -> bool:
	if _parameter_take != null:
		_cancel_parameter_recording()
		return true
	if _busy:
		return false
	if _has_pose_draft():
		_cancel_pose_drafts()
		return true
	if _mesh_edit_session != null:
		_cancel_mesh_gesture()
		return true
	if _editor_placer.is_transform_dragging():
		_editor_placer.cancel_transform_drag()
		return true
	if _finish_pending_authoring() != OK:
		return false
	if not _document.undo():
		return false
	_project_document()
	return true


func redo_document() -> bool:
	if _parameter_take != null or _has_pose_draft() or _busy or _mesh_edit_session != null or _editor_placer.is_transform_dragging() or _finish_pending_authoring() != OK:
		return false
	if not _document.redo():
		return false
	_project_document()
	return true


func _project_document() -> void:
	_cancel_mesh_gesture(false)
	var view_transform := _model_root.transform
	var selected_id := _editor_placer.get_selected_document_layer_id()
	var rig_values := _editor_rigger._parameter_preview_values.duplicate()
	var rig_selection := _editor_rigger._selected_parameter_id
	var selected_by_tab := {}
	for tab: EditorModelTree in [_editor_mesher, _editor_rigger, _editor_animator]:
		if is_instance_valid(tab._selected_node):
			selected_by_tab[tab] = String(tab._selected_node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	_suppress_dirty_tracking = true
	_editor_mesher._reset_interaction_state()
	_editor_rigger._stop_pointer_interaction()
	_editor_rigger.restore_parameter_preview_base()
	_editor_animator.stop_and_restore()
	for tab: EditorModelTree in [_editor_mesher, _editor_rigger, _editor_animator]:
		tab._set_selected_node(null)
	_clip_controller.clear()
	TwberModelCodec.apply_to_model_root(_document.snapshot().to_model_resource(), _model_root)
	_model_root.transform = view_transform
	_reload_editors_from_preview()
	_editor_placer.select_document_layer(selected_id)
	_editor_rigger._parameter_preview_values = rig_values
	_editor_rigger._selected_parameter_id = rig_selection
	_editor_rigger._refresh_parameter_panel()
	_editor_rigger.preview_parameters()
	var nodes := TwberParameterMapper.get_layer_nodes_by_id(_model_root)
	for tab: EditorModelTree in selected_by_tab:
		tab._select_node(nodes.get(selected_by_tab[tab]) as Node2D)
	_suppress_dirty_tracking = false
	_refresh_document_dirty()
	_refresh_history_menu()
	if not _dirty:
		_clear_recovery()


func _prepare_model_dialog(dialog: FileDialog) -> void:
	var error := TwberAppSettings.ensure_directory(
		TwberAppSettings.MODELS_DIRECTORY_NAME
	)
	if error != OK:
		_set_editor_status("Could not create model library: %s" % error_string(error))
		return
	dialog.current_dir = TwberAppSettings.get_directory_path(
		TwberAppSettings.MODELS_DIRECTORY_NAME
	)


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
	_refresh_current_model_label()


func _refresh_current_model_label() -> void:
	if _current_model_label == null:
		return
	var model_name := (
		_current_model_path.get_file()
		if not _current_model_path.is_empty()
		else "Untitled"
	)
	_current_model_label.text = "%s%s" % [model_name, " *" if _dirty else ""]
	_current_model_label.tooltip_text = (
		_current_model_path
		if not _current_model_path.is_empty()
		else "This model has not been saved yet."
	)




func _set_dirty(dirty: bool) -> void:
	_dirty = dirty
	_refresh_current_model_label()
	if _autosave_timer == null:
		return
	if dirty:
		_autosave_timer.start()
	else:
		_autosave_timer.stop()


func is_dirty() -> bool:
	return _dirty


func _on_autosave_timer_timeout() -> void:
	_write_autosave()


func _write_autosave() -> Error:
	if not _dirty:
		return OK
	if _busy or _autosave_active or _mesh_edit_session != null or _editor_placer.is_transform_dragging():
		_autosave_timer.start()
		return ERR_BUSY
	var directory_error := TwberAppSettings.ensure_directory(
		TwberAppSettings.AUTOSAVES_DIRECTORY_NAME
	)
	if directory_error != OK:
		_set_editor_status("Autosave unavailable: %s" % error_string(directory_error))
		return directory_error

	var snapshot := _prepare_document_snapshot()
	if snapshot == null:
		return ERR_INVALID_DATA
	_autosave_active = true
	var generation := _recovery_generation
	var source_path := _current_model_path
	var result: Variant = await _run_background(
		TwberModelCodec.export_prepared_twber.bind(
			TwberModelCodec.prepare_twber_export(snapshot.to_model_resource()), _recovery_model_path()
		)
	)
	var error := int(result) as Error
	if generation != _recovery_generation:
		_autosave_active = false
		DirAccess.remove_absolute(_recovery_model_path())
		return ERR_SKIP
	if error == OK:
		error = _write_recovery_metadata(source_path)
	_autosave_active = false
	if error == OK:
		_owns_recovery = true
		_set_editor_status("Autosaved recovery copy")
	else:
		_set_editor_status("Autosave failed: %s" % error_string(error))
	return error


func _write_recovery_metadata(source_path: String) -> Error:
	var metadata := ConfigFile.new()
	metadata.set_value("recovery", "source_path", source_path)
	metadata.set_value(
		"recovery",
		"saved_at",
		Time.get_datetime_string_from_system(false, true),
	)
	return metadata.save(_recovery_metadata_path())


func _check_for_recovery() -> void:
	if not FileAccess.file_exists(_recovery_model_path()):
		return
	var metadata := ConfigFile.new()
	metadata.load(_recovery_metadata_path())
	var source_path := str(metadata.get_value("recovery", "source_path", ""))
	var saved_at := str(metadata.get_value("recovery", "saved_at", "an earlier session"))
	var model_name := source_path.get_file() if not source_path.is_empty() else "an untitled model"
	_recovery_dialog.dialog_text = (
		"Twber found an autosave for %s from %s.\n\nRecover it now?"
		% [model_name, saved_at]
	)
	_recovery_dialog.popup_centered()


func _recover_autosave() -> void:
	if _busy:
		return
	_set_busy(true, "Recovering autosaved model…")
	var result: Variant = await _run_background(
		TwberModelCodec.load_model.bind(_recovery_model_path())
	)
	if result is not TwberModelResource:
		_set_busy(false, "Recovery failed")
		return
	var metadata := ConfigFile.new()
	metadata.load(_recovery_metadata_path())
	var source_path := str(metadata.get_value("recovery", "source_path", ""))
	if _apply_opened_model(result as TwberModelResource, source_path, false) != OK:
		_set_busy(false, "Recovery failed: invalid model")
		return
	_owns_recovery = true
	_document.invalidate_saved_state()
	_set_busy(false, "Recovered autosaved model")


func _clear_recovery(force := false) -> void:
	_recovery_generation += 1
	if not force and not _owns_recovery:
		return
	for path: String in [_recovery_model_path(), _recovery_metadata_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_owns_recovery = false


func _recovery_model_path() -> String:
	return TwberAppSettings.get_directory_path(
		TwberAppSettings.AUTOSAVES_DIRECTORY_NAME
	).path_join(RECOVERY_MODEL_FILE)


func _recovery_metadata_path() -> String:
	return TwberAppSettings.get_directory_path(
		TwberAppSettings.AUTOSAVES_DIRECTORY_NAME
	).path_join(RECOVERY_METADATA_FILE)


func get_current_model_path() -> String:
	return _current_model_path


func is_busy() -> bool:
	return _busy


func _set_busy(busy: bool, status: String) -> void:
	_busy = busy
	_file_menu_button.disabled = busy
	_edit_menu_button.disabled = busy
	_mode_bar.mouse_behavior_recursive = (
		Control.MOUSE_BEHAVIOR_DISABLED if busy else Control.MOUSE_BEHAVIOR_ENABLED
	)
	_mode_bar.modulate.a = 0.65 if busy else 1.0
	if _workspace_binding != null:
		_workspace_binding.workspace.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if busy else Control.MOUSE_BEHAVIOR_ENABLED
		_workspace_binding.modes.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP
		_workspace_binding.workspace.modulate.a = 0.65 if busy else 1.0
		for panel: TwberDockPanel in _workspace_binding.workspace.panels.values():
			panel.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if busy else Control.MOUSE_BEHAVIOR_ENABLED
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


func _has_pose_draft() -> bool:
	return (_editor_rigger.pose_draft != null and _editor_rigger.pose_draft.has_draft()) or (_editor_animator.pose_draft != null and _editor_animator.pose_draft.has_draft())


func _cancel_pose_drafts() -> void:
	_editor_rigger.cancel_pose_draft()
	_editor_animator.cancel_pose_draft()


func _on_pose_draft_changed() -> void:
	_refresh_history_menu()
	if _editor_rigger.pose_draft.has_draft():
		_set_editor_status("Unbound pose: Bind to keep it; Escape to discard")
	elif _editor_animator.pose_draft.has_draft():
		_set_editor_status("Unrecorded pose: Add Point (+) to keep it; Escape to discard")
	else:
		_set_editor_status("Ready")


func _toggle_parameter_recording() -> void:
	if _parameter_take != null:
		_finish_parameter_recording()
		return
	if _busy or _finish_pending_authoring() != OK:
		return
	_cancel_pose_drafts()
	var model := _document.snapshot().to_model_resource()
	var take := TwberParameterTake.new(model.parameters)
	if take.sample(0.0, _editor_rigger._parameter_preview_values) != OK:
		_set_editor_status("Create a parameter before recording a take")
		return
	_parameter_take = take
	_take_started_usec = Time.get_ticks_usec()
	_refresh_recording_controls()
	_set_editor_status("Recording parameters — Finish take to keep it; Escape to discard")


func _sample_parameter_recording(values: Dictionary) -> void:
	if _parameter_take == null:
		return
	var error := _parameter_take.sample(_recording_elapsed(), values)
	if error != OK:
		_cancel_parameter_recording()
		_set_editor_status("Recording cancelled: %s" % error_string(error))


func _recording_elapsed() -> float:
	return float(Time.get_ticks_usec() - _take_started_usec) / 1000000.0


func _finish_parameter_recording() -> Error:
	if _parameter_take == null:
		return ERR_UNCONFIGURED
	var take := _parameter_take.to_clip(_recording_elapsed())
	_parameter_take = null
	_refresh_recording_controls()
	var error := _execute_timeline_command(TwberImportParameterTake.new(take))
	if error == OK:
		_mode_bar.current_tab = _editor_animator.get_index()
		_set_editor_status("Recorded take — play it or export PNG frames in Animate")
	return error


func _cancel_parameter_recording() -> void:
	if _parameter_take == null:
		return
	_parameter_take = null
	_refresh_recording_controls()
	_set_editor_status("Recording discarded")


func _refresh_recording_controls() -> void:
	_record_take_button.text = "Finish take" if _parameter_take != null else "Record parameters"
	_cancel_take_button.disabled = _parameter_take == null
	_refresh_history_menu()


func _show_frame_export(animation_id: String) -> void:
	if _busy or _finish_pending_authoring() != OK:
		return
	_frame_export_dialog.show_for(_document.snapshot().to_model_resource(), animation_id)


func _on_workspace_selection(id: String, mode: int) -> void:
	if mode == _active_tab and not _changing_mode and not _suppress_dirty_tracking:
		_selected_document_layer_id = id


func _active_selection_id() -> String:
	if _active_tab == 0:
		return _editor_placer.get_selected_document_layer_id()
	var tool := _controllers.get_child(_active_tab) as EditorModelTree
	return String(tool._selected_node.get_meta(TwberModelCodec.LAYER_ID_META, "")) if is_instance_valid(tool._selected_node) else _selected_document_layer_id


func _select_workspace_layer(id: String) -> void:
	_selected_document_layer_id = id
	if _active_tab == 0:
		_editor_placer.select_document_layer(id)
	else:
		var tool := _controllers.get_child(_active_tab) as EditorModelTree
		tool._select_node(TwberParameterMapper.get_layer_nodes_by_id(_model_root).get(id) as Node2D)


func _watch_workspace_window(window: Window) -> void:
	window.focus_exited.connect(_schedule_workspace_focus_check)
	window.set_meta("twber_editor", self)
	window.set_script(preload("res://editor/workspace/twber_workspace_window.gd"))


func _schedule_workspace_focus_check() -> void:
	if _focus_check_pending:
		return
	_focus_check_pending = true
	_check_workspace_focus.call_deferred()


func _check_workspace_focus() -> void:
	await get_tree().process_frame
	_focus_check_pending = false
	if get_tree().root.has_focus():
		return
	for child: Node in find_children("*", "Window", true, false):
		if (child as Window).visible and (child as Window).has_focus():
			return
	_cancel_external_focus_edits()


func _cancel_external_focus_edits() -> void:
	_editor_placer.cancel_transform_drag()
	_cancel_mesh_gesture()
	_cancel_pose_drafts()
	_cancel_parameter_recording()


func _initialize_canvas_camera() -> void:
	if _workspace_binding == null:
		return
	_default_model_root_position = _workspace_binding.workspace.canvas.size * 0.5
	if _model_root.get_child_count() == 0:
		_center_workspace_canvas()


func _center_workspace_canvas() -> void:
	if _workspace_binding != null:
		_model_root.position = _workspace_binding.workspace.canvas.size * 0.5
		_on_model_preview_view_changed()


func _sync_workspace_minimum_size() -> void:
	if is_inside_tree():
		get_window().min_size = _previous_window_minimum.max(Vector2i(($PanelContainer as Control).get_combined_minimum_size().ceil()))
