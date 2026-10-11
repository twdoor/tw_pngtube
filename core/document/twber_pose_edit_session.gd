class_name TwberPoseEditSession extends RefCounted

# A transient evaluated pose, not a candidate authored model. Only Bind/Record
# builds an authoring command; neither pointer updates nor release write history.
var _document: TwberModelDocument
var _revision: int
var _context: Dictionary
var _layer: TwberLayerResource
var _baseline: TwberLayerStateResource
var _pose: TwberLayerStateResource
var _active := false


func _init(document: TwberModelDocument, id: String, context: Dictionary) -> void:
	_document = document
	_revision = document.get_revision()
	_context = context.duplicate(true)
	var model := document.snapshot().to_model_resource()
	_layer = TwberLayerHierarchy.index(model).get(id)
	if _layer == null:
		return
	var neutral := TwberLayerStateResource.from_layer_resource(_layer)
	if _context.get("mode") == "rig":
		_baseline = TwberRigSampling.sample_others(model, _layer, _context.get("values", {}), "", _context.get("snap", {}))
	else:
		var evaluator := TwberModelEvaluator.new()
		evaluator.configure(model)
		var playheads := {String(_context.get("animation_id", "")): float(_context.get("time", 0.0))}
		var poses := evaluator.evaluate({}, playheads)
		_baseline = poses.get(id, neutral).duplicate(true)
	_pose = _baseline.duplicate(true)
	_active = true


func is_current() -> bool:
	return _active and _document != null and _document.get_revision() == _revision


func has_changes() -> bool:
	return _active and not TwberLayerStateResource.same_pose(_baseline, _pose)


func get_pose() -> TwberLayerStateResource:
	return _pose.duplicate(true) if is_current() else null


func get_baseline() -> TwberLayerStateResource:
	return _baseline.duplicate(true) if _baseline != null else null


func get_layer() -> TwberLayerResource:
	return _layer.duplicate(true) if _layer != null else null


func update(pose: TwberLayerStateResource) -> Error:
	if not is_current():
		return ERR_BUSY
	if pose == null or pose.layer_id != _layer.id:
		return ERR_INVALID_PARAMETER
	var errors: Array[String] = []
	TwberDocumentValidator._validate_state(pose, {_layer.id: _layer}, errors)
	for component: float in [pose.self_modulate.r, pose.self_modulate.g, pose.self_modulate.b, pose.self_modulate.a, pose.animation_frame_rate]:
		if not is_finite(component):
			return ERR_INVALID_DATA
	if _layer.mesh != null and pose.mesh_vertices.size() != _layer.mesh.vertices.size():
		return ERR_INVALID_DATA
	if not errors.is_empty():
		return ERR_INVALID_DATA
	_pose = pose.materialized(_baseline)
	return OK


func make_command() -> TwberDocumentCommand:
	if not is_current():
		return null
	if _context.get("mode") == "rig":
		var id := String(_context.get("parameter_id", ""))
		if id.is_empty():
			return null
		return TwberEditParameter.new(TwberEditParameter.Operation.BIND_POSE, id, {
			"pose": _pose, "coordinate": _context.get("coordinate", Vector2.ZERO),
			"values": _context.get("values", {}), "snap": _context.get("snap", {}),
		})
	var id := String(_context.get("animation_id", ""))
	if id.is_empty():
		return null
	return TwberEditTimeline.new(TwberEditTimeline.Operation.SET_KEY, id, {
		"pose": _pose, "time": _context.get("time", 0.0),
	})


# The editor calls this only for parameter/clip name changes, which cannot alter
# a pose, its topology, or its binding target. Other revisions invalidate drafts.
func accept_name_revision() -> void:
	if _active:
		_revision = _document.get_revision()


func cancel() -> void:
	_active = false
	_document = null
	_layer = null
	_baseline = null
	_pose = null
