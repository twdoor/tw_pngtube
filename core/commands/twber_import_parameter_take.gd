class_name TwberImportParameterTake extends TwberEditTimeline

var _take: TwberTimelineAnimationResource


func _init(take: TwberTimelineAnimationResource) -> void:
	super(Operation.CREATE)
	_take = take.duplicate(true) if take != null else null
	label = "Record performance take" if _take != null and (not _take.keyframes.is_empty() or not _take.sprite_keys.is_empty()) else "Record parameter take"


func apply(model: TwberModelResource) -> Error:
	did_change = false
	layer_ids.clear()
	if _take == null or (_take.parameter_keys.is_empty() and _take.sprite_keys.is_empty()):
		return ERR_INVALID_DATA
	if not is_finite(_take.duration) or _take.duration < 0.05 or not is_finite(_take.fps) or _take.fps < 1.0 or _take.fps > 120.0:
		return ERR_INVALID_DATA
	# Validate against current parameter definitions before publishing any data.
	var validation_model := model.duplicate(true) as TwberModelResource
	var candidate := _take.duplicate(true) as TwberTimelineAnimationResource
	candidate.id = "recorded_take"
	while find(validation_model, candidate.id) != null:
		candidate.id += "_"
	validation_model.timeline_animations.append(candidate)
	if not TwberDocumentValidator.validate(validation_model).is_empty():
		return ERR_INVALID_DATA
	var error := super.apply(model)
	if error != OK:
		return error
	var clip := find(model, animation_id)
	var id := clip.id
	var names := {}
	for existing: TwberTimelineAnimationResource in model.timeline_animations:
		if existing != clip:
			names[existing.name] = true
	clip.copy_contents_from(_take)
	clip.id = id
	var index := 1
	while names.has("Take %d" % index):
		index += 1
	clip.name = "Take %d" % index
	layer_ids = clip.get_layer_ids()
	for key: TwberParameterKeyframeResource in clip.parameter_keys:
		_include_parameter_layers(TwberEditParameter.find(model, key.parameter_id))
	return OK
