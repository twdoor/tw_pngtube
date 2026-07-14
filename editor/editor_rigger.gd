class_name EditorRigger extends EditorModelTree

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
var _parameter_evaluator := TwberParameterEvaluator.new()


func _ready() -> void:
	_transform_button.button_pressed = true
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

	_initialize_model_tree()
	_setup_overlay()
	reload_from_preview()


func reload_from_preview(selected_node: Node2D = null) -> void:
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
	for vertex_index: int in _selected_vertex_indices:
		if not _drag_start_vertices.has(vertex_index):
			continue

		var start_position: Vector2 = _drag_start_vertices[vertex_index]
		var next_position := _snap_mesh_position(mesh_sprite, start_position + drag_offset)
		mesh_sprite.set_deformed_vertex(vertex_index, next_position)
	_queue_overlay_redraw()
	_overlay.accept_event()


func _begin_layer_transform_at(canvas_position: Vector2, mode: int) -> void:
	if _selected_node == null:
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
	if _selected_node == null:
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
				_selected_node.rotation = wrapf(next_rotation, -PI, PI)
		RigMode.SCALE_LAYER:
			var mouse_distance := maxf((canvas_position - _layer_transform_start_origin).length(), MIN_LAYER_SCALE_DISTANCE)
			var scale_factor := _snap_scale_factor(
					mouse_distance / _layer_transform_start_mouse_distance,
			)
			_selected_node.scale = _layer_transform_start_scale * scale_factor

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

	_set_vertex_selection(vertices_to_reset)
	for selected_vertex_index: int in vertices_to_reset:
		mesh_sprite.reset_deformed_vertex(selected_vertex_index)
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
	if _selected_node == null:
		return

	_reset_layer_to_initial_state(_selected_node)
	_clear_vertex_selection()
	_stop_pointer_interaction()
	_refresh_inspector()
	_queue_overlay_redraw()


func _on_opacity_slider_value_changed(value: float) -> void:
	if _updating_inspector or _selected_node == null:
		return

	var canvas_item: CanvasItem = _selected_node
	var color := TwberAlphaClipController.get_authored_self_modulate(canvas_item)
	color.a = value
	TwberAlphaClipController.set_authored_self_modulate(canvas_item, color)
	if canvas_item is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = canvas_item
		mesh_sprite.sync_visual_state()


func _on_visible_check_box_toggled(enabled: bool) -> void:
	if _updating_inspector or _selected_node == null:
		return

	_selected_node.visible = enabled
	_queue_overlay_redraw()


func _on_animation_frame_rate_value_changed(value: float) -> void:
	if _updating_inspector:
		return

	var animated_sprite := _get_selected_animated_sprite()
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var animation := _get_animated_sprite_animation(animated_sprite)
	if not animated_sprite.sprite_frames.has_animation(animation):
		return

	animated_sprite.sprite_frames.set_animation_speed(animation, value)


func _on_animation_selected(index: int) -> void:
	if _updating_inspector:
		return

	var animated_sprite := _get_selected_animated_sprite()
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var selected_animation := _get_animation_name_from_option(index)
	if selected_animation == &"" or not animated_sprite.sprite_frames.has_animation(selected_animation):
		return

	animated_sprite.animation = selected_animation
	animated_sprite.play(selected_animation)
	_refresh_inspector()


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

	for child: Node in _parameter_list.get_children():
		_parameter_list.remove_child(child)
		child.queue_free()

	_parameter_value_controls.clear()
	_parameter_select_buttons.clear()

	var parameters := _get_model_parameters()
	_sync_parameter_preview_values(parameters)
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
	header.add_theme_constant_override("separation", 4)
	content.add_child(header)

	var select_button := Button.new()
	select_button.custom_minimum_size = Vector2(48.0, 28.0)
	select_button.toggle_mode = true
	select_button.text = _get_parameter_type_label(parameter.value_type).to_upper()
	select_button.tooltip_text = _get_parameter_position_count_text(parameter)
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
	name_edit.text_changed.connect(func(text_value: String) -> void:
		parameter.name = text_value.strip_edges()
		_set_model_parameters(_get_model_parameters())
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

	if parameter.value_type != TwberParameterResource.ValueType.BOOL:
		content.add_child(_create_parameter_range_editor(parameter))

	var value_control := _create_parameter_value_control(parameter)
	content.add_child(value_control)
	_parameter_value_controls[parameter.id] = value_control
	return card


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
		parameter.min_value = minf(value, upper_limit)
	else:
		var lower_limit := parameter.get_scalar_min()
		var highest_bound: Variant = _get_bound_component_extreme(parameter, 0, false)
		if highest_bound != null:
			lower_limit = maxf(lower_limit, float(highest_bound))
		parameter.max_value = maxf(value, lower_limit)

	minimum_edit.set_value_no_signal(parameter.get_scalar_min())
	maximum_edit.set_value_no_signal(parameter.get_scalar_max())
	_update_scalar_range_spin_limits(parameter, minimum_edit, maximum_edit)
	_finish_parameter_range_change(parameter)


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

	parameter.min_vector2 = range_min
	parameter.max_vector2 = range_max
	minimum_edit.set_value_no_signal(range_min[axis])
	maximum_edit.set_value_no_signal(range_max[axis])
	_update_vector_range_spin_limits(parameter, axis, minimum_edit, maximum_edit)
	_finish_parameter_range_change(parameter)


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
	if not found:
		return null
	return extreme


func _finish_parameter_range_change(parameter: TwberParameterResource) -> void:
	var current_value: Variant = _parameter_preview_values.get(
			parameter.id,
			parameter.get_default_value(),
	)
	_parameter_preview_values[parameter.id] = parameter.value_from_coordinate(
			parameter.coordinate_from_value(current_value),
	)
	_selected_parameter_id = parameter.id
	_update_parameter_selection()
	_update_parameter_control(parameter)
	_refresh_position_buttons()
	_set_model_parameters(_get_model_parameters())
	if visible:
		preview_parameters()


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
	var parameter := TwberParameterResource.new()
	parameter.value_type = value_type as TwberParameterResource.ValueType
	_configure_new_parameter(parameter)

	var parameters := _get_model_parameters()
	parameters.append(parameter)
	_set_model_parameters(parameters)
	_parameter_preview_values[parameter.id] = parameter.get_default_value()
	_selected_parameter_id = parameter.id
	_refresh_parameter_panel()
	preview_parameters()


func _configure_new_parameter(parameter: TwberParameterResource) -> void:
	match parameter.value_type:
		TwberParameterResource.ValueType.BOOL:
			parameter.id = _make_unique_parameter_id("bool")
			parameter.name = _make_unique_parameter_name("Bool")
			parameter.min_value = 0.0
			parameter.max_value = 1.0
			parameter.step = TwberParameterResource.DISCRETE_STEP
			parameter.default_bool = false
		TwberParameterResource.ValueType.INT:
			parameter.id = _make_unique_parameter_id("int")
			parameter.name = _make_unique_parameter_name("Int")
			parameter.min_value = 0.0
			parameter.max_value = 10.0
			parameter.step = TwberParameterResource.DISCRETE_STEP
			parameter.default_int = 0
		TwberParameterResource.ValueType.VECTOR2:
			parameter.id = _make_unique_parameter_id("vector")
			parameter.name = _make_unique_parameter_name("Vector")
			parameter.min_vector2 = Vector2(-1.0, -1.0)
			parameter.max_vector2 = Vector2(1.0, 1.0)
			parameter.step = TwberParameterResource.CONTINUOUS_STEP
			parameter.default_vector2 = Vector2.ZERO
		_:
			parameter.id = _make_unique_parameter_id("float")
			parameter.name = _make_unique_parameter_name("Float")
			parameter.min_value = 0.0
			parameter.max_value = 1.0
			parameter.step = TwberParameterResource.CONTINUOUS_STEP
			parameter.default_float = 0.0


func _delete_parameter(parameter_id: String) -> void:
	var parameters := _get_model_parameters()
	for index: int in range(parameters.size() - 1, -1, -1):
		if parameters[index].id == parameter_id:
			parameters.remove_at(index)

	_parameter_preview_values.erase(parameter_id)
	if _selected_parameter_id == parameter_id:
		_selected_parameter_id = ""

	_set_model_parameters(parameters)
	_refresh_parameter_panel()
	preview_parameters()


func _on_bind_position_button_pressed() -> void:
	var parameter := _get_selected_parameter()
	var layer_id := _get_selected_model_layer_id()
	if parameter == null or _selected_node == null or layer_id.is_empty():
		return

	# The object currently contains the contributions from every active parameter,
	# plus the user's edits. Store only the selected parameter's contribution so
	# unrelated visibility, transform, colour, and mesh changes are not baked into it.
	var edited_state := TwberLayerStateResource.new()
	edited_state.capture_from_node(_selected_node)
	restore_parameter_preview_base()
	_reset_layer_to_initial_state(_selected_node, false)

	var base_state := TwberLayerStateResource.new()
	base_state.capture_from_node(_selected_node)
	var other_affected_layer_ids := _apply_parameter_preview_values(parameter.id)
	for affected_layer_id: String in other_affected_layer_ids:
		_previewed_layer_ids[affected_layer_id] = true
	var clip_controller := TwberAlphaClipController.attach_to(_model_root)
	clip_controller.sync_now(other_affected_layer_ids)

	var other_parameters_state := TwberLayerStateResource.new()
	other_parameters_state.capture_from_node(_selected_node)
	var isolated_state := TwberLayerStateResource.isolate_contribution(
			base_state,
			edited_state,
			other_parameters_state,
	)
	if isolated_state == null:
		preview_parameters()
		return

	var coordinate := _get_parameter_preview_coordinate(parameter)
	var parameter_position := parameter.find_position(coordinate)
	if parameter_position == null:
		parameter_position = TwberParameterPositionResource.new()
		parameter_position.coordinate = coordinate
		parameter.positions.append(parameter_position)

	parameter_position.upsert_state(isolated_state)
	_set_model_parameters(_get_model_parameters())
	_refresh_parameter_panel()
	preview_parameters()


func _on_remove_position_button_pressed() -> void:
	var parameter := _get_selected_parameter()
	var layer_id := _get_selected_model_layer_id()
	if parameter == null or layer_id.is_empty():
		return

	var parameter_position := parameter.find_position(
			_get_parameter_preview_coordinate(parameter),
	)
	if parameter_position == null or not parameter_position.remove_state(layer_id):
		return

	if parameter_position.layer_states.is_empty():
		parameter.positions.erase(parameter_position)

	_set_model_parameters(_get_model_parameters())
	_refresh_parameter_panel()
	preview_parameters()


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
	if not visible:
		return
	restore_parameter_preview_base()
	if _model_root != null:
		var affected_layer_ids := _apply_parameter_preview_values()
		for layer_id: String in affected_layer_ids:
			_previewed_layer_ids[layer_id] = true
		var clip_controller := TwberAlphaClipController.attach_to(_model_root)
		clip_controller.sync_now(affected_layer_ids)

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


func _make_unique_parameter_id(prefix: String) -> String:
	var index := 1
	while true:
		var parameter_id := "%s_%03d" % [prefix, index]
		if _find_parameter_by_id(parameter_id) == null:
			return parameter_id
		index += 1

	return prefix


func _make_unique_parameter_name(prefix: String) -> String:
	var existing_names := {}
	for parameter: TwberParameterResource in _get_model_parameters():
		existing_names[parameter.name] = true

	var index := 1
	while true:
		var parameter_name := "%s %d" % [prefix, index]
		if not existing_names.has(parameter_name):
			return parameter_name
		index += 1

	return prefix


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

	_initial_layer_states_by_node_id[node_id] = {
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
	var old_transform := node.get_global_transform_with_canvas()
	var local_pivot := old_transform.affine_inverse() * canvas_origin
	local_pivot = _snap_pixel_position(local_pivot)
	var snapped_canvas_origin := old_transform * local_pivot
	var next_transform := old_transform
	next_transform.origin = snapped_canvas_origin
	var local_shift := next_transform.affine_inverse() * old_transform.origin

	_set_node_canvas_origin(node, snapped_canvas_origin, false)
	_shift_node_local_content(node, local_shift)


func _shift_node_local_content(node: Node2D, local_shift: Vector2) -> void:
	if node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		mesh_sprite.shift_local_geometry(local_shift)
	elif node is Sprite2D:
		var sprite: Sprite2D = node
		sprite.offset += local_shift
	elif node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = node
		animated_sprite.offset += local_shift

	for child: Node in node.get_children():
		if child is Node2D:
			child.position += local_shift


func _set_node_canvas_origin(
		node: Node2D,
		canvas_origin: Vector2,
		snap_to_grid := true,
) -> void:
	var parent := node.get_parent()
	if parent is CanvasItem:
		var parent_item: CanvasItem = parent
		var local_position := (
				parent_item.get_global_transform_with_canvas().affine_inverse()
				* canvas_origin
		)
		node.position = _snap_pixel_position(local_position) if snap_to_grid else local_position
	else:
		node.global_position = (
				_snap_pixel_position(canvas_origin) if snap_to_grid else canvas_origin
		)


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
