class_name EditorModelTree extends HSplitContainer

const TREE_COLUMN := 0
const MODEL_ROOT_NAME := "Textures"
const HANDLE_RADIUS := 5.0
const HANDLE_HIT_RADIUS := 12.0

@onready var _tree: Tree = %Tree
@export var _preview_layer: CanvasLayer

var _model_root: Node2D
var _selected_node: Node2D
var _overlay: Control
var _tree_items_by_node_id: Dictionary[int, TreeItem] = {}
var _tree_state_keys_by_node_id: Dictionary[int, String] = {}
var _selecting_tree_item := false
var _editor_settings := TwberEditorSettings.new()
var _observed_animated_sprite: AnimatedSprite2D


func set_editor_settings(settings: TwberEditorSettings) -> void:
	if settings == null:
		_editor_settings = TwberEditorSettings.new()
	else:
		_editor_settings = settings


func _is_pixel_snap_enabled() -> bool:
	return _editor_settings.pixel_snap_enabled


func _snap_pixel_position(value: Vector2, origin := Vector2.ZERO) -> Vector2:
	return _editor_settings.snap_pixel_position(value, origin)


func _snap_rotation(value: float) -> float:
	return _editor_settings.snap_rotation(value)


func _snap_scale_factor(value: float) -> float:
	return _editor_settings.snap_scale_factor(value)


func _snap_scale(value: Vector2) -> Vector2:
	return _editor_settings.snap_scale(value)


func _snap_mesh_position(mesh_sprite: TwberMeshSprite2D, value: Vector2) -> Vector2:
	if mesh_sprite == null:
		return value

	return _snap_pixel_position(value, mesh_sprite.get_texture_origin())


func _initialize_model_tree() -> void:
	_tree.clear()
	_tree.columns = 1
	_tree.hide_root = true
	_tree.set_column_expand(TREE_COLUMN, true)
	_tree.item_selected.connect(_on_tree_item_selected)
	_setup_preview()


func reload_from_preview(selected_node: Node2D = null) -> void:
	var node_to_select := selected_node if selected_node != null else _selected_node
	var collapsed_state := _get_tree_collapsed_state()
	_rebuild_tree(collapsed_state)

	if node_to_select != null and is_instance_valid(node_to_select):
		_select_node(node_to_select)
	else:
		_set_selected_node(null)


func _setup_preview() -> void:
	if _preview_layer == null:
		push_warning("%s needs a preview CanvasLayer." % name)
		return

	var existing_node := _preview_layer.get_node_or_null(MODEL_ROOT_NAME)
	if existing_node is Node2D:
		_model_root = existing_node
	else:
		push_warning("%s needs a Node2D named %s in the preview layer." % [name, MODEL_ROOT_NAME])


func _rebuild_tree(collapsed_state: Dictionary = {}) -> void:
	_tree.clear()
	_tree_items_by_node_id.clear()
	_tree_state_keys_by_node_id.clear()

	var root_item := _tree.create_item()
	if _model_root != null:
		TwberModelCodec.ensure_layer_ids(_model_root)
		_add_model_children(root_item, _model_root, collapsed_state)


func _add_model_children(parent_item: TreeItem, parent_node: Node, collapsed_state: Dictionary) -> void:
	for child: Node in parent_node.get_children():
		if child is not Node2D:
			continue

		var node_2d: Node2D = child
		_on_model_node_imported(node_2d)

		var item := _tree.create_item(parent_item)
		item.set_text(TREE_COLUMN, node_2d.name)
		item.set_metadata(TREE_COLUMN, node_2d)
		var node_id := node_2d.get_instance_id()
		_tree_items_by_node_id[node_id] = item
		var state_key := _get_tree_state_key(node_2d)
		_tree_state_keys_by_node_id[node_id] = state_key
		if collapsed_state.has(state_key):
			item.set_collapsed(collapsed_state[state_key])

		_add_model_children(item, node_2d, collapsed_state)


func _on_tree_item_selected() -> void:
	if _selecting_tree_item:
		return

	_set_selected_node(_get_node_from_item(_tree.get_selected()))


func _select_node(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		_set_selected_node(null)
		return

	var node_id := node.get_instance_id()
	if not _tree_items_by_node_id.has(node_id):
		_set_selected_node(null)
		return

	_selecting_tree_item = true
	_tree.deselect_all()
	var item: TreeItem = _tree_items_by_node_id[node_id]
	item.select(TREE_COLUMN)
	_selecting_tree_item = false
	_set_selected_node(node)


func _set_selected_node(node: Node2D) -> void:
	_stop_observing_selected_animation()
	_selected_node = node
	if node is AnimatedSprite2D:
		_observed_animated_sprite = node
		_observed_animated_sprite.frame_changed.connect(_queue_overlay_redraw)
		_observed_animated_sprite.animation_changed.connect(_queue_overlay_redraw)
	_on_model_node_selected()


func _stop_observing_selected_animation() -> void:
	if _observed_animated_sprite == null or not is_instance_valid(_observed_animated_sprite):
		_observed_animated_sprite = null
		return
	if _observed_animated_sprite.frame_changed.is_connected(_queue_overlay_redraw):
		_observed_animated_sprite.frame_changed.disconnect(_queue_overlay_redraw)
	if _observed_animated_sprite.animation_changed.is_connected(_queue_overlay_redraw):
		_observed_animated_sprite.animation_changed.disconnect(_queue_overlay_redraw)
	_observed_animated_sprite = null


func _get_tree_collapsed_state() -> Dictionary[String, bool]:
	var collapsed_state: Dictionary[String, bool] = {}
	for node_id: int in _tree_items_by_node_id:
		var item: TreeItem = _tree_items_by_node_id[node_id]
		if item != null and _tree_state_keys_by_node_id.has(node_id):
			collapsed_state[_tree_state_keys_by_node_id[node_id]] = item.is_collapsed()

	return collapsed_state


func _get_tree_state_key(node: Node2D) -> String:
	var layer_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	if not layer_id.is_empty():
		return "layer:%s" % layer_id

	return "instance:%d" % node.get_instance_id()


func _get_node_from_item(item: TreeItem) -> Node2D:
	if item == null:
		return null

	var node: Variant = item.get_metadata(TREE_COLUMN)
	if node is Node2D and is_instance_valid(node):
		return node

	return null


func _get_sprite_texture_origin(sprite: Sprite2D) -> Vector2:
	if sprite.texture == null:
		return sprite.offset

	var origin := sprite.offset
	if sprite.centered:
		origin -= sprite.texture.get_size() * 0.5

	return origin


func _find_vertex_at_canvas_position(
		mesh_sprite: TwberMeshSprite2D,
		canvas_position: Vector2,
) -> int:
	if mesh_sprite.mesh_data == null:
		return -1

	var editor_position := _canvas_to_editor_position(canvas_position)
	var best_index := -1
	var best_distance := HANDLE_HIT_RADIUS
	for index: int in mesh_sprite.mesh_data.vertices.size():
		var vertex_position := _node_to_editor_position(
				mesh_sprite,
				mesh_sprite.mesh_data.vertices[index],
		)
		var distance := editor_position.distance_to(vertex_position)
		if distance <= best_distance:
			best_distance = distance
			best_index = index

	return best_index


func _node_to_editor_position(node: Node2D, local_position: Vector2) -> Vector2:
	return _canvas_to_editor_position(node.get_global_transform_with_canvas() * local_position)


func _viewport_to_node_position(node: Node2D, viewport_position: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas().affine_inverse() * viewport_position


func _canvas_to_editor_position(canvas_position: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas().affine_inverse() * canvas_position


func _overlay_local_to_viewport(local_position: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas() * local_position


func _queue_overlay_redraw() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func refresh_overlay() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _on_model_node_imported(_node: Node2D) -> void:
	pass


func _on_model_node_selected() -> void:
	pass
