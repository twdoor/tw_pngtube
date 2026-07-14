class_name EditorMesher extends EditorModelTree

signal model_tree_changed

const EDGE_HIT_RADIUS := 12.0
const TRIANGLE_COLOR := Color(0.19, 0.75, 1.0, 0.8)
const EDGE_COLOR := Color(0.9, 0.95, 1.0, 0.75)
const CUT_EDGE_COLOR := Color(1.0, 0.28, 0.2, 0.95)
const JOIN_EDGE_COLOR := Color(0.42, 1.0, 0.5, 0.95)
const HANDLE_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const SELECTED_HANDLE_COLOR := Color(1.0, 0.78, 0.22, 1.0)
const SELECTION_STROKE_COLOR := Color(1.0, 0.78, 0.22, 0.95)
const SELECTION_FILL_COLOR := Color(1.0, 0.78, 0.22, 0.16)
const SOURCE_TEXTURE_COLOR := Color(1.0, 1.0, 1.0, 0.42)
const UNSUPPORTED_COLOR := Color(1.0, 0.35, 0.25, 0.75)
const LASSO_MIN_POINT_DISTANCE := 4.0
const VISIBLE_PIXEL_ALPHA_THRESHOLD := 0.01

enum MeshMode {
	ADD_POINT,
	REMOVE_POINT,
	EDIT_POINT,
	RECTANGLE_SELECT,
	LASSO_SELECT,
	CUT_EDGE,
	JOIN_EDGE,
}

@onready var _add_point_button: Button = %AddPointButton
@onready var _remove_point_button: Button = %RemovePointButton
@onready var _rectangle_select_button: Button = %RectangleSelectButton
@onready var _lasso_select_button: Button = %LassoSelectButton
@onready var _cut_button: Button = %CutButton
@onready var _join_button: Button = %JoinButton
@onready var _fast_mesh_button: Button = %FastMeshButton
@onready var _horizontal_vertices: SpinBox = %HorizontalVertices
@onready var _vertical_vertices: SpinBox = %VerticalVertices
@onready var _fast_mesh_dialog: ConfirmationDialog = %FastMeshDialog
@onready var _edit_panel: Control = $Panel

var _selected_vertex_indices: Array[int] = []
var _join_first_vertex_index := -1
var _dragging_vertex := false
var _holding_remove := false
var _holding_cut := false
var _drag_start_position := Vector2.ZERO
var _drag_start_vertices := {}
var _selecting_vertices := false
var _selection_additive := false
var _selection_mode := MeshMode.RECTANGLE_SELECT
var _selection_start_position := Vector2.ZERO
var _selection_current_position := Vector2.ZERO
var _lasso_points := PackedVector2Array()


func _ready() -> void:
	_add_point_button.button_pressed = true
	_fast_mesh_button.pressed.connect(_on_fast_mesh_button_pressed)
	_fast_mesh_dialog.confirmed.connect(_on_generate_grid_button_pressed)
	_initialize_model_tree()
	_setup_overlay()
	reload_from_preview()


func _setup_overlay() -> void:
	_edit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_panel.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	_overlay = Control.new()
	_overlay.name = "MeshOverlay"
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
	else:
		_draw_unsupported_marker(_selected_node)


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
		_stop_pointer_actions()
		if _selecting_vertices:
			_finish_vertex_selection()
		_overlay.accept_event()
		return

	var mode := _get_mode()
	if mode != MeshMode.JOIN_EDGE:
		_join_first_vertex_index = -1

	match mode:
		MeshMode.ADD_POINT:
			_add_point_at(viewport_position)
		MeshMode.REMOVE_POINT:
			_holding_remove = true
			_remove_point_at(viewport_position)
		MeshMode.EDIT_POINT:
			_begin_edit_point_at(viewport_position, event.shift_pressed)
		MeshMode.RECTANGLE_SELECT:
			_begin_rectangle_selection(viewport_position, event.shift_pressed)
		MeshMode.LASSO_SELECT:
			_begin_lasso_selection(viewport_position, event.shift_pressed)
		MeshMode.CUT_EDGE:
			_holding_cut = true
			_cut_edge_at(viewport_position)
		MeshMode.JOIN_EDGE:
			_join_edge_at(viewport_position)

	_overlay.accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion, viewport_position: Vector2) -> void:
	if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_stop_pointer_actions()
		_selecting_vertices = false
		return

	if not (_selected_node is TwberMeshSprite2D):
		return

	if _dragging_vertex:
		var mesh_sprite: TwberMeshSprite2D = _selected_node
		var drag_offset := _viewport_to_node_position(mesh_sprite, viewport_position) - _drag_start_position
		for vertex_index: int in _selected_vertex_indices:
			if not _drag_start_vertices.has(vertex_index):
				continue
			var previous_position: Vector2 = mesh_sprite.get_vertex(vertex_index)
			var start_position: Vector2 = _drag_start_vertices[vertex_index]
			var next_position := _snap_mesh_position(mesh_sprite, start_position + drag_offset)
			if not next_position.is_equal_approx(previous_position):
				mesh_sprite.set_vertex(vertex_index, next_position)
				_shift_parameter_mesh_vertex_states(mesh_sprite, vertex_index, next_position - previous_position)
		_queue_overlay_redraw()
		_overlay.accept_event()
	elif _selecting_vertices:
		_update_vertex_selection(viewport_position)
		_overlay.accept_event()
	elif _holding_remove:
		_remove_point_at(viewport_position)
		_overlay.accept_event()
	elif _holding_cut:
		_cut_edge_at(viewport_position)
		_overlay.accept_event()


func _stop_pointer_actions() -> void:
	_dragging_vertex = false
	_holding_remove = false
	_holding_cut = false
	_drag_start_vertices.clear()


func _reset_interaction_state() -> void:
	_stop_pointer_actions()
	_selected_vertex_indices.clear()
	_join_first_vertex_index = -1
	_selecting_vertices = false
	_lasso_points = PackedVector2Array()


func _add_point_at(canvas_position: Vector2) -> void:
	var was_plain_sprite := _selected_node is Sprite2D
	var mesh_sprite := _ensure_selected_mesh_sprite()
	if mesh_sprite == null:
		return

	var vertex_position := _snap_mesh_position(
			mesh_sprite,
			_viewport_to_node_position(mesh_sprite, canvas_position),
	)
	mesh_sprite.add_vertex(vertex_position)
	_selected_node = mesh_sprite
	_set_vertex_selection([mesh_sprite.get_vertex_count() - 1])
	_insert_parameter_mesh_vertex_states(mesh_sprite, mesh_sprite.get_vertex_count() - 1)

	if was_plain_sprite:
		model_tree_changed.emit()
		reload_from_preview(mesh_sprite)
	else:
		_queue_overlay_redraw()


func _remove_point_at(canvas_position: Vector2) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var vertex_index := _find_vertex_at_canvas_position(mesh_sprite, canvas_position)
	if vertex_index == -1:
		return

	_join_first_vertex_index = -1
	mesh_sprite.remove_vertex(vertex_index)
	_remove_parameter_mesh_vertex_states(mesh_sprite, vertex_index)
	if mesh_sprite.get_vertex_count() == 0:
		_holding_remove = false
		var sprite := _convert_mesh_to_sprite(mesh_sprite)
		model_tree_changed.emit()
		reload_from_preview(sprite)
		return

	_set_vertex_selection([mini(vertex_index, mesh_sprite.get_vertex_count() - 1)])
	_queue_overlay_redraw()


func _begin_edit_point_at(canvas_position: Vector2, additive_selection: bool) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var vertex_index := _find_vertex_at_canvas_position(mesh_sprite, canvas_position)
	if vertex_index == -1:
		if not additive_selection:
			_selected_vertex_indices.clear()
		_dragging_vertex = false
		_queue_overlay_redraw()
		return

	if additive_selection:
		_toggle_vertex_selection(vertex_index)
		_dragging_vertex = false
	else:
		_begin_vertex_drag(mesh_sprite, vertex_index, canvas_position)
	_queue_overlay_redraw()


func _cut_edge_at(canvas_position: Vector2) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var edge := _find_edge_at_canvas_position(mesh_sprite, canvas_position)
	if edge.is_empty():
		return

	mesh_sprite.cut_edge(int(edge[0]), int(edge[1]))
	_selected_vertex_indices.clear()
	_queue_overlay_redraw()


func _join_edge_at(canvas_position: Vector2) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var vertex_index := _find_vertex_at_canvas_position(mesh_sprite, canvas_position)
	if vertex_index == -1:
		return

	if _join_first_vertex_index == -1:
		_join_first_vertex_index = vertex_index
		_set_vertex_selection([vertex_index])
		_queue_overlay_redraw()
		return

	if _join_first_vertex_index == vertex_index:
		_join_first_vertex_index = -1
		_set_vertex_selection([vertex_index])
		_queue_overlay_redraw()
		return

	mesh_sprite.join_edge(_join_first_vertex_index, vertex_index)
	_set_vertex_selection([vertex_index])
	_join_first_vertex_index = -1
	_queue_overlay_redraw()


func _ensure_selected_mesh_sprite() -> TwberMeshSprite2D:
	if _selected_node is TwberMeshSprite2D:
		return _selected_node

	if _selected_node is Sprite2D:
		return _convert_sprite_to_mesh(_selected_node)

	return null


func _convert_sprite_to_mesh(sprite: Sprite2D) -> TwberMeshSprite2D:
	var mesh_sprite := TwberMeshSprite2D.new()
	mesh_sprite.texture = sprite.texture
	mesh_sprite.mesh_data = TwberMeshResource.new()
	mesh_sprite.mesh_data.texture_origin = _get_sprite_texture_origin(sprite)
	_copy_canvas_item_state(sprite, mesh_sprite)
	_replace_node(sprite, mesh_sprite)
	mesh_sprite.sync_mesh()
	_selected_node = mesh_sprite
	return mesh_sprite


func _convert_mesh_to_sprite(mesh_sprite: TwberMeshSprite2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = mesh_sprite.texture
	sprite.centered = true
	sprite.offset = mesh_sprite.get_texture_origin()
	if sprite.texture != null:
		sprite.offset += sprite.texture.get_size() * 0.5
	_copy_canvas_item_state(mesh_sprite, sprite)
	_replace_node(mesh_sprite, sprite)
	_selected_node = sprite
	_selected_vertex_indices.clear()
	return sprite


func _replace_node(old_node: Node2D, new_node: Node2D) -> void:
	var parent := old_node.get_parent()
	if parent == null:
		return

	var child_index := old_node.get_index()
	var children := old_node.get_children()
	for child: Node in children:
		old_node.remove_child(child)
		new_node.add_child(child)

	parent.remove_child(old_node)
	parent.add_child(new_node)
	parent.move_child(new_node, child_index)
	old_node.queue_free()


func _copy_canvas_item_state(source: Node2D, target: Node2D) -> void:
	target.name = source.name
	target.transform = source.transform
	target.visible = source.visible
	target.z_index = source.z_index
	target.z_as_relative = source.z_as_relative
	target.y_sort_enabled = source.y_sort_enabled
	target.texture_filter = source.texture_filter
	target.texture_repeat = source.texture_repeat
	target.material = source.material

	target.modulate = source.modulate
	target.self_modulate = source.self_modulate
	target.show_behind_parent = source.show_behind_parent
	target.clip_children = source.clip_children
	target.light_mask = source.light_mask
	target.visibility_layer = source.visibility_layer
	for metadata_name: StringName in source.get_meta_list():
		target.set_meta(metadata_name, source.get_meta(metadata_name))


func _insert_parameter_mesh_vertex_states(
		mesh_sprite: TwberMeshSprite2D,
		vertex_index: int,
) -> void:
	var current_vertices := mesh_sprite.mesh_data.vertices
	for layer_state: TwberLayerStateResource in _get_parameter_layer_states(mesh_sprite):
		if layer_state.mesh_vertices.size() == current_vertices.size() - 1:
			layer_state.mesh_vertices.insert(vertex_index, current_vertices[vertex_index])
		else:
			layer_state.mesh_vertices = current_vertices.duplicate()


func _remove_parameter_mesh_vertex_states(
		mesh_sprite: TwberMeshSprite2D,
		vertex_index: int,
) -> void:
	var current_vertices := mesh_sprite.mesh_data.vertices
	for layer_state: TwberLayerStateResource in _get_parameter_layer_states(mesh_sprite):
		if layer_state.mesh_vertices.size() == current_vertices.size() + 1:
			layer_state.mesh_vertices.remove_at(vertex_index)
		else:
			layer_state.mesh_vertices = current_vertices.duplicate()


func _shift_parameter_mesh_vertex_states(
		mesh_sprite: TwberMeshSprite2D,
		vertex_index: int,
		offset: Vector2,
) -> void:
	if offset.is_zero_approx():
		return
	var current_vertices := mesh_sprite.mesh_data.vertices
	for layer_state: TwberLayerStateResource in _get_parameter_layer_states(mesh_sprite):
		if layer_state.mesh_vertices.size() == current_vertices.size():
			layer_state.mesh_vertices[vertex_index] += offset
		else:
			layer_state.mesh_vertices = current_vertices.duplicate()


func _get_parameter_layer_states(node: Node2D) -> Array[TwberLayerStateResource]:
	var output: Array[TwberLayerStateResource] = []
	if _model_root == null:
		return output

	var layer_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	if layer_id.is_empty():
		return output

	var stored_parameters: Variant = _model_root.get_meta(
			TwberModelCodec.MODEL_PARAMETERS_META,
			[],
	)
	if stored_parameters is not Array:
		return output

	for value: Variant in stored_parameters:
		if value is not TwberParameterResource:
			continue
		var parameter: TwberParameterResource = value
		for parameter_position: TwberParameterPositionResource in parameter.positions:
			if parameter_position == null:
				continue
			var layer_state := parameter_position.find_state(layer_id)
			if layer_state != null:
				output.append(layer_state)
	return output


func _find_edge_at_canvas_position(mesh_sprite: TwberMeshSprite2D, canvas_position: Vector2) -> PackedInt32Array:
	if mesh_sprite.mesh_data == null:
		return PackedInt32Array()

	var editor_position := _canvas_to_editor_position(canvas_position)
	var vertices := mesh_sprite.mesh_data.vertices
	var triangles := mesh_sprite.mesh_data.triangles
	var best_edge := PackedInt32Array()
	var best_distance := EDGE_HIT_RADIUS

	for triangle_start: int in range(0, triangles.size() - 2, 3):
		var a := int(triangles[triangle_start])
		var b := int(triangles[triangle_start + 1])
		var c := int(triangles[triangle_start + 2])
		if (
				a < 0
				or b < 0
				or c < 0
				or a >= vertices.size()
				or b >= vertices.size()
				or c >= vertices.size()
		):
			continue

		var point_a := _node_to_editor_position(mesh_sprite, vertices[a])
		var point_b := _node_to_editor_position(mesh_sprite, vertices[b])
		var point_c := _node_to_editor_position(mesh_sprite, vertices[c])
		var distance_ab := _get_distance_to_segment(editor_position, point_a, point_b)
		if distance_ab <= best_distance:
			best_distance = distance_ab
			best_edge = PackedInt32Array([a, b])

		var distance_bc := _get_distance_to_segment(editor_position, point_b, point_c)
		if distance_bc <= best_distance:
			best_distance = distance_bc
			best_edge = PackedInt32Array([b, c])

		var distance_ca := _get_distance_to_segment(editor_position, point_c, point_a)
		if distance_ca <= best_distance:
			best_distance = distance_ca
			best_edge = PackedInt32Array([c, a])

	for edge_index: int in range(0, mesh_sprite.mesh_data.joined_edges.size() - 1, 2):
		var joined_a := int(mesh_sprite.mesh_data.joined_edges[edge_index])
		var joined_b := int(mesh_sprite.mesh_data.joined_edges[edge_index + 1])
		if (
				joined_a < 0
				or joined_b < 0
				or joined_a >= vertices.size()
				or joined_b >= vertices.size()
		):
			continue

		var joined_distance := _get_distance_to_segment(
				editor_position,
				_node_to_editor_position(mesh_sprite, vertices[joined_a]),
				_node_to_editor_position(mesh_sprite, vertices[joined_b])
		)
		if joined_distance <= best_distance:
			best_distance = joined_distance
			best_edge = PackedInt32Array([joined_a, joined_b])

	return best_edge


func _get_distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if is_zero_approx(length_squared):
		return point.distance_to(start)

	var t := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _draw_mesh_overlay(mesh_sprite: TwberMeshSprite2D) -> void:
	if mesh_sprite.mesh_data == null:
		return

	_draw_source_texture_reference(mesh_sprite)

	var vertices := mesh_sprite.mesh_data.vertices
	var triangles := mesh_sprite.mesh_data.triangles
	var edge_color := TRIANGLE_COLOR
	var mode := _get_mode()
	if mode == MeshMode.CUT_EDGE:
		edge_color = CUT_EDGE_COLOR
	elif mode == MeshMode.JOIN_EDGE:
		edge_color = JOIN_EDGE_COLOR
	for index: int in range(0, triangles.size() - 2, 3):
		var a := int(triangles[index])
		var b := int(triangles[index + 1])
		var c := int(triangles[index + 2])
		if (
				a < 0
				or b < 0
				or c < 0
				or a >= vertices.size()
				or b >= vertices.size()
				or c >= vertices.size()
		):
			continue

		var point_a := _node_to_editor_position(mesh_sprite, vertices[a])
		var point_b := _node_to_editor_position(mesh_sprite, vertices[b])
		var point_c := _node_to_editor_position(mesh_sprite, vertices[c])
		_overlay.draw_line(point_a, point_b, edge_color, 1.0)
		_overlay.draw_line(point_b, point_c, edge_color, 1.0)
		_overlay.draw_line(point_c, point_a, edge_color, 1.0)

	if triangles.is_empty() and vertices.size() > 1:
		for index: int in vertices.size() - 1:
			_overlay.draw_line(
					_node_to_editor_position(mesh_sprite, vertices[index]),
					_node_to_editor_position(mesh_sprite, vertices[index + 1]),
					EDGE_COLOR,
					1.0
			)

	for index: int in range(0, mesh_sprite.mesh_data.joined_edges.size() - 1, 2):
		var vertex_a := int(mesh_sprite.mesh_data.joined_edges[index])
		var vertex_b := int(mesh_sprite.mesh_data.joined_edges[index + 1])
		if (
				vertex_a < 0
				or vertex_b < 0
				or vertex_a >= vertices.size()
				or vertex_b >= vertices.size()
		):
			continue
		_overlay.draw_line(
				_node_to_editor_position(mesh_sprite, vertices[vertex_a]),
				_node_to_editor_position(mesh_sprite, vertices[vertex_b]),
				JOIN_EDGE_COLOR,
				1.5
		)

	for index: int in vertices.size():
		var color := HANDLE_COLOR
		if _selected_vertex_indices.has(index):
			color = SELECTED_HANDLE_COLOR
		if index == _join_first_vertex_index:
			color = JOIN_EDGE_COLOR
		_overlay.draw_circle(_node_to_editor_position(mesh_sprite, vertices[index]), HANDLE_RADIUS, color)


func _draw_selection_overlay() -> void:
	if not _selecting_vertices:
		return

	if _selection_mode == MeshMode.RECTANGLE_SELECT:
		var rect := _get_selection_rect()
		_overlay.draw_rect(rect, SELECTION_FILL_COLOR, true)
		_overlay.draw_rect(rect, SELECTION_STROKE_COLOR, false, 1.0)
	elif _selection_mode == MeshMode.LASSO_SELECT and _lasso_points.size() > 1:
		var points := _lasso_points.duplicate()
		if points[points.size() - 1] != _selection_current_position:
			points.append(_selection_current_position)
		_overlay.draw_polyline(points, SELECTION_STROKE_COLOR, 1.0)


func _draw_source_texture_reference(node: Node2D) -> void:
	var source_texture: Texture2D
	var texture_origin := Vector2.ZERO
	if node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		source_texture = mesh_sprite.texture
		texture_origin = mesh_sprite.get_texture_origin()
	elif node is Sprite2D:
		var sprite: Sprite2D = node
		source_texture = sprite.texture
		texture_origin = _get_sprite_texture_origin(sprite)

	if source_texture == null:
		return

	var source_transform := _overlay.get_global_transform_with_canvas().affine_inverse() * node.get_global_transform_with_canvas()
	_overlay.draw_set_transform_matrix(source_transform)
	_overlay.draw_texture(source_texture, texture_origin, SOURCE_TEXTURE_COLOR)
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_sprite_bounds(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return

	_draw_source_texture_reference(sprite)

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
				EDGE_COLOR,
				1.0
		)


func _draw_unsupported_marker(node: Node2D) -> void:
	_overlay.draw_circle(_node_to_editor_position(node, Vector2.ZERO), HANDLE_RADIUS, UNSUPPORTED_COLOR)


func _get_mode() -> int:
	if _add_point_button.button_pressed:
		return MeshMode.ADD_POINT
	if _remove_point_button.button_pressed:
		return MeshMode.REMOVE_POINT
	if _rectangle_select_button.button_pressed:
		return MeshMode.RECTANGLE_SELECT
	if _lasso_select_button.button_pressed:
		return MeshMode.LASSO_SELECT
	if _cut_button.button_pressed:
		return MeshMode.CUT_EDGE
	if _join_button.button_pressed:
		return MeshMode.JOIN_EDGE

	return MeshMode.EDIT_POINT


func _on_model_node_selected() -> void:
	_reset_interaction_state()
	_queue_overlay_redraw()


func _begin_vertex_drag(mesh_sprite: TwberMeshSprite2D, vertex_index: int, canvas_position: Vector2) -> void:
	if not _selected_vertex_indices.has(vertex_index):
		_set_vertex_selection([vertex_index])

	_drag_start_position = _viewport_to_node_position(mesh_sprite, canvas_position)
	_drag_start_vertices.clear()
	for selected_vertex_index: int in _selected_vertex_indices:
		if selected_vertex_index >= 0 and selected_vertex_index < mesh_sprite.get_vertex_count():
			_drag_start_vertices[selected_vertex_index] = mesh_sprite.get_vertex(selected_vertex_index)
	_dragging_vertex = not _drag_start_vertices.is_empty()


func _set_vertex_selection(vertex_indices: Array) -> void:
	_selected_vertex_indices.clear()
	for vertex_index: int in vertex_indices:
		if not _selected_vertex_indices.has(vertex_index):
			_selected_vertex_indices.append(vertex_index)


func _toggle_vertex_selection(vertex_index: int) -> void:
	var selected_index := _selected_vertex_indices.find(vertex_index)
	if selected_index == -1:
		_selected_vertex_indices.append(vertex_index)
	else:
		_selected_vertex_indices.remove_at(selected_index)


func _begin_rectangle_selection(canvas_position: Vector2, additive_selection: bool) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	_dragging_vertex = false
	_selecting_vertices = true
	_selection_additive = additive_selection
	_selection_mode = MeshMode.RECTANGLE_SELECT
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
	_selection_mode = MeshMode.LASSO_SELECT
	_selection_start_position = _canvas_to_editor_position(canvas_position)
	_selection_current_position = _selection_start_position
	_lasso_points = PackedVector2Array([_selection_start_position])
	_queue_overlay_redraw()


func _update_vertex_selection(canvas_position: Vector2) -> void:
	_selection_current_position = _canvas_to_editor_position(canvas_position)
	if _selection_mode == MeshMode.LASSO_SELECT and (
		_lasso_points.is_empty()
		or _lasso_points[_lasso_points.size() - 1].distance_to(_selection_current_position) >= LASSO_MIN_POINT_DISTANCE
	):
		_lasso_points.append(_selection_current_position)
	_queue_overlay_redraw()


func _finish_vertex_selection() -> void:
	if not (_selected_node is TwberMeshSprite2D):
		_selecting_vertices = false
		return

	if _selection_mode == MeshMode.LASSO_SELECT and (
		_lasso_points.is_empty() or _lasso_points[_lasso_points.size() - 1] != _selection_current_position
	):
		_lasso_points.append(_selection_current_position)

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var selected_indices := _find_vertices_in_active_selection(mesh_sprite)
	if _selection_additive:
		for vertex_index: int in selected_indices:
			if not _selected_vertex_indices.has(vertex_index):
				_selected_vertex_indices.append(vertex_index)
	else:
		_set_vertex_selection(selected_indices)
	_selecting_vertices = false
	_lasso_points = PackedVector2Array()
	_queue_overlay_redraw()


func _find_vertices_in_active_selection(mesh_sprite: TwberMeshSprite2D) -> Array[int]:
	var selected_indices: Array[int] = []
	if mesh_sprite.mesh_data == null:
		return selected_indices

	for index: int in mesh_sprite.mesh_data.vertices.size():
		var point := _node_to_editor_position(mesh_sprite, mesh_sprite.mesh_data.vertices[index])
		if _selection_mode == MeshMode.RECTANGLE_SELECT and _get_selection_rect().has_point(point):
			selected_indices.append(index)
		elif _selection_mode == MeshMode.LASSO_SELECT and _lasso_points.size() >= 3 and Geometry2D.is_point_in_polygon(point, _lasso_points):
			selected_indices.append(index)
	return selected_indices


func _get_selection_rect() -> Rect2:
	var top_left := _selection_start_position.min(_selection_current_position)
	return Rect2(top_left, _selection_start_position.max(_selection_current_position) - top_left)


func _on_generate_grid_button_pressed() -> void:
	var was_plain_sprite := _selected_node is Sprite2D
	var mesh_sprite := _ensure_selected_mesh_sprite()
	if mesh_sprite == null or mesh_sprite.texture == null:
		return

	var visible_rect := _get_visible_texture_rect(mesh_sprite.texture)
	if visible_rect.size.x < 1 or visible_rect.size.y < 1:
		return

	mesh_sprite.generate_grid_mesh(
			int(_horizontal_vertices.value),
			int(_vertical_vertices.value),
			visible_rect,
	)
	_reset_parameter_mesh_vertex_states(mesh_sprite)
	_set_vertex_selection([])
	if was_plain_sprite:
		model_tree_changed.emit()
		reload_from_preview(mesh_sprite)
	else:
		_queue_overlay_redraw()


func _on_fast_mesh_button_pressed() -> void:
	if not (_selected_node is Sprite2D or _selected_node is TwberMeshSprite2D):
		return
	_fast_mesh_dialog.popup_centered(Vector2i(300, 150))


func _get_visible_texture_rect(texture: Texture2D) -> Rect2i:
	var metadata_rect := TwberTextureUtils.get_visible_rect(texture)
	if metadata_rect.size.x > 0 and metadata_rect.size.y > 0:
		return metadata_rect

	var image := TwberTextureUtils.get_authoring_image(texture)
	if image == null:
		return Rect2i()
	return TwberTextureUtils.find_alpha_used_rect(image, VISIBLE_PIXEL_ALPHA_THRESHOLD)


func _reset_parameter_mesh_vertex_states(mesh_sprite: TwberMeshSprite2D) -> void:
	for layer_state: TwberLayerStateResource in _get_parameter_layer_states(mesh_sprite):
		layer_state.mesh_vertices = mesh_sprite.mesh_data.vertices.duplicate()
