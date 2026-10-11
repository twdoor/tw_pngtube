class_name EditorRigger extends EditorModelTree

signal parameter_values_previewed(values: Dictionary)

var execute_parameter_command: Callable
var execute_layer_command: Callable
var pose_draft: TwberPoseDraftController
var _editing_parameter_name: LineEdit
var _editing_parameter_id := ""


func finish_parameter_edits() -> Error:
	if not is_instance_valid(_editing_parameter_name):
		return OK
	var control := _editing_parameter_name
	var id := _editing_parameter_id
	_editing_parameter_name = null
	var parameter := _find_parameter_by_id(id)
	if parameter == null:
		return OK
	if parameter.name == control.text.strip_edges():
		control.text = parameter.name
		return OK
	var error := _submit_parameter_command(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, id, {"name": control.text}))
	control.text = parameter.name
	return error


func _submit_parameter_command(command: TwberEditParameter) -> Error:
	if not execute_parameter_command.is_valid():
		return ERR_UNCONFIGURED
	return execute_parameter_command.call(command)


func project_parameters(model: TwberModelResource, command: TwberEditParameter) -> void:
	# The edited pose is now authored. Restore its document rest before evaluating
	# the new bindings, including when this tool is called while hidden.
	if command.operation == TwberEditParameter.Operation.BIND_POSE:
		var id := command.get_bound_layer_id()
		var node := TwberParameterMapper.get_layer_nodes_by_id(_model_root).get(id) as Node2D
		if node != null:
			var layer: TwberLayerResource = TwberLayerHierarchy.index(model)[id]
			TwberLayerStateResource.from_layer_resource(layer).apply_to_node(node)
			TwberAlphaClipController.attach_to(_model_root).sync_now([id])
	sync_parameters(model)
	var parameters := _get_model_parameters()
	if command.operation == TwberEditParameter.Operation.CREATE:
		_selected_parameter_id = command.parameter_id
	if command.operation != TwberEditParameter.Operation.UPDATE:
		_refresh_parameter_panel()
	else:
		_sync_parameter_preview_values(parameters)
		for parameter: TwberParameterResource in parameters:
			_update_parameter_control(parameter)
		_refresh_position_buttons()
	# Renaming must not discard an unbound pose the user is still shaping.
	if not command.is_name_only():
		preview_parameters()


func sync_parameters(model: TwberModelResource) -> void:
	# Keep surviving projection objects stable for focused controls and their callbacks.
	var parameters: Array[TwberParameterResource] = []
	for source: TwberParameterResource in model.parameters:
		var target := _find_parameter_by_id(source.id)
		if target == null:
			target = source.duplicate(true)
		else:
			target.copy_contents_from(source)
		parameters.append(target)
	_set_model_parameters(parameters)


const EDGE_COLOR := Color(0.19, 0.75, 1.0, 0.9)
const LAYER_ORIGIN_COLOR := Color(1.0, 0.78, 0.22, 0.95)
const LAYER_GUIDE_COLOR := Color(1.0, 0.78, 0.22, 0.65)
const HANDLE_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const SELECTED_HANDLE_COLOR := Color(1.0, 0.78, 0.22, 1.0)
const SELECTION_STROKE_COLOR := Color(1.0, 0.78, 0.22, 0.95)
const SELECTION_FILL_COLOR := Color(1.0, 0.78, 0.22, 0.16)
const SPRITE_BOUNDS_COLOR := Color(0.9, 0.95, 1.0, 0.6)
const LASSO_MIN_POINT_DISTANCE := 4.0
const MIN_LAYER_SCALE_DISTANCE := 0.001

enum RigMode {
	TRANSFORM_LAYER,
	ROTATE_LAYER,
	SCALE_LAYER,
	CHANGE_PIVOT,
	DEFORM_VERTEX,
	RECTANGLE_SELECT,
	LASSO_SELECT,
	RESET_VERTEX,
}

@onready var _pointer_button: Button = %PointerButton
@onready var _transform_button: Button = %TransformButton
@onready var _rotate_button: Button = %RotateButton
@onready var _scale_button: Button = %ScaleButton
@onready var _change_pivot_button: Button = %ChangePivotButton
@onready var _deform_button: Button = %DeformButton
@onready var _rectangle_select_button: Button = %RectangleSelectButton
@onready var _lasso_select_button: Button = %LassoSelectButton
@onready var _reset_vertex_button: Button = %ResetVertexButton
@onready var _reset_layer_button: Button = %ResetLayerButton
@onready var _inspector: PanelContainer = %Inspector
@onready var _visible_check_box: CheckBox = %VisibleCheckBox
@onready var _opacity_slider: HSlider = %OpacitySlider
@onready var _animation_frame_rate: SpinBox = %AnimationFrameRate
@onready var _animations_box: Control = %AnimationsBox
@onready var _animations_option_button: OptionButton = %AnimationsOptionButton
@onready var _create_bool_button: Button = %BoolButton
@onready var _create_int_button: Button = %IntButton
@onready var _create_float_button: Button = %FloatButton
@onready var _create_vector_button: Button = %VectorButton
@onready var _parameter_list: VBoxContainer = %ParameterList
@onready var _bind_position_button: Button = %BindPositionButton
@onready var _remove_position_button: Button = %RemovePositionButton
@onready var _animation_binding_panel: PanelContainer = %AnimationBindingPanel
@onready var _model_animations_option: OptionButton = %ModelAnimationsOptionButton
@onready var _bind_animation_button: Button = %BindAnimationButton
@onready var _remove_animation_binding_button: Button = %RemoveAnimationBindingButton
@onready var _edit_panel: Control = $Panel

var _selected_vertex_indices: Array[int] = []
var _dragging_vertex := false
var _dragging_layer_transform := false
var _drag_start_position := Vector2.ZERO
var _drag_start_vertices := {}
var _layer_transform_mode: int = RigMode.TRANSFORM_LAYER
var _layer_transform_start_mouse := Vector2.ZERO
var _layer_transform_current_mouse := Vector2.ZERO
var _layer_transform_start_origin := Vector2.ZERO
var _layer_transform_start_rotation := 0.0
var _layer_transform_start_scale := Vector2.ONE
var _layer_transform_start_mouse_angle := 0.0
var _layer_transform_start_mouse_distance := 1.0
var _selecting_vertices := false
var _selection_additive := false
var _selection_mode := RigMode.RECTANGLE_SELECT
var _selection_start_position := Vector2.ZERO
var _selection_current_position := Vector2.ZERO
var _lasso_points := PackedVector2Array()
var _initial_layer_states_by_node_id: Dictionary = {}
var _updating_inspector := false
var _selected_parameter_id := ""
var _parameter_preview_values := {}
var _parameter_value_controls := {}
var _parameter_select_buttons := {}
var _previewed_layer_ids := {}
var _collapsed_parameter_ids := {}
var _parameter_evaluator := TwberParameterEvaluator.new()


func _ready() -> void:
	_pointer_button.button_pressed = true
	_reset_layer_button.pressed.connect(_on_reset_layer_button_pressed)
	_visible_check_box.toggled.connect(_on_visible_check_box_toggled)
	_opacity_slider.value_changed.connect(_on_opacity_slider_value_changed)
	_animation_frame_rate.value_changed.connect(_on_animation_frame_rate_value_changed)
	_animations_option_button.item_selected.connect(_on_animation_selected)
	_create_bool_button.pressed.connect(
			_on_create_parameter_pressed.bind(TwberParameterResource.ValueType.BOOL)
	)
	_create_int_button.pressed.connect(
			_on_create_parameter_pressed.bind(TwberParameterResource.ValueType.INT)
	)
	_create_float_button.pressed.connect(
			_on_create_parameter_pressed.bind(TwberParameterResource.ValueType.FLOAT)
	)
	_create_vector_button.pressed.connect(
			_on_create_parameter_pressed.bind(TwberParameterResource.ValueType.VECTOR2)
	)
	_bind_position_button.pressed.connect(_on_bind_position_button_pressed)
	_remove_position_button.pressed.connect(_on_remove_position_button_pressed)
	_bind_animation_button.pressed.connect(_on_bind_animation_button_pressed)
	_remove_animation_binding_button.pressed.connect(_on_remove_animation_binding_button_pressed)
	_model_animations_option.item_selected.connect(func(_index: int) -> void:
		_refresh_animation_binding_controls()
	)

	_initialize_model_tree()
	_setup_overlay()
	reload_from_preview()


func reload_from_preview(selected_node: Node2D = null) -> void:
	cancel_pose_draft()
	restore_parameter_preview_base()
	_previewed_layer_ids.clear()
	_initial_layer_states_by_node_id.clear()
	_parameter_preview_values.clear()
	super.reload_from_preview(selected_node)
	_parameter_evaluator.configure(_model_root, _get_model_parameters())
	if visible:
		preview_parameters()


func _setup_overlay() -> void:
	_edit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_panel.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	_overlay = Control.new()
	_overlay.name = "RigOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_overlay.draw.connect(_on_overlay_draw)
	_edit_panel.add_child(_overlay)


func _on_overlay_draw() -> void:
	if _selected_node == null:
		return

	if _selected_node is TwberMeshSprite2D:
		_draw_mesh_overlay(_selected_node)
		_draw_selection_overlay()
	elif _selected_node is Sprite2D:
		_draw_sprite_bounds(_selected_node)
	elif _selected_node is AnimatedSprite2D:
		_draw_animated_sprite_bounds(_selected_node)

	_draw_layer_transform_overlay(_selected_node)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if not visible or _model_root == null:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event, _overlay_local_to_viewport(event.position))
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event, _overlay_local_to_viewport(event.position))


func _handle_mouse_button(event: InputEventMouseButton, viewport_position: Vector2) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if not event.pressed:
		_stop_pointer_interaction()
		if _selecting_vertices:
			_finish_vertex_selection()
		_overlay.accept_event()
		return

	match _get_mode():
		RigMode.TRANSFORM_LAYER, RigMode.ROTATE_LAYER, RigMode.SCALE_LAYER:
			_begin_layer_transform_at(viewport_position, _get_mode())
		RigMode.CHANGE_PIVOT:
			_change_pivot_at(viewport_position)
		RigMode.DEFORM_VERTEX:
			_begin_deform_at(viewport_position, event.shift_pressed)
		RigMode.RECTANGLE_SELECT:
			_begin_rectangle_selection(viewport_position, event.shift_pressed)
		RigMode.LASSO_SELECT:
			_begin_lasso_selection(viewport_position, event.shift_pressed)
		RigMode.RESET_VERTEX:
			_reset_vertex_at(viewport_position)

	_overlay.accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion, viewport_position: Vector2) -> void:
	if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_stop_pointer_interaction()
		_selecting_vertices = false
		return

	if _dragging_layer_transform:
		_update_layer_transform(viewport_position)
		_overlay.accept_event()
		return

	if _selecting_vertices:
		_update_vertex_selection(viewport_position)
		_overlay.accept_event()
		return

	if not _dragging_vertex or not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var drag_offset := _viewport_to_node_position(mesh_sprite, viewport_position) - _drag_start_position
	var pose := pose_draft.pose()
	if pose == null:
		return
	for vertex_index: int in _selected_vertex_indices:
		if not _drag_start_vertices.has(vertex_index):
			continue

		var start_position: Vector2 = _drag_start_vertices[vertex_index]
		var next_position := _snap_mesh_position(mesh_sprite, start_position + drag_offset)
		pose.mesh_vertices[vertex_index] = next_position
	pose_draft.update(pose)
	_queue_overlay_redraw()
	_overlay.accept_event()


func _begin_layer_transform_at(canvas_position: Vector2, mode: int) -> void:
	if not _ensure_pose_draft():
		return

	_dragging_vertex = false
	_selecting_vertices = false
	_dragging_layer_transform = true
	_layer_transform_mode = mode
	_layer_transform_start_mouse = canvas_position
	_layer_transform_current_mouse = canvas_position
	_layer_transform_start_origin = _get_node_canvas_origin(_selected_node)
	_layer_transform_start_rotation = _selected_node.rotation
	_layer_transform_start_scale = _selected_node.scale

	var mouse_offset := canvas_position - _layer_transform_start_origin
	_layer_transform_start_mouse_angle = mouse_offset.angle()
	_layer_transform_start_mouse_distance = maxf(mouse_offset.length(), MIN_LAYER_SCALE_DISTANCE)
	_queue_overlay_redraw()


func _update_layer_transform(canvas_position: Vector2) -> void:
	if _selected_node == null or pose_draft == null or not pose_draft.has_draft():
		return

	_layer_transform_current_mouse = canvas_position
	match _layer_transform_mode:
		RigMode.TRANSFORM_LAYER:
			var drag_delta := canvas_position - _layer_transform_start_mouse
			_set_node_canvas_origin(_selected_node, _layer_transform_start_origin + drag_delta)
		RigMode.ROTATE_LAYER:
			var mouse_offset := canvas_position - _layer_transform_start_origin
			if mouse_offset.length_squared() > MIN_LAYER_SCALE_DISTANCE:
				var rotation_delta := angle_difference(
						_layer_transform_start_mouse_angle,
						mouse_offset.angle(),
				)
				var next_rotation := _snap_rotation(
						_layer_transform_start_rotation + rotation_delta,
				)
				edit_pose({"rotation": wrapf(next_rotation, -PI, PI)})
		RigMode.SCALE_LAYER:
			var mouse_distance := maxf((canvas_position - _layer_transform_start_origin).length(), MIN_LAYER_SCALE_DISTANCE)
			var scale_factor := _snap_scale_factor(
					mouse_distance / _layer_transform_start_mouse_distance,
			)
			edit_pose({"scale": _layer_transform_start_scale * scale_factor})

	_queue_overlay_redraw()


func _change_pivot_at(canvas_position: Vector2) -> void:
	if _selected_node == null:
		return

	_stop_pointer_interaction()
	_selecting_vertices = false
	_clear_vertex_selection()
	_change_node_pivot(_selected_node, canvas_position)
	_queue_overlay_redraw()


func _stop_pointer_interaction() -> void:
	_dragging_vertex = false
	_dragging_layer_transform = false
	if pose_draft != null:
		pose_draft.finish_interaction()


func _begin_deform_at(canvas_position: Vector2, additive_selection: bool) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var vertex_index := _find_vertex_at_canvas_position(mesh_sprite, canvas_position)
	if vertex_index == -1:
		if not additive_selection:
			_clear_vertex_selection()
		_dragging_vertex = false
		_queue_overlay_redraw()
		return

	if additive_selection:
		_toggle_vertex_selection(vertex_index)
		_dragging_vertex = false
	else:
		_begin_vertex_drag(mesh_sprite, vertex_index, canvas_position)
	_queue_overlay_redraw()


func _reset_vertex_at(canvas_position: Vector2) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var vertex_index := _find_vertex_at_canvas_position(mesh_sprite, canvas_position)
	if vertex_index == -1:
		return

	var vertices_to_reset: Array[int] = [vertex_index]
	if _is_vertex_selected(vertex_index):
		vertices_to_reset = _selected_vertex_indices.duplicate()

	if not _ensure_pose_draft():
		return
	_set_vertex_selection(vertices_to_reset)
	var pose := pose_draft.pose()
	var neutral := pose_draft.neutral()
	for index: int in vertices_to_reset:
		pose.mesh_vertices[index] = neutral.mesh_vertices[index]
	pose_draft.update(pose)
	_queue_overlay_redraw()


func _begin_rectangle_selection(canvas_position: Vector2, additive_selection: bool) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	_dragging_vertex = false
	_selecting_vertices = true
	_selection_additive = additive_selection
	_selection_mode = RigMode.RECTANGLE_SELECT
	_selection_start_position = _canvas_to_editor_position(canvas_position)
	_selection_current_position = _selection_start_position
	_lasso_points = PackedVector2Array()
	_queue_overlay_redraw()


func _begin_lasso_selection(canvas_position: Vector2, additive_selection: bool) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	_dragging_vertex = false
	_selecting_vertices = true
	_selection_additive = additive_selection
	_selection_mode = RigMode.LASSO_SELECT
	_selection_start_position = _canvas_to_editor_position(canvas_position)
	_selection_current_position = _selection_start_position
	_lasso_points = PackedVector2Array([_selection_start_position])
	_queue_overlay_redraw()


func _update_vertex_selection(canvas_position: Vector2) -> void:
	_selection_current_position = _canvas_to_editor_position(canvas_position)
	if _selection_mode == RigMode.LASSO_SELECT:
		if _lasso_points.is_empty() or _lasso_points[_lasso_points.size() - 1].distance_to(_selection_current_position) >= LASSO_MIN_POINT_DISTANCE:
			_lasso_points.append(_selection_current_position)

	_queue_overlay_redraw()


func _finish_vertex_selection() -> void:
	if not (_selected_node is TwberMeshSprite2D):
		_selecting_vertices = false
		return

	if (
			_selection_mode == RigMode.LASSO_SELECT
			and (_lasso_points.is_empty() or _lasso_points[_lasso_points.size() - 1] != _selection_current_position)
	):
		_lasso_points.append(_selection_current_position)

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var selected_indices := _find_vertices_in_active_selection(mesh_sprite)
	if _selection_additive:
		var merged_indices: Array[int] = _selected_vertex_indices.duplicate()
		for vertex_index: int in selected_indices:
			if not merged_indices.has(vertex_index):
				merged_indices.append(vertex_index)
		_set_vertex_selection(merged_indices)
	else:
		_set_vertex_selection(selected_indices)

	_selecting_vertices = false
	_lasso_points = PackedVector2Array()
	_queue_overlay_redraw()


func _find_vertices_in_active_selection(mesh_sprite: TwberMeshSprite2D) -> Array[int]:
	var selected_indices: Array[int] = []
	if mesh_sprite.mesh_data == null:
		return selected_indices

	var vertices := mesh_sprite.mesh_data.vertices
	if _selection_mode == RigMode.RECTANGLE_SELECT:
		var rect := _get_selection_rect()
		for index: int in vertices.size():
			if rect.has_point(_node_to_editor_position(mesh_sprite, vertices[index])):
				selected_indices.append(index)
		return selected_indices

	if _selection_mode == RigMode.LASSO_SELECT and _lasso_points.size() >= 3:
		for index: int in vertices.size():
			if Geometry2D.is_point_in_polygon(_node_to_editor_position(mesh_sprite, vertices[index]), _lasso_points):
				selected_indices.append(index)

	return selected_indices


func _get_selection_rect() -> Rect2:
	var top_left := Vector2(
			minf(_selection_start_position.x, _selection_current_position.x),
			minf(_selection_start_position.y, _selection_current_position.y)
	)
	var bottom_right := Vector2(
			maxf(_selection_start_position.x, _selection_current_position.x),
			maxf(_selection_start_position.y, _selection_current_position.y)
	)
	return Rect2(top_left, bottom_right - top_left)


func _on_reset_layer_button_pressed() -> void:
	if _ensure_pose_draft():
		pose_draft.update(pose_draft.neutral())
	_clear_vertex_selection()
	_stop_pointer_interaction()
	_refresh_inspector()
	_queue_overlay_redraw()


func _on_opacity_slider_value_changed(value: float) -> void:
	if _updating_inspector or not _ensure_pose_draft():
		return
	var color := pose_draft.pose().self_modulate
	color.a = value
	edit_pose({"self_modulate": color})


func _on_visible_check_box_toggled(enabled: bool) -> void:
	if not _updating_inspector:
		edit_pose({"visible": enabled})


func _on_animation_frame_rate_value_changed(value: float) -> void:
	if not _updating_inspector and _get_selected_animated_sprite() != null:
		edit_pose({"animation_frame_rate": value})


func _on_animation_selected(index: int) -> void:
	if _updating_inspector or not _ensure_pose_draft():
		return
	var name := String(_get_animation_name_from_option(index))
	var layer := pose_draft.neutral()
	var rate := layer.animation_frame_rate
	var sprite := _get_selected_animated_sprite()
	if sprite == null or not sprite.sprite_frames.has_animation(name):
		return
	rate = sprite.sprite_frames.get_animation_speed(name)
	edit_pose({"animation_name": name, "animation_frame_rate": rate})


func _hide_inspector() -> void:
	_inspector.visible = false
	_animations_box.visible = false
	_animation_frame_rate.visible = false
	_animations_option_button.clear()


func _refresh_inspector() -> void:
	if _selected_node == null:
		_hide_inspector()
		return

	var is_animated_layer := _selected_node is AnimatedSprite2D

	_updating_inspector = true
	_inspector.visible = true
	_visible_check_box.button_pressed = _selected_node.visible
	_opacity_slider.value = TwberAlphaClipController.get_authored_self_modulate(_selected_node).a
	_animation_frame_rate.visible = is_animated_layer
	_animations_box.visible = is_animated_layer

	if is_animated_layer and _selected_node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = _selected_node
		_refresh_animation_controls(animated_sprite)
		if animated_sprite.sprite_frames != null:
			var animation := _get_animated_sprite_animation(animated_sprite)
			if animated_sprite.sprite_frames.has_animation(animation):
				_animation_frame_rate.value = animated_sprite.sprite_frames.get_animation_speed(animation)
	else:
		_animations_option_button.clear()

	_updating_inspector = false


func _refresh_animation_controls(animated_sprite: AnimatedSprite2D) -> void:
	_animations_option_button.clear()

	if animated_sprite.sprite_frames == null:
		_animations_option_button.disabled = true
		return

	var animation_names := animated_sprite.sprite_frames.get_animation_names()
	var current_animation := _get_animated_sprite_animation(animated_sprite)

	for index: int in animation_names.size():
		var animation_name: String = animation_names[index]
		_animations_option_button.add_item(animation_name, index)
		if StringName(animation_name) == current_animation:
			_animations_option_button.select(index)

	_animations_option_button.disabled = animation_names.is_empty()


func _get_model_parameters() -> Array[TwberParameterResource]:
	var output: Array[TwberParameterResource] = []
	if _model_root == null:
		return output

	var stored_values: Variant = _model_root.get_meta(TwberModelCodec.MODEL_PARAMETERS_META, [])
	if stored_values is Array:
		for value: Variant in stored_values:
			if value is TwberParameterResource:
				output.append(value)

	return output


func _set_model_parameters(parameters: Array[TwberParameterResource]) -> void:
	if _model_root != null:
		_model_root.set_meta(TwberModelCodec.MODEL_PARAMETERS_META, parameters)
		_parameter_evaluator.update_parameters(parameters)


func _refresh_parameter_panel() -> void:
	if _parameter_list == null:
		return

	finish_parameter_edits()
	_editing_parameter_name = null
	for child: Node in _parameter_list.get_children():
		_parameter_list.remove_child(child)
		child.queue_free()

	_parameter_value_controls.clear()
	_parameter_select_buttons.clear()

	var parameters := _get_model_parameters()
	_sync_parameter_preview_values(parameters)
	_prune_collapsed_parameter_ids(parameters)
	if not _has_parameter_id(_selected_parameter_id):
		_selected_parameter_id = parameters[0].id if not parameters.is_empty() else ""

	for parameter: TwberParameterResource in parameters:
		_parameter_list.add_child(_create_parameter_card(parameter))

	_update_parameter_selection()
	_refresh_position_buttons()


func _sync_parameter_preview_values(parameters: Array[TwberParameterResource]) -> void:
	var next_values := {}
	for parameter: TwberParameterResource in parameters:
		if parameter == null or parameter.id.is_empty():
			continue
		var value: Variant = _parameter_preview_values.get(
				parameter.id,
				parameter.get_default_value(),
		)
		next_values[parameter.id] = parameter.value_from_coordinate(
				parameter.coordinate_from_value(value),
		)
	_parameter_preview_values = next_values


func _create_parameter_card(parameter: TwberParameterResource) -> Control:
	var card := PanelContainer.new()
	card.name = "ParameterCard_%s" % parameter.id
	card.custom_minimum_size = Vector2(0.0, 0.0)

	var margin := MarginContainer.new()
	for margin_name: StringName in [
			&"margin_left",
			&"margin_top",
			&"margin_right",
			&"margin_bottom",
	]:
		margin.add_theme_constant_override(margin_name, 6)
	card.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 4)
	content.add_child(header)

	var select_button := Button.new()
	select_button.name = "SelectButton"
	select_button.custom_minimum_size = Vector2(48.0, 28.0)
	select_button.toggle_mode = true
	select_button.tooltip_text = "%s\nRight-click to collapse or expand" % (
		_get_parameter_position_count_text(parameter)
	)
	select_button.pressed.connect(func() -> void:
		_select_parameter(parameter.id)
	)
	header.add_child(select_button)
	_parameter_select_buttons[parameter.id] = select_button

	var name_edit := LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text = parameter.name if not parameter.name.is_empty() else parameter.id
	name_edit.tooltip_text = parameter.id
	name_edit.focus_entered.connect(func() -> void:
		_select_parameter(parameter.id)
	)
	name_edit.text_changed.connect(func(_text: String) -> void:
		_editing_parameter_name = name_edit
		_editing_parameter_id = parameter.id
	)
	name_edit.text_submitted.connect(func(_text: String) -> void: finish_parameter_edits())
	name_edit.focus_exited.connect(func() -> void:
		if _editing_parameter_name == name_edit:
			finish_parameter_edits()
	)
	header.add_child(name_edit)

	var delete_button := Button.new()
	delete_button.custom_minimum_size = Vector2(28.0, 28.0)
	delete_button.text = "×"
	delete_button.tooltip_text = "Delete parameter"
	delete_button.pressed.connect(func() -> void:
		_delete_parameter(parameter.id)
	)
	header.add_child(delete_button)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 6)
	content.add_child(body)
	var card_is_collapsed := _collapsed_parameter_ids.has(parameter.id)
	body.visible = not card_is_collapsed
	_update_parameter_disclosure_button(select_button, parameter, card_is_collapsed)
	select_button.gui_input.connect(func(event: InputEvent) -> void:
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_RIGHT
			and event.pressed
		):
			_toggle_parameter_collapsed(parameter, body, select_button)
			select_button.accept_event()
	)

	if parameter.value_type != TwberParameterResource.ValueType.BOOL:
		body.add_child(_create_parameter_range_editor(parameter))

	var value_control := _create_parameter_value_control(parameter)
	body.add_child(value_control)
	_parameter_value_controls[parameter.id] = value_control
	return card


func _toggle_parameter_collapsed(
		parameter: TwberParameterResource,
		body: Control,
		select_button: Button,
) -> void:
	var card_is_collapsed := not _collapsed_parameter_ids.has(parameter.id)
	if card_is_collapsed:
		_collapsed_parameter_ids[parameter.id] = true
	else:
		_collapsed_parameter_ids.erase(parameter.id)
	body.visible = not card_is_collapsed
	_update_parameter_disclosure_button(select_button, parameter, card_is_collapsed)


func _update_parameter_disclosure_button(
		button: Button,
		parameter: TwberParameterResource,
		card_is_collapsed: bool,
) -> void:
	button.text = "%s%s" % [
		"▸" if card_is_collapsed else "▾",
		_get_parameter_type_label(parameter.value_type).to_upper(),
	]


func _prune_collapsed_parameter_ids(parameters: Array[TwberParameterResource]) -> void:
	var valid_ids := {}
	for parameter: TwberParameterResource in parameters:
		if parameter != null:
			valid_ids[parameter.id] = true
	for parameter_id: Variant in _collapsed_parameter_ids.keys():
		if not valid_ids.has(String(parameter_id)):
			_collapsed_parameter_ids.erase(parameter_id)


func _create_parameter_range_editor(parameter: TwberParameterResource) -> Control:
	if parameter.value_type == TwberParameterResource.ValueType.VECTOR2:
		return _create_vector_range_editor(parameter)
	return _create_scalar_range_editor(parameter)


func _create_scalar_range_editor(parameter: TwberParameterResource) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var minimum_label := Label.new()
	minimum_label.text = "Min"
	row.add_child(minimum_label)

	var use_integers := parameter.value_type == TwberParameterResource.ValueType.INT
	var minimum_edit := _create_range_spin_box(parameter.get_scalar_min(), use_integers)
	minimum_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(minimum_edit)

	var maximum_label := Label.new()
	maximum_label.text = "Max"
	row.add_child(maximum_label)

	var maximum_edit := _create_range_spin_box(parameter.get_scalar_max(), use_integers)
	maximum_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(maximum_edit)

	minimum_edit.value_changed.connect(func(value: float) -> void:
		_on_scalar_range_changed(parameter, true, value, minimum_edit, maximum_edit)
	)
	maximum_edit.value_changed.connect(func(value: float) -> void:
		_on_scalar_range_changed(parameter, false, value, minimum_edit, maximum_edit)
	)
	_update_scalar_range_spin_limits(parameter, minimum_edit, maximum_edit)
	return row


func _create_vector_range_editor(parameter: TwberParameterResource) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)

	var range_min := parameter.get_vector_min()
	var range_max := parameter.get_vector_max()
	var minimum_x_edit := _add_labeled_range_spin_box(grid, "Min X", range_min.x)
	var minimum_y_edit := _add_labeled_range_spin_box(grid, "Min Y", range_min.y)
	var maximum_x_edit := _add_labeled_range_spin_box(grid, "Max X", range_max.x)
	var maximum_y_edit := _add_labeled_range_spin_box(grid, "Max Y", range_max.y)

	minimum_x_edit.value_changed.connect(func(value: float) -> void:
		_on_vector_range_changed(parameter, 0, true, value, minimum_x_edit, maximum_x_edit)
	)
	minimum_y_edit.value_changed.connect(func(value: float) -> void:
		_on_vector_range_changed(parameter, 1, true, value, minimum_y_edit, maximum_y_edit)
	)
	maximum_x_edit.value_changed.connect(func(value: float) -> void:
		_on_vector_range_changed(parameter, 0, false, value, minimum_x_edit, maximum_x_edit)
	)
	maximum_y_edit.value_changed.connect(func(value: float) -> void:
		_on_vector_range_changed(parameter, 1, false, value, minimum_y_edit, maximum_y_edit)
	)
	_update_vector_range_spin_limits(parameter, 0, minimum_x_edit, maximum_x_edit)
	_update_vector_range_spin_limits(parameter, 1, minimum_y_edit, maximum_y_edit)
	return grid


func _add_labeled_range_spin_box(
		parent: GridContainer,
		label_text: String,
		value: float,
) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var spin_box := _create_range_spin_box(value, false)
	spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin_box)
	return spin_box


func _create_range_spin_box(value: float, use_integers: bool) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.custom_minimum_size = Vector2(62.0, 0.0)
	spin_box.min_value = -1000000.0
	spin_box.max_value = 1000000.0
	spin_box.step = (
			TwberParameterResource.DISCRETE_STEP
			if use_integers
			else TwberParameterResource.CONTINUOUS_STEP
	)
	spin_box.rounded = use_integers
	spin_box.value = value
	spin_box.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spin_box.update_on_text_changed = false
	spin_box.tooltip_text = "Remove bound positions before shrinking the range past them"
	return spin_box


func _create_parameter_value_control(parameter: TwberParameterResource) -> Control:
	var active_value: Variant = _parameter_preview_values.get(
			parameter.id,
			parameter.get_default_value(),
	)

	match parameter.value_type:
		TwberParameterResource.ValueType.BOOL:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var group := ButtonGroup.new()
			group.allow_unpress = false
			for option_value: bool in [false, true]:
				var option_button := Button.new()
				option_button.name = "TrueButton" if option_value else "FalseButton"
				option_button.text = "True" if option_value else "False"
				option_button.tooltip_text = "Preview the parameter as %s" % option_button.text.to_lower()
				option_button.toggle_mode = true
				option_button.button_group = group
				option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				option_button.button_pressed = bool(active_value) == option_value
				option_button.toggled.connect(func(enabled: bool) -> void:
					if enabled:
						_on_parameter_value_changed(parameter, option_value)
				)
				row.add_child(option_button)
			return row
		TwberParameterResource.ValueType.VECTOR2:
			var vector_field := ParameterVectorField.new()
			vector_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vector_field.configure(
					parameter.get_vector_min(),
					parameter.get_vector_max(),
					parameter.step,
			)
			vector_field.set_active_value(parameter.coordinate_from_value(active_value))
			vector_field.set_bound_markers(parameter.get_bound_coordinates())
			vector_field.value_changed.connect(func(value: Vector2) -> void:
				_on_parameter_value_changed(parameter, value)
			)
			return vector_field
		_:
			var scalar_track := ParameterScalarTrack.new()
			scalar_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var use_integers := parameter.value_type == TwberParameterResource.ValueType.INT
			scalar_track.configure(
					parameter.get_scalar_min(),
					parameter.get_scalar_max(),
					parameter.step,
					use_integers,
			)
			scalar_track.set_active_value(parameter.coordinate_from_value(active_value).x)
			scalar_track.set_bound_markers(_get_scalar_bound_markers(parameter))
			scalar_track.value_changed.connect(func(value: float) -> void:
				var parameter_value: Variant = value
				if use_integers:
					parameter_value = int(roundf(value))
				_on_parameter_value_changed(parameter, parameter_value)
			)
			return scalar_track


func _get_scalar_bound_markers(parameter: TwberParameterResource) -> Array[float]:
	var output: Array[float] = []
	for coordinate: Vector2 in parameter.get_bound_coordinates():
		output.append(coordinate.x)
	return output


func _on_scalar_range_changed(
		parameter: TwberParameterResource,
		editing_minimum: bool,
		value: float,
		minimum_edit: SpinBox,
		maximum_edit: SpinBox,
) -> void:
	if editing_minimum:
		var upper_limit := parameter.get_scalar_max()
		var lowest_bound: Variant = _get_bound_component_extreme(parameter, 0, true)
		if lowest_bound != null:
			upper_limit = minf(upper_limit, float(lowest_bound))
		_submit_parameter_command(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, parameter.id, {"min_value": minf(value, upper_limit)}))
	else:
		var lower_limit := parameter.get_scalar_min()
		var highest_bound: Variant = _get_bound_component_extreme(parameter, 0, false)
		if highest_bound != null:
			lower_limit = maxf(lower_limit, float(highest_bound))
		_submit_parameter_command(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, parameter.id, {"max_value": maxf(value, lower_limit)}))

	minimum_edit.set_value_no_signal(parameter.get_scalar_min())
	maximum_edit.set_value_no_signal(parameter.get_scalar_max())
	_update_scalar_range_spin_limits(parameter, minimum_edit, maximum_edit)


func _update_scalar_range_spin_limits(
		parameter: TwberParameterResource,
		minimum_edit: SpinBox,
		maximum_edit: SpinBox,
) -> void:
	var minimum_upper_limit := parameter.get_scalar_max()
	var lowest_bound: Variant = _get_bound_component_extreme(parameter, 0, true)
	if lowest_bound != null:
		minimum_upper_limit = minf(minimum_upper_limit, float(lowest_bound))
	minimum_edit.max_value = minimum_upper_limit

	var maximum_lower_limit := parameter.get_scalar_min()
	var highest_bound: Variant = _get_bound_component_extreme(parameter, 0, false)
	if highest_bound != null:
		maximum_lower_limit = maxf(maximum_lower_limit, float(highest_bound))
	maximum_edit.min_value = maximum_lower_limit


func _on_vector_range_changed(
		parameter: TwberParameterResource,
		axis: int,
		editing_minimum: bool,
		value: float,
		minimum_edit: SpinBox,
		maximum_edit: SpinBox,
) -> void:
	var range_min := parameter.get_vector_min()
	var range_max := parameter.get_vector_max()
	if editing_minimum:
		var upper_limit := range_max[axis]
		var lowest_bound: Variant = _get_bound_component_extreme(parameter, axis, true)
		if lowest_bound != null:
			upper_limit = minf(upper_limit, float(lowest_bound))
		range_min[axis] = minf(value, upper_limit)
	else:
		var lower_limit := range_min[axis]
		var highest_bound: Variant = _get_bound_component_extreme(parameter, axis, false)
		if highest_bound != null:
			lower_limit = maxf(lower_limit, float(highest_bound))
		range_max[axis] = maxf(value, lower_limit)

	_submit_parameter_command(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, parameter.id, {"min_vector2": range_min, "max_vector2": range_max}))
	range_min = parameter.get_vector_min()
	range_max = parameter.get_vector_max()
	minimum_edit.set_value_no_signal(range_min[axis])
	maximum_edit.set_value_no_signal(range_max[axis])
	_update_vector_range_spin_limits(parameter, axis, minimum_edit, maximum_edit)


func _update_vector_range_spin_limits(
		parameter: TwberParameterResource,
		axis: int,
		minimum_edit: SpinBox,
		maximum_edit: SpinBox,
) -> void:
	var range_min := parameter.get_vector_min()
	var range_max := parameter.get_vector_max()
	var minimum_upper_limit := range_max[axis]
	var lowest_bound: Variant = _get_bound_component_extreme(parameter, axis, true)
	if lowest_bound != null:
		minimum_upper_limit = minf(minimum_upper_limit, float(lowest_bound))
	minimum_edit.max_value = minimum_upper_limit

	var maximum_lower_limit := range_min[axis]
	var highest_bound: Variant = _get_bound_component_extreme(parameter, axis, false)
	if highest_bound != null:
		maximum_lower_limit = maxf(maximum_lower_limit, float(highest_bound))
	maximum_edit.min_value = maximum_lower_limit


func _get_bound_component_extreme(
		parameter: TwberParameterResource,
		axis: int,
		find_minimum: bool,
) -> Variant:
	var found := false
	var extreme := INF if find_minimum else -INF
	for parameter_position: TwberParameterPositionResource in parameter.positions:
		if parameter_position == null or parameter_position.layer_states.is_empty():
			continue
		var component := parameter_position.coordinate[axis]
		extreme = minf(extreme, component) if find_minimum else maxf(extreme, component)
		found = true
	for binding: TwberAnimationBindingResource in parameter.animation_bindings:
		var component := binding.coordinate[axis]
		extreme = minf(extreme, component) if find_minimum else maxf(extreme, component)
		found = true
	if not found:
		return null
	return extreme


func _on_parameter_value_changed(
		parameter: TwberParameterResource,
		value: Variant,
) -> void:
	_parameter_preview_values[parameter.id] = parameter.value_from_coordinate(
			parameter.coordinate_from_value(value),
	)
	_selected_parameter_id = parameter.id
	_update_parameter_selection()
	_refresh_position_buttons()
	preview_parameters()


func _select_parameter(parameter_id: String) -> void:
	if not _has_parameter_id(parameter_id):
		return
	_selected_parameter_id = parameter_id
	_update_parameter_selection()
	_refresh_position_buttons()
	preview_parameters()


func _update_parameter_selection() -> void:
	for parameter_id: Variant in _parameter_select_buttons:
		var select_button: Button = _parameter_select_buttons[parameter_id]
		select_button.set_pressed_no_signal(String(parameter_id) == _selected_parameter_id)


func _on_create_parameter_pressed(value_type: int) -> void:
	_submit_parameter_command(TwberEditParameter.new(TwberEditParameter.Operation.CREATE, "", {"value_type": value_type}))


func _delete_parameter(parameter_id: String) -> void:
	_submit_parameter_command(TwberEditParameter.new(TwberEditParameter.Operation.DELETE, parameter_id))


func _on_bind_position_button_pressed() -> void:
	if _get_selected_parameter() == null or not _ensure_pose_draft():
		return
	var command := pose_draft.make_command() as TwberEditParameter
	if command == null:
		cancel_pose_draft()
		return
	if _submit_parameter_command(command) == OK:
		cancel_pose_draft()
		preview_parameters()


func _on_remove_position_button_pressed() -> void:
	var parameter := _get_selected_parameter()
	var layer_id := _get_selected_model_layer_id()
	if parameter == null or layer_id.is_empty():
		return
	_submit_parameter_command(TwberEditParameter.new(TwberEditParameter.Operation.REMOVE_POSE, parameter.id, {
		"coordinate": _get_parameter_preview_coordinate(parameter), "layer_id": layer_id,
	}))


func _get_parameter_preview_coordinate(parameter: TwberParameterResource) -> Vector2:
	return parameter.coordinate_from_value(_parameter_preview_values.get(
			parameter.id,
			parameter.get_default_value(),
	))


func _update_parameter_control(parameter: TwberParameterResource) -> void:
	if not _parameter_value_controls.has(parameter.id):
		return

	var control: Control = _parameter_value_controls[parameter.id]
	var active_coordinate := _get_parameter_preview_coordinate(parameter)
	if control is ParameterScalarTrack:
		control.configure(
				parameter.get_scalar_min(),
				parameter.get_scalar_max(),
				parameter.step,
				parameter.value_type == TwberParameterResource.ValueType.INT,
		)
		control.set_active_value(active_coordinate.x)
		control.set_bound_markers(_get_scalar_bound_markers(parameter))
	elif control is ParameterVectorField:
		control.configure(
				parameter.get_vector_min(),
				parameter.get_vector_max(),
				parameter.step,
		)
		control.set_active_value(active_coordinate)
		control.set_bound_markers(parameter.get_bound_coordinates())

	if _parameter_select_buttons.has(parameter.id):
		var select_button: Button = _parameter_select_buttons[parameter.id]
		select_button.tooltip_text = _get_parameter_position_count_text(parameter)


func _get_parameter_position_count_text(parameter: TwberParameterResource) -> String:
	var count := 0
	for parameter_position: TwberParameterPositionResource in parameter.positions:
		if parameter_position != null and not parameter_position.layer_states.is_empty():
			count += 1
	return "%d bound position(s)" % count


func _refresh_position_buttons() -> void:
	var parameter := _get_selected_parameter()
	var can_bind := parameter != null and _selected_node != null
	var has_selected_state := can_bind and _has_selected_layer_state_at_preview(parameter)
	_bind_position_button.disabled = not can_bind
	_remove_position_button.disabled = not has_selected_state
	if not can_bind:
		_remove_position_button.tooltip_text = "Select a parameter and layer first"
	elif has_selected_state:
		_remove_position_button.tooltip_text = (
				"Remove the selected layer's state from the current parameter position"
		)
	elif parameter.find_position(_get_parameter_preview_coordinate(parameter)) != null:
		_remove_position_button.tooltip_text = (
				"This position currently contains states for other layers only"
		)
	else:
		_remove_position_button.tooltip_text = "The current parameter position is not bound"
	_refresh_animation_binding_controls()


func _refresh_animation_binding_controls() -> void:
	var selected_id := _get_selected_timeline_animation_id()
	_model_animations_option.clear()
	for animation: TwberTimelineAnimationResource in _get_timeline_animations():
		var index := _model_animations_option.item_count
		_model_animations_option.add_item(animation.name)
		_model_animations_option.set_item_metadata(index, animation.id)
		if animation.id == selected_id:
			_model_animations_option.select(index)

	var parameter := _get_selected_parameter()
	var supported := (
		parameter != null
		and (
			parameter.value_type == TwberParameterResource.ValueType.BOOL
			or parameter.value_type == TwberParameterResource.ValueType.INT
		)
	)
	_animation_binding_panel.visible = not _get_timeline_animations().is_empty()
	_model_animations_option.disabled = not supported
	var animation_id := _get_selected_timeline_animation_id()
	var binding: TwberAnimationBindingResource
	if supported and not animation_id.is_empty():
		binding = parameter.find_animation_binding(
				animation_id,
				_get_parameter_preview_coordinate(parameter),
		)
	_bind_animation_button.disabled = not supported or animation_id.is_empty()
	_remove_animation_binding_button.disabled = binding == null
	if not supported:
		_bind_animation_button.tooltip_text = "Select a bool or int parameter"
	else:
		_bind_animation_button.tooltip_text = (
				"Run this animation when %s is %s" % [
					parameter.name,
					str(parameter.value_from_coordinate(_get_parameter_preview_coordinate(parameter))),
				]
		)


func _get_timeline_animations() -> Array[TwberTimelineAnimationResource]:
	var output: Array[TwberTimelineAnimationResource] = []
	if _model_root == null:
		return output
	var values: Variant = _model_root.get_meta(TwberModelCodec.MODEL_TIMELINE_ANIMATIONS_META, [])
	if values is Array:
		for value: Variant in values:
			if value is TwberTimelineAnimationResource:
				output.append(value)
	return output


func _get_selected_timeline_animation_id() -> String:
	if _model_animations_option.item_count == 0 or _model_animations_option.selected < 0:
		return ""
	return String(_model_animations_option.get_item_metadata(_model_animations_option.selected))


func _on_bind_animation_button_pressed() -> void:
	_edit_animation_binding(TwberEditParameter.Operation.BIND_ANIMATION)


func _on_remove_animation_binding_button_pressed() -> void:
	_edit_animation_binding(TwberEditParameter.Operation.REMOVE_ANIMATION)


func _edit_animation_binding(operation: TwberEditParameter.Operation) -> void:
	var parameter := _get_selected_parameter()
	var animation_id := _get_selected_timeline_animation_id()
	if parameter == null or animation_id.is_empty():
		return
	_submit_parameter_command(TwberEditParameter.new(operation, parameter.id, {
		"coordinate": _get_parameter_preview_coordinate(parameter), "animation_id": animation_id,
	}))


func _has_selected_layer_state_at_preview(parameter: TwberParameterResource) -> bool:
	if parameter == null:
		return false
	var layer_id := _get_selected_model_layer_id()
	if layer_id.is_empty():
		return false
	var parameter_position := parameter.find_position(
			_get_parameter_preview_coordinate(parameter),
	)
	return parameter_position != null and parameter_position.find_state(layer_id) != null


func preview_parameters() -> void:
	cancel_pose_draft()
	if not visible:
		return
	restore_parameter_preview_base()
	if _model_root != null:
		var affected_layer_ids := _apply_parameter_preview_values()
		for layer_id: String in affected_layer_ids:
			_previewed_layer_ids[layer_id] = true
		var clip_controller := TwberAlphaClipController.attach_to(_model_root)
		clip_controller.sync_now(affected_layer_ids)

	parameter_values_previewed.emit(_parameter_preview_values.duplicate())
	if _selected_node != null:
		_refresh_inspector()
	_queue_overlay_redraw()


func _apply_parameter_preview_values(excluded_parameter_id := "") -> Array[String]:
	if _model_root == null:
		return []

	var affected_layer_ids := _parameter_evaluator.apply(
			_parameter_preview_values,
			excluded_parameter_id,
	)
	_snap_parameter_preview_layers(affected_layer_ids)
	return affected_layer_ids


func _snap_parameter_preview_layers(layer_ids: Array[String]) -> void:
	if not _is_pixel_snap_enabled() or layer_ids.is_empty() or _model_root == null:
		return

	var layer_nodes := _parameter_evaluator.get_layer_nodes()
	for layer_id: String in layer_ids:
		if not layer_nodes.has(layer_id):
			continue
		var node := layer_nodes[layer_id] as Node2D
		if node == null:
			continue
		node.position = _snap_pixel_position(node.position)
		node.rotation = _snap_rotation(node.rotation)
		node.scale = _snap_scale(node.scale)
		_snap_parameter_preview_mesh(node)


func _snap_parameter_preview_mesh(node: Node2D) -> void:
	if node is not TwberMeshSprite2D:
		return

	var mesh_sprite: TwberMeshSprite2D = node
	if mesh_sprite.mesh_data == null or mesh_sprite.mesh_data.vertices.is_empty():
		return

	var snapped_vertices := mesh_sprite.mesh_data.vertices.duplicate()
	var changed := false
	for vertex_index: int in snapped_vertices.size():
		var snapped_position := _snap_mesh_position(
				mesh_sprite,
				snapped_vertices[vertex_index],
		)
		if not snapped_position.is_equal_approx(snapped_vertices[vertex_index]):
			snapped_vertices[vertex_index] = snapped_position
			changed = true

	if changed:
		mesh_sprite.mesh_data.vertices = snapped_vertices
		mesh_sprite.sync_mesh()


func restore_parameter_preview_base() -> void:
	cancel_pose_draft()
	if _previewed_layer_ids.is_empty() or _model_root == null:
		return
	_restore_initial_states_in_tree(_model_root, _previewed_layer_ids)
	var renderer := TwberModelBatchRenderer2D.find_on(_model_root)
	if renderer is TwberModelBatchRenderer2D:
		var restored_nodes: Array[Node2D] = []
		var layer_nodes := _parameter_evaluator.get_layer_nodes()
		for layer_id: Variant in _previewed_layer_ids:
			var node := layer_nodes.get(String(layer_id)) as Node2D
			if node != null:
				restored_nodes.append(node)
		if not restored_nodes.is_empty():
			renderer.update_dynamic_geometry_for_nodes(restored_nodes)
	_previewed_layer_ids.clear()


func _restore_initial_states_in_tree(parent: Node, layer_ids: Dictionary) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue
		var node_2d: Node2D = child
		var layer_id := String(node_2d.get_meta(TwberModelCodec.LAYER_ID_META, ""))
		if layer_ids.has(layer_id) and _initial_layer_states_by_node_id.has(node_2d.get_instance_id()):
			_reset_layer_to_initial_state(node_2d, false)
		_restore_initial_states_in_tree(node_2d, layer_ids)


func _get_selected_parameter() -> TwberParameterResource:
	return _find_parameter_by_id(_selected_parameter_id)


func _has_parameter_id(parameter_id: String) -> bool:
	return not parameter_id.is_empty() and _find_parameter_by_id(parameter_id) != null


func _find_parameter_by_id(parameter_id: String) -> TwberParameterResource:
	for parameter: TwberParameterResource in _get_model_parameters():
		if parameter.id == parameter_id:
			return parameter
	return null


func _get_selected_model_layer_id() -> String:
	if _selected_node == null:
		return ""

	if not _selected_node.has_meta(TwberModelCodec.LAYER_ID_META):
		TwberModelCodec.ensure_layer_ids(_model_root)

	return String(_selected_node.get_meta(TwberModelCodec.LAYER_ID_META, ""))


func _get_parameter_type_label(value_type: int) -> String:
	match value_type:
		TwberParameterResource.ValueType.BOOL:
			return "bool"
		TwberParameterResource.ValueType.INT:
			return "int"
		TwberParameterResource.ValueType.VECTOR2:
			return "vec"
		_:
			return "float"


func _get_selected_animated_sprite() -> AnimatedSprite2D:
	if _selected_node is AnimatedSprite2D:
		return _selected_node

	return null


func _get_animation_name_from_option(index: int) -> StringName:
	if index < 0 or index >= _animations_option_button.item_count:
		return &""

	return StringName(_animations_option_button.get_item_text(index))


func _get_animated_sprite_animation(animated_sprite: AnimatedSprite2D) -> StringName:
	if animated_sprite.sprite_frames == null:
		return &"default"

	var animation := animated_sprite.animation
	if animation != &"" and animated_sprite.sprite_frames.has_animation(animation):
		return animation

	var animation_names := animated_sprite.sprite_frames.get_animation_names()
	if not animation_names.is_empty():
		return animation_names[0]

	return &"default"


func _reset_layer_to_initial_state(node: Node2D, restore_children := true) -> void:
	var state := _get_initial_layer_state(node)
	node.position = state["position"]
	node.rotation = state["rotation"]
	node.scale = state["scale"]
	node.visible = state["visible"]
	TwberAlphaClipController.set_authored_self_modulate(node, state["self_modulate"])
	_restore_layer_content_state(node, state, restore_children)


func _remember_initial_layer_state(node: Node2D) -> void:
	var node_id := node.get_instance_id()
	if _initial_layer_states_by_node_id.has(node_id):
		return

	_initial_layer_states_by_node_id[node_id] = _capture_initial_layer_state(node)




func _capture_initial_layer_state(node: Node2D) -> Dictionary:
	return {
		"position": node.position,
		"rotation": node.rotation,
		"scale": node.scale,
		"visible": node.visible,
		"self_modulate": TwberAlphaClipController.get_authored_self_modulate(node),
		"content": _capture_layer_content_state(node),
		"child_positions": _capture_direct_child_positions(node),
	}




func _get_initial_layer_state(node: Node2D) -> Dictionary:
	_remember_initial_layer_state(node)
	return _initial_layer_states_by_node_id[node.get_instance_id()]


func _capture_layer_content_state(node: Node2D) -> Dictionary:
	var state := {}
	if node is Sprite2D:
		var sprite: Sprite2D = node
		state["sprite_offset"] = sprite.offset
	elif node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = node
		state["animated_offset"] = animated_sprite.offset
		if animated_sprite.sprite_frames != null:
			var animation_speeds := {}
			for animation_name: StringName in animated_sprite.sprite_frames.get_animation_names():
				animation_speeds[String(animation_name)] = (
					animated_sprite.sprite_frames.get_animation_speed(animation_name)
				)
			state["animated_animation_speeds"] = animation_speeds
			var animation := animated_sprite.animation
			if animation != &"" and animated_sprite.sprite_frames.has_animation(animation):
				state["animated_animation"] = animation
	elif node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		if mesh_sprite.mesh_data != null:
			mesh_sprite.mesh_data.ensure_rest_vertices()
			state["mesh_texture_origin"] = mesh_sprite.mesh_data.texture_origin
			state["mesh_vertices"] = mesh_sprite.mesh_data.vertices.duplicate()
			state["mesh_rest_vertices"] = mesh_sprite.mesh_data.rest_vertices.duplicate()
			state["mesh_uvs"] = mesh_sprite.mesh_data.uvs.duplicate()

	return state


func _restore_layer_content_state(
		node: Node2D,
		state: Dictionary,
		restore_children: bool,
) -> void:
	var content: Dictionary = state.get("content", {})
	if node is Sprite2D and content.has("sprite_offset"):
		var sprite: Sprite2D = node
		sprite.offset = content["sprite_offset"]
	elif node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = node
		if content.has("animated_offset"):
			animated_sprite.offset = content["animated_offset"]

		if animated_sprite.sprite_frames != null:
			var animation_speeds: Dictionary = content.get("animated_animation_speeds", {})
			for animation_name_value: Variant in animation_speeds:
				var animation_name := StringName(animation_name_value)
				if animated_sprite.sprite_frames.has_animation(animation_name):
					animated_sprite.sprite_frames.set_animation_speed(
							animation_name,
							float(animation_speeds[animation_name_value]),
					)

		if animated_sprite.sprite_frames != null and content.has("animated_animation"):
			var animation := StringName(content["animated_animation"])
			if animation != &"" and animated_sprite.sprite_frames.has_animation(animation):
				animated_sprite.animation = animation
	elif node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		if mesh_sprite.mesh_data != null:
			if content.has("mesh_texture_origin"):
				mesh_sprite.mesh_data.texture_origin = content["mesh_texture_origin"]
			if content.has("mesh_vertices"):
				mesh_sprite.mesh_data.vertices = content["mesh_vertices"].duplicate()
			if content.has("mesh_rest_vertices"):
				mesh_sprite.mesh_data.rest_vertices = content["mesh_rest_vertices"].duplicate()
			if content.has("mesh_uvs"):
				mesh_sprite.mesh_data.uvs = content["mesh_uvs"].duplicate()
			mesh_sprite.sync_mesh()

	if restore_children:
		_restore_direct_child_positions(node, state.get("child_positions", {}))


func _capture_direct_child_positions(node: Node2D) -> Dictionary:
	var child_positions := {}
	for child: Node in node.get_children():
		if child is not Node2D:
			continue

		child_positions[child.get_instance_id()] = child.position

	return child_positions


func _restore_direct_child_positions(node: Node2D, child_positions: Dictionary) -> void:
	for child: Node in node.get_children():
		if child is not Node2D:
			continue

		var child_id := child.get_instance_id()
		if child_positions.has(child_id):
			child.position = child_positions[child_id]


func _begin_vertex_drag(mesh_sprite: TwberMeshSprite2D, vertex_index: int, canvas_position: Vector2) -> void:
	if not _ensure_pose_draft():
		return
	if not _is_vertex_selected(vertex_index):
		_set_vertex_selection([vertex_index])

	_prune_vertex_selection(mesh_sprite.get_vertex_count())
	_drag_start_position = _viewport_to_node_position(mesh_sprite, canvas_position)
	_drag_start_vertices.clear()
	for selected_vertex_index: int in _selected_vertex_indices:
		_drag_start_vertices[selected_vertex_index] = mesh_sprite.get_vertex(selected_vertex_index)

	_dragging_vertex = not _drag_start_vertices.is_empty()


func _set_vertex_selection(vertex_indices: Array) -> void:
	_selected_vertex_indices.clear()
	var seen := {}
	for vertex_index: int in vertex_indices:
		if seen.has(vertex_index):
			continue

		seen[vertex_index] = true
		_selected_vertex_indices.append(vertex_index)


func _clear_vertex_selection() -> void:
	_selected_vertex_indices.clear()
	_drag_start_vertices.clear()


func _toggle_vertex_selection(vertex_index: int) -> void:
	var selected_index := _selected_vertex_indices.find(vertex_index)
	if selected_index == -1:
		_selected_vertex_indices.append(vertex_index)
	else:
		_selected_vertex_indices.remove_at(selected_index)


func _is_vertex_selected(vertex_index: int) -> bool:
	return _selected_vertex_indices.has(vertex_index)


func _prune_vertex_selection(vertex_count: int) -> void:
	for selection_index: int in range(_selected_vertex_indices.size() - 1, -1, -1):
		var vertex_index := _selected_vertex_indices[selection_index]
		if vertex_index < 0 or vertex_index >= vertex_count:
			_selected_vertex_indices.remove_at(selection_index)


func _draw_mesh_overlay(mesh_sprite: TwberMeshSprite2D) -> void:
	if mesh_sprite.mesh_data == null:
		return

	var vertices := mesh_sprite.mesh_data.vertices
	var triangles := mesh_sprite.mesh_data.triangles

	_draw_mesh_edges(mesh_sprite, vertices, triangles, EDGE_COLOR)

	_prune_vertex_selection(vertices.size())
	for index: int in vertices.size():
		var vertex_position := _node_to_editor_position(mesh_sprite, vertices[index])
		var color := HANDLE_COLOR
		if _is_vertex_selected(index):
			color = SELECTED_HANDLE_COLOR
		_overlay.draw_circle(vertex_position, HANDLE_RADIUS, color)


func _draw_selection_overlay() -> void:
	if not _selecting_vertices:
		return

	if _selection_mode == RigMode.RECTANGLE_SELECT:
		var rect := _get_selection_rect()
		_overlay.draw_rect(rect, SELECTION_FILL_COLOR, true)
		_overlay.draw_rect(rect, SELECTION_STROKE_COLOR, false, 1.0)
	elif _selection_mode == RigMode.LASSO_SELECT and _lasso_points.size() > 1:
		var points := _lasso_points.duplicate()
		if points[points.size() - 1] != _selection_current_position:
			points.append(_selection_current_position)
		_overlay.draw_polyline(points, SELECTION_STROKE_COLOR, 1.0)


func _draw_mesh_edges(
		node: TwberMeshSprite2D,
		vertices: PackedVector2Array,
		triangles: PackedInt32Array,
		color: Color,
) -> void:
	for triangle_start: int in range(0, triangles.size() - 2, 3):
		var a := int(triangles[triangle_start])
		var b := int(triangles[triangle_start + 1])
		var c := int(triangles[triangle_start + 2])
		if a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
			continue

		var point_a := _node_to_editor_position(node, vertices[a])
		var point_b := _node_to_editor_position(node, vertices[b])
		var point_c := _node_to_editor_position(node, vertices[c])
		_overlay.draw_line(point_a, point_b, color, 1.0)
		_overlay.draw_line(point_b, point_c, color, 1.0)
		_overlay.draw_line(point_c, point_a, color, 1.0)

	if triangles.is_empty() and vertices.size() > 1:
		for index: int in vertices.size() - 1:
			_overlay.draw_line(
					_node_to_editor_position(node, vertices[index]),
					_node_to_editor_position(node, vertices[index + 1]),
					color,
					1.0
			)


func _draw_sprite_bounds(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return

	var origin := _get_sprite_texture_origin(sprite)
	var texture_size := sprite.texture.get_size()
	var points := [
		origin,
		origin + Vector2(texture_size.x, 0.0),
		origin + texture_size,
		origin + Vector2(0.0, texture_size.y),
	]

	for index: int in points.size():
		_overlay.draw_line(
				_node_to_editor_position(sprite, points[index]),
				_node_to_editor_position(sprite, points[(index + 1) % points.size()]),
				SPRITE_BOUNDS_COLOR,
				1.0
			)


func _draw_animated_sprite_bounds(animated_sprite: AnimatedSprite2D) -> void:
	var texture := _get_animated_sprite_texture(animated_sprite)
	if texture == null:
		return

	var origin := animated_sprite.offset
	if animated_sprite.centered:
		origin -= texture.get_size() * 0.5

	var texture_size := texture.get_size()
	var points := [
		origin,
		origin + Vector2(texture_size.x, 0.0),
		origin + texture_size,
		origin + Vector2(0.0, texture_size.y),
	]

	for index: int in points.size():
		_overlay.draw_line(
				_node_to_editor_position(animated_sprite, points[index]),
				_node_to_editor_position(animated_sprite, points[(index + 1) % points.size()]),
				SPRITE_BOUNDS_COLOR,
				1.0
		)


func _get_animated_sprite_texture(animated_sprite: AnimatedSprite2D) -> Texture2D:
	if animated_sprite.sprite_frames == null:
		return null

	var animation := animated_sprite.animation
	if not animated_sprite.sprite_frames.has_animation(animation):
		return null

	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation)
	if frame_count == 0:
		return null

	return animated_sprite.sprite_frames.get_frame_texture(animation, clampi(animated_sprite.frame, 0, frame_count - 1))


func _draw_layer_transform_overlay(node: Node2D) -> void:
	_draw_layer_origin(node)

	if not _dragging_layer_transform:
		return

	if _layer_transform_mode == RigMode.ROTATE_LAYER or _layer_transform_mode == RigMode.SCALE_LAYER:
		var origin := _canvas_to_editor_position(_layer_transform_start_origin)
		var mouse_position := _canvas_to_editor_position(_layer_transform_current_mouse)
		_overlay.draw_line(origin, mouse_position, LAYER_GUIDE_COLOR, 1.0)


func _draw_layer_origin(node: Node2D) -> void:
	_overlay.draw_circle(_canvas_to_editor_position(_get_node_canvas_origin(node)), HANDLE_RADIUS, LAYER_ORIGIN_COLOR)


func _get_node_canvas_origin(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func _change_node_pivot(node: Node2D, canvas_origin: Vector2) -> void:
	if not is_instance_valid(node) or not execute_layer_command.is_valid():
		return
	var transform := node.get_global_transform_with_canvas()
	if is_zero_approx(transform.determinant()):
		return
	var pivot := _snap_pixel_position(transform.affine_inverse() * canvas_origin)
	var id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	execute_layer_command.call(TwberSetPivot.new(id, pivot))


func _set_node_canvas_origin(node: Node2D, canvas_origin: Vector2) -> void:
	var parent := node.get_parent() as CanvasItem
	var position := canvas_origin
	if parent != null:
		var transform := parent.get_global_transform_with_canvas()
		if is_zero_approx(transform.determinant()):
			return
		position = transform.affine_inverse() * canvas_origin
	edit_pose({"position": _snap_pixel_position(position)})


func _get_mode() -> int:
	if _transform_button.button_pressed:
		return RigMode.TRANSFORM_LAYER
	if _rotate_button.button_pressed:
		return RigMode.ROTATE_LAYER
	if _scale_button.button_pressed:
		return RigMode.SCALE_LAYER
	if _change_pivot_button.button_pressed:
		return RigMode.CHANGE_PIVOT
	if _deform_button.button_pressed:
		return RigMode.DEFORM_VERTEX
	if _rectangle_select_button.button_pressed:
		return RigMode.RECTANGLE_SELECT
	if _lasso_select_button.button_pressed:
		return RigMode.LASSO_SELECT
	if _reset_vertex_button.button_pressed:
		return RigMode.RESET_VERTEX

	return RigMode.TRANSFORM_LAYER


func _on_model_node_imported(node: Node2D) -> void:
	_remember_initial_layer_state(node)


func _on_model_node_selected() -> void:
	cancel_pose_draft()
	_clear_vertex_selection()
	_stop_pointer_interaction()
	if _selected_node == null:
		_hide_inspector()
	else:
		_refresh_inspector()
	_refresh_parameter_panel()
	_queue_overlay_redraw()


func _queue_overlay_redraw() -> void:
	super._queue_overlay_redraw()
	if _model_root == null:
		return
	var renderer := TwberModelBatchRenderer2D.find_on(_model_root)
	if renderer is TwberModelBatchRenderer2D:
		var dirty_nodes: Array[Node2D] = []
		var seen_node_ids := {}
		if _selected_node != null:
			dirty_nodes.append(_selected_node)
			seen_node_ids[_selected_node.get_instance_id()] = true
		var layer_nodes := _parameter_evaluator.get_layer_nodes()
		for layer_id: Variant in _previewed_layer_ids:
			var node := layer_nodes.get(String(layer_id)) as Node2D
			if node == null or seen_node_ids.has(node.get_instance_id()):
				continue
			seen_node_ids[node.get_instance_id()] = true
			dirty_nodes.append(node)
		if not dirty_nodes.is_empty():
			renderer.update_dynamic_geometry_for_nodes(dirty_nodes)


func cancel_pose_draft() -> bool:
	var cancelled := pose_draft.cancel() if pose_draft != null else false
	_stop_pointer_interaction()
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
	var parameter := _get_selected_parameter()
	return pose_draft.begin(_selected_node, {
		"mode": "rig", "parameter_id": parameter.id if parameter != null else "",
		"coordinate": _get_parameter_preview_coordinate(parameter) if parameter != null else Vector2.ZERO,
		"values": _parameter_preview_values,
		"snap": {"pixels": _is_pixel_snap_enabled(), "rotation": deg_to_rad(_editor_settings.rotation_snap_degrees), "scale": TwberEditorSettings.SCALE_SNAP_STEP},
	})


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stop_pointer_interaction()
