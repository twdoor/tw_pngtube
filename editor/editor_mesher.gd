class_name EditorMesher extends HSplitContainer

signal model_tree_changed

const TREE_COLUMN := 0
const ROOT_LAYER_ID := 0
const INVALID_LAYER_ID := -1
const MODEL_ROOT_NAME := "Textures"
const HANDLE_RADIUS := 5.0
const HANDLE_HIT_RADIUS := 12.0
const EDGE_HIT_RADIUS := 12.0
const TRIANGLE_COLOR := Color(0.19, 0.75, 1.0, 0.8)
const EDGE_COLOR := Color(0.9, 0.95, 1.0, 0.75)
const CUT_EDGE_COLOR := Color(1.0, 0.28, 0.2, 0.95)
const HANDLE_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const SELECTED_HANDLE_COLOR := Color(1.0, 0.78, 0.22, 1.0)
const SOURCE_TEXTURE_COLOR := Color(1.0, 1.0, 1.0, 0.42)
const UNSUPPORTED_COLOR := Color(1.0, 0.35, 0.25, 0.75)
const TwberMeshResourceScript := preload("res://model/twber_mesh_resource.gd")

enum MeshMode {
	ADD_POINT,
	REMOVE_POINT,
	EDIT_POINT,
	CUT_EDGE,
}

@onready var _add_point_button: Button = %AddPointButton
@onready var _remove_point_button: Button = %RemovePointButton
@onready var _edit_point_button: Button = %EditPointButton
@onready var _cut_button: Button = %CutButton
@onready var _tree: Tree = %Tree
@onready var _edit_panel: Control = $Panel
@export var _preview_layer: CanvasLayer

var _root_item: TreeItem
var _model_root: Node2D
var _selected_layer_id := INVALID_LAYER_ID
var _selected_node: Node2D
var _selected_vertex_index := -1
var _dragging_vertex := false
var _holding_remove := false
var _holding_cut := false
var _overlay: Control
var _layers_by_id: Dictionary = {}
var _root_layer_ids: Array[int] = []
var _tree_items_by_id: Dictionary = {}
var _next_item_id := 1


func _ready() -> void:
	_add_point_button.button_pressed = true

	_tree.clear()
	_tree.columns = 1
	_tree.hide_root = true
	_tree.set_column_expand(TREE_COLUMN, true)
	_tree.item_selected.connect(_on_tree_item_selected)
	_setup_overlay()

	_setup_preview()
	reload_from_preview()
	set_process(true)


func _process(_delta: float) -> void:
	if visible:
		_queue_overlay_redraw()


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
		_dragging_vertex = false
		_holding_remove = false
		_holding_cut = false
		_overlay.accept_event()
		return

	match _get_mode():
		MeshMode.ADD_POINT:
			_add_point_at(viewport_position)
		MeshMode.REMOVE_POINT:
			_holding_remove = true
			_remove_point_at(viewport_position)
		MeshMode.EDIT_POINT:
			_begin_edit_point_at(viewport_position)
		MeshMode.CUT_EDGE:
			_holding_cut = true
			_cut_edge_at(viewport_position)

	_overlay.accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion, viewport_position: Vector2) -> void:
	if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_dragging_vertex = false
		_holding_remove = false
		_holding_cut = false
		return

	if not (_selected_node is TwberMeshSprite2D):
		return

	if _dragging_vertex:
		var mesh_sprite: TwberMeshSprite2D = _selected_node
		mesh_sprite.set_vertex(_selected_vertex_index, _viewport_to_node_position(mesh_sprite, viewport_position))
		_queue_overlay_redraw()
		_overlay.accept_event()
	elif _holding_remove:
		_remove_point_at(viewport_position)
		_overlay.accept_event()
	elif _holding_cut:
		_cut_edge_at(viewport_position)
		_overlay.accept_event()


func _add_point_at(canvas_position: Vector2) -> void:
	var was_plain_sprite := _selected_node is Sprite2D
	var mesh_sprite := _ensure_selected_mesh_sprite()
	if mesh_sprite == null:
		return

	mesh_sprite.add_vertex(_viewport_to_node_position(mesh_sprite, canvas_position))
	_selected_node = mesh_sprite
	_selected_vertex_index = mesh_sprite.get_vertex_count() - 1

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

	mesh_sprite.remove_vertex(vertex_index)
	if mesh_sprite.get_vertex_count() == 0:
		_holding_remove = false
		var sprite := _convert_mesh_to_sprite(mesh_sprite)
		model_tree_changed.emit()
		reload_from_preview(sprite)
		return

	_selected_vertex_index = mini(vertex_index, mesh_sprite.get_vertex_count() - 1)
	_queue_overlay_redraw()


func _begin_edit_point_at(canvas_position: Vector2) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var vertex_index := _find_vertex_at_canvas_position(mesh_sprite, canvas_position)
	if vertex_index == -1:
		_selected_vertex_index = -1
		_dragging_vertex = false
		_queue_overlay_redraw()
		return

	_selected_vertex_index = vertex_index
	_dragging_vertex = true
	_queue_overlay_redraw()


func _cut_edge_at(canvas_position: Vector2) -> void:
	if not (_selected_node is TwberMeshSprite2D):
		return

	var mesh_sprite: TwberMeshSprite2D = _selected_node
	var triangle_start := _find_triangle_edge_at_canvas_position(mesh_sprite, canvas_position)
	if triangle_start == -1:
		return

	_remove_triangle(mesh_sprite, triangle_start)
	_selected_vertex_index = -1
	mesh_sprite.sync_mesh()
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
	mesh_sprite.mesh_data = TwberMeshResourceScript.new()
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
	_copy_canvas_item_state(mesh_sprite, sprite)
	_replace_node(mesh_sprite, sprite)
	_selected_node = sprite
	_selected_vertex_index = -1
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

	if source is CanvasItem and target is CanvasItem:
		var source_item: CanvasItem = source
		var target_item: CanvasItem = target
		target_item.modulate = source_item.modulate
		target_item.self_modulate = source_item.self_modulate
		target_item.show_behind_parent = source_item.show_behind_parent
		target_item.clip_children = source_item.clip_children
		target_item.light_mask = source_item.light_mask
		target_item.visibility_layer = source_item.visibility_layer


func _get_sprite_texture_origin(sprite: Sprite2D) -> Vector2:
	if sprite.texture == null:
		return sprite.offset

	var origin := sprite.offset
	if sprite.centered:
		origin -= sprite.texture.get_size() * 0.5

	return origin


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


func _find_triangle_edge_at_canvas_position(mesh_sprite: TwberMeshSprite2D, canvas_position: Vector2) -> int:
	if mesh_sprite.mesh_data == null:
		return -1

	var editor_position := _canvas_to_editor_position(canvas_position)
	var vertices := mesh_sprite.mesh_data.vertices
	var triangles := mesh_sprite.mesh_data.triangles
	var best_triangle_start := -1
	var best_distance := EDGE_HIT_RADIUS

	for triangle_start: int in range(0, triangles.size() - 2, 3):
		var a := int(triangles[triangle_start])
		var b := int(triangles[triangle_start + 1])
		var c := int(triangles[triangle_start + 2])
		if a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
			continue

		var point_a := _node_to_editor_position(mesh_sprite, vertices[a])
		var point_b := _node_to_editor_position(mesh_sprite, vertices[b])
		var point_c := _node_to_editor_position(mesh_sprite, vertices[c])
		var edge_distance := minf(
				_get_distance_to_segment(editor_position, point_a, point_b),
				minf(
						_get_distance_to_segment(editor_position, point_b, point_c),
						_get_distance_to_segment(editor_position, point_c, point_a)
				)
		)

		if edge_distance <= best_distance:
			best_distance = edge_distance
			best_triangle_start = triangle_start

	return best_triangle_start


func _remove_triangle(mesh_sprite: TwberMeshSprite2D, triangle_start: int) -> void:
	if mesh_sprite.mesh_data == null:
		return

	var triangles := mesh_sprite.mesh_data.triangles
	var next_triangles := PackedInt32Array()
	for index: int in range(0, triangles.size() - 2, 3):
		if index == triangle_start:
			continue

		next_triangles.append(triangles[index])
		next_triangles.append(triangles[index + 1])
		next_triangles.append(triangles[index + 2])

	mesh_sprite.mesh_data.triangles = next_triangles


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
	if _get_mode() == MeshMode.CUT_EDGE:
		edge_color = CUT_EDGE_COLOR
	for index: int in range(0, triangles.size() - 2, 3):
		var a := int(triangles[index])
		var b := int(triangles[index + 1])
		var c := int(triangles[index + 2])
		if a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
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

	for index: int in vertices.size():
		var color := HANDLE_COLOR
		if index == _selected_vertex_index:
			color = SELECTED_HANDLE_COLOR
		_overlay.draw_circle(_node_to_editor_position(mesh_sprite, vertices[index]), HANDLE_RADIUS, color)


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


func _node_to_editor_position(node: Node2D, local_position: Vector2) -> Vector2:
	return _canvas_to_editor_position(node.get_global_transform_with_canvas() * local_position)


func _viewport_to_node_position(node: Node2D, viewport_position: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas().affine_inverse() * viewport_position


func _canvas_to_editor_position(canvas_position: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas().affine_inverse() * canvas_position


func _get_mode() -> int:
	if _add_point_button.button_pressed:
		return MeshMode.ADD_POINT
	if _remove_point_button.button_pressed:
		return MeshMode.REMOVE_POINT
	if _cut_button.button_pressed:
		return MeshMode.CUT_EDGE
	if _edit_point_button.button_pressed:
		return MeshMode.EDIT_POINT

	return MeshMode.EDIT_POINT


func _overlay_local_to_viewport(local_position: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas() * local_position


func _queue_overlay_redraw() -> void:
	if _overlay != null:
		_overlay.queue_redraw()
	queue_redraw()


func _setup_preview() -> void:
	if _preview_layer == null:
		push_warning("EditorMesher needs a preview CanvasLayer.")
		return

	var existing_node := _preview_layer.get_node_or_null(MODEL_ROOT_NAME)
	if existing_node is Node2D:
		_model_root = existing_node
	else:
		push_warning("EditorMesher needs a Node2D named %s in the preview layer." % MODEL_ROOT_NAME)


func _import_model_children(parent_node: Node, parent_id: int, child_ids: Array) -> void:
	for child: Node in parent_node.get_children():
		if child is not Node2D:
			continue

		var layer_id := _next_item_id
		_next_item_id += 1
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
		_selected_vertex_index = -1
		_queue_overlay_redraw()
		return

	_selected_layer_id = layer_id
	var layer: Dictionary = _layers_by_id[layer_id]
	_selected_node = layer["node"]
	_selected_vertex_index = -1
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
