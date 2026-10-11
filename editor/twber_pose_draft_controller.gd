class_name TwberPoseDraftController extends RefCounted

signal changed
var _document: TwberModelDocument
var _root: Node2D
var _node: Node2D
var _session: TwberPoseEditSession
var _context: Dictionary = {}


func _init(document: TwberModelDocument, root: Node2D) -> void:
	_document = document
	_root = root


func has_draft() -> bool:
	return _session != null


func begin(node: Node2D, context: Dictionary) -> bool:
	if _session != null:
		if _node == node and _session.is_current() and _context == context:
			return true
		cancel()
	if not is_instance_valid(node):
		return false
	var id := String(node.get_meta(TwberModelCodec.LAYER_ID_META, ""))
	_session = TwberPoseEditSession.new(_document, id, context)
	if not _session.is_current():
		_session = null
		return false
	_node = node
	_context = context.duplicate(true)
	_project(_session.get_pose())
	changed.emit()
	return true


func pose() -> TwberLayerStateResource:
	return _session.get_pose() if _session != null else null


func neutral() -> TwberLayerStateResource:
	return TwberLayerStateResource.from_layer_resource(_session.get_layer()) if _session != null else null


func update(value: TwberLayerStateResource) -> Error:
	if _session == null:
		return ERR_UNCONFIGURED
	var error := _session.update(value)
	if error == OK:
		_project(_session.get_pose())
	elif error == ERR_BUSY:
		cancel()
	return error


func make_command() -> TwberDocumentCommand:
	return _session.make_command() if _session != null else null


func accept_name_revision() -> void:
	if _session != null:
		_session.accept_name_revision()


func finish_interaction() -> void:
	if _session != null and not _session.has_changes():
		cancel()


func cancel() -> bool:
	if _session == null:
		return false
	_project(_session.get_baseline())
	_session.cancel()
	_session = null
	_node = null
	_context.clear()
	changed.emit()
	return true


func _project(state: TwberLayerStateResource) -> void:
	if state == null or not is_instance_valid(_node):
		return
	# Restore frame rates before applying this pose, including animations that a
	# previous draft selected. Otherwise rate previews leak across cancellation.
	if _node is AnimatedSprite2D and _node.sprite_frames != null:
		for animation: TwberAnimationResource in _session.get_layer().animations:
			if _node.sprite_frames.has_animation(animation.name):
				_node.sprite_frames.set_animation_speed(animation.name, animation.speed)
	state.apply_to_node(_node)
	TwberAlphaClipController.set_authored_self_modulate(_node, state.self_modulate)
	TwberAlphaClipController.attach_to(_root).sync_now([state.layer_id])
	var renderer := TwberModelBatchRenderer2D.find_on(_root)
	if renderer != null:
		renderer.update_dynamic_geometry_for_nodes([_node])
