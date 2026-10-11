class_name EditorAnimator extends EditorModelTree

signal export_frames_requested(animation_id: String)
@onready var _export_frames: Button = get_panel_control("ExportFrames")
@onready var _authored_sprite_timing: Button = get_panel_control("AuthoredSpriteTiming")
var _sprite_playing_before_preview: Dictionary = {}

var execute_timeline_command: Callable
var execute_layer_command: Callable
var get_document_model: Callable
var _sprite_timeline := TwberSpriteTimeline.new()
var _pose_evaluator := TwberModelEvaluator.new()
var _track_parameters: Array[TwberParameterResource] = []
var _track_parameter_id := ""
var pose_draft: TwberPoseDraftController
var _pending_name_id := ""
var _pending_name_value := ""

const ACCENT := Color(1.0, 0.78, 0.22, 1.0)
const GUIDE := Color(1.0, 0.78, 0.22, 0.65)
const BOUNDS := Color(0.9, 0.95, 1.0, 0.65)
const KEY_COLOR := Color(0.19, 0.75, 1.0, 1.0)
const MIN_SCALE_DISTANCE := 0.001

enum ToolMode { POINTER, MOVE, ROTATE, SCALE, PIVOT, DEFORM, RECTANGLE, LASSO, RESET_VERTEX }

@onready var _pointer_button: Button = get_panel_control("PointerButton")
@onready var _move_button: Button = get_panel_control("MoveButton")
@onready var _rotate_button: Button = get_panel_control("RotateButton")
@onready var _scale_button: Button = get_panel_control("ScaleButton")
@onready var _pivot_button: Button = get_panel_control("PivotButton")
@onready var _deform_button: Button = get_panel_control("DeformButton")
@onready var _rectangle_select_button: Button = get_panel_control("RectangleSelectButton")
@onready var _lasso_select_button: Button = get_panel_control("LassoSelectButton")
@onready var _reset_vertex_button: Button = get_panel_control("ResetVertexButton")
@onready var _reset_layer_button: Button = get_panel_control("ResetLayerButton")
@onready var _inspector: VBoxContainer = get_panel_control("Inspector")
@onready var _selected_layer_label: Label = get_panel_control("SelectedLayerLabel")
@onready var _transform_label: Label = get_panel_control("TransformLabel")
@onready var _timeline: Control = get_panel_control("Timeline")
@onready var _add_point_button: Button = get_panel_control("AddPointButton")
@onready var _delete_point_button: Button = get_panel_control("DeletePointButton")
@onready var _play_button: Button = get_panel_control("PlayButton")
@onready var _time_label: Label = get_panel_control("TimeLabel")
@onready var _fps_spin_box: SpinBox = get_panel_control("FpsSpinBox")
@onready var _animation_list: ItemList = get_panel_control("AnimationList")
@onready var _new_animation_button: Button = get_panel_control("NewAnimationButton")
@onready var _delete_animation_button: Button = get_panel_control("DeleteAnimationButton")
@onready var _name_edit: LineEdit = get_panel_control("NameEdit")
@onready var _duration_spin_box: SpinBox = get_panel_control("DurationSpinBox")
@onready var _loop_check_box: CheckBox = get_panel_control("LoopCheckBox")
@onready var _track_parameter: OptionButton = get_panel_control("TrackParameter")
@onready var _track_x: SpinBox = get_panel_control("TrackX")
@onready var _track_y: SpinBox = get_panel_control("TrackY")
@onready var _track_hold: CheckBox = get_panel_control("TrackHold")
@onready var _key_parameter: Button = get_panel_control("KeyParameter")
@onready var _remove_parameter_key: Button = get_panel_control("RemoveParameterKey")
@onready var _priority: SpinBox = get_panel_control("Priority")


var _selected_animation_id := ""
var _playhead := 0.0
var _playing := false
var _preview_active := false
var _updating_ui := false
var _base_states: Dictionary[String, TwberLayerStateResource] = {}
var _nodes_by_layer_id: Dictionary[String, Node2D] = {}
var _dragging := false
var _drag_mode := ToolMode.POINTER
var _drag_start_mouse := Vector2.ZERO
var _drag_start_origin := Vector2.ZERO
var _drag_start_rotation := 0.0
var _drag_start_scale := Vector2.ONE
var _drag_start_angle := 0.0
var _drag_start_distance := 1.0
var _drag_vertex := -1
var _drag_vertex_start := Vector2.ZERO
var _selected_vertices: Array[int] = []
var _drag_vertices_start := {}
var _selecting_vertices := false
var _selection_additive := false
var _selection_start := Vector2.ZERO
var _selection_current := Vector2.ZERO
var _lasso_points := PackedVector2Array()


func _ready() -> void:
	_authored_sprite_timing.pressed.connect(func() -> void:
		_submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.CLEAR_SPRITE_TIMING, _selected_animation_id))
	)
	_export_frames.pressed.connect(func() -> void: export_frames_requested.emit(_selected_animation_id))
	_pointer_button.button_pressed = true
	_initialize_model_tree()
	_overlay.draw.connect(_draw_overlay)
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_timeline.draw.connect(_draw_timeline)
	_timeline.gui_input.connect(_on_timeline_gui_input)
	_add_point_button.pressed.connect(_add_point)
	_delete_point_button.pressed.connect(_delete_point)
	_play_button.pressed.connect(_toggle_playback)
	_new_animation_button.pressed.connect(_create_animation)
	_delete_animation_button.pressed.connect(_delete_animation)
	_animation_list.item_selected.connect(_select_animation_index)
	_name_edit.text_changed.connect(_on_animation_name_changed)
	_name_edit.text_submitted.connect(func(_value: String) -> void: finish_animation_edits())
	_name_edit.focus_exited.connect(finish_animation_edits)
	_duration_spin_box.value_changed.connect(_change_duration)
	_loop_check_box.toggled.connect(_change_loop)
	_fps_spin_box.value_changed.connect(_change_fps)
	_reset_layer_button.pressed.connect(_reset_selected_layer)
	_track_parameter.item_selected.connect(_select_track_parameter)
	_track_x.value_changed.connect(_change_track_value)
	_track_y.value_changed.connect(_change_track_value)
	_track_hold.toggled.connect(func(_value: bool) -> void: _key_parameter_value())
	_key_parameter.pressed.connect(_key_parameter_value)
	_remove_parameter_key.pressed.connect(_delete_parameter_key)
	_priority.value_changed.connect(func(value: float) -> void: _change_animation_settings({"priority": int(value)}))
	set_process(false)
	reload_from_preview()


func reload_from_preview(selected_node: Node2D = null) -> void:
	cancel_pose_draft()
	_pending_name_id = ""
	stop_and_restore()
	super.reload_from_preview(selected_node)
	_capture_base_pose()
	_refresh_animation_list()
	_refresh_inspector()
	_apply_animation_at_playhead()


func stop_and_restore() -> void:
	cancel_pose_draft()
	_playing = false
	set_process(false)
	if is_instance_valid(_play_button):
		_play_button.text = "Play"
	_restore_base_pose()
	_preview_active = false
	for node: AnimatedSprite2D in _sprite_playing_before_preview:
		if is_instance_valid(node) and _sprite_playing_before_preview[node]:
			node.play()
	_sprite_playing_before_preview.clear()


func _process(delta: float) -> void:
	var animation := _get_selected_animation()
	if not _playing or animation == null:
		set_process(false)
		return
	_playhead += delta
	if _playhead > animation.duration:
		if animation.loop:
			_playhead = fmod(_playhead, animation.duration)
		else:
			_playhead = animation.duration
			_playing = false
			set_process(false)
			_play_button.text = "Play"
	_apply_animation_at_playhead()


func _unhandled_key_input(event: InputEvent) -> void:
	if not tool_active or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_Q: _pointer_button.button_pressed = true
		KEY_W: _move_button.button_pressed = true
		KEY_E: _rotate_button.button_pressed = true
		KEY_R: _scale_button.button_pressed = true
		KEY_T: _pivot_button.button_pressed = true
		KEY_P: _deform_button.button_pressed = true
		KEY_M: _rectangle_select_button.button_pressed = true
		KEY_L: _lasso_select_button.button_pressed = true
		KEY_BACKSPACE: _reset_vertex_button.button_pressed = true


func _capture_base_pose() -> void:
	if get_document_model.is_valid():
		_configure_evaluation(get_document_model.call())


func _configure_evaluation(model: TwberModelResource) -> void:
	_pose_evaluator.configure(model)
	_sprite_timeline.configure(model)
	_base_states.assign(_pose_evaluator.neutral_states())
	_nodes_by_layer_id.assign(TwberParameterMapper.get_layer_nodes_by_id(_model_root))
	_track_parameters = model.parameters
	_track_parameter.clear()
	for parameter: TwberParameterResource in _track_parameters:
		var index := _track_parameter.item_count
		_track_parameter.add_item(parameter.name)
		_track_parameter.set_item_metadata(index, parameter.id)
		if parameter.id == _track_parameter_id:
			_track_parameter.select(index)
	if _track_parameter.item_count > 0:
		_track_parameter_id = String(_track_parameter.get_item_metadata(_track_parameter.selected))
	else:
		_track_parameter_id = ""


func sync_document(model: TwberModelResource) -> void:
	# Parameter deletion also removes its keys, atomically with the parameter.
	_set_animations(model.timeline_animations)
	_configure_evaluation(model)
	_refresh_parameter_track()
	if tool_active:
		_apply_animation_at_playhead()


func _restore_base_pose() -> void:
	# A cached pose only belongs to the active animation edit session. An
	# inactive tab must never restore over changes made by Place or Mesh.
	if not _preview_active:
		return
	for layer_id: String in _base_states:
		var node: Node2D = _nodes_by_layer_id.get(layer_id)
		if node != null and is_instance_valid(node):
			_base_states[layer_id].apply_to_node(node)
			TwberAlphaClipController.set_authored_self_modulate(node, _base_states[layer_id].self_modulate)




func _apply_animation_at_playhead() -> void:
	cancel_pose_draft()
	if not tool_active:
		return
	if not _preview_active:
		_capture_base_pose()
		_preview_active = true
		for node: Node2D in _nodes_by_layer_id.values():
			if node is AnimatedSprite2D:
				_sprite_playing_before_preview[node] = node.is_playing()
	_restore_base_pose()
	var animation := _get_selected_animation()
	var playheads := {animation.id: _playhead} if animation != null else {}
	var poses := _pose_evaluator.evaluate({}, playheads)
	for id: String in poses:
		var node := _nodes_by_layer_id.get(id) as Node2D
		if node != null:
			var state: TwberLayerStateResource = poses[id]
			state.apply_to_node(node)
			TwberAlphaClipController.set_authored_self_modulate(node, state.self_modulate)
	TwberSpriteFrameSampler.apply(_nodes_by_layer_id, _sprite_timeline.seek(animation.id, _playhead) if animation != null else _sprite_timeline.rest_states())
	TwberAlphaClipController.attach_to(_model_root).sync_now()
	_refresh_parameter_track()
	_refresh_time_ui()
	_refresh_inspector()
	_queue_overlay_redraw()


func _get_animations() -> Array[TwberTimelineAnimationResource]:
	var output: Array[TwberTimelineAnimationResource] = []
	if _model_root == null:
		return output
	var stored: Variant = _model_root.get_meta(TwberModelCodec.MODEL_TIMELINE_ANIMATIONS_META, [])
	if stored is Array:
		for value: Variant in stored:
			if value is TwberTimelineAnimationResource:
				output.append(value)
	return output


func _set_animations(animations: Array[TwberTimelineAnimationResource]) -> void:
	if _model_root != null:
		_model_root.set_meta(TwberModelCodec.MODEL_TIMELINE_ANIMATIONS_META, animations)


func _get_selected_animation() -> TwberTimelineAnimationResource:
	for animation: TwberTimelineAnimationResource in _get_animations():
		if animation.id == _selected_animation_id:
			return animation
	return null


func _submit_timeline_command(command: TwberEditTimeline) -> Error:
	if not execute_timeline_command.is_valid():
		return ERR_UNCONFIGURED
	return execute_timeline_command.call(command)


func _on_animation_name_changed(value: String) -> void:
	if _updating_ui or _get_selected_animation() == null:
		return
	_pending_name_id = _selected_animation_id
	_pending_name_value = value


func finish_animation_edits() -> Error:
	if _pending_name_id.is_empty():
		return OK
	var id := _pending_name_id
	var value := _pending_name_value
	_pending_name_id = ""
	return _submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, id, {"name": value}))


func project_animations(model: TwberModelResource, command: TwberEditTimeline) -> void:
	var existing := {}
	for animation: TwberTimelineAnimationResource in _get_animations():
		existing[animation.id] = animation
	var animations: Array[TwberTimelineAnimationResource] = []
	for source: TwberTimelineAnimationResource in model.timeline_animations:
		var target := existing.get(source.id) as TwberTimelineAnimationResource
		if target == null:
			target = source.duplicate(true)
		else:
			target.copy_contents_from(source)
		animations.append(target)
	_set_animations(animations)
	_configure_evaluation(model)
	var old_playhead := _playhead
	if command.operation in [TwberEditTimeline.Operation.CREATE, TwberEditTimeline.Operation.DELETE]:
		stop_and_restore()
		if command.operation == TwberEditTimeline.Operation.CREATE:
			_selected_animation_id = command.animation_id
		_playhead = 0.0
	_refresh_animation_list()
	# Metadata edits preserve playback and an uncommitted pose. Key edits
	# explicitly replace the displayed pose with the newly authored sample.
	if command.operation != TwberEditTimeline.Operation.UPDATE or old_playhead != _playhead:
		_apply_animation_at_playhead()


func _create_animation() -> void:
	_submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.CREATE))


func _delete_animation() -> void:
	if _get_selected_animation() != null:
		_submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.DELETE, _selected_animation_id))


func _refresh_animation_list() -> void:
	finish_animation_edits()
	_updating_ui = true
	_animation_list.clear()
	var animations := _get_animations()
	for animation: TwberTimelineAnimationResource in animations:
		var index := _animation_list.add_item(animation.name)
		_animation_list.set_item_metadata(index, animation.id)
		if animation.id == _selected_animation_id:
			_animation_list.select(index)
	if _get_selected_animation() == null and not animations.is_empty():
		_selected_animation_id = animations[0].id
		_animation_list.select(0)
	if animations.is_empty():
		_selected_animation_id = ""
	var selected := _get_selected_animation()
	_playhead = clampf(_playhead, 0.0, selected.duration) if selected != null else 0.0
	_name_edit.editable = selected != null
	_duration_spin_box.editable = selected != null
	_fps_spin_box.editable = selected != null
	_priority.editable = selected != null
	_loop_check_box.disabled = selected == null
	_delete_animation_button.disabled = selected == null
	_export_frames.disabled = selected == null
	_add_point_button.disabled = selected == null or _selected_node == null
	if selected != null:
		_name_edit.text = selected.name
		_duration_spin_box.value = selected.duration
		_loop_check_box.button_pressed = selected.loop
		_fps_spin_box.value = selected.fps
		_priority.value = selected.priority
	else:
		_name_edit.text = ""
		_fps_spin_box.value = 30.0
	_updating_ui = false
	_refresh_parameter_track()
	_refresh_time_ui()
	_timeline.queue_redraw()


func _select_animation_index(index: int) -> void:
	if index < 0 or index >= _animation_list.item_count:
		return
	if finish_animation_edits() != OK:
		return
	_selected_animation_id = String(_animation_list.get_item_metadata(index))
	_playhead = 0.0
	_refresh_animation_list()
	_apply_animation_at_playhead()


func _rename_animation(value: String) -> void:
	_change_animation_settings({"name": value})


func _change_duration(value: float) -> void:
	_change_animation_settings({"duration": value})


func _change_loop(enabled: bool) -> void:
	_change_animation_settings({"loop": enabled})


func _change_fps(value: float) -> void:
	_change_animation_settings({"fps": value})


func _change_animation_settings(settings: Dictionary) -> void:
	if _updating_ui or _get_selected_animation() == null:
		return
	_submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, _selected_animation_id, settings))


func _add_point() -> void:
	if _get_selected_animation() == null or not _ensure_pose_draft():
		return
	var command := pose_draft.make_command() as TwberEditTimeline
	if command == null:
		cancel_pose_draft()
		return
	if _submit_timeline_command(command) == OK:
		cancel_pose_draft()
		_apply_animation_at_playhead()


func _delete_point() -> void:
	var layer_id := _get_selected_layer_id()
	if _get_selected_animation() == null or layer_id.is_empty():
		return
	_submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.REMOVE_KEY, _selected_animation_id, {
		"time": _playhead, "layer_id": layer_id,
	}))


func _toggle_playback() -> void:
	cancel_pose_draft()
	if _get_selected_animation() == null:
		return
	_playing = not _playing
	_play_button.text = "Pause" if _playing else "Play"
	set_process(_playing)


func _reset_selected_layer() -> void:
	if _ensure_pose_draft():
		pose_draft.update(pose_draft.neutral())
	_selected_vertices.clear()
	_refresh_inspector()
	_queue_overlay_redraw()


func _on_model_node_selected() -> void:
	cancel_pose_draft()
	_dragging = false
	_drag_vertex = -1
	_selected_vertices.clear()
	_selecting_vertices = false
	_refresh_inspector()
	_refresh_animation_list()
	_queue_overlay_redraw()


func _refresh_inspector() -> void:
	_inspector.visible = _selected_node != null
	if _selected_node == null:
		return
	_selected_layer_label.text = _selected_node.name
	_transform_label.text = "Position  %.1f, %.1f\nRotation  %.1f°\nScale     %.2f, %.2f" % [
		_selected_node.position.x,
		_selected_node.position.y,
		rad_to_deg(_selected_node.rotation),
		_selected_node.scale.x,
		_selected_node.scale.y,
	]


func _on_timeline_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var animation := _get_selected_animation()
		if animation == null:
			return
		var usable_width := maxf(_timeline.size.x - 24.0, 1.0)
		_playhead = clampf((event.position.x - 12.0) / usable_width, 0.0, 1.0) * animation.duration
		_playhead = clampf(roundf(_playhead * animation.fps) / animation.fps, 0.0, animation.duration)
		_apply_animation_at_playhead()
		_timeline.accept_event()


func _draw_timeline() -> void:
	var start := Vector2(12.0, _timeline.size.y * 0.55)
	var finish := Vector2(_timeline.size.x - 12.0, start.y)
	_timeline.draw_line(start, finish, Color(0.65, 0.68, 0.72), 2.0)
	var animation := _get_selected_animation()
	if animation == null:
		return
	var width := maxf(finish.x - start.x, 1.0)
	for keyframe: TwberTimelineKeyframeResource in animation.keyframes:
		var x := start.x + clampf(keyframe.time / animation.duration, 0.0, 1.0) * width
		var color := ACCENT if keyframe.layer_state != null and keyframe.layer_state.layer_id == _get_selected_layer_id() else KEY_COLOR
		var points := PackedVector2Array([
			Vector2(x, start.y - 7.0), Vector2(x + 7.0, start.y),
			Vector2(x, start.y + 7.0), Vector2(x - 7.0, start.y),
		])
		_timeline.draw_colored_polygon(points, color)
	for key: TwberParameterKeyframeResource in animation.parameter_keys:
		if key.parameter_id != _track_parameter_id:
			continue
		var x := start.x + key.time / animation.duration * width
		_timeline.draw_circle(Vector2(x, start.y - 18.0), 4.0, Color(0.5, 1.0, 0.6))
	var playhead_x := start.x + clampf(_playhead / animation.duration, 0.0, 1.0) * width
	_timeline.draw_line(Vector2(playhead_x, 5.0), Vector2(playhead_x, _timeline.size.y - 5.0), ACCENT, 2.0)


func _refresh_time_ui() -> void:
	var sprite_clip := _get_selected_animation()
	_authored_sprite_timing.visible = sprite_clip != null and not sprite_clip.sprite_keys.is_empty()
	var animation := _get_selected_animation()
	var duration := animation.duration if animation != null else 0.0
	_time_label.text = "%.2f / %.2fs" % [_playhead, duration]
	_delete_point_button.disabled = not _has_point_at_playhead()
	_timeline.queue_redraw()


func _has_point_at_playhead() -> bool:
	var animation := _get_selected_animation()
	var layer_id := _get_selected_layer_id()
	if animation == null or layer_id.is_empty():
		return false
	return TwberEditTimeline.find_key(animation, layer_id, _playhead) >= 0


func _on_overlay_gui_input(event: InputEvent) -> void:
	if not tool_active or _selected_node == null:
		return
	var canvas_position := _overlay_local_to_viewport(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_tool_drag(canvas_position, event.shift_pressed)
		else:
			if _selecting_vertices:
				_finish_vertex_selection()
			_dragging = false
			_drag_vertex = -1
			if pose_draft != null:
				pose_draft.finish_interaction()
		_overlay.accept_event()
	elif event is InputEventMouseMotion and _dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_update_tool_drag(canvas_position)
		_overlay.accept_event()


func _begin_tool_drag(canvas_position: Vector2, additive_selection: bool) -> void:
	_drag_mode = _get_tool_mode()
	if _drag_mode == ToolMode.POINTER:
		return
	if _drag_mode == ToolMode.PIVOT:
		_change_node_pivot(canvas_position)
		return
	if _drag_mode == ToolMode.RESET_VERTEX:
		_reset_vertex_at(canvas_position)
		return
	if _drag_mode == ToolMode.RECTANGLE or _drag_mode == ToolMode.LASSO:
		if _selected_node is not TwberMeshSprite2D:
			return
		_selecting_vertices = true
		_selection_additive = additive_selection
		_selection_start = _canvas_to_editor_position(canvas_position)
		_selection_current = _selection_start
		_lasso_points = PackedVector2Array([_selection_start]) if _drag_mode == ToolMode.LASSO else PackedVector2Array()
		_dragging = true
		return
	if not _ensure_pose_draft():
		return
	if _drag_mode == ToolMode.DEFORM:
		if _selected_node is not TwberMeshSprite2D:
			return
		var mesh: TwberMeshSprite2D = _selected_node
		_drag_vertex = _find_vertex_at_canvas_position(mesh, canvas_position)
		if _drag_vertex < 0:
			if not additive_selection:
				_selected_vertices.clear()
			return
		if additive_selection:
			if _selected_vertices.has(_drag_vertex):
				_selected_vertices.erase(_drag_vertex)
			else:
				_selected_vertices.append(_drag_vertex)
			_queue_overlay_redraw()
			return
		if not _selected_vertices.has(_drag_vertex):
			_selected_vertices.assign([_drag_vertex])
		_drag_vertex_start = mesh.get_vertex(_drag_vertex)
		_drag_vertices_start.clear()
		for vertex_index: int in _selected_vertices:
			_drag_vertices_start[vertex_index] = mesh.get_vertex(vertex_index)
	_dragging = true
	_drag_start_mouse = canvas_position
	_drag_start_origin = _get_node_canvas_origin(_selected_node)
	_drag_start_rotation = _selected_node.rotation
	_drag_start_scale = _selected_node.scale
	var offset := canvas_position - _drag_start_origin
	_drag_start_angle = offset.angle()
	_drag_start_distance = maxf(offset.length(), MIN_SCALE_DISTANCE)


func _update_tool_drag(canvas_position: Vector2) -> void:
	if _selecting_vertices:
		_selection_current = _canvas_to_editor_position(canvas_position)
		if (
			_drag_mode == ToolMode.LASSO
			and (_lasso_points.is_empty() or _lasso_points[-1].distance_to(_selection_current) >= 4.0)
		):
			_lasso_points.append(_selection_current)
		_queue_overlay_redraw()
		return
	if pose_draft == null or not pose_draft.has_draft():
		return
	match _drag_mode:
		ToolMode.MOVE:
			_set_node_canvas_origin(_selected_node, _drag_start_origin + canvas_position - _drag_start_mouse)
		ToolMode.ROTATE:
			var offset := canvas_position - _drag_start_origin
			edit_pose({"rotation": _snap_rotation(_drag_start_rotation + angle_difference(_drag_start_angle, offset.angle()))})
		ToolMode.SCALE:
			var distance := maxf((canvas_position - _drag_start_origin).length(), MIN_SCALE_DISTANCE)
			edit_pose({"scale": _drag_start_scale * _snap_scale_factor(distance / _drag_start_distance)})
		ToolMode.DEFORM:
			var mesh: TwberMeshSprite2D = _selected_node
			var local_delta := _viewport_to_node_position(mesh, canvas_position) - _viewport_to_node_position(mesh, _drag_start_mouse)
			var pose := pose_draft.pose()
			for vertex_index: int in _selected_vertices:
				var start: Vector2 = _drag_vertices_start.get(vertex_index, mesh.get_vertex(vertex_index))
				pose.mesh_vertices[vertex_index] = _snap_mesh_position(mesh, start + local_delta)
			pose_draft.update(pose)
	_refresh_inspector()
	_queue_overlay_redraw()


func _finish_vertex_selection() -> void:
	_selecting_vertices = false
	if _selected_node is not TwberMeshSprite2D:
		return
	var mesh: TwberMeshSprite2D = _selected_node
	if mesh.mesh_data == null:
		return
	var found: Array[int] = []
	if _drag_mode == ToolMode.RECTANGLE:
		var rect := _get_selection_rect()
		for index: int in mesh.mesh_data.vertices.size():
			if rect.has_point(_node_to_editor_position(mesh, mesh.mesh_data.vertices[index])):
				found.append(index)
	elif _lasso_points.size() >= 3:
		for index: int in mesh.mesh_data.vertices.size():
			if Geometry2D.is_point_in_polygon(
					_node_to_editor_position(mesh, mesh.mesh_data.vertices[index]),
					_lasso_points,
			):
				found.append(index)
	if _selection_additive:
		for index: int in found:
			if not _selected_vertices.has(index):
				_selected_vertices.append(index)
	else:
		_selected_vertices = found
	_lasso_points = PackedVector2Array()
	_queue_overlay_redraw()


func _get_selection_rect() -> Rect2:
	var start := Vector2(
			minf(_selection_start.x, _selection_current.x),
			minf(_selection_start.y, _selection_current.y),
	)
	var finish := Vector2(
			maxf(_selection_start.x, _selection_current.x),
			maxf(_selection_start.y, _selection_current.y),
	)
	return Rect2(start, finish - start)


func _reset_vertex_at(canvas_position: Vector2) -> void:
	if _selected_node is not TwberMeshSprite2D:
		return
	var mesh: TwberMeshSprite2D = _selected_node
	var vertex_index := _find_vertex_at_canvas_position(mesh, canvas_position)
	if vertex_index < 0:
		return
	var targets: Array[int] = _selected_vertices.duplicate() if _selected_vertices.has(vertex_index) else [vertex_index]
	if not _ensure_pose_draft():
		return
	var pose := pose_draft.pose()
	var neutral := pose_draft.neutral()
	for target: int in targets:
		pose.mesh_vertices[target] = neutral.mesh_vertices[target]
	pose_draft.update(pose)
	_selected_vertices = targets
	_queue_overlay_redraw()


func _draw_overlay() -> void:
	if not tool_active or _selected_node == null:
		return
	var origin := _canvas_to_editor_position(_get_node_canvas_origin(_selected_node))
	_overlay.draw_circle(origin, 5.0, ACCENT)
	if _dragging and (_drag_mode == ToolMode.ROTATE or _drag_mode == ToolMode.SCALE):
		_overlay.draw_line(origin, _canvas_to_editor_position(_drag_start_mouse), GUIDE, 1.0)
	if _selected_node is TwberMeshSprite2D:
		var mesh: TwberMeshSprite2D = _selected_node
		if mesh.mesh_data != null:
			for index: int in mesh.mesh_data.vertices.size():
				var color := ACCENT if _selected_vertices.has(index) else BOUNDS
				_overlay.draw_circle(_node_to_editor_position(mesh, mesh.mesh_data.vertices[index]), 4.0, color)
	elif _selected_node is Sprite2D:
		_draw_sprite_bounds(_selected_node)
	if _selecting_vertices:
		if _drag_mode == ToolMode.RECTANGLE:
			var rect := _get_selection_rect()
			_overlay.draw_rect(rect, Color(1.0, 0.78, 0.22, 0.15), true)
			_overlay.draw_rect(rect, ACCENT, false, 1.0)
		elif _lasso_points.size() > 1:
			_overlay.draw_polyline(_lasso_points, ACCENT, 1.0)


func _draw_sprite_bounds(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	var origin := _get_sprite_texture_origin(sprite)
	var size := sprite.texture.get_size()
	var points := [origin, origin + Vector2(size.x, 0), origin + size, origin + Vector2(0, size.y)]
	for index: int in points.size():
		_overlay.draw_line(
				_node_to_editor_position(sprite, points[index]),
				_node_to_editor_position(sprite, points[(index + 1) % points.size()]),
				BOUNDS,
				1.0,
		)


func _set_node_canvas_origin(node: Node2D, canvas_origin: Vector2) -> void:
	var parent := node.get_parent() as CanvasItem
	var position := canvas_origin
	if parent != null:
		var transform := parent.get_global_transform_with_canvas()
		if is_zero_approx(transform.determinant()):
			return
		position = transform.affine_inverse() * canvas_origin
	edit_pose({"position": _snap_pixel_position(position)})


func _change_node_pivot(canvas_position: Vector2) -> void:
	if _selected_node == null or not execute_layer_command.is_valid():
		return
	var transform := _selected_node.get_global_transform_with_canvas()
	if is_zero_approx(transform.determinant()):
		return
	var pivot := _snap_pixel_position(transform.affine_inverse() * canvas_position)
	execute_layer_command.call(TwberSetPivot.new(_get_selected_layer_id(), pivot))


func _get_node_canvas_origin(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func _get_selected_layer_id() -> String:
	return String(_selected_node.get_meta(TwberModelCodec.LAYER_ID_META, "")) if _selected_node != null else ""


func _get_tool_mode() -> ToolMode:
	if _move_button.button_pressed: return ToolMode.MOVE
	if _rotate_button.button_pressed: return ToolMode.ROTATE
	if _scale_button.button_pressed: return ToolMode.SCALE
	if _pivot_button.button_pressed: return ToolMode.PIVOT
	if _deform_button.button_pressed: return ToolMode.DEFORM
	if _rectangle_select_button.button_pressed: return ToolMode.RECTANGLE
	if _lasso_select_button.button_pressed: return ToolMode.LASSO
	if _reset_vertex_button.button_pressed: return ToolMode.RESET_VERTEX
	return ToolMode.POINTER



func cancel_pose_draft() -> bool:
	var cancelled := pose_draft.cancel() if pose_draft != null else false
	_dragging = false
	_drag_vertex = -1
	_selecting_vertices = false
	if cancelled:
		_refresh_inspector()
		_queue_overlay_redraw()
	return cancelled


func edit_pose(changes: Dictionary) -> void:
	if not _ensure_pose_draft():
		return
	var pose := pose_draft.pose()
	for field: String in changes:
		pose.set(field, changes[field])
	pose_draft.update(pose)
	_refresh_inspector()
	_queue_overlay_redraw()


func _ensure_pose_draft() -> bool:
	if pose_draft == null or _selected_node == null:
		return false
	_playing = false
	set_process(false)
	_play_button.text = "Play"
	return pose_draft.begin(_selected_node, {"mode": "timeline", "animation_id": _selected_animation_id, "time": _playhead})


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		_drag_vertex = -1
		if pose_draft != null:
			pose_draft.finish_interaction()


func _selected_track_parameter() -> TwberParameterResource:
	for parameter: TwberParameterResource in _track_parameters:
		if parameter.id == _track_parameter_id:
			return parameter
	return null


func _select_track_parameter(index: int) -> void:
	_track_parameter_id = String(_track_parameter.get_item_metadata(index))
	_refresh_parameter_track()
	_timeline.queue_redraw()


func _refresh_parameter_track() -> void:
	var parameter := _selected_track_parameter()
	var clip := _get_selected_animation()
	var enabled := parameter != null and clip != null
	_track_x.editable = enabled
	_track_y.editable = enabled
	_key_parameter.disabled = not enabled
	_remove_parameter_key.disabled = true
	_track_hold.disabled = not enabled
	if not enabled:
		return
	_updating_ui = true
	var vector := parameter.value_type == TwberParameterResource.ValueType.VECTOR2
	_track_y.visible = vector
	var minimum := parameter.get_vector_min() if vector else Vector2(parameter.get_scalar_min(), 0)
	var maximum := parameter.get_vector_max() if vector else Vector2(parameter.get_scalar_max(), 0)
	_track_x.min_value = minimum.x
	_track_x.max_value = maximum.x
	_track_y.min_value = minimum.y
	_track_y.max_value = maximum.y
	_track_x.step = parameter.step
	_track_y.step = parameter.step
	var values := _pose_evaluator.resolve_parameters({}, {clip.id: _playhead})
	var coordinate := parameter.coordinate_from_value(values.get(parameter.id, parameter.get_default_value()))
	_track_x.value = coordinate.x
	_track_y.value = coordinate.y
	var index := TwberEditTimeline.find_parameter_key(clip, parameter.id, _playhead)
	_track_hold.set_pressed_no_signal(index >= 0 and clip.parameter_keys[index].interpolation == TwberParameterKeyframeResource.Interpolation.HOLD)
	if parameter.value_type in [TwberParameterResource.ValueType.BOOL, TwberParameterResource.ValueType.INT]:
		_track_hold.set_pressed_no_signal(true)
		_track_hold.disabled = true
	_remove_parameter_key.disabled = index < 0
	_updating_ui = false


func _change_track_value(_value: float) -> void:
	_key_parameter_value()


func _key_parameter_value() -> void:
	if _updating_ui or _selected_track_parameter() == null or _get_selected_animation() == null:
		return
	_playing = false
	set_process(false)
	_play_button.text = "Play"
	_submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.SET_PARAMETER_KEY, _selected_animation_id, {
		"parameter_id": _track_parameter_id, "time": _playhead,
		"coordinate": Vector2(_track_x.value, _track_y.value),
		"interpolation": TwberParameterKeyframeResource.Interpolation.HOLD if _track_hold.button_pressed else TwberParameterKeyframeResource.Interpolation.LINEAR,
	}))


func _delete_parameter_key() -> void:
	if _get_selected_animation() != null:
		_submit_timeline_command(TwberEditTimeline.new(TwberEditTimeline.Operation.REMOVE_PARAMETER_KEY, _selected_animation_id, {
			"parameter_id": _track_parameter_id, "time": _playhead,
		}))
