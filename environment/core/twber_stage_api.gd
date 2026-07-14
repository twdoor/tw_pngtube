class_name TwberStageApi extends RefCounted

@warning_ignore("unused_signal")
signal item_added(item: Node2D)
@warning_ignore("unused_signal")
signal item_removed(item: Node2D)
@warning_ignore("unused_signal")
signal item_selected(item: Node2D)
@warning_ignore("unused_signal")
signal item_drag_started(item: Node2D)
@warning_ignore("unused_signal")
signal item_drag_ended(item: Node2D)

var _get_items: Callable
var _get_bounds: Callable
var _get_source_path: Callable
var _add_image_asset: Callable
var _get_attachment_anchor: Callable
var _bring_item_to_front: Callable
var _set_background_color: Callable
var _set_background_image: Callable
var _clear_background: Callable


func configure(
		items_callable: Callable,
		bounds_callable: Callable,
		source_path_callable: Callable,
		add_image_asset_callable: Callable,
		attachment_anchor_callable: Callable,
		bring_item_to_front_callable: Callable,
		set_background_color_callable: Callable,
		set_background_image_callable: Callable,
		clear_background_callable: Callable,
) -> void:
	_get_items = items_callable
	_get_bounds = bounds_callable
	_get_source_path = source_path_callable
	_add_image_asset = add_image_asset_callable
	_get_attachment_anchor = attachment_anchor_callable
	_bring_item_to_front = bring_item_to_front_callable
	_set_background_color = set_background_color_callable
	_set_background_image = set_background_image_callable
	_clear_background = clear_background_callable


func get_items() -> Array[Node2D]:
	var output: Array[Node2D] = []
	if not _get_items.is_valid():
		return output
	for value: Variant in _get_items.call():
		if value is Node2D:
			output.append(value)
	return output


func get_item_bounds(item: Node2D) -> Rect2:
	return _get_bounds.call(item) as Rect2 if _get_bounds.is_valid() else Rect2()


func get_item_source_path(item: Node2D) -> String:
	return String(_get_source_path.call(item)) if _get_source_path.is_valid() else ""


func add_image_asset(path: String) -> void:
	if _add_image_asset.is_valid():
		_add_image_asset.call(path)


func get_attachment_anchor(item: Node2D, global_point: Vector2) -> Node2D:
	if not _get_attachment_anchor.is_valid():
		return null
	var anchor: Variant = _get_attachment_anchor.call(item, global_point)
	return anchor as Node2D if anchor is Node2D else null


func bring_item_to_front(item: Node2D) -> void:
	if _bring_item_to_front.is_valid():
		_bring_item_to_front.call(item)


func set_background_color(color: Color) -> void:
	if _set_background_color.is_valid():
		_set_background_color.call(color)


func set_background_image(path: String) -> void:
	if _set_background_image.is_valid():
		_set_background_image.call(path)


func clear_background() -> void:
	if _clear_background.is_valid():
		_clear_background.call()
