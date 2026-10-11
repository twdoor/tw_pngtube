extends SceneTree

var failures: Array[String] = []
var _now := [0]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_mapping()
	_test_baked_channels()
	await _test_prepared_save()
	await _test_environment_take()
	await _test_triggered_take()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Twber Environment recording tests passed (%s)." % DisplayServer.get_name())
	quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _model() -> TwberModelResource:
	var model := TwberModelResource.new()
	var layer := TwberLayerResource.new()
	layer.id = "face"
	layer.name = "Face"
	layer.type = TwberLayerResource.LayerType.SPRITE
	layer.centered = false
	layer.texture_id = "red"
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	model.textures["red"] = ImageTexture.create_from_image(image)
	var parameter := TwberParameterResource.new()
	parameter.id = "move"
	parameter.name = "Move"
	var sample := TwberParameterPositionResource.new()
	sample.coordinate = Vector2(1, 0)
	var pose := TwberLayerStateResource.from_layer_resource(layer)
	pose.channels = TwberLayerStateResource.Channel.POSITION
	pose.position = Vector2(8, 0)
	sample.layer_states.append(pose)
	parameter.positions.append(sample)
	model.parameters.append(parameter)
	return model


func _test_mapping() -> void:
	var microphone := preload("res://package_sources/microphone/binding_mapper.gd").new()
	var mouse := preload("res://package_sources/mouse/binding_mapper.gd").new()
	var parameter := TwberParameterResource.new()
	expect(is_equal_approx(microphone.map_value(parameter, {}, -35.0), 0.5), "Microphone maps dB without controls")
	expect(microphone.map_value(parameter, {"minimum_db": -10.0, "maximum_db": -60.0}, -35.0) == 0.5, "Reversed ranges normalize")
	expect(microphone.map_value(parameter, {"minimum_db": -10.0, "maximum_db": -10.0}, -10.0) == 1.0, "Equal range endpoints have a finite threshold result")
	parameter.value_type = TwberParameterResource.ValueType.BOOL
	expect(microphone.map_value(parameter, {}, -40.0) and not microphone.map_value(parameter, {}, -41.0), "Boolean mapping preserves the threshold boundary")
	parameter.value_type = TwberParameterResource.ValueType.INT
	parameter.max_value = 10
	expect(microphone.map_value(parameter, {}, -34.0) == 5, "Integer microphone mapping rounds to whole steps")
	var context := {"display_rects": [Rect2(-200, 0, 200, 100), Rect2(0, 0, 400, 200)], "current_display": 0}
	expect(mouse.map_value(parameter, {}, Vector2(-100, 50), context) == Vector2.ZERO, "Automatic mouse mapping supports negative display origins")
	expect(mouse.map_value(parameter, {"display_mode": "fixed", "display_index": 1}, Vector2(-100, 50), context) == Vector2(-1, 0.5), "Fixed display mapping clamps offscreen input")
	expect(mouse.map_value(parameter, {"display_mode": "fixed", "display_index": 99}, Vector2(200, 100), context) == Vector2.ZERO, "Disconnected fixed displays fall back to pointer display")
	expect(mouse.map_value(parameter, {}, Vector2.ONE, {}) == Vector2.ZERO, "Missing display geometry is deterministic")
	var first: float = TwberInputSmoothing.advance(0.0, 1.0, 0.02)
	expect(first > 0 and first < 1 and TwberInputSmoothing.advance(first, 1.0, 1.0) == 1.0, "Smoothing advances and settles without nodes")


func _test_prepared_save() -> void:
	var source := _model()
	var prepared := TwberModelCodec.prepare_twber_export(source)
	# Both authored metadata and image payloads must be detached before dispatch.
	source.parameters[0].name = "Changed after preparation"
	var replacement := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	replacement.fill(Color.BLUE)
	(source.textures["red"] as ImageTexture).update(replacement)
	var path := ProjectSettings.globalize_path("user://prepared-take-%d.twber" % Time.get_ticks_usec())
	var task := TwberBackgroundTask.new()
	root.add_child(task)
	var started := task.start(TwberModelCodec.export_prepared_twber.bind(prepared, path))
	expect(started == OK, "Prepared archive starts on a background worker")
	if started != OK:
		task.queue_free()
		return
	var error: Error = await task.completed
	expect(error == OK, "Prepared archive writes without renderer access from its worker")
	var loaded := TwberModelCodec.load_model(path)
	expect(loaded != null and loaded.parameters[0].name == "Move", "Prepared archive owns its parameter metadata")
	if loaded != null:
		var image := TwberTextureUtils.get_authoring_image(loaded.textures["red"])
		expect(image != null and image.get_pixel(0, 0).r > 0.9 and image.get_pixel(0, 0).b < 0.1,
			"Prepared archive owns image bytes independent of subsequent GPU texture changes")
	DirAccess.remove_absolute(path)


func _test_environment_take() -> void:
	# An isolated workspace avoids restoring earlier tests' model instances.
	var settings := preload("res://environment/core/twber_environment_settings.gd").new()
	settings.load()
	settings.set_workspace([], -1)
	settings.save()
	var environment := preload("res://environment/environment.tscn").instantiate() as TwberEnvironment
	root.add_child(environment)
	await process_frame
	for record: Dictionary in environment._package_manager.get_packages().values():
		var provider := record.get("package") as TwberInputProvider
		if provider != null:
			provider.set_provider_enabled(false)
	environment.set_process(false)
	var registry := environment._input_registry
	expect(registry.get_mapping(&"microphone.level_db") != null, "Packaged microphone registers its data-only mapper")
	var source := _model()
	var target := environment._add_model_instance(source, "", "model")
	var other := environment._add_model_instance(_model(), "", "model")
	await process_frame
	environment._select_model(target)
	var recorder := environment._performance_recorder
	recorder._clock = func() -> int: return _now[0]
	var entry := environment._get_model_entry(target)
	(entry["bindings"] as Dictionary)["move"] = {"source_id": &"microphone.level_db", "configuration": {}}
	expect(recorder.start_recording(target) == OK, "Environment starts a model-owned take")
	expect(environment._home_button.disabled, "Navigation cannot discard an active take")
	environment._select_model(other)
	other.set_parameter_value("move", 1.0)
	_now[0] = 125000
	registry.get_provider(&"microphone").value_changed.emit(&"level_db", -10.0)
	expect(target.get_parameter_value("move") == 0.0, "Raw source targets do not get recorded before smoothing")
	environment._process(0.02)
	target.evaluate_parameters()
	var middle: float = target.get_parameter_value("move")
	expect(middle > 0.0 and middle < 1.0, "The runtime applies the intermediate smoothed input")
	# Reparenting the dock must preserve a live session and its subscriptions.
	environment._toggle_controls_detached()
	await process_frame
	environment._embed_controls()
	await process_frame
	expect(recorder._session != null and recorder._target == target, "Detaching controls preserves the original recording target")
	_now[0] = 250000
	environment._process(0.25)
	target.evaluate_parameters()
	expect(target.get_parameter_value("move") == 1.0, "Smoothing reaches its normalized target")
	_now[0] = 375000
	environment._on_parameter_value_changed("move", 0.5, target)
	target.evaluate_parameters()
	var live := target._layer_nodes["face"] as Node2D
	expect(live.position == Vector2(4, 0), "Manual input shares the normalized runtime route")
	_now[0] = 500000
	expect(recorder.finish_recording() == OK, "Environment finishes through the native take command")
	while recorder._saving:
		await process_frame
	var path := recorder._last_path
	expect(not path.is_empty() and FileAccess.file_exists(path) and recorder._pending == null, "Finished takes automatically persist as portable copies")
	var recorded := TwberModelCodec.load_model(path)
	if recorded == null:
		environment.free()
		return
	expect(source.timeline_animations.is_empty() and other.model.timeline_animations.is_empty(), "Recording leaves both loaded source models untouched")
	expect(recorded.root_position == source.root_position and recorded.root_scale == source.root_scale, "Stage placement never enters the authored take copy")
	var id := recorder._last_animation_id
	var clip := TwberEditTimeline.find(recorded, id)
	expect(clip != null and clip.parameter_keys.size() == 4, "Only normalized changes on the original instance are stored")
	var evaluator := TwberModelEvaluator.new()
	evaluator.configure(recorded)
	for pair: Vector2 in [Vector2(0, 0), Vector2(0.124, 0), Vector2(0.125, middle), Vector2(0.25, 1), Vector2(0.375, 0.5)]:
		var pose: TwberLayerStateResource = evaluator.evaluate({}, {id: pair.x})["face"]
		expect(pose.position.is_equal_approx(Vector2(8 * pair.y, 0)), "Saved playback reproduces applied live input at %s" % pair.x)
	if DisplayServer.get_name() != "headless":
		var output := path.get_basename() + "-frames"
		var exporter := TwberFrameExporter.new()
		expect(await exporter.export_sequence(root, recorded, id, output, Vector2i(32, 32), 4.0) == OK, "Environment takes export with the shared renderer")
		var first := Image.load_from_file(output.path_join("frame_000000.png"))
		var second := Image.load_from_file(output.path_join("frame_000001.png"))
		expect(first != null and first.get_pixel(17, 17).r > 0.9 and first.get_pixel(0, 0).a < 0.01, "Environment export begins at recorded defaults on a transparent canvas")
		expect(second != null and second.get_pixel(25, 17).r > 0.9 and second.get_pixel(17, 17).a < 0.01, "Environment PNG output reproduces the smoothed recorded movement")
		_remove_directory(output)
	# A write failure retains a completed take; retry cannot replace any file.
	recorder._pending = recorded.duplicate(true)
	await recorder.save_pending(path)
	expect(recorder._pending != null and recorder.blocks_navigation(), "Existing destinations keep the pending take and block accidental navigation")
	await recorder.save_pending(path + "/missing/retry.twber")
	expect(recorder._pending != null and not recorder._saving, "Write failure preserves the take for retry")
	var retry_path := path.get_basename() + "-retry.twber"
	await recorder.save_pending(retry_path)
	expect(recorder._pending == null and FileAccess.file_exists(retry_path) and not environment._home_button.disabled, "Retry to another path completes without losing the take")
	_now[0] = 1000000
	expect(recorder.start_recording(target) == OK, "Another recording can start after saving")
	recorder.cancel_recording()
	expect(recorder._session == null and FileAccess.file_exists(path), "Canceling a new session preserves completed takes")
	recorder.start_recording(target)
	target.set_model(_model())
	expect(recorder._session == null, "Replacing the target cancels its stale session")
	recorder.start_recording(target)
	environment._select_model(target)
	environment.remove_selected_model()
	await process_frame
	expect(recorder._session == null, "Removing the original instance cancels recording even after selection changes")
	environment.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(retry_path)


func _trigger_model() -> TwberModelResource:
	var model := _model()
	var clip := TwberTimelineAnimationResource.new()
	clip.id = "gesture"
	clip.duration = 1.0
	clip.loop = true
	for time: float in [0.0, 1.0]:
		var key := TwberTimelineKeyframeResource.new()
		key.time = time
		key.layer_state = TwberLayerStateResource.new()
		key.layer_state.layer_id = "face"
		key.layer_state.channels = TwberLayerStateResource.Channel.POSITION
		key.layer_state.position = Vector2(4 + 8 * time, 0)
		clip.keyframes.append(key)
		var input := TwberParameterKeyframeResource.new()
		input.parameter_id = "move"
		input.time = time
		input.coordinate.x = time
		clip.parameter_keys.append(input)
	model.timeline_animations.append(clip)
	var accent := clip.duplicate(true) as TwberTimelineAnimationResource
	accent.id = "accent"
	accent.duration = 0.5
	accent.loop = false
	accent.priority = 10
	accent.parameter_keys.clear()
	accent.keyframes[0].layer_state.position.x = -4
	accent.keyframes[1].time = 0.5
	accent.keyframes[1].layer_state.position.x = 4
	model.timeline_animations.append(accent)
	for id: String in ["gesture", "accent"]:
		var gate := TwberParameterResource.new()
		gate.id = id
		gate.value_type = TwberParameterResource.ValueType.BOOL
		var binding := TwberAnimationBindingResource.new()
		binding.animation_id = id
		binding.coordinate.x = 1
		gate.animation_bindings.append(binding)
		model.parameters.append(gate)
	return model


func _test_baked_channels() -> void:
	var model := _trigger_model()
	var mesh := TwberMeshResource.new()
	mesh.vertices = PackedVector2Array([Vector2.ZERO, Vector2(4, 0), Vector2(0, 4)])
	mesh.uvs = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	mesh.triangles = PackedInt32Array([0, 1, 2])
	model.layers[0].mesh = mesh
	for key: TwberTimelineKeyframeResource in model.timeline_animations[0].keyframes:
		var state := key.layer_state
		state.channels = TwberLayerStateResource.ALL_CHANNELS
		state.rotation = key.time
		state.scale = Vector2.ONE * (1.0 + key.time)
		state.visible = key.time == 0.0
		state.self_modulate = Color(1.0, 1.0 - key.time, 1.0, 1.0 - key.time * 0.5)
		state.mesh_vertices = PackedVector2Array([Vector2.ZERO, Vector2(4 + key.time, 0), Vector2(0, 4)])
		state.animation_name = "first" if key.time == 0.0 else "second"
		state.animation_frame_rate = 4 + key.time * 4
	var take := TwberModelTake.new()
	expect(take.start(model, {}) == OK, "Performance capture supports all property channels")
	var live := TwberModelEvaluator.new()
	live.configure(model)
	var expected := {0.0: (live.evaluate()["face"] as TwberLayerStateResource).duplicate(true)}
	for time: float in [0.25, 0.5, 0.75]:
		expect(take.sample(time, {"gesture": true}, {"gesture": time}) == OK, "Property observation records atomically")
		expected[time] = (live.evaluate({"gesture": true}, {"gesture": time})["face"] as TwberLayerStateResource).duplicate(true)
	expect(take.sample(0.8, {"move": NAN}) == ERR_INVALID_PARAMETER
		and take.sample(0.8, {}, {"missing": 0.0}) == ERR_INVALID_PARAMETER
		and take.sample(0.7, {}, {}) == ERR_INVALID_PARAMETER, "Invalid input, phase references, and timestamps reject the entire observation")
	expect(take.sample(0.875, {"gesture": false}, {}) == OK, "Release captures neutral mesh and properties")
	expected[0.875] = (live.evaluate()["face"] as TwberLayerStateResource).duplicate(true)
	var result := take.finish(1.0)
	expect(result.error == OK, "Full property take imports into its snapshot")
	if result.error != OK:
		return
	var playback := TwberModelEvaluator.new()
	playback.configure(result.model)
	for time: float in expected:
		var pose: TwberLayerStateResource = playback.evaluate({}, {result.animation_id: time + 0.01})["face"]
		expect(TwberLayerStateResource.same_pose(pose, expected[time]), "Baked hold reproduces transforms, color, visibility, mesh and sprite settings at %s" % time)
	var bounded := TwberParameterTake.new(_model().parameters)
	expect(bounded.sample(0.0, {"move": 0.0}, 1) == OK
		and bounded.sample(0.0, {"move": 1.0}, 1) == OK
		and bounded.sample(0.1, {"move": 0.5}, 1) == ERR_OUT_OF_MEMORY,
		"Shared take budget permits replacement but rejects additional keys atomically")
	expect(bounded.to_clip(0.2).parameter_keys[0].coordinate.x == 1.0, "Budget rejection keeps the last valid captured value")


func _test_triggered_take() -> void:
	var source := _trigger_model()
	var runtime := TwberRuntimeModel.new()
	root.add_child(runtime)
	runtime.set_model(source)
	runtime.set_parameter_value("gesture", true)
	runtime._process(0.25)
	runtime.set_process(false)
	var recorder := TwberPerformanceRecorder.new()
	root.add_child(recorder)
	recorder.selected_model = runtime
	recorder._clock = func() -> int: return _now[0]
	_now[0] = 0
	expect(recorder.start_recording(runtime) == OK, "Recording can start midway through a running clip")
	var expected := {0.0: (runtime._layer_nodes["face"] as Node2D).position}
	var resolved := {0.0: runtime._pose_evaluator.resolve_parameters(runtime.get_parameter_values(), runtime.get_animation_playheads())}
	var events := [
		[0.125, {}, 0.125],
		[0.25, {"gesture": false}, 0.0],
		[0.375, {"gesture": true}, 0.0],
		[0.5, {}, 1.25],
		[0.625, {"accent": true}, 0.125],
		[0.75, {"gesture": false, "accent": false}, 0.0],
		[0.875, {"accent": true}, 2.0],
	]
	for event: Array in events:
		_now[0] = int(event[0] * 1000000)
		runtime.set_parameter_values(event[1])
		runtime._process(event[2])
		runtime.set_process(false)
		expected[event[0]] = (runtime._layer_nodes["face"] as Node2D).position
		resolved[event[0]] = runtime._pose_evaluator.resolve_parameters(runtime.get_parameter_values(), runtime.get_animation_playheads())
	expect(expected[0.0] == Vector2(6, 0) and expected[0.25] == Vector2.ZERO
		and expected[0.375] == Vector2(4, 0) and expected[0.5] == Vector2(6, 0)
		and expected[0.625] == Vector2(-2, 0) and expected[0.875] == Vector2(4, 0),
		"Live fixture exercises active start, release, restart, loop wrap, priority and nonloop endpoint")
	_now[0] = 1000000
	expect(recorder.finish_recording() == OK, "Triggered performance finishes as native tracks")
	while recorder._saving:
		await process_frame
	var path := recorder._last_path
	var recorded := TwberModelCodec.load_model(path)
	expect(recorded != null, "Triggered take saves as a portable model")
	if recorded == null:
		recorder.free()
		runtime.free()
		return
	var id := recorder._last_animation_id
	var take := TwberEditTimeline.find(recorded, id)
	expect(not take.keyframes.is_empty() and take.keyframes.size() == expected.size(), "Changed poses are baked once per observed timestamp")
	for key: TwberTimelineKeyframeResource in take.keyframes:
		expect(key.interpolation == TwberTimelineKeyframeResource.Interpolation.HOLD
			and key.layer_state.channels == TwberLayerStateResource.Channel.POSITION,
			"Saved property keys hold their value and own only triggered channels")
	var evaluator := TwberModelEvaluator.new()
	evaluator.configure(recorded)
	for time: float in expected:
		var pose: TwberLayerStateResource = evaluator.evaluate({}, {id: time})["face"]
		expect(pose.position.is_equal_approx(expected[time]), "Saved triggered playback matches observed live pose at %s" % time)
		expect(evaluator.resolve_parameters({}, {id: time}) == resolved[time], "Triggered parameter output is baked without replaying trigger bindings at %s" % time)
		var held: TwberLayerStateResource = evaluator.evaluate({}, {id: time + 0.05})["face"]
		expect(held.position.is_equal_approx(expected[time]), "Captured property pose holds until the next observation")
	# Native editing and history retain recorded timing and source isolation.
	var document := TwberModelDocument.new()
	document.replace_model(source)
	var command := TwberImportParameterTake.new(take)
	expect(document.execute(command) == OK and document.get_undo_label() == "Record performance take", "A mixed take imports as one native transaction")
	expect(document.undo() and document.snapshot().to_model_resource().timeline_animations.size() == 2
		and document.redo(), "Undo and Redo retain the complete parameter/property take")
	var replacement := take.keyframes[1].layer_state.duplicate(true) as TwberLayerStateResource
	replacement.position.x = 30
	expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.SET_KEY, command.animation_id,
		{"time": take.keyframes[1].time, "pose": replacement})) == OK, "Baked keys remain editable through normal timeline commands")
	var edited := TwberEditTimeline.find(document.snapshot().to_model_resource(), command.animation_id)
	expect(edited.get_keyframes_for_layer("face")[1].interpolation == TwberTimelineKeyframeResource.Interpolation.HOLD, "Editing a captured pose preserves hold timing")
	expect(source.timeline_animations.size() == 2 and source.timeline_animations[0].keyframes[0].interpolation == 0, "Source clips remain untouched")
	var legacy := TwberModelCodec.to_dictionary(source, false)
	legacy["format_version"] = 10
	for animation: Dictionary in legacy["timeline_animations"]:
		for key: Dictionary in animation["keyframes"]:
			key.erase("interpolation")
	var migrated := TwberModelCodec.from_dictionary(legacy)
	expect(migrated != null and migrated.timeline_animations[0].keyframes[0].interpolation == 0, "Legacy property keys retain linear interpolation")
	var invalid := take.duplicate(true) as TwberTimelineAnimationResource
	invalid.keyframes[0].interpolation = 99 as TwberTimelineKeyframeResource.Interpolation
	var revision := document.get_revision()
	expect(document.execute(TwberImportParameterTake.new(invalid)) == ERR_INVALID_DATA
		and document.get_revision() == revision, "Invalid baked timing fails atomically")
	if DisplayServer.get_name() != "headless":
		var output := path.get_basename() + "-trigger-frames"
		var exporter := TwberFrameExporter.new()
		expect(await exporter.export_sequence(root, recorded, id, output, Vector2i(32, 32), 4.0) == OK, "Triggered take exports through the shared evaluator")
		for index: int in 4:
			var image := Image.load_from_file(output.path_join("frame_%06d.png" % index))
			var x := 23 if index in [0, 2] else 17
			expect(image != null and image.get_pixel(x, 17).r > 0.9 and image.get_pixel(0, 0).a < 0.01,
				"Exported pixels match triggered motion and release at frame %d" % index)
		_remove_directory(output)
	recorder.free()
	runtime.free()
	DirAccess.remove_absolute(path)


func _remove_directory(path: String) -> void:
	for child: String in DirAccess.get_directories_at(path):
		_remove_directory(path.path_join(child))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
