class_name EditorPlacer extends HSplitContainer

const TREE_COLUMN := 0
const VISIBILITY_COLUMN := TREE_COLUMN
const VISIBILITY_BUTTON_ID := 0
const VISIBILITY_BUTTON_INDEX := 0
const DRAG_DATA_TYPE := &"editor_placer_tree_item"
const ROOT_LAYER_ID := 0
const INVALID_LAYER_ID := -1
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.webp ; Image files"
const MODEL_ROOT_NAME := "Textures"
const TREE_VISIBILITY_ICON_SIZE := Vector2i(24, 24)
const SHOW_ICON := preload("res://shared/assets/Icon_PictoIcon_Show.Png")
const HIDE_ICON := preload("res://shared/assets/Icon_PictoIcon_Hide.Png")

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
var _visibility_show_icon: Texture2D
var _visibility_hide_icon: Texture2D
var _updating_inspector := false
var _model_root: Node2D
var _next_item_id := 1
var _layers_by_id: Dictionary = {}
var _root_layer_ids: Array[int] = []
var _tree_items_by_id: Dictionary = {}
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
	_tree.button_clicked.connect(_on_tree_button_clicked)

	_texture_button_placeholder = _change_texture_button.texture_normal
	_animation_frame_rate.min_value = 0.1
	_animation_frame_rate.step = 0.1
	_visibility_show_icon = _make_tree_icon(SHOW_ICON)
	_visibility_hide_icon = _make_tree_icon(HIDE_ICON)
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
	_load_model_tree_from_preview()
	_rebuild_tree()
	_set_selected_layer(INVALID_LAYER_ID)


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
	var old_name: String = layer["name"]
	var new_name := item.get_text(TREE_COLUMN).strip_edges()
	if new_name.is_empty():
		item.set_text(TREE_COLUMN, old_name)
		return

	layer["name"] = new_name
	var model_node: Node = layer["node"]
	model_node.name = new_name
	_layers_by_id[layer_id] = layer
	item.set_text(TREE_COLUMN, new_name)


func _on_tree_button_clicked(
		item: TreeItem,
		column: int,
		id: int,
		mouse_button_index: int,
) -> void:
	if (
			column != VISIBILITY_COLUMN
			or id != VISIBILITY_BUTTON_ID
			or mouse_button_index != MOUSE_BUTTON_LEFT
	):
		return

	var layer_id := _get_layer_id_from_item(item)
	if layer_id == INVALID_LAYER_ID:
		return

	var collapsed_state := _get_tree_collapsed_state()
	_toggle_layer_visibility(layer_id)
	_restore_tree_collapsed_state(collapsed_state)


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

	_rebuild_tree(duplicate_id)
	_sync_model_tree()
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

	_delete_layer_tree(_selected_layer_id)

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

	var texture := load(path)
	if texture is not Texture2D:
		push_warning("Selected file is not a Texture2D: %s" % path)
		return

	var layer: Dictionary = _layers_by_id[layer_id]
	var model_node: Node = layer["node"]
	if model_node is Sprite2D:
		model_node.texture = texture
	elif model_node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = model_node
		mesh_sprite.texture = texture
		mesh_sprite.sync_mesh()

	if layer_id == _selected_layer_id:
		_refresh_inspector()


func _on_replacement_animation_textures_selected(layer_id: int, paths: PackedStringArray) -> void:
	if not _layers_by_id.has(layer_id):
		return

	var layer: Dictionary = _layers_by_id[layer_id]
	var animated_sprite: AnimatedSprite2D = layer["node"]
	if animated_sprite is not AnimatedSprite2D:
		return

	var textures := _load_textures_from_paths(paths)
	if textures.is_empty():
		return

	_replace_animated_sprite_animation_frames(animated_sprite, textures)

	if layer_id == _selected_layer_id:
		_refresh_inspector()


func _on_opacity_slider_value_changed(value: float) -> void:
	if _updating_inspector or not _layers_by_id.has(_selected_layer_id):
		return

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var model_node: Node = layer["node"]
	if model_node is CanvasItem:
		var canvas_item: CanvasItem = model_node
		var color := canvas_item.modulate
		color.a = value
		canvas_item.modulate = color


func _on_clip_option_button_item_selected(index: int) -> void:
	if _updating_inspector or not _layers_by_id.has(_selected_layer_id):
		return

	var layer: Dictionary = _layers_by_id[_selected_layer_id]
	var model_node: Node = layer["node"]
	if model_node is CanvasItem:
		model_node.clip_children = index


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
	_change_texture_button.visible = _can_layer_use_texture(layer)
	_opacity_slider.visible = has_layer_actions
	_clip_option_button.visible = has_layer_actions
	_animation_frame_rate.visible = is_animated_layer
	_animations_box.visible = is_animated_layer

	if model_node is CanvasItem:
		var canvas_item: CanvasItem = model_node
		_opacity_slider.value = canvas_item.modulate.a
		_clip_option_button.select(clampi(canvas_item.clip_children, 0, _clip_option_button.item_count - 1))

	if _can_layer_use_texture(layer):
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
		animated_sprite.sprite_frames = SpriteFrames.new()

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
	var image := texture.get_image()
	if image != null:
		var used_rect := image.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0:
			var atlas_texture := AtlasTexture.new()
			atlas_texture.atlas = texture
			atlas_texture.region = Rect2(used_rect.position, used_rect.size)
			preview_texture = atlas_texture

	_texture_preview_cache[cache_key] = preview_texture
	return preview_texture


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
	var texture := load(path)
	if texture is not Texture2D:
		push_warning("Selected file is not a Texture2D: %s" % path)
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
	var textures: Array[Texture2D] = []
	for path: String in paths:
		var texture := load(path)
		if texture is Texture2D:
			textures.append(texture)
		else:
			push_warning("Selected file is not a Texture2D: %s" % path)

	return textures


func _create_texture_file_dialog(file_mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.file_mode = file_mode
	dialog.filters = PackedStringArray([IMAGE_FILTER])
	dialog.use_native_dialog = false
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	return dialog


func _create_layer(item_type: int, layer_name: String = "", textures: Array = []) -> void:
	_item_counts[item_type] += 1

	if layer_name.is_empty():
		layer_name = "%s %d" % [_get_item_type_label(item_type), _item_counts[item_type]]

	var layer_id := _next_item_id
	var parent_id := ROOT_LAYER_ID
	var model_node := _create_model_node(item_type, layer_name, textures)
	_layers_by_id[layer_id] = {
		"id": layer_id,
		"type": item_type,
		"name": layer_name,
		"parent_id": parent_id,
		"children": [],
		"node": model_node,
	}
	_get_child_ids(parent_id).append(layer_id)

	_next_item_id += 1
	_rebuild_tree(layer_id)
	_sync_model_tree()
	_set_selected_layer(layer_id)


func _create_model_node(item_type: int, layer_name: String, textures: Array) -> Node2D:
	var node: Node2D
	match item_type:
		PlacerItemType.LAYER:
			var sprite := Sprite2D.new()
			if not textures.is_empty() and textures[0] is Texture2D:
				sprite.texture = textures[0]
			node = sprite
		PlacerItemType.ANIMATION_LAYER:
			var animated_sprite := AnimatedSprite2D.new()
			animated_sprite.sprite_frames = _create_sprite_frames(textures)
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
	var layer_name: String = source_layer["name"]
	if copy_root_name:
		layer_name = _make_unique_layer_name(parent_id, "%s Copy" % layer_name)

	var layer_id := _next_item_id
	_next_item_id += 1

	duplicated_node.name = layer_name
	_layers_by_id[layer_id] = {
		"id": layer_id,
		"type": source_layer["type"],
		"name": layer_name,
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


func _move_layer(dragged_id: int, target_id: int, drop_section: int) -> void:
	_move_layers([dragged_id], target_id, drop_section)


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
		_layers_by_id[dragged_id] = dragged_layer
		insert_index += 1

	_rebuild_tree()
	_sync_model_tree()
	_select_layer_ids(moving_ids)
	_set_selected_layer(moving_ids[moving_ids.size() - 1])


func _rebuild_tree(selected_layer_id: int = INVALID_LAYER_ID) -> void:
	var collapsed_state := _get_tree_collapsed_state()
	_tree.clear()
	_tree_items_by_id.clear()
	_root_item = _tree.create_item()

	_add_layer_items(_root_item, _root_layer_ids, collapsed_state)

	if selected_layer_id != INVALID_LAYER_ID and _tree_items_by_id.has(selected_layer_id):
		var selected_item: TreeItem = _tree_items_by_id[selected_layer_id]
		selected_item.select(TREE_COLUMN)


func _add_layer_items(parent_item: TreeItem, layer_ids: Array, collapsed_state: Dictionary) -> void:
	for layer_id: int in layer_ids:
		var layer: Dictionary = _layers_by_id[layer_id]
		var item := _tree.create_item(parent_item)
		item.set_text(TREE_COLUMN, layer["name"])
		item.set_metadata(TREE_COLUMN, layer_id)
		item.set_metadata(VISIBILITY_COLUMN, layer_id)
		item.set_editable(TREE_COLUMN, true)
		if collapsed_state.has(layer_id):
			item.set_collapsed(collapsed_state[layer_id])
		_update_visibility_button(item, _is_layer_visible(layer))
		_tree_items_by_id[layer_id] = item

		_add_layer_items(item, layer["children"], collapsed_state)


func _toggle_layer_visibility(layer_id: int) -> void:
	if not _layers_by_id.has(layer_id):
		return

	var layer: Dictionary = _layers_by_id[layer_id]
	var model_node: Node = layer["node"]
	if not (model_node is CanvasItem):
		return

	var canvas_item: CanvasItem = model_node
	canvas_item.visible = not canvas_item.visible

	if _tree_items_by_id.has(layer_id):
		var item: TreeItem = _tree_items_by_id[layer_id]
		var was_collapsed := item.is_collapsed()
		_update_visibility_button(item, canvas_item.visible)
		item.set_collapsed(was_collapsed)


func _is_layer_visible(layer: Dictionary) -> bool:
	var model_node: Node = layer["node"]
	if model_node is CanvasItem:
		var canvas_item: CanvasItem = model_node
		return canvas_item.visible

	return true


func _make_tree_icon(source: Texture2D) -> Texture2D:
	var image: Image = source.get_image()
	if image == null:
		return source

	image.resize(TREE_VISIBILITY_ICON_SIZE.x, TREE_VISIBILITY_ICON_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _update_visibility_button(item: TreeItem, layer_visible: bool) -> void:
	var icon: Texture2D = _visibility_show_icon
	var tooltip := "Hide layer"
	if not layer_visible:
		icon = _visibility_hide_icon
		tooltip = "Show layer"

	if item.get_button_count(VISIBILITY_COLUMN) == 0:
		item.add_button(VISIBILITY_COLUMN, icon, VISIBILITY_BUTTON_ID, false, tooltip)
	else:
		item.set_button(VISIBILITY_COLUMN, VISIBILITY_BUTTON_INDEX, icon)
		item.set_button_tooltip_text(VISIBILITY_COLUMN, VISIBILITY_BUTTON_INDEX, tooltip)
		item.set_button_description(VISIBILITY_COLUMN, VISIBILITY_BUTTON_INDEX, tooltip)


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
		var layer_name := child.name
		_next_item_id += 1

		_layers_by_id[layer_id] = {
			"id": layer_id,
			"type": item_type,
			"name": layer_name,
			"parent_id": parent_id,
			"children": [],
			"node": child,
		}
		child_ids.append(layer_id)
		_remember_imported_item_count(item_type, layer_name)

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
		used_names[layer["name"]] = true

	if not used_names.has(desired_name):
		return desired_name

	var suffix := 2
	var unique_name := "%s %d" % [desired_name, suffix]
	while used_names.has(unique_name):
		suffix += 1
		unique_name = "%s %d" % [desired_name, suffix]

	return unique_name


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

	if not used_names.has(base_name):
		return base_name

	var suffix := 2
	var unique_name := "%s %d" % [base_name, suffix]
	while used_names.has(unique_name):
		suffix += 1
		unique_name = "%s %d" % [base_name, suffix]

	return unique_name


func _sync_model_tree() -> void:
	if _model_root == null:
		return

	_sync_model_children(_model_root, _root_layer_ids)


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


func _get_tree_collapsed_state() -> Dictionary:
	var collapsed_state := {}
	for layer_id: int in _tree_items_by_id.keys():
		var item: TreeItem = _tree_items_by_id[layer_id]
		if item != null:
			collapsed_state[layer_id] = item.is_collapsed()

	return collapsed_state


func _restore_tree_collapsed_state(collapsed_state: Dictionary) -> void:
	for layer_id: int in collapsed_state.keys():
		if _tree_items_by_id.has(layer_id):
			var item: TreeItem = _tree_items_by_id[layer_id]
			item.set_collapsed(collapsed_state[layer_id])


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
