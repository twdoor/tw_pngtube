class_name EditorRigger extends HSplitContainer

const TREE_COLUMN := 0
const ROOT_LAYER_ID := 0
const INVALID_LAYER_ID := -1
const MODEL_ROOT_NAME := "Textures"
const HANDLE_RADIUS := 5.0
const HANDLE_HIT_RADIUS := 12.0
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
@onready var _tree: Tree = %Tree
@onready var _inspector: PanelContainer = %Inspector
@onready var _visible_check_box: CheckBox = %VisibleCheckBox
@onready var _opacity_slider: HSlider = %OpacitySlider
@onready var _animation_frame_rate: SpinBox = %AnimationFrameRate
@onready var _animations_box: Control = %AnimationsBox
@onready var _animations_option_button: OptionButton = %AnimationsOptionButton
@onready var _edit_panel: Control = $Panel
@export var _preview_layer: CanvasLayer

var _root_item: TreeItem
var _model_root: Node2D
var _selected_layer_id := INVALID_LAYER_ID
var _selected_node: Node2D
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
var _overlay: Control
var _layers_by_id: Dictionary = {}
var _root_layer_ids: Array[int] = []
var _tree_items_by_id: Dictionary = {}
var _initial_layer_states_by_node_id: Dictionary = {}
var _next_item_id := 1
var _updating_inspector := false


func _ready() -> void:
	_transform_button.button_pressed = true
	_reset_layer_button.pressed.connect(_on_reset_layer_button_pressed)
	_visible_check_box.toggled.connect(_on_visible_check_box_toggled)
	_opacity_slider.value_changed.connect(_on_opacity_slider_value_changed)
	_animation_frame_rate.value_changed.connect(_on_animation_frame_rate_value_changed)
	_animations_option_button.item_selected.connect(_on_animation_selected)

	_tree.clear()
	_tree.columns = 1
	_tree.hide_root = true
	_tree.set_column_expand(TREE_COLUMN, true)
	_tree.item_selected.connect(_on_tree_item_selected)
	_setup_overlay()

	_setup_preview()
	_hide_inspector()
	reload_from_preview()
	set_process(true)


func _process(_delta: float) -> void:
	if visible:
		_queue_overlay_redraw()


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

	if _selected_node != null:
		_draw_layer_transform_overlay(_selected_node)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if not visible or _model_root == null:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event, _overlay_local_to_viewport(event.position))
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event, _overlay_local_to_viewport(event.position))


func reload_from_preview(selected_node: Node2D = null) -> void:
	var node_to_select := selected_node
	if node_to_select == null:
		node_to_select = _selected_node

	_layers_by_id.clear()
	_root_layer_ids.clear()
	_tree_items_by_id.clear()
	_next_item_id = 1

	if _model_root != null:
		_import_model_children(_model_root, ROOT_LAYER_ID, _root_layer_ids)

	_rebuild_tree()

	if node_to_select != null:
		_select_node(node_to_select)
	elif _selected_layer_id != INVALID_LAYER_ID:
		_set_selected_layer(_selected_layer_id)
	else:
		_set_selected_layer(INVALID_LAYER_ID)


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
		mesh_sprite.set_deformed_vertex(vertex_index, start_position + drag_offset)
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
	_update_layer_transform(canvas_position)


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
				_selected_node.rotation = _layer_transform_start_rotation + mouse_offset.angle() - _layer_transform_start_mouse_angle
		RigMode.SCALE_LAYER:
			var mouse_distance := maxf((canvas_position - _layer_transform_start_origin).length(), MIN_LAYER_SCALE_DISTANCE)
			var scale_factor := mouse_distance / _layer_transform_start_mouse_distance
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
	var color := canvas_item.self_modulate
	color.a = value
	canvas_item.self_modulate = color
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
	_opacity_slider.value = _selected_node.self_modulate.a
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


func _reset_layer_to_initial_state(node: Node2D) -> void:
	var state := _get_initial_layer_state(node)
	node.position = state["position"]
	node.rotation = state["rotation"]
	node.scale = state["scale"]
	node.visible = state["visible"]
	node.self_modulate = state["self_modulate"]
	_restore_layer_content_state(node, state)

	if node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		mesh_sprite.reset_deformation()
		mesh_sprite.sync_visual_state()


func _remember_initial_layer_state(node: Node2D) -> void:
	var node_id := node.get_instance_id()
	if _initial_layer_states_by_node_id.has(node_id):
		return

	_initial_layer_states_by_node_id[node_id] = {
		"position": node.position,
		"rotation": node.rotation,
		"scale": node.scale,
		"visible": node.visible,
		"self_modulate": node.self_modulate,
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
	elif node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		if mesh_sprite.mesh_data != null:
			mesh_sprite.mesh_data.ensure_rest_vertices()
			state["mesh_texture_origin"] = mesh_sprite.mesh_data.texture_origin
			state["mesh_vertices"] = mesh_sprite.mesh_data.vertices.duplicate()
			state["mesh_rest_vertices"] = mesh_sprite.mesh_data.rest_vertices.duplicate()
			state["mesh_uvs"] = mesh_sprite.mesh_data.uvs.duplicate()

	return state


func _restore_layer_content_state(node: Node2D, state: Dictionary) -> void:
	var content: Dictionary = state.get("content", {})
	if node is Sprite2D and content.has("sprite_offset"):
		var sprite: Sprite2D = node
		sprite.offset = content["sprite_offset"]
	elif node is AnimatedSprite2D and content.has("animated_offset"):
		var animated_sprite: AnimatedSprite2D = node
		animated_sprite.offset = content["animated_offset"]
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


func _find_vertex_at_canvas_position(mesh_sprite: TwberMeshSprite2D, canvas_position: Vector2) -> int:
	if mesh_sprite.mesh_data == null:
		return -1

	var editor_position := _canvas_to_editor_position(canvas_position)
	var best_index := -1
	var best_distance := HANDLE_HIT_RADIUS
	for index: int in mesh_sprite.mesh_data.vertices.size():
		var vertex_position := _node_to_editor_position(mesh_sprite, mesh_sprite.mesh_data.vertices[index])
		var distance := editor_position.distance_to(vertex_position)
		if distance <= best_distance:
			best_distance = distance
			best_index = index

	return best_index


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


func _get_sprite_texture_origin(sprite: Sprite2D) -> Vector2:
	if sprite.texture == null:
		return sprite.offset

	var origin := sprite.offset
	if sprite.centered:
		origin -= sprite.texture.get_size() * 0.5

	return origin


func _node_to_editor_position(node: Node2D, local_position: Vector2) -> Vector2:
	return _canvas_to_editor_position(node.get_global_transform_with_canvas() * local_position)


func _viewport_to_node_position(node: Node2D, viewport_position: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas().affine_inverse() * viewport_position


func _get_node_canvas_origin(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func _change_node_pivot(node: Node2D, canvas_origin: Vector2) -> void:
	var old_transform := node.get_global_transform_with_canvas()
	var next_transform := old_transform
	next_transform.origin = canvas_origin
	var local_shift := next_transform.affine_inverse() * old_transform.origin

	_set_node_canvas_origin(node, canvas_origin)
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


func _set_node_canvas_origin(node: Node2D, canvas_origin: Vector2) -> void:
	var parent := node.get_parent()
	if parent is CanvasItem:
		var parent_item: CanvasItem = parent
		node.position = parent_item.get_global_transform_with_canvas().affine_inverse() * canvas_origin
	else:
		node.global_position = canvas_origin


func _canvas_to_editor_position(canvas_position: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas().affine_inverse() * canvas_position


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


func _overlay_local_to_viewport(local_position: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas() * local_position


func _queue_overlay_redraw() -> void:
	if _overlay != null:
		_overlay.queue_redraw()
	queue_redraw()


func _setup_preview() -> void:
	if _preview_layer == null:
		push_warning("EditorRigger needs a preview CanvasLayer.")
		return

	var existing_node := _preview_layer.get_node_or_null(MODEL_ROOT_NAME)
	if existing_node is Node2D:
		_model_root = existing_node
	else:
		push_warning("EditorRigger needs a Node2D named %s in the preview layer." % MODEL_ROOT_NAME)


func _import_model_children(parent_node: Node, parent_id: int, child_ids: Array) -> void:
	for child: Node in parent_node.get_children():
		if child is not Node2D:
			continue

		var layer_id := _next_item_id
		_next_item_id += 1
		_remember_initial_layer_state(child)
		_layers_by_id[layer_id] = {
			"id": layer_id,
			"name": child.name,
			"parent_id": parent_id,
			"children": [],
			"node": child,
		}
		child_ids.append(layer_id)

		var layer: Dictionary = _layers_by_id[layer_id]
		_import_model_children(child, layer_id, layer["children"])


func _rebuild_tree() -> void:
	var collapsed_state := _get_tree_collapsed_state()
	_tree.clear()
	_tree_items_by_id.clear()
	_root_item = _tree.create_item()
	_add_layer_items(_root_item, _root_layer_ids, collapsed_state)


func _add_layer_items(parent_item: TreeItem, layer_ids: Array, collapsed_state: Dictionary) -> void:
	for layer_id: int in layer_ids:
		var layer: Dictionary = _layers_by_id[layer_id]
		var item := _tree.create_item(parent_item)
		item.set_text(TREE_COLUMN, layer["name"])
		item.set_metadata(TREE_COLUMN, layer_id)
		if collapsed_state.has(layer_id):
			item.set_collapsed(collapsed_state[layer_id])
		_tree_items_by_id[layer_id] = item
		_add_layer_items(item, layer["children"], collapsed_state)


func _on_tree_item_selected() -> void:
	_set_selected_layer(_get_layer_id_from_item(_tree.get_selected()))


func _set_selected_layer(layer_id: int) -> void:
	if not _layers_by_id.has(layer_id):
		_selected_layer_id = INVALID_LAYER_ID
		_selected_node = null
		_clear_vertex_selection()
		_stop_pointer_interaction()
		_hide_inspector()
		_queue_overlay_redraw()
		return

	_selected_layer_id = layer_id
	var layer: Dictionary = _layers_by_id[layer_id]
	_selected_node = layer["node"]
	_clear_vertex_selection()
	_stop_pointer_interaction()
	_refresh_inspector()
	_queue_overlay_redraw()


func _select_node(node: Node2D) -> void:
	var layer_id := _get_layer_id_for_node(node)
	if layer_id == INVALID_LAYER_ID:
		_set_selected_layer(INVALID_LAYER_ID)
		return

	if _tree_items_by_id.has(layer_id):
		_tree.deselect_all()
		var item: TreeItem = _tree_items_by_id[layer_id]
		item.select(TREE_COLUMN)
	_set_selected_layer(layer_id)


func _get_layer_id_for_node(node: Node2D) -> int:
	for layer_id: int in _layers_by_id.keys():
		var layer: Dictionary = _layers_by_id[layer_id]
		if layer["node"] == node:
			return layer_id

	return INVALID_LAYER_ID


func _get_tree_collapsed_state() -> Dictionary:
	var collapsed_state := {}
	for layer_id: int in _tree_items_by_id.keys():
		var item: TreeItem = _tree_items_by_id[layer_id]
		if item != null:
			collapsed_state[layer_id] = item.is_collapsed()

	return collapsed_state


func _get_layer_id_from_item(item: TreeItem) -> int:
	if item == null:
		return INVALID_LAYER_ID

	var layer_id: Variant = item.get_metadata(TREE_COLUMN)
	if layer_id is int and _layers_by_id.has(layer_id):
		return layer_id

	return INVALID_LAYER_ID
