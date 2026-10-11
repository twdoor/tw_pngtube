class_name EditorPlacer extends TwberEditorTool

signal model_render_changed(rebuild_atlases: bool, reconfigure_batching: bool)
signal transform_committed(node: Node2D)
signal transform_cancelled

var prepare_transform: Callable
var execute_hierarchy_command: Callable
var execute_layer_command: Callable
var _previous_ids_by_document_id: Dictionary[String, int] = {}

const TREE_COLUMN := 0
const DRAG_DATA_TYPE := &"editor_placer_tree_item"
const ROOT_LAYER_ID := 0
const INVALID_LAYER_ID := -1
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.webp ; Image files"
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

@onready var _layer_button: Button = get_panel_control("LayerButton")
@onready var _animation_layer_button: Button = get_panel_control("AnimationLayerButton")
@onready var _empty_button: Button = get_panel_control("EmptyButton")
@onready var _pointer_button: Button = get_panel_control("PointerButton")
@onready var _move_button: Button = get_panel_control("MoveButton")
@onready var _rotate_button: Button = get_panel_control("RotateButton")
@onready var _scale_button: Button = get_panel_control("ScaleButton")
@onready var _pivot_button: Button = get_panel_control("PivotButton")
@onready var _mirror_button: Button = get_panel_control("MirrorButton")
@onready var _tree: Tree = get_panel_control("Tree")
@onready var _inspector: VBoxContainer = get_panel_control("Inspector")
@onready var _layer_actions: Control = get_panel_control("LayerActions")
@onready var _change_texture_button: TextureButton = get_panel_control("ChangeTextureButton")
@onready var _visible_check_box: CheckBox = get_panel_control("VisibleCheckBox")
@onready var _show_behind_parent_check_box: CheckBox = get_panel_control("ShowBehindParentCheckBox")
@onready var _opacity_slider: HSlider = get_panel_control("OpacitySlider")
@onready var _clip_option_button: OptionButton = get_panel_control("ClipOptionButton")
@onready var _animation_frame_rate: SpinBox = get_panel_control("AnimationFrameRate")
@onready var _animations_box: Control = get_panel_control("AnimationsBox")
@onready var _animations_option_button: OptionButton = get_panel_control("AnimationsOptionButton")
@onready var _new_animation_button: Button = get_panel_control("NewAnimationButton")
@onready var _delete_animation_button: Button = get_panel_control("DeleteAnimationButton")
@onready var _rename_animation_button: Button = get_panel_control("RenameAnimationButton")
@onready var _duplicate_button: Button = get_panel_control("DuplicateButton")
@onready var _delete_button: Button = get_panel_control("DeleteButton")

var _root_item: TreeItem
var _selected_layer_id := INVALID_LAYER_ID
var _texture_button_placeholder: Texture2D
var _texture_preview_cache: Dictionary = {}
var _texture_preview_cache_order: Array[Variant] = []
var _editor_settings: TwberEditorSettings
var _updating_inspector := false
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


func get_selected_document_layer_id() -> String:
	var node := _get_selected_model_node()
	return String(node.get_meta(TwberModelCodec.LAYER_ID_META, "")) if is_instance_valid(node) else ""


func select_document_layer(id: String) -> void:
	select_document_layers([id])


func select_document_layers(ids: Array[String]) -> void:
	var selected: Array[int] = []
	for key: int in _layers_by_id:
		var node := _layers_by_id[key]["node"] as Node2D
		if ids.has(String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))):
			selected.append(key)
	_select_layer_ids(selected)
	_set_selected_layer(selected.back() if not selected.is_empty() else INVALID_LAYER_ID)


func _document_ids(ids: Array) -> Array[String]:
	var result: Array[String] = []
	for id: int in ids:
		if _layers_by_id.has(id):
			var node := _layers_by_id[id]["node"] as Node2D
			result.append(String(node.get_meta(TwberModelCodec.LAYER_ID_META, "")))
	return result


func set_editor_settings(settings: TwberEditorSettings) -> void:
	_editor_settings = settings
	_texture_preview_cache.clear()
	_texture_preview_cache_order.clear()
	_refresh_inspector()


func refresh_overlay() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _setup_transform_overlay() -> void:
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_overlay.draw.connect(_on_overlay_draw)


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
	if not tool_active or _model_root == null:
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
	if prepare_transform.is_valid() and prepare_transform.call() != OK:
		return
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
		transform_committed.emit(node)
	refresh_overlay()


func is_transform_dragging() -> bool:
	return _dragging_transform


func cancel_transform_drag() -> void:
	if not _dragging_transform:
		return
	var node := _get_selected_model_node()
	_dragging_transform = false
	if is_instance_valid(node):
		node.position = _transform_start_position
		node.rotation = _transform_start_rotation
		node.scale = _transform_start_scale
	transform_cancelled.emit()
	refresh_overlay()


func finish_transform_drag() -> void:
	_finish_transform_drag()


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
	if node == null or not execute_layer_command.is_valid():
		return
	var transform := node.get_global_transform_with_canvas()
	if is_zero_approx(transform.determinant()):
		return
	var pivot := _snap_pixel_position(transform.affine_inverse() * canvas_origin)
	execute_layer_command.call(TwberSetPivot.new(get_selected_document_layer_id(), pivot))







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

	if execute_layer_command.is_valid():
		execute_layer_command.call(TwberEditLayer.new(String(model_node.get_meta(TwberModelCodec.LAYER_ID_META, "")), TwberEditLayer.Operation.SETTINGS, {"name": new_name}))


func _on_tree_item_selected() -> void:
	_set_selected_layer(_get_layer_id_from_item(_tree.get_selected()))


func _on_tree_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if selected:
		_set_selected_layer(_get_layer_id_from_item(item))


func _on_duplicate_button_pressed() -> void:
	if not execute_hierarchy_command.is_valid():
		return
	var ids := _document_ids(_get_selected_layer_ids())
	if ids.is_empty():
		ids = _document_ids([_selected_layer_id])
	execute_hierarchy_command.call(TwberDuplicateLayers.new(ids))


func _on_delete_button_pressed() -> void:
	if execute_hierarchy_command.is_valid():
		execute_hierarchy_command.call(TwberDeleteLayers.new(_document_ids([_selected_layer_id])))


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
	if texture != null:
		_submit_layer_edit(_layers_by_id[layer_id]["node"], TwberEditLayer.Operation.REPLACE_TEXTURE, {}, [texture])


func _on_replacement_animation_textures_selected(layer_id: int, paths: PackedStringArray) -> void:
	if not _layers_by_id.has(layer_id):
		return
	var node := _layers_by_id[layer_id]["node"] as AnimatedSprite2D
	if node == null:
		return
	var textures := _load_textures_from_paths(paths)
	if not textures.is_empty():
		_submit_layer_edit(node, TwberEditLayer.Operation.REPLACE_FRAMES, {"animation": String(node.animation)}, textures)


func _on_visible_check_box_toggled(enabled: bool) -> void:
	if not _updating_inspector:
		_submit_layer_edit(_get_selected_model_node(), TwberEditLayer.Operation.SETTINGS, {"visible": enabled})


func _on_show_behind_parent_toggled(enabled: bool) -> void:
	if not _updating_inspector:
		_submit_layer_edit(_get_selected_model_node(), TwberEditLayer.Operation.SETTINGS, {"show_behind_parent": enabled})


func _on_opacity_slider_value_changed(value: float) -> void:
	if not _updating_inspector:
		_submit_layer_edit(_get_selected_model_node(), TwberEditLayer.Operation.SETTINGS, {"opacity": value})


func _on_clip_option_button_item_selected(index: int) -> void:
	if not _updating_inspector:
		_submit_layer_edit(_get_selected_model_node(), TwberEditLayer.Operation.SETTINGS, {"clip_children": index})


func _on_animation_frame_rate_value_changed(value: float) -> void:
	if not _updating_inspector:
		_submit_layer_edit(_get_selected_animated_sprite(), TwberEditLayer.Operation.SET_ANIMATION_SPEED, {"speed": value})


func _on_animation_selected(index: int) -> void:
	if not _updating_inspector:
		_submit_layer_edit(_get_selected_animated_sprite(), TwberEditLayer.Operation.SELECT_ANIMATION, {"animation": String(_get_animation_name_from_option(index))})


func _on_new_animation_button_pressed() -> void:
	var animated_sprite := _get_selected_animated_sprite()
	if animated_sprite == null:
		return

	_open_animation_name_dialog("New Animation", _make_unique_animation_name(animated_sprite, "Animation"), func(animation_name: String) -> void:
		_add_animation_to_sprite(animated_sprite, animation_name)
	)


func _on_delete_animation_button_pressed() -> void:
	_submit_layer_edit(_get_selected_animated_sprite(), TwberEditLayer.Operation.DELETE_ANIMATION)


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
		document_layer_selected.emit("")
		_hide_inspector()
		refresh_overlay()
		return

	_selected_layer_id = layer_id
	_refresh_inspector()
	document_layer_selected.emit(get_selected_document_layer_id())


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
	_submit_layer_edit(animated_sprite, TwberEditLayer.Operation.CREATE_ANIMATION, {"name": animation_name})


func _rename_animation_on_sprite(animated_sprite: AnimatedSprite2D, old_name: StringName, animation_name: String) -> void:
	_submit_layer_edit(animated_sprite, TwberEditLayer.Operation.RENAME_ANIMATION, {"animation": String(old_name), "name": animation_name})


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
	if not execute_hierarchy_command.is_valid():
		return
	_item_counts[item_type] += 1
	if layer_name.is_empty():
		layer_name = "%s %d" % [_get_item_type_label(item_type), _item_counts[item_type]]
	execute_hierarchy_command.call(_make_create_layer_command(item_type, layer_name, textures))


func _make_create_layer_command(item_type: int, layer_name: String, textures: Array) -> TwberCreateLayer:
	var layer := TwberLayerResource.new()
	layer.name = layer_name
	var assets: Dictionary[String, Texture2D] = {}
	var sources: Dictionary[String, String] = {}
	var frames: Array[String] = []
	for value: Variant in textures:
		if value is Texture2D:
			var id := "import_%d" % assets.size()
			assets[id] = value
			sources[id] = TwberModelCodec._get_texture_source_path(value)
			frames.append(id)
	match item_type:
		PlacerItemType.LAYER:
			layer.type = TwberLayerResource.LayerType.SPRITE
			if not frames.is_empty():
				layer.texture_id = frames[0]
		PlacerItemType.ANIMATION_LAYER:
			layer.type = TwberLayerResource.LayerType.ANIMATED_SPRITE
			var animation := TwberAnimationResource.new()
			animation.frame_texture_ids = frames
			for _id: String in frames:
				animation.frame_durations.append(1.0)
			layer.animations.append(animation)
	if not frames.is_empty() and item_type != PlacerItemType.EMPTY:
		layer.offset = TwberTextureUtils.get_centered_sprite_offset(assets[frames[0]])
	return TwberCreateLayer.new(layer, "", assets, sources)


func _mirror_layers(settings: Dictionary, requested_source_ids: Array) -> void:
	if execute_hierarchy_command.is_valid():
		execute_hierarchy_command.call(TwberMirrorLayers.new(_document_ids(requested_source_ids), settings))


# Kept as a UI helper for the mirror dialog; geometry and binding edits live in
# the document command.
func _mirror_parameter_coordinate(parameter: TwberParameterResource, coordinate: Vector2, settings: Dictionary) -> Vector2:
	return TwberMirrorLayers.new([], settings)._mirror_parameter_coordinate(parameter, coordinate, settings)


func _submit_layer_edit(node: Node2D, operation: TwberEditLayer.Operation, data: Dictionary = {}, textures: Array[Texture2D] = []) -> void:
	if not is_instance_valid(node) or not execute_layer_command.is_valid():
		return
	var id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	execute_layer_command.call(TwberEditLayer.new(id, operation, data, textures))


func _move_layers(dragged_ids: Array, target_id: int, drop_section: int) -> void:
	if not execute_hierarchy_command.is_valid():
		return
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
	var parent_document_id := ""
	if new_parent_id != ROOT_LAYER_ID:
		parent_document_id = _document_ids([new_parent_id])[0]
	var before_id := ""
	if drop_section != 0:
		var siblings := _get_child_ids(new_parent_id).duplicate()
		for id: int in moving_ids:
			siblings.erase(id)
		var index := siblings.find(target_id) + (1 if drop_section > 0 else 0)
		if index < siblings.size():
			before_id = _document_ids([siblings[index]])[0]
	execute_hierarchy_command.call(TwberReparentLayers.new(_document_ids(moving_ids), parent_document_id, before_id))
	return


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
	assert(_model_root != null, "Tool controller needs a model root.")
	_load_model_tree_from_preview()


func _load_model_tree_from_preview() -> void:
	_previous_ids_by_document_id.clear()
	for id: int in _layers_by_id:
		var node := _layers_by_id[id]["node"] as Node2D
		if is_instance_valid(node):
			var document_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
			if not document_id.is_empty():
				_previous_ids_by_document_id[document_id] = id
	_layers_by_id.clear()
	_root_layer_ids.clear()
	_tree_items_by_id.clear()
	_next_item_id = 1
	for id: int in _previous_ids_by_document_id.values():
		_next_item_id = maxi(_next_item_id, id + 1)

	for item_type: int in _item_counts.keys():
		_item_counts[item_type] = 0

	_import_model_children(_model_root, ROOT_LAYER_ID, _root_layer_ids)


func _import_model_children(parent_node: Node, parent_id: int, child_ids: Array) -> void:
	for child: Node in parent_node.get_children():
		if child is not Node2D:
			continue

		var document_id := String(child.get_meta(TwberModelCodec.LAYER_ID_META, ""))
		var layer_id := int(_previous_ids_by_document_id.get(document_id, _next_item_id))
		var item_type := _get_item_type_from_model_node(child)
		_next_item_id = maxi(_next_item_id, layer_id + 1)

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
