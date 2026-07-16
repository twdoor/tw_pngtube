class_name EditorPlacer extends HSplitContainer

signal model_render_changed(rebuild_atlases: bool, reconfigure_batching: bool)

const TREE_COLUMN := 0
const DRAG_DATA_TYPE := &"editor_placer_tree_item"
const ROOT_LAYER_ID := 0
const INVALID_LAYER_ID := -1
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.webp ; Image files"
const MODEL_ROOT_NAME := "Textures"
const TEXTURE_PREVIEW_ALPHA_THRESHOLD := 0.001
const TEXTURE_RUNTIME_COMPRESS_MODE := Image.COMPRESS_S3TC
const TEXTURE_RUNTIME_COMPRESS_SOURCE := Image.COMPRESS_SOURCE_GENERIC
const TEXTURE_PREVIEW_CACHE_LIMIT := 128
const MIRROR_DIALOG_SCENE := preload("res://editor/mirror_dialog.tscn")
const MIN_LAYER_SCALE_DISTANCE := 0.001
const LAYER_ORIGIN_COLOR := Color(1.0, 0.78, 0.22, 0.95)
const LAYER_GUIDE_COLOR := Color(1.0, 0.78, 0.22, 0.65)
const HANDLE_RADIUS := 5.0

enum PlacerItemType {
	LAYER,
	ANIMATION_LAYER,
	EMPTY,
}

enum TransformMode {
	POINTER,
	MOVE,
	ROTATE,
	SCALE,
	PIVOT,
}

@onready var _layer_button: Button = %LayerButton
@onready var _animation_layer_button: Button = %AnimationLayerButton
@onready var _empty_button: Button = %EmptyButton
@onready var _pointer_button: Button = %PointerButton
@onready var _move_button: Button = %MoveButton
@onready var _rotate_button: Button = %RotateButton
@onready var _scale_button: Button = %ScaleButton
@onready var _pivot_button: Button = %PivotButton
@onready var _mirror_button: Button = %MirrorButton
@onready var _tree: Tree = %Tree
@onready var _inspector: PanelContainer = %Inspector
@onready var _layer_actions: Control = %LayerActions
@onready var _change_texture_button: TextureButton = %ChangeTextureButton
@onready var _visible_check_box: CheckBox = %VisibleCheckBox
@onready var _show_behind_parent_check_box: CheckBox = %ShowBehindParentCheckBox
@onready var _opacity_slider: HSlider = %OpacitySlider
@onready var _clip_option_button: OptionButton = %ClipOptionButton
@onready var _animation_frame_rate: SpinBox = %AnimationFrameRate
@onready var _animations_box: Control = %AnimationsBox
@onready var _animations_option_button: OptionButton = %AnimationsOptionButton
@onready var _new_animation_button: Button = %NewAnimationButton
@onready var _delete_animation_button: Button = %DeleteAnimationButton
@onready var _rename_animation_button: Button = %RenameAnimationButton
@onready var _duplicate_button: Button = %DuplicateButton
@onready var _delete_button: Button = %DeleteButton
@onready var _edit_panel: Control = $Panel
@export var _preview_layer: CanvasLayer
@export var _new_model_root_position := Vector2.ZERO
@export var _new_model_root_scale := Vector2(0.1, 0.1)

var _root_item: TreeItem
var _selected_layer_id := INVALID_LAYER_ID
var _texture_button_placeholder: Texture2D
var _texture_preview_cache: Dictionary = {}
var _texture_preview_cache_order: Array[Variant] = []
var _editor_settings: TwberEditorSettings
var _updating_inspector := false
var _model_root: Node2D
var _next_item_id := 1
var _layers_by_id: Dictionary = {}
var _root_layer_ids: Array[int] = []
var _tree_items_by_id: Dictionary = {}
var _tree_state_keys_by_id: Dictionary[int, String] = {}
var _item_counts: Dictionary = {
	PlacerItemType.LAYER: 0,
	PlacerItemType.ANIMATION_LAYER: 0,
	PlacerItemType.EMPTY: 0,
}
var _overlay: Control
var _dragging_transform := false
var _transform_mode: int = TransformMode.POINTER
var _transform_start_mouse := Vector2.ZERO
var _transform_current_mouse := Vector2.ZERO
var _transform_start_origin := Vector2.ZERO
var _transform_start_position := Vector2.ZERO
var _transform_start_rotation := 0.0
var _transform_start_scale := Vector2.ONE
var _transform_start_mouse_angle := 0.0
var _transform_start_mouse_distance := 1.0


func _ready() -> void:
	_pointer_button.button_pressed = true
	_layer_button.pressed.connect(_on_add_item_pressed.bind(PlacerItemType.LAYER))
	_animation_layer_button.pressed.connect(_on_add_item_pressed.bind(PlacerItemType.ANIMATION_LAYER))
	_empty_button.pressed.connect(_on_add_item_pressed.bind(PlacerItemType.EMPTY))
	_mirror_button.pressed.connect(_open_mirror_dialog)
	_duplicate_button.pressed.connect(_on_duplicate_button_pressed)
	_delete_button.pressed.connect(_on_delete_button_pressed)
	_change_texture_button.pressed.connect(_on_change_texture_button_pressed)
	_visible_check_box.toggled.connect(_on_visible_check_box_toggled)
	_show_behind_parent_check_box.toggled.connect(_on_show_behind_parent_toggled)
	_opacity_slider.value_changed.connect(_on_opacity_slider_value_changed)
	_clip_option_button.item_selected.connect(_on_clip_option_button_item_selected)
	_animation_frame_rate.value_changed.connect(_on_animation_frame_rate_value_changed)
	_animations_option_button.item_selected.connect(_on_animation_selected)
	_new_animation_button.pressed.connect(_on_new_animation_button_pressed)
	_delete_animation_button.pressed.connect(_on_delete_animation_button_pressed)
	_rename_animation_button.pressed.connect(_on_rename_animation_button_pressed)

	_setup_preview()
	_setup_transform_overlay()

	_tree.clear()
	_tree.columns = 1
	_tree.hide_root = true
	_tree.set_column_expand(TREE_COLUMN, true)
	_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
	_tree.set_drag_forwarding(_get_tree_drag_data, _can_drop_tree_data, _drop_tree_data)
	_tree.item_selected.connect(_on_tree_item_selected)
	_tree.multi_selected.connect(_on_tree_multi_selected)
	_tree.item_activated.connect(_on_tree_item_activated)
	_tree.item_edited.connect(_on_tree_item_edited)

	_texture_button_placeholder = _change_texture_button.texture_normal
	_animation_frame_rate.min_value = 0.1
	_animation_frame_rate.step = 0.1
	_hide_inspector()
	_rebuild_tree()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _tree != null:
		_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED


func _on_add_item_pressed(item_type: int) -> void:
	match item_type:
		PlacerItemType.LAYER:
			_open_texture_dialog()
		PlacerItemType.ANIMATION_LAYER:
			_open_animation_texture_dialog()
		PlacerItemType.EMPTY:
			_create_layer(PlacerItemType.EMPTY, "", [])


func _open_mirror_dialog() -> void:
	var source_ids := _filter_top_level_layer_ids(_get_selected_layer_ids())
	if source_ids.is_empty():
		return
	var dialog := MIRROR_DIALOG_SCENE.instantiate() as AcceptDialog
	dialog.connect(&"mirror_requested", _mirror_layers.bind(source_ids))
	add_child(dialog)
	_show_dialog_on_editor_screen(dialog)


func _show_dialog_on_editor_screen(dialog: Window) -> void:
	var host_window := get_window()
	var screen_index := 0
	if host_window != null and DisplayServer.get_screen_count() > 0:
		screen_index = clampi(
			DisplayServer.window_get_current_screen(host_window.get_window_id()),
			0,
			DisplayServer.get_screen_count() - 1,
		)
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		usable_rect = Rect2i(
			DisplayServer.screen_get_position(screen_index),
			DisplayServer.screen_get_size(screen_index),
		)
	var centered_position := usable_rect.position + Vector2i(
		maxi(floori(float(usable_rect.size.x - dialog.size.x) / 2.0), 0),
		maxi(floori(float(usable_rect.size.y - dialog.size.y) / 2.0), 0),
	)
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_ABSOLUTE
	dialog.position = centered_position
	# Window.popup* recalculates global coordinates and rejects valid positions on
	# some multi-monitor Wayland layouts. The position is already resolved here.
	dialog.show()


func reload_from_preview() -> void:
	var collapsed_state := _get_tree_collapsed_state()
	_load_model_tree_from_preview()
	_rebuild_tree(INVALID_LAYER_ID, collapsed_state)
	_set_selected_layer(INVALID_LAYER_ID)


func set_editor_settings(settings: TwberEditorSettings) -> void:
	_editor_settings = settings
	_texture_preview_cache.clear()
	_texture_preview_cache_order.clear()
	_refresh_inspector()


func refresh_overlay() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _setup_transform_overlay() -> void:
	_edit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_panel.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	_overlay = Control.new()
	_overlay.name = "PlacerOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_overlay.draw.connect(_on_overlay_draw)
	_edit_panel.add_child(_overlay)


func _on_overlay_draw() -> void:
	var node := _get_selected_model_node()
	if node == null:
		return
	var origin := _canvas_to_overlay_position(_get_node_canvas_origin(node))
	_overlay.draw_circle(origin, HANDLE_RADIUS, LAYER_ORIGIN_COLOR)
	if (
		_dragging_transform
		and (_transform_mode == TransformMode.ROTATE or _transform_mode == TransformMode.SCALE)
	):
		_overlay.draw_line(
			origin,
			_canvas_to_overlay_position(_transform_current_mouse),
			LAYER_GUIDE_COLOR,
			1.0,
		)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if not visible or _model_root == null:
		return
	if event is InputEventMouseButton:
		_handle_transform_mouse_button(
			event,
			_overlay.get_global_transform_with_canvas() * event.position,
		)
	elif event is InputEventMouseMotion:
		_handle_transform_mouse_motion(
			event,
			_overlay.get_global_transform_with_canvas() * event.position,
		)


func _handle_transform_mouse_button(event: InputEventMouseButton, canvas_position: Vector2) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		_finish_transform_drag()
		_overlay.accept_event()
		return

	var mode := _get_transform_mode()
	if mode == TransformMode.PIVOT:
		_change_selected_pivot(canvas_position)
	elif mode != TransformMode.POINTER:
		_begin_transform_drag(canvas_position, mode)
	_overlay.accept_event()


func _handle_transform_mouse_motion(event: InputEventMouseMotion, canvas_position: Vector2) -> void:
	if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_finish_transform_drag()
		return
	if not _dragging_transform:
		return
	_update_transform_drag(canvas_position)
	_overlay.accept_event()


func _begin_transform_drag(canvas_position: Vector2, mode: int) -> void:
	var node := _get_selected_model_node()
	if node == null:
		return
	_dragging_transform = true
	_transform_mode = mode
	_transform_start_mouse = canvas_position
	_transform_current_mouse = canvas_position
	_transform_start_origin = _get_node_canvas_origin(node)
	_transform_start_position = node.position
	_transform_start_rotation = node.rotation
	_transform_start_scale = node.scale
	var mouse_offset := canvas_position - _transform_start_origin
	_transform_start_mouse_angle = mouse_offset.angle()
	_transform_start_mouse_distance = maxf(mouse_offset.length(), MIN_LAYER_SCALE_DISTANCE)
	refresh_overlay()


func _update_transform_drag(canvas_position: Vector2) -> void:
	var node := _get_selected_model_node()
	if node == null:
		return
	_transform_current_mouse = canvas_position
	match _transform_mode:
		TransformMode.MOVE:
			_set_node_canvas_origin(
				node,
				_transform_start_origin + canvas_position - _transform_start_mouse,
			)
		TransformMode.ROTATE:
			var mouse_offset := canvas_position - _transform_start_origin
			if mouse_offset.length_squared() > MIN_LAYER_SCALE_DISTANCE:
				node.rotation = wrapf(
					_snap_rotation(
						_transform_start_rotation
						+ angle_difference(_transform_start_mouse_angle, mouse_offset.angle()),
					),
					-PI,
					PI,
				)
		TransformMode.SCALE:
			var mouse_distance := maxf(
				(canvas_position - _transform_start_origin).length(),
				MIN_LAYER_SCALE_DISTANCE,
			)
			var factor := _snap_scale_factor(mouse_distance / _transform_start_mouse_distance)
			node.scale = _transform_start_scale * factor
	model_render_changed.emit(false, false)
	refresh_overlay()


func _finish_transform_drag() -> void:
	if not _dragging_transform:
		return
	var node := _get_selected_model_node()
	_dragging_transform = false
	if node != null:
		_rebase_parameter_states_for_neutral_transform(
			node,
			node.position - _transform_start_position,
			angle_difference(_transform_start_rotation, node.rotation),
			node.scale - _transform_start_scale,
		)
	refresh_overlay()


func _get_transform_mode() -> int:
	if _move_button.button_pressed:
		return TransformMode.MOVE
	if _rotate_button.button_pressed:
		return TransformMode.ROTATE
	if _scale_button.button_pressed:
		return TransformMode.SCALE
	if _pivot_button.button_pressed:
		return TransformMode.PIVOT
	return TransformMode.POINTER


func _get_selected_model_node() -> Node2D:
	if not _layers_by_id.has(_selected_layer_id):
		return null
	return _layers_by_id[_selected_layer_id]["node"] as Node2D


func _get_node_canvas_origin(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin


func _canvas_to_overlay_position(canvas_position: Vector2) -> Vector2:
	return _overlay.get_global_transform_with_canvas().affine_inverse() * canvas_position


func _set_node_canvas_origin(
		node: Node2D,
		canvas_origin: Vector2,
		snap_to_grid := true,
) -> void:
	var parent := node.get_parent()
	if parent is CanvasItem:
		var local_position := (
			(parent as CanvasItem).get_global_transform_with_canvas().affine_inverse()
			* canvas_origin
		)
		node.position = _snap_pixel_position(local_position) if snap_to_grid else local_position
	else:
		node.global_position = _snap_pixel_position(canvas_origin) if snap_to_grid else canvas_origin


func _snap_pixel_position(value: Vector2) -> Vector2:
	return _editor_settings.snap_pixel_position(value) if _editor_settings != null else value


func _snap_rotation(value: float) -> float:
	return _editor_settings.snap_rotation(value) if _editor_settings != null else value


func _snap_scale_factor(value: float) -> float:
	return _editor_settings.snap_scale_factor(value) if _editor_settings != null else value


func _change_selected_pivot(canvas_origin: Vector2) -> void:
	var node := _get_selected_model_node()
	if node == null:
		return
	var old_transform := node.get_global_transform_with_canvas()
	var local_pivot := _snap_pixel_position(old_transform.affine_inverse() * canvas_origin)
	var snapped_canvas_origin := old_transform * local_pivot
	var next_transform := old_transform
	next_transform.origin = snapped_canvas_origin
	var local_shift := next_transform.affine_inverse() * old_transform.origin
	var old_rotation := node.rotation
	var old_scale := node.scale

	_set_node_canvas_origin(node, snapped_canvas_origin, false)
	_shift_node_local_content(node, local_shift)
	_rebase_parameter_states_for_pivot(
		node,
		local_pivot,
		local_shift,
		old_rotation,
		old_scale,
	)
	model_render_changed.emit(false, false)
	refresh_overlay()


func _shift_node_local_content(node: Node2D, local_shift: Vector2) -> void:
	if node is TwberMeshSprite2D:
		(node as TwberMeshSprite2D).shift_local_geometry(local_shift)
	elif node is Sprite2D:
		(node as Sprite2D).offset += local_shift
	elif node is AnimatedSprite2D:
		(node as AnimatedSprite2D).offset += local_shift
	for child: Node in node.get_children():
		if child is Node2D:
			child.position += local_shift


func _rebase_parameter_states_for_neutral_transform(
		node: Node2D,
		position_delta: Vector2,
		rotation_delta: float,
		scale_delta: Vector2,
) -> void:
	var layer_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	if layer_id.is_empty():
		return
	for state: TwberLayerStateResource in _get_parameter_states_for_layer(layer_id):
		if state.has_channel(TwberLayerStateResource.Channel.POSITION):
			state.position += position_delta
		if state.has_channel(TwberLayerStateResource.Channel.ROTATION):
			state.rotation = wrapf(state.rotation + rotation_delta, -PI, PI)
		if state.has_channel(TwberLayerStateResource.Channel.SCALE):
			state.scale += scale_delta


func _rebase_parameter_states_for_pivot(
		node: Node2D,
		local_pivot: Vector2,
		local_shift: Vector2,
		base_rotation: float,
		base_scale: Vector2,
) -> void:
	var layer_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	for state: TwberLayerStateResource in _get_parameter_states_for_layer(layer_id):
		if state.has_channel(TwberLayerStateResource.Channel.POSITION):
			var state_rotation := (
				state.rotation
				if state.has_channel(TwberLayerStateResource.Channel.ROTATION)
				else base_rotation
			)
			var state_scale := (
				state.scale
				if state.has_channel(TwberLayerStateResource.Channel.SCALE)
				else base_scale
			)
			state.position += Vector2(
				local_pivot.x * state_scale.x,
				local_pivot.y * state_scale.y,
			).rotated(state_rotation)
		if state.has_channel(TwberLayerStateResource.Channel.MESH):
			for vertex_index: int in state.mesh_vertices.size():
				state.mesh_vertices[vertex_index] += local_shift

	for child: Node in node.get_children():
		if child is not Node2D:
			continue
		var child_layer_id := String(child.get_meta(TwberModelCodec.LAYER_ID_META, ""))
		for child_state: TwberLayerStateResource in _get_parameter_states_for_layer(child_layer_id):
			if child_state.has_channel(TwberLayerStateResource.Channel.POSITION):
				child_state.position += local_shift


func _get_parameter_states_for_layer(layer_id: String) -> Array[TwberLayerStateResource]:
	var output: Array[TwberLayerStateResource] = []
	if layer_id.is_empty() or _model_root == null:
		return output
	var stored_parameters: Variant = _model_root.get_meta(TwberModelCodec.MODEL_PARAMETERS_META, [])
	if stored_parameters is not Array:
		return output
	for value: Variant in stored_parameters:
		if value is not TwberParameterResource:
			continue
		for parameter_position: TwberParameterPositionResource in value.positions:
			if parameter_position == null:
				continue
			var state := parameter_position.find_state(layer_id)
			if state != null:
				output.append(state)
	return output


func _get_tree_drag_data(at_position: Vector2) -> Variant:
	var item := _tree.get_item_at_position(at_position)
	if item == null or item == _root_item:
		return null

	var layer_id := _get_layer_id_from_item(item)
	if layer_id == INVALID_LAYER_ID:
		return null

	if not item.is_selected(TREE_COLUMN):
		_tree.deselect_all()
		item.select(TREE_COLUMN)

	var dragged_ids := _get_selected_layer_ids()
	if not dragged_ids.has(layer_id):
		dragged_ids = [layer_id]
	dragged_ids = _filter_top_level_layer_ids(dragged_ids)

	var preview_text := item.get_text(TREE_COLUMN)
	if dragged_ids.size() > 1:
		preview_text = "%d layers" % dragged_ids.size()

	_tree.set_drag_preview(_make_drag_preview(preview_text))
	return {
		"type": DRAG_DATA_TYPE,
		"tree": _tree,
		"layer_id": layer_id,
		"layer_ids": dragged_ids,
	}


func _can_drop_tree_data(at_position: Vector2, data: Variant) -> bool:
	var dragged_ids := _get_dragged_layer_ids(data)
	if dragged_ids.is_empty():
		_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
		return false

	_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	var target_item := _tree.get_item_at_position(at_position)
	var target_id := _get_layer_id_from_item(target_item)
	var drop_section := _tree.get_drop_section_at_position(at_position)
	if target_id == INVALID_LAYER_ID or dragged_ids.has(target_id) or drop_section == -100:
		_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
		return false

	for dragged_id: int in dragged_ids:
		if _is_layer_ancestor_of(dragged_id, target_id):
			_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
			return false

	return true


func _drop_tree_data(at_position: Vector2, data: Variant) -> void:
	var dragged_ids := _get_dragged_layer_ids(data)
	var target_item := _tree.get_item_at_position(at_position)
	var target_id := _get_layer_id_from_item(target_item)
	var drop_section := _tree.get_drop_section_at_position(at_position)

	if (
			dragged_ids.is_empty()
			or target_id == INVALID_LAYER_ID
			or dragged_ids.has(target_id)
			or drop_section == -100
	):
		_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
		return

	for dragged_id: int in dragged_ids:
		if _is_layer_ancestor_of(dragged_id, target_id):
			_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
			return

	_move_layers(dragged_ids, target_id, drop_section)
	_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED


func _on_tree_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return

	item.set_editable(TREE_COLUMN, true)
	_tree.edit_selected(true)


func _on_tree_item_edited() -> void:
	var item := _tree.get_edited()
	if item == null or _tree.get_edited_column() != TREE_COLUMN:
		return

	var layer_id := _get_layer_id_from_item(item)
	if layer_id == INVALID_LAYER_ID:
		return

	var layer: Dictionary = _layers_by_id[layer_id]
	var model_node: Node2D = layer["node"]
	var old_name := String(model_node.name)
	var new_name := item.get_text(TREE_COLUMN).strip_edges()
	if new_name.is_empty():
		item.set_text(TREE_COLUMN, old_name)
		return

	model_node.name = new_name
	item.set_text(TREE_COLUMN, model_node.name)


func _on_tree_item_selected() -> void:
	_set_selected_layer(_get_layer_id_from_item(_tree.get_selected()))


func _on_tree_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if selected:
		_set_selected_layer(_get_layer_id_from_item(item))


func _on_duplicate_button_pressed() -> void:
	if not _layers_by_id.has(_selected_layer_id):
		return

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var parent_id: int = layer["parent_id"]
	var siblings := _get_child_ids(parent_id)
	var selected_index := siblings.find(_selected_layer_id)
	if selected_index == -1:
		return

	var duplicate_id := _duplicate_layer_tree(_selected_layer_id, parent_id, true)
	siblings.insert(selected_index + 1, duplicate_id)

	_sync_model_tree()
	_rebuild_tree(duplicate_id)
	_set_selected_layer(duplicate_id)


func _on_delete_button_pressed() -> void:
	if not _layers_by_id.has(_selected_layer_id):
		return

	var deleted_layer: Dictionary = _layers_by_id[_selected_layer_id]
	var parent_id: int = deleted_layer["parent_id"]
	var siblings := _get_child_ids(parent_id)
	var deleted_index := siblings.find(_selected_layer_id)
	var next_selected_id := INVALID_LAYER_ID

	if deleted_index != -1:
		siblings.remove_at(deleted_index)
		if deleted_index < siblings.size():
			next_selected_id = siblings[deleted_index]
		elif not siblings.is_empty():
			next_selected_id = siblings[siblings.size() - 1]
		elif parent_id != ROOT_LAYER_ID:
			next_selected_id = parent_id

	_prune_parameter_states_for_layer_tree(_selected_layer_id)
	_delete_layer_tree(_selected_layer_id)
	model_render_changed.emit(false, true)

	_rebuild_tree(next_selected_id)
	_set_selected_layer(next_selected_id)


func _on_change_texture_button_pressed() -> void:
	if not _can_selected_layer_use_texture():
		return

	var layer_id := _selected_layer_id
	var layer: Dictionary = _layers_by_id[layer_id]
	var model_node: Node = layer["node"]
	var dialog: FileDialog
	if model_node is AnimatedSprite2D:
		dialog = _create_texture_file_dialog(FileDialog.FILE_MODE_OPEN_FILES, "Choose replacement animation frames")
		dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
			_on_replacement_animation_textures_selected(layer_id, paths)
			dialog.queue_free()
		)
	else:
		dialog = _create_texture_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Choose replacement texture")
		dialog.file_selected.connect(func(path: String) -> void:
			_on_replacement_texture_selected(layer_id, path)
			dialog.queue_free()
		)

	dialog.popup_centered_ratio(0.7)


func _on_replacement_texture_selected(layer_id: int, path: String) -> void:
	if not _layers_by_id.has(layer_id):
		return

	var texture := _load_texture_from_path(path)
	if texture == null:
		return

	var layer: Dictionary = _layers_by_id[layer_id]
	var model_node: Node = layer["node"]
	if model_node is Sprite2D:
		var sprite: Sprite2D = model_node
		var previous_default_offset := TwberTextureUtils.get_centered_sprite_offset(sprite.texture)
		var custom_offset := sprite.offset - previous_default_offset
		sprite.texture = texture
		sprite.offset = TwberTextureUtils.get_centered_sprite_offset(texture) + custom_offset
	elif model_node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = model_node
		mesh_sprite.replace_texture(texture)
	model_render_changed.emit(true, true)

	if layer_id == _selected_layer_id:
		_refresh_inspector()


func _on_replacement_animation_textures_selected(layer_id: int, paths: PackedStringArray) -> void:
	if not _layers_by_id.has(layer_id):
		return

	var layer: Dictionary = _layers_by_id[layer_id]
	var model_node: Node = layer["node"]
	if model_node is not AnimatedSprite2D:
		return
	var animated_sprite: AnimatedSprite2D = model_node

	var textures := _load_textures_from_paths(paths)
	if textures.is_empty():
		return

	var previous_texture := _get_layer_texture(layer)
	var previous_default_offset := TwberTextureUtils.get_centered_sprite_offset(previous_texture)
	var custom_offset := animated_sprite.offset - previous_default_offset
	_replace_animated_sprite_animation_frames(animated_sprite, textures)
	animated_sprite.offset = TwberTextureUtils.get_centered_sprite_offset(textures[0]) + custom_offset
	model_render_changed.emit(true, true)

	if layer_id == _selected_layer_id:
		_refresh_inspector()


func _on_visible_check_box_toggled(enabled: bool) -> void:
	if _updating_inspector or not _layers_by_id.has(_selected_layer_id):
		return

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var model_node: Node = layer["node"]
	if model_node is CanvasItem:
		var canvas_item: CanvasItem = model_node
		canvas_item.visible = enabled


func _on_show_behind_parent_toggled(enabled: bool) -> void:
	if _updating_inspector or not _layers_by_id.has(_selected_layer_id):
		return
	var model_node := _layers_by_id[_selected_layer_id]["node"] as CanvasItem
	if model_node == null:
		return
	model_node.show_behind_parent = enabled
	model_render_changed.emit(false, true)


func _on_opacity_slider_value_changed(value: float) -> void:
	if _updating_inspector or not _layers_by_id.has(_selected_layer_id):
		return

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var model_node: Node = layer["node"]
	if model_node is CanvasItem:
		var canvas_item := model_node as CanvasItem
		var color := TwberAlphaClipController.get_authored_self_modulate(canvas_item)
		color.a = value
		TwberAlphaClipController.set_authored_self_modulate(canvas_item, color)
		if canvas_item is TwberMeshSprite2D:
			var mesh_sprite: TwberMeshSprite2D = canvas_item
			mesh_sprite.sync_visual_state()
		else:
			model_render_changed.emit(false, false)


func _on_clip_option_button_item_selected(index: int) -> void:
	if _updating_inspector or not _layers_by_id.has(_selected_layer_id):
		return

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var model_node: Node = layer["node"]
	if model_node is CanvasItem:
		TwberAlphaClipController.set_authored_clip_mode(
			model_node as CanvasItem,
			index as CanvasItem.ClipChildrenMode,
		)
		model_render_changed.emit(false, true)


func _on_animation_frame_rate_value_changed(value: float) -> void:
	if _updating_inspector or not _layers_by_id.has(_selected_layer_id):
		return

	var animated_sprite := _get_selected_animated_sprite()
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
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


func _on_new_animation_button_pressed() -> void:
	var animated_sprite := _get_selected_animated_sprite()
	if animated_sprite == null:
		return

	_open_animation_name_dialog("New Animation", _make_unique_animation_name(animated_sprite, "Animation"), func(animation_name: String) -> void:
		_add_animation_to_sprite(animated_sprite, animation_name)
	)


func _on_delete_animation_button_pressed() -> void:
	var animated_sprite := _get_selected_animated_sprite()
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var sprite_frames := animated_sprite.sprite_frames
	var animation := _get_animated_sprite_animation(animated_sprite)
	if not sprite_frames.has_animation(animation) or sprite_frames.get_animation_names().size() <= 1:
		return

	sprite_frames.remove_animation(animation)
	var next_animation := _get_animated_sprite_animation(animated_sprite)
	animated_sprite.animation = next_animation
	animated_sprite.play(next_animation)
	_refresh_inspector()


func _on_rename_animation_button_pressed() -> void:
	var animated_sprite := _get_selected_animated_sprite()
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

	var old_name := _get_animated_sprite_animation(animated_sprite)
	if not animated_sprite.sprite_frames.has_animation(old_name):
		return

	_open_animation_name_dialog("Rename Animation", String(old_name), func(animation_name: String) -> void:
		_rename_animation_on_sprite(animated_sprite, old_name, animation_name)
	)


func _set_selected_layer(layer_id: int) -> void:
	if not _layers_by_id.has(layer_id):
		_selected_layer_id = INVALID_LAYER_ID
		_hide_inspector()
		refresh_overlay()
		return

	_selected_layer_id = layer_id
	_refresh_inspector()


func _hide_inspector() -> void:
	_inspector.visible = false
	_animations_box.visible = false
	_animations_option_button.clear()
	_set_texture_button_texture(null)


func _refresh_inspector() -> void:
	if not _layers_by_id.has(_selected_layer_id):
		_hide_inspector()
		return

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var model_node: Node = layer["node"]
	var has_layer_actions := _can_layer_use_texture(layer)
	var is_animated_layer := model_node is AnimatedSprite2D

	_updating_inspector = true
	_inspector.visible = true
	_layer_actions.visible = has_layer_actions
	_change_texture_button.visible = has_layer_actions
	_opacity_slider.visible = has_layer_actions
	_clip_option_button.visible = has_layer_actions
	_animation_frame_rate.visible = is_animated_layer
	_animations_box.visible = is_animated_layer

	if model_node is CanvasItem:
		var canvas_item: CanvasItem = model_node
		_visible_check_box.button_pressed = canvas_item.visible
		_show_behind_parent_check_box.button_pressed = canvas_item.show_behind_parent
		_opacity_slider.value = TwberAlphaClipController.get_authored_self_modulate(canvas_item).a
		var clip_mode := TwberAlphaClipController.get_authored_clip_mode(canvas_item)
		_clip_option_button.select(clampi(clip_mode, 0, _clip_option_button.item_count - 1))

	if has_layer_actions:
		_set_texture_button_texture(_get_layer_texture(layer))
	else:
		_set_texture_button_texture(null)

	if is_animated_layer and model_node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = model_node
		_refresh_animation_controls(animated_sprite)
		if animated_sprite.sprite_frames != null:
			var animation := _get_animated_sprite_animation(animated_sprite)
			if animated_sprite.sprite_frames.has_animation(animation):
				_animation_frame_rate.value = animated_sprite.sprite_frames.get_animation_speed(animation)
	else:
		_animations_option_button.clear()

	_updating_inspector = false
	refresh_overlay()


func _refresh_animation_controls(animated_sprite: AnimatedSprite2D) -> void:
	_animations_option_button.clear()
	_new_animation_button.disabled = false
	_delete_animation_button.disabled = true
	_rename_animation_button.disabled = true

	if animated_sprite.sprite_frames == null:
		_animations_option_button.disabled = true
		return

	var sprite_frames := animated_sprite.sprite_frames
	var animation_names := sprite_frames.get_animation_names()
	var current_animation := _get_animated_sprite_animation(animated_sprite)

	for index: int in animation_names.size():
		var animation_name: String = animation_names[index]
		_animations_option_button.add_item(animation_name, index)
		if StringName(animation_name) == current_animation:
			_animations_option_button.select(index)

	_animations_option_button.disabled = animation_names.is_empty()
	_delete_animation_button.disabled = animation_names.size() <= 1
	_rename_animation_button.disabled = animation_names.is_empty()


func _can_selected_layer_use_texture() -> bool:
	if not _layers_by_id.has(_selected_layer_id):
		return false

	return _can_layer_use_texture(_layers_by_id[_selected_layer_id])


func _can_layer_use_texture(layer: Dictionary) -> bool:
	var model_node: Node = layer["node"]
	return model_node is Sprite2D or model_node is AnimatedSprite2D or model_node is TwberMeshSprite2D


func _get_layer_texture(layer: Dictionary) -> Texture2D:
	var model_node: Node = layer["node"]
	if model_node is Sprite2D:
		return model_node.texture

	if model_node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = model_node
		return mesh_sprite.texture

	if model_node is AnimatedSprite2D:
		var animated_sprite: AnimatedSprite2D = model_node
		if animated_sprite.sprite_frames == null:
			return null

		var animation := _get_animated_sprite_animation(animated_sprite)
		if not animated_sprite.sprite_frames.has_animation(animation):
			return null

		if animated_sprite.sprite_frames.get_frame_count(animation) == 0:
			return null

		return animated_sprite.sprite_frames.get_frame_texture(animation, 0)

	return null


func _set_texture_button_texture(texture: Texture2D) -> void:
	var button_texture := _get_texture_button_preview(texture)
	_change_texture_button.texture_normal = button_texture
	_change_texture_button.texture_pressed = button_texture
	_change_texture_button.texture_hover = button_texture
	_change_texture_button.texture_disabled = button_texture


func _get_texture_button_preview(texture: Texture2D) -> Texture2D:
	if texture == null:
		return _texture_button_placeholder

	var cache_key: Variant = texture.resource_path
	if texture.resource_path.is_empty():
		cache_key = texture.get_instance_id()
	if _texture_preview_cache.has(cache_key):
		return _texture_preview_cache[cache_key]

	var preview_texture: Texture2D = texture
	var used_rect := TwberTextureUtils.get_visible_rect(texture)
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		var image := TwberTextureUtils.get_authoring_image(texture)
		if image != null:
			used_rect = _get_texture_alpha_used_rect(image)
	if used_rect.size.x > 0 and used_rect.size.y > 0:
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = texture
		atlas_texture.region = Rect2(used_rect.position, used_rect.size)
		preview_texture = atlas_texture

	_cache_texture_preview(cache_key, preview_texture)
	return preview_texture


func _cache_texture_preview(cache_key: Variant, texture: Texture2D) -> void:
	if _texture_preview_cache.has(cache_key):
		_texture_preview_cache_order.erase(cache_key)
	_texture_preview_cache[cache_key] = texture
	_texture_preview_cache_order.append(cache_key)
	while _texture_preview_cache_order.size() > TEXTURE_PREVIEW_CACHE_LIMIT:
		var oldest_key: Variant = _texture_preview_cache_order.pop_front()
		_texture_preview_cache.erase(oldest_key)


func _get_texture_alpha_used_rect(image: Image) -> Rect2i:
	return TwberTextureUtils.find_alpha_used_rect(image, TEXTURE_PREVIEW_ALPHA_THRESHOLD)


func _replace_animated_sprite_animation_frames(animated_sprite: AnimatedSprite2D, textures: Array[Texture2D]) -> void:
	if textures.is_empty():
		return

	if animated_sprite.sprite_frames == null:
		animated_sprite.sprite_frames = SpriteFrames.new()

	var sprite_frames := animated_sprite.sprite_frames
	var animation := _get_animated_sprite_animation(animated_sprite)
	if not sprite_frames.has_animation(animation):
		sprite_frames.add_animation(animation)

	sprite_frames.clear(animation)
	for texture: Texture2D in textures:
		sprite_frames.add_frame(animation, texture)

	animated_sprite.animation = animation
	animated_sprite.play(animation)


func _get_selected_animated_sprite() -> AnimatedSprite2D:
	if not _layers_by_id.has(_selected_layer_id):
		return null

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var model_node: Node = layer["node"]
	if model_node is AnimatedSprite2D:
		return model_node

	return null


func _get_animation_name_from_option(index: int) -> StringName:
	if index < 0 or index >= _animations_option_button.item_count:
		return &""

	return StringName(_animations_option_button.get_item_text(index))


func _add_animation_to_sprite(animated_sprite: AnimatedSprite2D, animation_name: String) -> void:
	if animated_sprite.sprite_frames == null:
		animated_sprite.sprite_frames = SpriteFrames.new()

	var sprite_frames := animated_sprite.sprite_frames
	var new_animation := StringName(_make_unique_animation_name(animated_sprite, animation_name))
	var source_animation := _get_animated_sprite_animation(animated_sprite)

	if not sprite_frames.has_animation(new_animation):
		sprite_frames.add_animation(new_animation)

	if sprite_frames.has_animation(source_animation):
		sprite_frames.set_animation_loop(new_animation, sprite_frames.get_animation_loop(source_animation))
		sprite_frames.set_animation_speed(new_animation, sprite_frames.get_animation_speed(source_animation))
		for frame_index: int in sprite_frames.get_frame_count(source_animation):
			sprite_frames.add_frame(
					new_animation,
					sprite_frames.get_frame_texture(source_animation, frame_index),
					sprite_frames.get_frame_duration(source_animation, frame_index)
			)

	animated_sprite.animation = new_animation
	animated_sprite.play(new_animation)
	_refresh_inspector()


func _rename_animation_on_sprite(animated_sprite: AnimatedSprite2D, old_name: StringName, animation_name: String) -> void:
	if animated_sprite.sprite_frames == null:
		return

	var sprite_frames := animated_sprite.sprite_frames
	if not sprite_frames.has_animation(old_name):
		return

	var new_name := StringName(_make_unique_animation_name(animated_sprite, animation_name, old_name))
	if new_name == old_name:
		_refresh_inspector()
		return

	sprite_frames.rename_animation(old_name, new_name)
	animated_sprite.animation = new_name
	animated_sprite.play(new_name)
	_refresh_inspector()


func _open_animation_name_dialog(title: String, initial_name: String, submitted: Callable) -> void:
	var dialog := AcceptDialog.new()
	var line_edit := LineEdit.new()

	dialog.title = title
	dialog.min_size = Vector2i(320, 96)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(func() -> void:
		_submit_animation_name_dialog(line_edit, dialog, submitted)
	)

	line_edit.text = initial_name
	line_edit.select_all()
	line_edit.text_submitted.connect(func(_text: String) -> void:
		_submit_animation_name_dialog(line_edit, dialog, submitted)
	)

	dialog.add_child(line_edit)
	add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus.call_deferred()


func _submit_animation_name_dialog(line_edit: LineEdit, dialog: AcceptDialog, submitted: Callable) -> void:
	var animation_name := line_edit.text.strip_edges()
	if animation_name.is_empty():
		dialog.queue_free()
		return

	submitted.call(animation_name)
	dialog.queue_free()


func _open_texture_dialog() -> void:
	var dialog := _create_texture_file_dialog(FileDialog.FILE_MODE_OPEN_FILES, "Choose sprite textures")
	dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		_on_textures_selected(paths)
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.7)


func _open_animation_texture_dialog() -> void:
	var dialog := _create_texture_file_dialog(FileDialog.FILE_MODE_OPEN_FILES, "Choose animation textures")
	dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		_on_animation_textures_selected(paths)
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.7)


func _on_texture_selected(path: String) -> void:
	var texture := _load_texture_from_path(path)
	if texture == null:
		return

	_create_layer(PlacerItemType.LAYER, _make_name_from_path(path), [texture])


func _on_textures_selected(paths: PackedStringArray) -> void:
	for path: String in paths:
		_on_texture_selected(path)


func _on_animation_textures_selected(paths: PackedStringArray) -> void:
	var textures := _load_textures_from_paths(paths)

	if textures.is_empty():
		return

	_create_layer(PlacerItemType.ANIMATION_LAYER, _make_name_from_path(paths[0]), textures)


func _load_textures_from_paths(paths: PackedStringArray) -> Array[Texture2D]:
	var records: Array[Dictionary] = []
	for path: String in paths:
		var record := _load_image_record_from_path(path)
		if not record.is_empty():
			records.append(record)

	var textures: Array[Texture2D] = []
	if records.is_empty():
		return textures

	var forced_trim_rect := _get_shared_animation_trim_rect(records)
	for record: Dictionary in records:
		var texture := _create_texture_from_image_record(record, forced_trim_rect)
		if texture != null:
			textures.append(texture)

	return textures


func _create_texture_file_dialog(file_mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = file_mode
	dialog.filters = PackedStringArray([IMAGE_FILTER])
	dialog.use_native_dialog = false
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	return dialog


func _load_texture_from_path(selected_path: String) -> Texture2D:
	var record := _load_image_record_from_path(selected_path)
	if record.is_empty():
		return null
	return _create_texture_from_image_record(record)


func _load_image_record_from_path(selected_path: String) -> Dictionary:
	var path := _normalize_texture_path(selected_path)
	if path.begins_with("res://"):
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			var source_image := Image.new()
			if source_image.load(absolute_path) == OK:
				return {
					"image": source_image,
					"path": path,
					"name": _make_name_from_path(path),
				}
	if path.begins_with("res://") or path.begins_with("uid://"):
		var resource := load(path)
		if resource is Texture2D:
			var resource_texture: Texture2D = resource
			var resource_image := TwberTextureUtils.get_readable_image(resource_texture)
			if resource_image != null:
				return {
					"image": resource_image,
					"path": path,
					"name": resource_texture.resource_name,
				}

		push_warning("Selected file is not a Texture2D: %s" % selected_path)
		return {}

	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		push_warning("Could not load image file %s: %s" % [selected_path, error_string(error)])
		return {}

	return {
		"image": image,
		"path": path,
		"name": _make_name_from_path(path),
	}


func _create_texture_from_image_record(
		record: Dictionary,
		forced_trim_rect: Rect2i = Rect2i(),
) -> Texture2D:
	var source_image: Image = record.get("image") as Image
	if source_image == null:
		return null

	var trim_enabled := (
			_editor_settings != null
			and _editor_settings.trim_transparent_borders
	)
	if forced_trim_rect.size.x < 0 or forced_trim_rect.size.y < 0:
		trim_enabled = false
		forced_trim_rect = Rect2i()
	var alpha_threshold := (
			_editor_settings.trim_alpha_threshold
			if _editor_settings != null
			else TwberEditorSettings.DEFAULT_TRIM_ALPHA_THRESHOLD
	)
	var trim_padding := (
			_editor_settings.trim_padding
			if _editor_settings != null
			else TwberEditorSettings.DEFAULT_TRIM_PADDING
	)
	var prepared := TwberTextureUtils.prepare_image(
			source_image,
			trim_enabled,
			alpha_threshold,
			trim_padding,
			forced_trim_rect,
	)
	if prepared.is_empty():
		return null

	var image: Image = prepared["image"]
	_runtime_compress_image_if_needed(String(record.get("path", "")), image)
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = String(record.get("name", ""))
	texture.set_meta(TwberModelCodec.TEXTURE_SOURCE_PATH_META, String(record.get("path", "")))
	TwberTextureUtils.apply_metadata(texture, prepared)
	return texture


func _get_shared_animation_trim_rect(records: Array[Dictionary]) -> Rect2i:
	if _editor_settings == null or not _editor_settings.trim_transparent_borders:
		return Rect2i()
	if records.is_empty():
		return Rect2i()

	var first_image: Image = records[0].get("image") as Image
	if first_image == null:
		return Rect2i()
	var shared_size := Vector2i(first_image.get_width(), first_image.get_height())
	var union_rect := Rect2i()
	for record: Dictionary in records:
		var image: Image = record.get("image") as Image
		if image == null or Vector2i(image.get_width(), image.get_height()) != shared_size:
			# AnimatedSprite2D has one offset for every frame. Keeping mixed-size
			# frames untrimmed prevents per-frame alignment shifts.
			return Rect2i(Vector2i(-1, -1), Vector2i(-1, -1))
		var used_rect := TwberTextureUtils.find_alpha_used_rect(
				image,
				_editor_settings.trim_alpha_threshold,
		)
		if used_rect.size.x <= 0 or used_rect.size.y <= 0:
			continue
		union_rect = used_rect if union_rect.size == Vector2i.ZERO else union_rect.merge(used_rect)

	return TwberTextureUtils.padded_rect(
			union_rect,
			_editor_settings.trim_padding,
			shared_size,
	)


func _normalize_texture_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("uid://") or path.begins_with("user://"):
		return path

	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	var normalized_path := path.replace("\\", "/")
	if not project_root.ends_with("/"):
		project_root += "/"

	if normalized_path.begins_with(project_root):
		return "res://%s" % normalized_path.substr(project_root.length())

	return path


func _runtime_compress_image_if_needed(path: String, image: Image) -> bool:
	if _editor_settings == null:
		return false
	if image.is_compressed():
		return false
	if not _editor_settings.should_vram_compress_size(image.get_width(), image.get_height()):
		return false

	var error := image.compress(TEXTURE_RUNTIME_COMPRESS_MODE, TEXTURE_RUNTIME_COMPRESS_SOURCE)
	if error != OK:
		push_warning("Could not runtime-compress texture %s: %s" % [path, error_string(error)])
		return false

	return true


func _create_layer(item_type: int, layer_name: String = "", textures: Array = []) -> void:
	_item_counts[item_type] += 1

	if layer_name.is_empty():
		layer_name = "%s %d" % [_get_item_type_label(item_type), _item_counts[item_type]]

	var layer_id := _next_item_id
	var parent_id := ROOT_LAYER_ID
	var model_node := _create_model_node(item_type, layer_name, textures)
	_layers_by_id[layer_id] = {
		"parent_id": parent_id,
		"children": [],
		"node": model_node,
	}
	_get_child_ids(parent_id).append(layer_id)

	_next_item_id += 1
	_sync_model_tree()
	model_render_changed.emit(true, true)
	_rebuild_tree(layer_id)
	_set_selected_layer(layer_id)


func _create_model_node(item_type: int, layer_name: String, textures: Array) -> Node2D:
	var node: Node2D
	match item_type:
		PlacerItemType.LAYER:
			var sprite := Sprite2D.new()
			if not textures.is_empty() and textures[0] is Texture2D:
				sprite.texture = textures[0]
				sprite.offset = TwberTextureUtils.get_centered_sprite_offset(sprite.texture)
			node = sprite
		PlacerItemType.ANIMATION_LAYER:
			var animated_sprite := AnimatedSprite2D.new()
			animated_sprite.sprite_frames = _create_sprite_frames(textures)
			if not textures.is_empty() and textures[0] is Texture2D:
				animated_sprite.offset = TwberTextureUtils.get_centered_sprite_offset(textures[0])
			animated_sprite.animation = &"default"
			animated_sprite.autoplay = "default"
			animated_sprite.play(&"default")
			node = animated_sprite
		PlacerItemType.EMPTY:
			node = Node2D.new()
		_:
			node = Node2D.new()

	node.name = layer_name
	return node


func _create_sprite_frames(textures: Array) -> SpriteFrames:
	var sprite_frames := SpriteFrames.new()
	if not sprite_frames.has_animation(&"default"):
		sprite_frames.add_animation(&"default")

	sprite_frames.clear(&"default")
	sprite_frames.set_animation_loop(&"default", true)
	sprite_frames.set_animation_speed(&"default", 4.0)

	for texture: Variant in textures:
		if texture is Texture2D:
			sprite_frames.add_frame(&"default", texture)

	return sprite_frames


func _mirror_layers(settings: Dictionary, requested_source_ids: Array) -> void:
	var source_ids := _filter_top_level_layer_ids(requested_source_ids)
	if source_ids.is_empty() or _model_root == null:
		return
	TwberModelCodec.ensure_layer_ids(_model_root)

	var placer_id_mapping := {}
	var duplicated_root_ids: Array[int] = []
	for source_id: int in source_ids:
		if not _layers_by_id.has(source_id):
			continue
		var source_layer: Dictionary = _layers_by_id[source_id]
		var parent_id: int = source_layer["parent_id"]
		var duplicate_id := _duplicate_layer_tree(source_id, parent_id, false)
		_map_mirrored_layer_tree(source_id, duplicate_id, placer_id_mapping)
		_apply_mirror_to_layer_tree(
			source_id,
			duplicate_id,
			bool(settings.get("geometry_x", true)),
			bool(settings.get("geometry_y", false)),
		)
		var siblings := _get_child_ids(parent_id)
		var source_index := siblings.find(source_id)
		siblings.insert(source_index + 1 if source_index >= 0 else siblings.size(), duplicate_id)
		duplicated_root_ids.append(duplicate_id)

	if duplicated_root_ids.is_empty():
		return
	_sync_model_tree()
	TwberModelCodec.ensure_layer_ids(_model_root)
	_copy_mirrored_parameter_bindings(settings, placer_id_mapping)
	_rebuild_tree()
	_select_layer_ids(duplicated_root_ids)
	_set_selected_layer(duplicated_root_ids[duplicated_root_ids.size() - 1])


func _map_mirrored_layer_tree(source_id: int, duplicate_id: int, output: Dictionary) -> void:
	output[source_id] = duplicate_id
	var source_children: Array = _layers_by_id[source_id]["children"]
	var duplicate_children: Array = _layers_by_id[duplicate_id]["children"]
	for index: int in mini(source_children.size(), duplicate_children.size()):
		_map_mirrored_layer_tree(source_children[index], duplicate_children[index], output)


func _apply_mirror_to_layer_tree(
		source_id: int,
		duplicate_id: int,
		mirror_x: bool,
		mirror_y: bool,
) -> void:
	var source_layer: Dictionary = _layers_by_id[source_id]
	var duplicate_layer: Dictionary = _layers_by_id[duplicate_id]
	var duplicate_node := duplicate_layer["node"] as Node2D
	var parent_id: int = duplicate_layer["parent_id"]
	duplicate_node.name = _make_unique_layer_name(
		parent_id,
		_get_mirrored_name(String((source_layer["node"] as Node2D).name)),
	)
	_mirror_node_data(duplicate_node, mirror_x, mirror_y)

	var source_children: Array = source_layer["children"]
	var duplicate_children: Array = duplicate_layer["children"]
	for index: int in mini(source_children.size(), duplicate_children.size()):
		_apply_mirror_to_layer_tree(
			source_children[index],
			duplicate_children[index],
			mirror_x,
			mirror_y,
		)


func _mirror_node_data(node: Node2D, mirror_x: bool, mirror_y: bool) -> void:
	node.position = _mirror_vector(node.position, mirror_x, mirror_y)
	if mirror_x != mirror_y:
		node.rotation = wrapf(-node.rotation, -PI, PI)

	if node is TwberMeshSprite2D:
		var mesh_sprite := node as TwberMeshSprite2D
		if mesh_sprite.mesh_data != null:
			mesh_sprite.mesh_data.texture_origin = _mirror_vector(
				mesh_sprite.mesh_data.texture_origin,
				mirror_x,
				mirror_y,
			)
			_mirror_packed_vectors(mesh_sprite.mesh_data.vertices, mirror_x, mirror_y)
			_mirror_packed_vectors(mesh_sprite.mesh_data.rest_vertices, mirror_x, mirror_y)
			mesh_sprite.sync_mesh()
	elif node is Sprite2D:
		var sprite := node as Sprite2D
		sprite.offset = _mirror_vector(sprite.offset, mirror_x, mirror_y)
		if mirror_x:
			sprite.flip_h = not sprite.flip_h
		if mirror_y:
			sprite.flip_v = not sprite.flip_v
	elif node is AnimatedSprite2D:
		var animated_sprite := node as AnimatedSprite2D
		animated_sprite.offset = _mirror_vector(animated_sprite.offset, mirror_x, mirror_y)
		if mirror_x:
			animated_sprite.flip_h = not animated_sprite.flip_h
		if mirror_y:
			animated_sprite.flip_v = not animated_sprite.flip_v


func _copy_mirrored_parameter_bindings(settings: Dictionary, placer_id_mapping: Dictionary) -> void:
	var layer_id_mapping := {}
	for source_placer_id: Variant in placer_id_mapping:
		var duplicate_placer_id := int(placer_id_mapping[source_placer_id])
		var source_node := _layers_by_id[int(source_placer_id)]["node"] as Node2D
		var duplicate_node := _layers_by_id[duplicate_placer_id]["node"] as Node2D
		var source_layer_id := String(source_node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
		var duplicate_layer_id := String(duplicate_node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
		if not source_layer_id.is_empty() and not duplicate_layer_id.is_empty():
			layer_id_mapping[source_layer_id] = duplicate_layer_id

	var parameters: Array[TwberParameterResource] = []
	for value: Variant in _model_root.get_meta(TwberModelCodec.MODEL_PARAMETERS_META, []):
		if value is TwberParameterResource:
			parameters.append(value)
	var source_parameters := parameters.duplicate()
	var create_new_parameters := bool(settings.get("new_parameter", false))
	for parameter: TwberParameterResource in source_parameters:
		var target_parameter := parameter
		if create_new_parameters:
			target_parameter = _make_mirrored_parameter(parameter, parameters, settings)
		var copied_any := _copy_parameter_layer_states(
			parameter,
			target_parameter,
			layer_id_mapping,
			settings,
		)
		if create_new_parameters and copied_any:
			parameters.append(target_parameter)

	_model_root.set_meta(TwberModelCodec.MODEL_PARAMETERS_META, parameters)


func _copy_parameter_layer_states(
		source_parameter: TwberParameterResource,
		target_parameter: TwberParameterResource,
		layer_id_mapping: Dictionary,
		settings: Dictionary,
) -> bool:
	var copied_any := false
	var source_positions := source_parameter.positions.duplicate()
	for source_position: TwberParameterPositionResource in source_positions:
		if source_position == null:
			continue
		var mirrored_states: Array[TwberLayerStateResource] = []
		var source_states := source_position.layer_states.duplicate()
		for source_state: TwberLayerStateResource in source_states:
			if source_state == null or not layer_id_mapping.has(source_state.layer_id):
				continue
			var mirrored_state := source_state.duplicate(true) as TwberLayerStateResource
			mirrored_state.layer_id = String(layer_id_mapping[source_state.layer_id])
			_mirror_layer_state_geometry(
				mirrored_state,
				bool(settings.get("geometry_x", true)),
				bool(settings.get("geometry_y", false)),
			)
			mirrored_states.append(mirrored_state)
		if mirrored_states.is_empty():
			continue

		var coordinate := _mirror_parameter_coordinate(source_parameter, source_position.coordinate, settings)
		var target_position := target_parameter.find_position(coordinate)
		if target_position == null:
			target_position = TwberParameterPositionResource.new()
			target_position.coordinate = coordinate
			target_parameter.positions.append(target_position)
		for mirrored_state: TwberLayerStateResource in mirrored_states:
			target_position.upsert_state(mirrored_state)
		copied_any = true
	return copied_any


func _make_mirrored_parameter(
		source: TwberParameterResource,
		existing_parameters: Array[TwberParameterResource],
		settings: Dictionary,
) -> TwberParameterResource:
	var mirrored := source.duplicate(true) as TwberParameterResource
	mirrored.positions.clear()
	mirrored.name = _make_unique_parameter_name_for_mirror(
		_get_mirrored_name(source.name),
		existing_parameters,
	)
	mirrored.id = _make_unique_parameter_id_for_mirror(
		_get_mirrored_name(source.id),
		existing_parameters,
	)
	var mirrored_default := _mirror_parameter_coordinate(
		source,
		source.coordinate_from_value(source.get_default_value()),
		settings,
	)
	match source.value_type:
		TwberParameterResource.ValueType.BOOL:
			mirrored.default_bool = mirrored_default.x >= 0.5
		TwberParameterResource.ValueType.INT:
			mirrored.default_int = int(roundf(mirrored_default.x))
		TwberParameterResource.ValueType.VECTOR2:
			mirrored.default_vector2 = mirrored_default
		_:
			mirrored.default_float = mirrored_default.x
	return mirrored


func _mirror_parameter_coordinate(
		parameter: TwberParameterResource,
		coordinate: Vector2,
		settings: Dictionary,
) -> Vector2:
	var output := coordinate
	if bool(settings.get("bindings_x", false)):
		if parameter.value_type == TwberParameterResource.ValueType.VECTOR2:
			output.x = parameter.get_vector_min().x + parameter.get_vector_max().x - output.x
		else:
			output.x = parameter.get_scalar_min() + parameter.get_scalar_max() - output.x
	if (
		bool(settings.get("bindings_y", false))
		and parameter.value_type == TwberParameterResource.ValueType.VECTOR2
	):
		output.y = parameter.get_vector_min().y + parameter.get_vector_max().y - output.y
	return parameter.clamp_coordinate(output)


func _mirror_layer_state_geometry(
		state: TwberLayerStateResource,
		mirror_x: bool,
		mirror_y: bool,
) -> void:
	if state.has_channel(TwberLayerStateResource.Channel.POSITION):
		state.position = _mirror_vector(state.position, mirror_x, mirror_y)
	if state.has_channel(TwberLayerStateResource.Channel.ROTATION) and mirror_x != mirror_y:
		state.rotation = wrapf(-state.rotation, -PI, PI)
	if state.has_channel(TwberLayerStateResource.Channel.MESH):
		_mirror_packed_vectors(state.mesh_vertices, mirror_x, mirror_y)


func _mirror_packed_vectors(values: PackedVector2Array, mirror_x: bool, mirror_y: bool) -> void:
	for index: int in values.size():
		values[index] = _mirror_vector(values[index], mirror_x, mirror_y)


func _mirror_vector(value: Vector2, mirror_x: bool, mirror_y: bool) -> Vector2:
	return Vector2(-value.x if mirror_x else value.x, -value.y if mirror_y else value.y)


func _get_mirrored_name(source_name: String) -> String:
	var pairs := [
		["Left", "Right"], ["left", "right"], ["LEFT", "RIGHT"],
		["_L", "_R"], [".L", ".R"], ["-L", "-R"], [" L", " R"],
	]
	for pair: Array in pairs:
		if source_name.contains(pair[0]):
			return source_name.replace(pair[0], pair[1])
		if source_name.contains(pair[1]):
			return source_name.replace(pair[1], pair[0])
	if source_name.ends_with("L"):
		return source_name.left(source_name.length() - 1) + "R"
	if source_name.ends_with("R"):
		return source_name.left(source_name.length() - 1) + "L"
	return "%s Mirror" % source_name


func _make_unique_parameter_name_for_mirror(
		desired_name: String,
		parameters: Array[TwberParameterResource],
) -> String:
	var used := {}
	for parameter: TwberParameterResource in parameters:
		used[parameter.name] = true
	return _make_unique_name(desired_name, used)


func _make_unique_parameter_id_for_mirror(
		desired_id: String,
		parameters: Array[TwberParameterResource],
) -> String:
	var base_id := desired_id.strip_edges().replace(" ", "_").to_lower()
	if base_id.is_empty():
		base_id = "parameter_mirror"
	var used := {}
	for parameter: TwberParameterResource in parameters:
		used[parameter.id] = true
	return _make_unique_name(base_id, used)


func _duplicate_layer_tree(source_id: int, parent_id: int, copy_root_name: bool) -> int:
	var source_layer: Dictionary = _layers_by_id[source_id]
	var source_node: Node2D = source_layer["node"]
	var duplicated_node := _duplicate_model_node_without_children(source_node)
	var layer_name := String(source_node.name)
	if copy_root_name:
		layer_name = _make_unique_layer_name(parent_id, "%s Copy" % layer_name)

	var layer_id := _next_item_id
	_next_item_id += 1

	duplicated_node.name = layer_name
	_layers_by_id[layer_id] = {
		"parent_id": parent_id,
		"children": [],
		"node": duplicated_node,
	}

	var source_children: Array = source_layer["children"]
	var duplicated_layer: Dictionary = _layers_by_id[layer_id]
	var duplicated_children: Array = duplicated_layer["children"]
	for source_child_id: int in source_children:
		duplicated_children.append(_duplicate_layer_tree(source_child_id, layer_id, false))

	return layer_id


func _duplicate_model_node_without_children(source_node: Node2D) -> Node2D:
	var duplicated_node := source_node.duplicate()
	if duplicated_node is not Node2D:
		return Node2D.new()
	if duplicated_node.has_meta(TwberModelCodec.LAYER_ID_META):
		duplicated_node.remove_meta(TwberModelCodec.LAYER_ID_META)

	for child: Node in duplicated_node.get_children():
		duplicated_node.remove_child(child)
		child.free()

	if duplicated_node is AnimatedSprite2D and duplicated_node.sprite_frames != null:
		duplicated_node.sprite_frames = duplicated_node.sprite_frames.duplicate(true)
	elif duplicated_node is TwberMeshSprite2D:
		var duplicated_mesh_sprite: TwberMeshSprite2D = duplicated_node
		if duplicated_mesh_sprite.mesh_data != null:
			duplicated_mesh_sprite.mesh_data = duplicated_mesh_sprite.mesh_data.duplicate(true)
			duplicated_mesh_sprite.sync_mesh()

	return duplicated_node


func _delete_layer_tree(layer_id: int) -> void:
	if not _layers_by_id.has(layer_id):
		return

	var layer: Dictionary = _layers_by_id[layer_id]
	var child_ids: Array = layer["children"].duplicate()
	for child_id: int in child_ids:
		_delete_layer_tree(child_id)

	var model_node: Node = layer["node"]
	if model_node.get_parent() != null:
		model_node.get_parent().remove_child(model_node)
	model_node.queue_free()
	_layers_by_id.erase(layer_id)


func _prune_parameter_states_for_layer_tree(layer_id: int) -> void:
	if _model_root == null or not _layers_by_id.has(layer_id):
		return

	TwberModelCodec.ensure_layer_ids(_model_root)
	var deleted_model_layer_ids := {}
	_collect_model_layer_ids(layer_id, deleted_model_layer_ids)

	var stored_parameters: Variant = _model_root.get_meta(
			TwberModelCodec.MODEL_PARAMETERS_META,
			[],
	)
	if stored_parameters is not Array:
		return

	for value: Variant in stored_parameters:
		if value is not TwberParameterResource:
			continue
		var parameter: TwberParameterResource = value
		for position_index: int in range(parameter.positions.size() - 1, -1, -1):
			var parameter_position := parameter.positions[position_index]
			if parameter_position == null:
				parameter.positions.remove_at(position_index)
				continue
			for model_layer_id: Variant in deleted_model_layer_ids:
				parameter_position.remove_state(String(model_layer_id))
			if parameter_position.layer_states.is_empty():
				parameter.positions.remove_at(position_index)

	_model_root.set_meta(TwberModelCodec.MODEL_PARAMETERS_META, stored_parameters)


func _collect_model_layer_ids(layer_id: int, output: Dictionary) -> void:
	var layer: Dictionary = _layers_by_id[layer_id]
	var model_node: Node2D = layer["node"]
	var model_layer_id := String(model_node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	if not model_layer_id.is_empty():
		output[model_layer_id] = true

	for child_id: int in layer["children"]:
		_collect_model_layer_ids(child_id, output)


func _move_layers(dragged_ids: Array, target_id: int, drop_section: int) -> void:
	var moving_ids := _filter_top_level_layer_ids(dragged_ids)
	if moving_ids.is_empty() or not _layers_by_id.has(target_id) or moving_ids.has(target_id):
		return

	for dragged_id: int in moving_ids:
		if not _layers_by_id.has(dragged_id) or _is_layer_ancestor_of(dragged_id, target_id):
			return

	var new_parent_id := target_id
	if drop_section != 0:
		var target_layer: Dictionary = _layers_by_id[target_id]
		new_parent_id = target_layer["parent_id"]
	var new_parent_node: Node2D = (
		_model_root
		if new_parent_id == ROOT_LAYER_ID
		else _layers_by_id[new_parent_id]["node"] as Node2D
	)
	for dragged_id: int in moving_ids:
		var moving_node := _layers_by_id[dragged_id]["node"] as Node2D
		var old_parent := moving_node.get_parent() as Node2D
		if old_parent != null and old_parent != new_parent_node:
			_rebase_parameter_states_for_reparent(moving_node, old_parent, new_parent_node)

	for dragged_id: int in moving_ids:
		var dragged_layer: Dictionary = _layers_by_id[dragged_id]
		_remove_child_id(dragged_layer["parent_id"], dragged_id)

	var insert_index := _get_child_ids(new_parent_id).size()
	if drop_section != 0:
		var siblings := _get_child_ids(new_parent_id)
		var target_index := siblings.find(target_id)
		if target_index == -1:
			return

		insert_index = target_index
		if drop_section > 0:
			insert_index += 1

	for dragged_id: int in moving_ids:
		var dragged_layer: Dictionary = _layers_by_id[dragged_id]
		_insert_child_id(new_parent_id, dragged_id, insert_index)
		dragged_layer["parent_id"] = new_parent_id
		insert_index += 1

	_sync_model_tree()
	_rebuild_tree()
	_select_layer_ids(moving_ids)
	_set_selected_layer(moving_ids[moving_ids.size() - 1])


func _rebuild_tree(
		selected_layer_id: int = INVALID_LAYER_ID,
		preserved_collapsed_state: Dictionary = {},
) -> void:
	var collapsed_state := preserved_collapsed_state
	if collapsed_state.is_empty():
		collapsed_state = _get_tree_collapsed_state()
	if _model_root != null:
		TwberModelCodec.ensure_layer_ids(_model_root)
	_tree.clear()
	_tree_items_by_id.clear()
	_tree_state_keys_by_id.clear()
	_root_item = _tree.create_item()

	_add_layer_items(_root_item, _root_layer_ids, collapsed_state)

	if selected_layer_id != INVALID_LAYER_ID and _tree_items_by_id.has(selected_layer_id):
		var selected_item: TreeItem = _tree_items_by_id[selected_layer_id]
		selected_item.select(TREE_COLUMN)


func _add_layer_items(parent_item: TreeItem, layer_ids: Array, collapsed_state: Dictionary) -> void:
	for layer_id: int in layer_ids:
		var layer: Dictionary = _layers_by_id[layer_id]
		var model_node: Node2D = layer["node"]
		var item := _tree.create_item(parent_item)
		item.set_text(TREE_COLUMN, model_node.name)
		item.set_metadata(TREE_COLUMN, layer_id)
		item.set_editable(TREE_COLUMN, true)
		var state_key := _get_tree_state_key(model_node)
		_tree_state_keys_by_id[layer_id] = state_key
		if collapsed_state.has(state_key):
			item.set_collapsed(collapsed_state[state_key])
		_tree_items_by_id[layer_id] = item

		_add_layer_items(item, layer["children"], collapsed_state)


func _setup_preview() -> void:
	if _preview_layer == null:
		push_warning("EditorPlacer needs a preview CanvasLayer.")
		return

	_model_root = _get_or_create_model_root()
	_load_model_tree_from_preview()


func _get_or_create_model_root() -> Node2D:
	var existing_node := _preview_layer.get_node_or_null(MODEL_ROOT_NAME)
	if existing_node is Node2D:
		return existing_node

	if existing_node != null:
		push_warning("Preview CanvasLayer has a non-Node2D child named %s." % MODEL_ROOT_NAME)

	var model_root := Node2D.new()
	model_root.name = MODEL_ROOT_NAME
	model_root.position = _new_model_root_position
	model_root.scale = _new_model_root_scale
	_preview_layer.add_child(model_root)
	return model_root


func _load_model_tree_from_preview() -> void:
	_layers_by_id.clear()
	_root_layer_ids.clear()
	_tree_items_by_id.clear()
	_next_item_id = 1

	for item_type: int in _item_counts.keys():
		_item_counts[item_type] = 0

	_import_model_children(_model_root, ROOT_LAYER_ID, _root_layer_ids)


func _import_model_children(parent_node: Node, parent_id: int, child_ids: Array) -> void:
	for child: Node in parent_node.get_children():
		if child is not Node2D:
			continue

		var layer_id := _next_item_id
		var item_type := _get_item_type_from_model_node(child)
		_next_item_id += 1

		_layers_by_id[layer_id] = {
			"parent_id": parent_id,
			"children": [],
			"node": child,
		}
		child_ids.append(layer_id)
		_remember_imported_item_count(item_type, child.name)

		var layer: Dictionary = _layers_by_id[layer_id]
		_import_model_children(child, layer_id, layer["children"])


func _get_item_type_from_model_node(node: Node) -> int:
	if node is AnimatedSprite2D:
		return PlacerItemType.ANIMATION_LAYER
	if node is TwberMeshSprite2D:
		return PlacerItemType.LAYER
	if node is Sprite2D:
		return PlacerItemType.LAYER
	return PlacerItemType.EMPTY


func _remember_imported_item_count(item_type: int, layer_name: String) -> void:
	var label := _get_item_type_label(item_type)
	var prefix := "%s " % label
	if not layer_name.begins_with(prefix):
		return

	var count_text := layer_name.substr(prefix.length())
	if count_text.is_valid_int():
		_item_counts[item_type] = maxi(_item_counts[item_type], count_text.to_int())


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


func _make_unique_layer_name(parent_id: int, desired_name: String) -> String:
	var used_names := {}
	for child_id: int in _get_child_ids(parent_id):
		var layer: Dictionary = _layers_by_id[child_id]
		var model_node: Node2D = layer["node"]
		used_names[model_node.name] = true

	return _make_unique_name(desired_name, used_names)


func _make_unique_animation_name(animated_sprite: AnimatedSprite2D, desired_name: String, ignored_name: StringName = &"") -> String:
	var base_name := desired_name.strip_edges()
	if base_name.is_empty():
		base_name = "Animation"

	if animated_sprite.sprite_frames == null:
		return base_name

	var used_names := {}
	for animation_name: String in animated_sprite.sprite_frames.get_animation_names():
		if StringName(animation_name) == ignored_name:
			continue
		used_names[animation_name] = true

	return _make_unique_name(base_name, used_names)


func _make_unique_name(desired_name: String, used_names: Dictionary) -> String:
	if not used_names.has(desired_name):
		return desired_name

	var suffix := 2
	var unique_name := "%s %d" % [desired_name, suffix]
	while used_names.has(unique_name):
		suffix += 1
		unique_name = "%s %d" % [desired_name, suffix]

	return unique_name


func _sync_model_tree() -> void:
	if _model_root == null:
		return

	_sync_model_children(_model_root, _root_layer_ids)
	model_render_changed.emit(false, true)


func _sync_model_children(parent_node: Node, child_ids: Array) -> void:
	for index: int in child_ids.size():
		var child_id: int = child_ids[index]
		var layer: Dictionary = _layers_by_id[child_id]
		var model_node: Node = layer["node"]

		if model_node.get_parent() != parent_node:
			if model_node.get_parent() == null:
				parent_node.add_child(model_node)
			else:
				model_node.reparent(parent_node, true)

		parent_node.move_child(model_node, index)
		_sync_model_children(model_node, layer["children"])


func _rebase_parameter_states_for_reparent(
		node: Node2D,
		old_parent: Node2D,
		new_parent: Node2D,
) -> void:
	var layer_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	if layer_id.is_empty():
		return
	var old_to_new := (
		new_parent.get_global_transform_with_canvas().affine_inverse()
		* old_parent.get_global_transform_with_canvas()
	)
	for state: TwberLayerStateResource in _get_parameter_states_for_layer(layer_id):
		var state_position := (
			state.position
			if state.has_channel(TwberLayerStateResource.Channel.POSITION)
			else node.position
		)
		var state_rotation := (
			state.rotation
			if state.has_channel(TwberLayerStateResource.Channel.ROTATION)
			else node.rotation
		)
		var state_scale := (
			state.scale
			if state.has_channel(TwberLayerStateResource.Channel.SCALE)
			else node.scale
		)
		var rebased := old_to_new * Transform2D(
			state_rotation,
			state_scale,
			0.0,
			state_position,
		)
		if state.has_channel(TwberLayerStateResource.Channel.POSITION):
			state.position = rebased.origin
		if state.has_channel(TwberLayerStateResource.Channel.ROTATION):
			state.rotation = rebased.get_rotation()
		if state.has_channel(TwberLayerStateResource.Channel.SCALE):
			state.scale = rebased.get_scale()


func _get_tree_collapsed_state() -> Dictionary[String, bool]:
	var collapsed_state: Dictionary[String, bool] = {}
	for layer_id: int in _tree_items_by_id.keys():
		var item: TreeItem = _tree_items_by_id[layer_id]
		if item != null and _tree_state_keys_by_id.has(layer_id):
			collapsed_state[_tree_state_keys_by_id[layer_id]] = item.is_collapsed()

	return collapsed_state


func _get_tree_state_key(node: Node2D) -> String:
	var layer_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	if not layer_id.is_empty():
		return "layer:%s" % layer_id

	return "instance:%d" % node.get_instance_id()


func _get_selected_layer_ids() -> Array[int]:
	var selected_ids: Array[int] = []
	var item := _tree.get_next_selected(null)
	while item != null:
		var layer_id := _get_layer_id_from_item(item)
		if layer_id != INVALID_LAYER_ID:
			selected_ids.append(layer_id)
		item = _tree.get_next_selected(item)

	return selected_ids


func _select_layer_ids(layer_ids: Array) -> void:
	_tree.deselect_all()
	for layer_id: int in layer_ids:
		if _tree_items_by_id.has(layer_id):
			var item: TreeItem = _tree_items_by_id[layer_id]
			item.select(TREE_COLUMN)


func _filter_top_level_layer_ids(layer_ids: Array) -> Array[int]:
	var filtered_ids: Array[int] = []
	var seen := {}
	for layer_id: int in layer_ids:
		if not _layers_by_id.has(layer_id) or seen.has(layer_id):
			continue

		seen[layer_id] = true
		var has_selected_ancestor := false
		for possible_parent_id: int in layer_ids:
			if possible_parent_id != layer_id and _layers_by_id.has(possible_parent_id):
				if _is_layer_ancestor_of(possible_parent_id, layer_id):
					has_selected_ancestor = true
					break

		if not has_selected_ancestor:
			filtered_ids.append(layer_id)

	return filtered_ids


func _get_dragged_layer_ids(data: Variant) -> Array[int]:
	var layer_ids: Array[int] = []
	if not (data is Dictionary):
		return layer_ids

	var drag_data: Dictionary = data
	if drag_data.get("type") != DRAG_DATA_TYPE or drag_data.get("tree") != _tree:
		return layer_ids

	var raw_layer_ids: Variant = drag_data.get("layer_ids", [])
	if raw_layer_ids is Array:
		for layer_id: Variant in raw_layer_ids:
			if layer_id is int and _layers_by_id.has(layer_id):
				layer_ids.append(layer_id)

	if not layer_ids.is_empty():
		return _filter_top_level_layer_ids(layer_ids)

	var layer_id: Variant = drag_data.get("layer_id", INVALID_LAYER_ID)
	if layer_id is int and _layers_by_id.has(layer_id):
		layer_ids.append(layer_id)

	return layer_ids


func _get_layer_id_from_item(item: TreeItem) -> int:
	if item == null:
		return INVALID_LAYER_ID

	var layer_id: Variant = item.get_metadata(TREE_COLUMN)
	if layer_id is int and _layers_by_id.has(layer_id):
		return layer_id

	return INVALID_LAYER_ID


func _get_child_ids(parent_id: int) -> Array:
	if parent_id == ROOT_LAYER_ID:
		return _root_layer_ids

	return _layers_by_id[parent_id]["children"]


func _remove_child_id(parent_id: int, child_id: int) -> void:
	var child_ids := _get_child_ids(parent_id)
	var index := child_ids.find(child_id)
	if index != -1:
		child_ids.remove_at(index)


func _insert_child_id(parent_id: int, child_id: int, index: int) -> void:
	var child_ids := _get_child_ids(parent_id)
	child_ids.insert(clampi(index, 0, child_ids.size()), child_id)


func _is_layer_ancestor_of(parent_id: int, possible_child_id: int) -> bool:
	var current_id := possible_child_id
	while current_id != ROOT_LAYER_ID:
		var current_layer: Dictionary = _layers_by_id[current_id]
		var current_parent_id: int = current_layer["parent_id"]
		if current_parent_id == parent_id:
			return true
		current_id = current_parent_id

	return false


func _get_item_type_label(item_type: int) -> String:
	match item_type:
		PlacerItemType.LAYER:
			return "Layer"
		PlacerItemType.ANIMATION_LAYER:
			return "AnimatedLayer"
		PlacerItemType.EMPTY:
			return "Empty"
		_:
			return "Item"


func _make_name_from_path(path: String) -> String:
	var base_name := path.get_file().get_basename().strip_edges()
	if base_name.is_empty():
		return ""

	var parts := base_name.replace("-", "_").split("_", false)
	var layer_name := ""
	for part: String in parts:
		if part.is_empty():
			continue
		layer_name += part.substr(0, 1).to_upper() + part.substr(1)

	return layer_name if not layer_name.is_empty() else base_name


func _make_drag_preview(text: String) -> Control:
	var preview := PanelContainer.new()
	var margin := MarginContainer.new()
	var label := Label.new()

	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	label.text = text

	margin.add_child(label)
	preview.add_child(margin)
	return preview
