extends TwberEnvironmentPackage

var _enabled := true
var _attachments: Dictionary = {}
var _drop_window: Window


func _process(_delta: float) -> void:
	if not _enabled:
		return
	for child_id: int in _attachments.keys():
		var attachment: Dictionary = _attachments[child_id]
		var child := (attachment.get("child") as WeakRef).get_ref() as Node2D
		var anchor := (attachment.get("anchor") as WeakRef).get_ref() as Node2D
		if child == null or anchor == null:
			_attachments.erase(child_id)
			continue
		var last_parent_transform := attachment.get("last_parent_transform") as Transform2D
		child.global_transform = anchor.global_transform * last_parent_transform.affine_inverse() * child.global_transform
		attachment["last_parent_transform"] = anchor.global_transform
		_attachments[child_id] = attachment


func set_stage_api(value: TwberStageApi) -> void:
	if stage_api != null:
		_disconnect_stage_api()
	super.set_stage_api(value)
	if stage_api == null:
		return
	stage_api.item_drag_started.connect(_on_item_drag_started)
	stage_api.item_drag_ended.connect(_on_item_drag_ended)
	stage_api.item_selected.connect(_on_item_selected)
	stage_api.item_removed.connect(_on_item_removed)
	_drop_window = get_window()
	if _drop_window != null and not _drop_window.files_dropped.is_connected(_on_files_dropped):
		_drop_window.files_dropped.connect(_on_files_dropped)


func get_package_name() -> String:
	return "Model Attachments"


func get_package_description() -> String:
	return "Drop one stage item over another to make it follow that model."


func get_default_enabled() -> bool:
	return true


func is_package_enabled() -> bool:
	return _enabled


func set_package_enabled(value: bool) -> void:
	_enabled = value
	set_process(value)
	if not value:
		_attachments.clear()


func _on_item_drag_started(item: Node2D) -> void:
	# Picking an attached item should move it independently immediately.
	_attachments.erase(item.get_instance_id())


func _on_item_selected(item: Node2D) -> void:
	if not _enabled or stage_api == null:
		return
	_bring_attached_children_forward(item)


func _on_files_dropped(files: PackedStringArray) -> void:
	if not _enabled or stage_api == null:
		return
	for path: String in files:
		if path.get_extension().to_lower() in ["png", "webp", "jpg", "jpeg"]:
			stage_api.add_image_asset(path)
			# Asset loading is asynchronous; process additional files after this one
			# rather than having them collide with the active background operation.
			return


func _bring_attached_children_forward(parent_item: Node2D) -> void:
	# Walk in current stage order so sibling attachments retain their stacking.
	for candidate: Node2D in stage_api.get_items():
		var attachment: Dictionary = _attachments.get(candidate.get_instance_id(), {})
		if attachment.is_empty():
			continue
		var parent_ref := attachment.get("parent_item") as WeakRef
		if parent_ref == null or parent_ref.get_ref() != parent_item:
			continue
		stage_api.bring_item_to_front(candidate)
		_bring_attached_children_forward(candidate)


func _on_item_drag_ended(item: Node2D) -> void:
	if not _enabled or stage_api == null:
		return
	var item_bounds := stage_api.get_item_bounds(item)
	var drop_point := item_bounds.get_center() if item_bounds.has_area() else item.global_position
	var items := stage_api.get_items()
	for index: int in range(items.size() - 1, -1, -1):
		var candidate := items[index]
		if candidate == item or _would_create_cycle(item, candidate):
			continue
		var candidate_bounds := stage_api.get_item_bounds(candidate)
		if candidate_bounds.has_area() and candidate_bounds.has_point(drop_point):
			var anchor := stage_api.get_attachment_anchor(candidate, drop_point)
			if anchor != null:
				_attach(item, candidate, anchor)
				return


func _attach(child: Node2D, parent_item: Node2D, anchor: Node2D) -> void:
	_attachments[child.get_instance_id()] = {
		"child": weakref(child),
		"parent_item": weakref(parent_item),
		"anchor": weakref(anchor),
		"last_parent_transform": anchor.global_transform,
	}


func _would_create_cycle(child: Node2D, candidate_parent: Node2D) -> bool:
	var current := candidate_parent
	while current != null:
		if current == child:
			return true
		var attachment: Dictionary = _attachments.get(current.get_instance_id(), {})
		if attachment.is_empty():
			return false
		var parent_ref := attachment.get("parent_item") as WeakRef
		current = parent_ref.get_ref() as Node2D if parent_ref != null else null
	return false


func _on_item_removed(item: Node2D) -> void:
	_attachments.erase(item.get_instance_id())
	for child_id: int in _attachments.keys():
		var attachment: Dictionary = _attachments[child_id]
		var parent_ref := attachment.get("parent_item") as WeakRef
		if parent_ref != null and parent_ref.get_ref() == item:
			_attachments.erase(child_id)


func _disconnect_stage_api() -> void:
	if _drop_window != null and _drop_window.files_dropped.is_connected(_on_files_dropped):
		_drop_window.files_dropped.disconnect(_on_files_dropped)
	_drop_window = null
	if stage_api.item_drag_started.is_connected(_on_item_drag_started):
		stage_api.item_drag_started.disconnect(_on_item_drag_started)
	if stage_api.item_drag_ended.is_connected(_on_item_drag_ended):
		stage_api.item_drag_ended.disconnect(_on_item_drag_ended)
	if stage_api.item_selected.is_connected(_on_item_selected):
		stage_api.item_selected.disconnect(_on_item_selected)
	if stage_api.item_removed.is_connected(_on_item_removed):
		stage_api.item_removed.disconnect(_on_item_removed)
