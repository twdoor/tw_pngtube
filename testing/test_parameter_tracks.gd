extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_sampling()
	_test_reference_mesh_composition()
	_test_commands_and_archives()
	await _test_editor_and_runtime()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Twber parameter track tests passed.")
	quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _key(id: String, time: float, coordinate: Vector2) -> TwberParameterKeyframeResource:
	var key := TwberParameterKeyframeResource.new()
	key.parameter_id = id
	key.time = time
	key.coordinate = coordinate
	return key


func _model() -> TwberModelResource:
	var model := TwberModelResource.new()
	var layer := TwberLayerResource.new()
	layer.id = "face"
	layer.name = "Face"
	layer.position = Vector2(10, 20)
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)
	var move := TwberParameterResource.new()
	move.id = "move"
	move.name = "Move"
	var sample := TwberParameterPositionResource.new()
	sample.coordinate = Vector2(1, 0)
	var state := TwberLayerStateResource.from_layer_resource(layer)
	state.channels = TwberLayerStateResource.Channel.POSITION
	state.position.x = 30
	sample.layer_states.append(state)
	move.positions.append(sample)
	model.parameters.append(move)
	var trigger := TwberParameterResource.new()
	trigger.id = "play"
	trigger.name = "Play"
	trigger.value_type = TwberParameterResource.ValueType.BOOL
	trigger.step = 1.0
	var binding := TwberAnimationBindingResource.new()
	binding.animation_id = "motion"
	binding.coordinate = Vector2(1, 0)
	trigger.animation_bindings.append(binding)
	model.parameters.append(trigger)
	var clip := TwberTimelineAnimationResource.new()
	clip.id = "motion"
	clip.name = "Motion"
	clip.parameter_keys.assign([_key("move", 1.0, Vector2(1, 0)), _key("move", 0.0, Vector2.ZERO)])
	model.timeline_animations.append(clip)
	return model


func _test_sampling() -> void:
	var model := _model()
	var evaluator := TwberModelEvaluator.new()
	evaluator.configure(model)
	var neutral := TwberLayerStateResource.from_layer_resource(model.layers[0])
	for value: float in [0.0, 0.125, 0.5, 0.9, 1.0]:
		# The allocating reference sampler/composer is independent of the optimized kernel.
		var sample := TwberParameterMapper.sample_layer_state(model.parameters[0], Vector2(value, 0), "face", neutral)
		var contributions: Array[TwberLayerStateResource] = [sample]
		var reference := TwberLayerStateResource.compose(neutral, contributions)
		var live: TwberLayerStateResource = evaluator.evaluate({"move": value})["face"].duplicate(true)
		var animated: TwberLayerStateResource = evaluator.evaluate({"move": 0.9}, {"motion": value})["face"]
		expect(TwberLayerStateResource.same_pose(reference, live) and TwberLayerStateResource.same_pose(live, animated),
			"Live, recorded parameters, and reference composition agree at %s" % value)
	var saved: TwberLayerStateResource = evaluator.evaluate({}, {"motion": 0.5})["face"].duplicate(true)
	model.parameters[0].positions[0].layer_states[0].position.x = 999
	model.timeline_animations[0].parameter_keys[0].coordinate.x = 0
	expect(evaluator.evaluate({}, {"motion": 0.5})["face"].position == saved.position,
		"Compiled instances detach both rig definitions and clip keys")
	expect(evaluator.evaluate()["face"].position == Vector2(10, 20), "No previous frame contributes to an inactive clip")
	model = _model()
	var clip := model.timeline_animations[0]
	var rotation_key := TwberTimelineKeyframeResource.new()
	rotation_key.layer_state = neutral.duplicate(true)
	rotation_key.layer_state.channels = TwberLayerStateResource.Channel.ROTATION
	rotation_key.layer_state.rotation = 0.75
	clip.keyframes.append(rotation_key)
	evaluator.configure(model)
	var pose: TwberLayerStateResource = evaluator.evaluate({}, {"motion": 0.5})["face"]
	expect(pose.position == Vector2(20, 20) and is_equal_approx(pose.rotation, 0.75),
		"Explicit property keys override only their channels after the parameter rig")
	var other := clip.duplicate(true) as TwberTimelineAnimationResource
	other.id = "aaa"
	other.priority = 1
	other.parameter_keys.assign([_key("move", 0, Vector2(0.25, 0))])
	other.keyframes[0].layer_state.rotation = -0.5
	model.timeline_animations.append(other)
	evaluator.configure(model)
	pose = evaluator.evaluate({}, {"aaa": 0.5, "motion": 0.5})["face"]
	expect(pose.position == Vector2(15, 20) and is_equal_approx(pose.rotation, -0.5), "Higher clip priority wins at both stages")
	other.priority = 0
	evaluator.configure(model)
	var first: TwberLayerStateResource = evaluator.evaluate({}, {"aaa": 0.5, "motion": 0.5})["face"].duplicate(true)
	pose = evaluator.evaluate({}, {"motion": 0.5, "aaa": 0.5})["face"]
	expect(TwberLayerStateResource.same_pose(first, pose) and pose.position == Vector2(20, 20),
		"Equal priority uses stable IDs independent of activation dictionary order")
	clip.parameter_keys[1].interpolation = TwberParameterKeyframeResource.Interpolation.HOLD
	evaluator.configure(model)
	expect(evaluator.resolve_parameters({}, {"motion": 0.999})["move"] == 0.0
		and evaluator.resolve_parameters({}, {"motion": 1.0})["move"] == 1.0, "Hold switches exactly at the next key")
	for type: int in [TwberParameterResource.ValueType.BOOL, TwberParameterResource.ValueType.INT, TwberParameterResource.ValueType.VECTOR2]:
		var parameter := TwberParameterResource.new()
		parameter.id = "typed"
		parameter.value_type = type as TwberParameterResource.ValueType
		parameter.step = 1.0 if type != TwberParameterResource.ValueType.VECTOR2 else TwberParameterResource.CONTINUOUS_STEP
		model.parameters.append(parameter)
		clip.parameter_keys.assign([_key("typed", 0, Vector2.ZERO), _key("typed", 1, Vector2.ONE if type == TwberParameterResource.ValueType.VECTOR2 else Vector2(1, 0))])
		evaluator.configure(model)
		var value: Variant = evaluator.resolve_parameters({}, {"motion": 0.75})["typed"]
		var expected: Variant = 0
		if type == TwberParameterResource.ValueType.VECTOR2:
			expected = Vector2(0.75, 0.75)
		elif type == TwberParameterResource.ValueType.BOOL:
			expected = false
		expect(value == expected,
			"Typed parameter interpolation respects discrete and vector semantics")
		model.parameters.erase(parameter)


func _test_commands_and_archives() -> void:
	var document := TwberModelDocument.new()
	document.replace_model(_model())
	var command := TwberEditTimeline.new(TwberEditTimeline.Operation.SET_PARAMETER_KEY, "motion", {"parameter_id": "move", "time": 0.5, "coordinate": Vector2(0.25, 0)})
	expect(document.execute(command) == OK, "Native parameter keys execute without nodes")
	var revision := document.get_revision()
	expect(document.execute(command) == OK and document.get_revision() == revision, "Identical parameter keys leave history unchanged")
	expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.SET_PARAMETER_KEY, "motion", {"parameter_id": "move", "time": 0.5, "coordinate": Vector2(NAN, 0)})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "Nonfinite key values fail atomically")
	expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, "motion", {"duration": 0.75})) == ERR_INVALID_PARAMETER,
		"Duration changes cannot truncate parameter keys")
	expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, "move", {"step": 0.5})) == ERR_INVALID_DATA
		and document.get_revision() == revision, "Parameter settings cannot silently displace authored timeline values")
	var model := document.snapshot().to_model_resource()
	var path := "user://twber_parameter_tracks.twber"
	expect(TwberModelCodec.export_twber(model, path) == OK, "Parameter clips export")
	var loaded := TwberModelCodec.load_model(path)
	expect(loaded != null and loaded.format_version == TwberModelResource.FORMAT_VERSION and loaded.timeline_animations[0].parameter_keys.size() == 3,
		"Parameter keys round trip through the current format")
	var old_data := TwberModelCodec.to_dictionary(model, false)
	old_data["format_version"] = 9
	old_data["timeline_animations"][0].erase("parameter_keys")
	expect(TwberModelCodec.from_dictionary(old_data).timeline_animations[0].parameter_keys.is_empty(), "Old clips load with empty parameter tracks")
	var invalid := model.duplicate(true) as TwberModelResource
	invalid.timeline_animations[0].parameter_keys.append(invalid.timeline_animations[0].parameter_keys[0].duplicate(true))
	expect(not TwberDocumentValidator.validate(invalid).is_empty(), "Duplicate target/time keys are rejected")
	expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.DELETE, "move")) == OK
		and document.snapshot().to_model_resource().timeline_animations[0].parameter_keys.is_empty(), "Parameter deletion removes dependent keys atomically")
	expect(document.undo() and document.snapshot().to_model_resource().timeline_animations[0].parameter_keys.size() == 3,
		"One Undo restores the parameter and all its keys")
	expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.REMOVE_PARAMETER_KEY, "motion", {"parameter_id": "move", "time": 0.5})) == OK,
		"Parameter key removal is a document action")
	document.undo()
	var mirror := TwberMirrorLayers.new(["face"], {"new_parameter": true, "geometry_x": true, "bindings_x": true})
	expect(document.execute(mirror) == OK and document.snapshot().to_model_resource().timeline_animations[0].parameter_keys.size() == 6,
		"A separate mirrored parameter receives copied timeline keys")
	var mirrored_keys := document.snapshot().to_model_resource().timeline_animations[0].parameter_keys
	expect(mirrored_keys[3].coordinate.x == 1.0 - mirrored_keys[0].coordinate.x,
		"Mirrored timeline values follow the mirrored parameter coordinate system")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_editor_and_runtime() -> void:
	var model := _model()
	var runtime := TwberRuntimeModel.new()
	runtime.enable_runtime_atlases = false
	root.add_child(runtime)
	runtime.set_model(model)
	runtime.set_parameter_value("play", true)
	runtime.evaluate_parameters()
	runtime._process(0.5)
	runtime.set_process(false)
	var runtime_node := runtime.get_child(0) as Node2D
	expect(runtime_node.position == Vector2(20, 20), "Triggered runtime playback samples parameter tracks")
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(model, "")
	var animator := editor._editor_animator
	editor._menus.current_tab = animator.get_index()
	animator._playhead = 0.5
	animator._apply_animation_at_playhead()
	var node := editor._model_root.get_child(0) as Node2D
	expect(node.position == runtime_node.position and not editor.is_dirty(), "Editor scrubbing and runtime playback produce identical poses")
	animator._track_x.value = 0.75
	expect(editor.is_dirty() and editor._document.get_undo_label() == "Set parameter key" and node.position == Vector2(25, 20),
		"Animate parameter controls author keys without a selected layer")
	expect(editor.undo_document(), "Parameter key control supports Undo")
	node = editor._model_root.get_child(0) as Node2D
	animator._playhead = 0.5
	animator._apply_animation_at_playhead()
	expect(node.position == Vector2(20, 20), "Undo recompiles the clip and restores interpolation")
	animator._select_node(node)
	animator.edit_pose({"position": Vector2(40, 20)})
	animator.cancel_pose_draft()
	expect(node.position == Vector2(20, 20), "Pose drafts restore parameter-track-driven baselines")
	runtime.set_parameter_value("play", false)
	runtime.set_parameter_value("move", 0.25)
	runtime.evaluate_parameters()
	expect(runtime_node.position == Vector2(15, 20), "Stopping a trigger restores live inputs without stale clip output")
	runtime.set_parameter_value("play", true)
	runtime.evaluate_parameters()
	runtime._process(1.25)
	runtime.set_process(false)
	expect(runtime_node.position == Vector2(15, 20), "Looping uses the same sampler at the wrapped playhead")
	model.timeline_animations[0].loop = false
	runtime.set_model(model)
	runtime_node = runtime.get_child(0) as Node2D
	runtime.set_parameter_value("play", true)
	runtime.evaluate_parameters()
	runtime._process(2.0)
	runtime.set_process(false)
	expect(runtime_node.position == Vector2(30, 20), "Nonlooping clips hold their final parameter key")
	# A clip may key its own trigger parameter: activation reads external inputs,
	# so there is no same-frame recursion or feedback through its resolved output.
	model.timeline_animations[0].parameter_keys.append(_key("play", 0, Vector2.ZERO))
	runtime.set_model(model)
	runtime.set_parameter_value("play", true)
	runtime.evaluate_parameters()
	runtime._process(0.5)
	runtime.set_process(false)
	expect(runtime._active_animation_playheads.has("motion") and runtime.get_parameter_value("play") == true,
		"Resolved track values never feed back into live trigger inputs")
	editor.free()
	runtime.free()


func _test_reference_mesh_composition() -> void:
	var model := _model()
	var layer := model.layers[0]
	layer.type = TwberLayerResource.LayerType.MESH_SPRITE
	layer.mesh = TwberMeshResource.new()
	layer.mesh.set_vertices(PackedVector2Array([Vector2.ZERO, Vector2(40, 0), Vector2(0, 40)]))
	layer.mesh.triangles = PackedInt32Array([0, 1, 2])
	var neutral := TwberLayerStateResource.from_layer_resource(layer)
	var vector := TwberParameterResource.new()
	vector.id = "look"
	vector.value_type = TwberParameterResource.ValueType.VECTOR2
	for coordinate: Vector2 in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		var sample := TwberParameterPositionResource.new()
		sample.coordinate = coordinate
		var state := neutral.duplicate(true) as TwberLayerStateResource
		state.position += coordinate * Vector2(3, 5)
		state.scale += coordinate * 0.2
		state.rotation = coordinate.x * 0.25
		state.self_modulate.a = 0.8
		state.mesh_vertices[1] += coordinate * 2.0
		sample.layer_states.append(state)
		vector.positions.append(sample)
	model.parameters.append(vector)
	var evaluator := TwberModelEvaluator.new()
	evaluator.configure(model)
	for x: float in [-1.0, -0.5, 0.0, 0.3, 1.0]:
		for y: float in [-1.0, -0.3, 0.0, 0.5, 1.0]:
			var contributions: Array[TwberLayerStateResource] = []
			contributions.append(TwberParameterMapper.sample_layer_state(model.parameters[0], Vector2(0.25, 0), "face", neutral))
			contributions.append(TwberParameterMapper.sample_layer_state(vector, Vector2(x, y), "face", neutral))
			var reference := TwberLayerStateResource.compose(neutral, contributions)
			var output: TwberLayerStateResource = evaluator.evaluate({"move": 0.25, "look": Vector2(x, y)})["face"]
			expect(TwberLayerStateResource.same_pose(reference, output),
				"Compiled scalar/2D mesh composition matches the reference at %s" % Vector2(x, y))
	var other := TwberModelEvaluator.new()
	other.configure(model)
	var neutral_copy := evaluator.neutral_states()
	neutral_copy["face"].position = Vector2(999, 999)
	evaluator.evaluate({"look": Vector2.ONE})
	expect(other.evaluate()["face"].position == neutral.position,
		"Neutral snapshots and separate evaluator instances cannot contaminate one another")
