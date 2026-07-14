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

enum PlacerItemType {
	LAYER,
	ANIMATION_LAYER,
	EMPTY,
}

@onready var _layer_button: Button = %LayerButton
@onready var _animation_layer_button: Button = %AnimationLayerButton
@onready var _empty_button: Button = %EmptyButton
@onready var _tree: Tree = %Tree
@onready var _inspector: PanelContainer = %Inspector
@onready var _layer_actions: Control = %LayerActions
@onready var _change_texture_button: TextureButton = %ChangeTextureButton
@onready var _visible_check_box: CheckBox = %VisibleCheckBox
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


func _ready() -> void:
	_layer_button.pressed.connect(_on_add_item_pressed.bind(PlacerItemType.LAYER))
	_animation_layer_button.pressed.connect(_on_add_item_pressed.bind(PlacerItemType.ANIMATION_LAYER))
	_empty_button.pressed.connect(_on_add_item_pressed.bind(PlacerItemType.EMPTY))
	_duplicate_button.pressed.connect(_on_duplicate_button_pressed)
	_delete_button.pressed.connect(_on_delete_button_pressed)
	_change_texture_button.pressed.connect(_on_change_texture_button_pressed)
	_visible_check_box.toggled.connect(_on_visible_check_box_toggled)
	_opacity_slider.value_changed.connect(_on_opacity_slider_value_changed)
	_clip_option_button.item_selected.connect(_on_clip_option_button_item_selected)
	_animation_frame_rate.value_changed.connect(_on_animation_frame_rate_value_changed)
	_animations_option_button.item_selected.connect(_on_animation_selected)
	_new_animation_button.pressed.connect(_on_new_animation_button_pressed)
	_delete_animation_button.pressed.connect(_on_delete_animation_button_pressed)
	_rename_animation_button.pressed.connect(_on_rename_animation_button_pressed)

	_setup_preview()

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
			if model_node.get_parent() != null:
				model_node.get_parent().remove_child(model_node)
			parent_node.add_child(model_node)

		parent_node.move_child(model_node, index)
		_sync_model_children(model_node, layer["children"])


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
