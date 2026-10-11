extends SceneTree

var failures: Array[String] = []
var _now := [0]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_authored_timing()
	await _test_performance()
	await _test_sprite_only()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Twber sprite clock tests passed (%s)." % DisplayServer.get_name())
	quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _model() -> TwberModelResource:
	var model := TwberModelResource.new()
	var layer := TwberLayerResource.new()
	layer.id = "sprite"
	layer.type = TwberLayerResource.LayerType.ANIMATED_SPRITE
	layer.current_animation = "Idle"
	layer.centered = false
	for name: String in ["Idle", "Other"]:
		var animation := TwberAnimationResource.new()
		animation.name = name
		animation.speed = 4.0 if name == "Idle" else 8.0
		animation.loop = name == "Idle"
		animation.frame_texture_ids.assign(["red", "blue"] if name == "Idle" else ["green", "yellow"])
		animation.frame_durations.assign([1.0, 2.0] if name == "Idle" else [1.0, 1.0])
		layer.animations.append(animation)
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)
	var colors := {"red": Color.RED, "blue": Color.BLUE, "green": Color.GREEN, "yellow": Color.YELLOW}
	for name: String in colors:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(colors[name])
		model.textures[name] = ImageTexture.create_from_image(image)
	var mode := TwberParameterResource.new()
	mode.id = "mode"
	mode.value_type = TwberParameterResource.ValueType.INT
	mode.max_value = 3
	mode.step = 1
	for index: int in range(1, 4):
		var sample := TwberParameterPositionResource.new()
		sample.coordinate.x = index
		var pose := TwberLayerStateResource.from_layer_resource(layer)
		pose.channels = TwberLayerStateResource.Channel.ANIMATION | TwberLayerStateResource.Channel.ANIMATION_FRAME_RATE
		pose.animation_name = "Other" if index == 2 else "Idle"
		pose.animation_frame_rate = 0.0 if index == 1 else (8.0 if index == 2 else 4.0)
		sample.layer_states.append(pose)
		mode.positions.append(sample)
	model.parameters.append(mode)
	return model


func _test_authored_timing() -> void:
	var model := _model()
	var clip := TwberTimelineAnimationResource.new()
	clip.id = "authored"
	clip.duration = 2.0
	for data: Array in [[0.0, "Idle", 4.0], [0.5, "Idle", 0.0], [0.75, "Other", 8.0], [1.0, "Idle", 4.0]]:
		var key := TwberTimelineKeyframeResource.new()
		key.time = data[0]
		key.interpolation = TwberTimelineKeyframeResource.Interpolation.HOLD
		key.layer_state = TwberLayerStateResource.new()
		key.layer_state.layer_id = "sprite"
		key.layer_state.channels = TwberLayerStateResource.Channel.ANIMATION | TwberLayerStateResource.Channel.ANIMATION_FRAME_RATE
		key.layer_state.animation_name = data[1]
		key.layer_state.animation_frame_rate = data[2]
		clip.keyframes.append(key)
	model.timeline_animations.append(clip)
	var timeline := TwberSpriteTimeline.new()
	timeline.configure(model)
	var expected := {0.25: ["Idle", 1.0], 0.5: ["Idle", 2.0], 0.7: ["Idle", 2.0], 0.75: ["Other", 0.0], 0.875: ["Other", 1.0], 1.0: ["Idle", 0.0], 1.25: ["Idle", 1.0]}
	for time: float in [1.25, 0.25, 0.75, 0.875, 0.7, 0.5, 1.0, 1.25]:
		var state: Dictionary = timeline.seek("authored", time)["sprite"]
		expect(state.animation == expected[time][0] and absf(state.phase - expected[time][1]) < 0.000001,
			"Authored switches, held rates and arbitrary seek order share a clock at %s" % time)
	# Fractional visits must not become integration checkpoints.
	var first: Dictionary = timeline.seek("authored", 0.333)["sprite"]
	timeline.seek("authored", 0.331)
	expect(timeline.seek("authored", 0.333)["sprite"] == first, "Fractional seeks are independent of earlier visits")
	var ramp := clip.duplicate(true) as TwberTimelineAnimationResource
	ramp.id = "ramp"
	ramp.keyframes.resize(2)
	ramp.keyframes[0].layer_state.animation_frame_rate = 0.0
	ramp.keyframes[0].interpolation = TwberTimelineKeyframeResource.Interpolation.LINEAR
	ramp.keyframes[1].time = 1.0
	ramp.keyframes[1].layer_state.animation_frame_rate = 8.0
	model.timeline_animations.append(ramp)
	timeline.configure(model)
	var phase: float = timeline.seek("ramp", 1.0)["sprite"].phase
	expect(absf(phase - 4.0) < 0.02 and phase < 5.0, "Changing rate integrates elapsed speed instead of multiplying final speed by clip time")
	var runtime := TwberRuntimeModel.new()
	root.add_child(runtime)
	runtime.set_model(model)
	for time: float in [0.25, 0.5, 0.75, 0.875, 1.0, 1.25]:
		runtime.seek_animation("authored", time)
		var sprite := runtime._layer_nodes["sprite"] as AnimatedSprite2D
		expect(not sprite.is_playing(), "Explicit seeking disables Godot's independent sprite clock")
		expect(str(sprite.animation) == expected[time][0], "Runtime seek projects the shared sprite selection")
	runtime.free()


func _test_performance() -> void:
	var model := _model()
	var runtime := TwberRuntimeModel.new()
	root.add_child(runtime)
	runtime.set_model(model)
	expect(runtime.is_processing(), "Untriggered sprites keep the runtime clock alive")
	runtime._process(0.375)
	runtime.set_process(false)
	var sprite := runtime._layer_nodes["sprite"] as AnimatedSprite2D
	expect(sprite.frame == 1 and is_equal_approx(sprite.frame_progress, 0.25), "Shared live clock respects unequal relative frame durations")
	var recorder := TwberPerformanceRecorder.new()
	root.add_child(recorder)
	recorder.selected_model = runtime
	recorder._clock = func() -> int: return _now[0]
	_now[0] = 0
	expect(recorder.start_recording(runtime) == OK, "Recording starts from the current sprite phase")
	var expected := {0.0: ["Idle", 1, 0.25]}
	for index: int in range(1, 6):
		_now[0] = index * 250000
		runtime._process(0.25)
		if index <= 3:
			runtime.set_parameter_value("mode", index)
			runtime.evaluate_parameters()
		runtime.set_process(false)
		expected[float(index) * 0.25] = [str(sprite.animation), sprite.frame, sprite.frame_progress]
	expect(expected[0.25] == ["Idle", 1, 0.75] and expected[0.5] == ["Other", 0, 0.0]
		and expected[0.75] == ["Idle", 0, 0.0] and expected[1.0] == ["Idle", 1, 0.0],
		"Live rate changes pause without resetting phase and switches restart the new animation")
	_now[0] = 1500000
	expect(recorder.finish_recording() == OK, "Sprite performance finishes as native tracks")
	while recorder._saving:
		await process_frame
	var path := recorder._last_path
	var recorded := TwberModelCodec.load_model(path)
	expect(recorded != null, "Sprite phase markers round trip through the archive")
	if recorded == null:
		recorder.free()
		runtime.free()
		return
	var id := recorder._last_animation_id
	var clip := TwberEditTimeline.find(recorded, id)
	expect(clip.sprite_keys.size() == 4 and clip.sprite_keys[0].phase == 1.5,
		"Constant-rate runs compact to phase anchors and preserve the initial offset")
	var played := TwberRuntimeModel.new()
	root.add_child(played)
	played.set_model(recorded)
	var playback_sprite := played._layer_nodes["sprite"] as AnimatedSprite2D
	for time: float in [1.25, 0.0, 0.75, 0.25, 1.0, 0.5]:
		played.seek_animation(id, time)
		expect(str(playback_sprite.animation) == expected[time][0] and playback_sprite.frame == expected[time][1]
			and is_equal_approx(playback_sprite.frame_progress, expected[time][2]), "Recorded playback reproduces live frame and progress at %s" % time)
	# Long nonloop phases clamp to the last frame, even with interpolation between anchors.
	played.seek_animation(id, 0.74)
	expect(playback_sprite.animation == &"Other" and playback_sprite.frame == 1, "Nonlooping recorded sprites reach their final frame")
	_test_triggered_take(recorded, id, expected)
	await _test_editor(recorded, id, expected)
	_test_history(recorded, id)
	if DisplayServer.get_name() != "headless":
		var colors := [Color.BLUE, Color.BLUE, Color.GREEN, Color.RED, Color.BLUE, Color.BLUE]
		var exporter := TwberFrameExporter.new()
		var output := path.get_basename() + "-sprites"
		expect(await exporter.export_sequence(root, recorded, id, output, Vector2i(32, 32), 4.0) == OK, "Sprite timing exports through the shared clock")
		for index: int in colors.size():
			var image := Image.load_from_file(output.path_join("frame_%06d.png" % index))
			expect(image != null and image.get_pixel(17, 17).is_equal_approx(colors[index]) and image.get_pixel(0, 0).a < 0.01,
				"PNG pixels match the observed live sprite at frame %d" % index)
		_remove_directory(output)
	played.free()
	recorder.free()
	runtime.free()
	DirAccess.remove_absolute(path)


func _test_triggered_take(model: TwberModelResource, id: String, expected: Dictionary) -> void:
	var triggered := model.duplicate(true) as TwberModelResource
	var parameter := TwberParameterResource.new()
	parameter.id = "play_take"
	parameter.value_type = TwberParameterResource.ValueType.BOOL
	var binding := TwberAnimationBindingResource.new()
	binding.animation_id = id
	binding.coordinate = Vector2(1.0, 0.0)
	parameter.animation_bindings.append(binding)
	triggered.parameters.append(parameter)
	var runtime := TwberRuntimeModel.new()
	root.add_child(runtime)
	runtime.set_model(triggered)
	runtime.set_parameter_value("play_take", true)
	runtime.evaluate_parameters()
	var sprite := runtime._layer_nodes["sprite"] as AnimatedSprite2D
	for index: int in range(6):
		if index > 0:
			runtime._process(0.25)
		var time := float(index) * 0.25
		expect(str(sprite.animation) == expected[time][0] and sprite.frame == expected[time][1]
			and is_equal_approx(sprite.frame_progress, expected[time][2]),
			"Live triggers replay captured sprite timing at %s" % time)
	runtime.set_parameter_value("play_take", false)
	runtime.evaluate_parameters()
	runtime.set_parameter_value("play_take", true)
	runtime.evaluate_parameters()
	expect(sprite.frame == 1 and is_equal_approx(sprite.frame_progress, 0.25),
		"Retriggering a take restores its recorded starting offset")
	runtime._process(2.0)
	var end_phase: float = runtime.get_sprite_states()["sprite"].phase
	runtime._process(0.5)
	expect(is_equal_approx(runtime.get_sprite_states()["sprite"].phase, end_phase),
		"Nonlooping take triggers hold their sprite endpoint")
	runtime.free()


func _test_editor(model: TwberModelResource, id: String, expected: Dictionary) -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(model, "")
	var animator := editor._editor_animator
	editor._mode_bar.current_tab = animator.get_index()
	animator._selected_animation_id = id
	for time: float in [1.0, 0.0, 0.5, 0.25, 0.75]:
		animator._playhead = time
		animator._apply_animation_at_playhead()
		var sprite := animator._nodes_by_layer_id["sprite"] as AnimatedSprite2D
		expect(str(sprite.animation) == expected[time][0] and sprite.frame == expected[time][1]
			and is_equal_approx(sprite.frame_progress, expected[time][2]), "Animate scrubbing reproduces the saved live sprite at %s" % time)
	expect(animator._authored_sprite_timing.visible, "Recorded timing exposes an authoring override")
	animator._authored_sprite_timing.pressed.emit()
	expect(TwberEditTimeline.find(editor._document.snapshot().to_model_resource(), id).sprite_keys.is_empty()
		and editor.undo_document(), "Switching to authored timing is undoable from Animate")
	editor.free()


func _test_history(model: TwberModelResource, id: String) -> void:
	var document := TwberModelDocument.new()
	document.replace_model(model)
	var duplicate := TwberDuplicateLayers.new(["sprite"])
	expect(document.execute(duplicate) == OK, "Duplicating animated layers retains their timing")
	var clip := TwberEditTimeline.find(document.snapshot().to_model_resource(), id)
	expect(clip.sprite_keys.size() == 8 and clip.sprite_keys[4].layer_id == duplicate.id_mapping["sprite"], "Duplicated sprite anchors point to the new layer")
	expect(document.execute(TwberDeleteLayers.new([duplicate.id_mapping["sprite"]])) == OK
		and TwberEditTimeline.find(document.snapshot().to_model_resource(), id).sprite_keys.size() == 4,
		"Deleting a layer removes its phase markers")
	expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, id, {"duration": 0.5})) == ERR_INVALID_PARAMETER,
		"Duration edits cannot truncate phase markers")
	expect(document.execute(TwberEditLayer.new("sprite", TwberEditLayer.Operation.RENAME_ANIMATION,
		{"animation": "Idle", "name": "Rest"})) == OK, "Sprite animations with captured timing can be renamed")
	clip = TwberEditTimeline.find(document.snapshot().to_model_resource(), id)
	expect(clip.sprite_keys[0].animation_name == "Rest" and document.undo(),
		"Renaming remaps captured animation names and remains undoable")
	expect(document.execute(TwberEditLayer.new("sprite", TwberEditLayer.Operation.DELETE_ANIMATION,
		{"animation": "Other"})) == OK, "Referenced sprite animations can be deleted")
	clip = TwberEditTimeline.find(document.snapshot().to_model_resource(), id)
	expect(clip.sprite_keys[2].animation_name == "Idle" and document.undo(),
		"Deleting remaps captured names to the surviving animation")
	var invalid := model.duplicate(true) as TwberModelResource
	var take := TwberEditTimeline.find(invalid, id)
	take.sprite_keys[0].phase = NAN
	expect(not TwberDocumentValidator.validate(invalid).is_empty(), "Nonfinite captured phase is rejected")
	var legacy := TwberModelCodec.to_dictionary(model, false)
	legacy["format_version"] = 11
	for animation: Dictionary in legacy["timeline_animations"]:
		animation.erase("sprite_keys")
	var loaded := TwberModelCodec.from_dictionary(legacy)
	expect(loaded != null and TwberEditTimeline.find(loaded, id).sprite_keys.is_empty(), "Legacy clips load with authored sprite timing")


func _test_sprite_only() -> void:
	var model := _model()
	model.parameters.clear()
	var clock := TwberSpriteClock.new()
	clock.configure(model)
	clock.advance(0.375)
	var take := TwberModelTake.new()
	expect(take.start(model, {}, {}, clock.states()) == OK, "A model with only animated artwork can be recorded")
	clock.advance(0.25)
	expect(take.sample(0.25, {}, {}, clock.states()) == OK, "Sprite-only takes retain their clocks without parameter keys")
	var result := take.finish(0.5)
	expect(result.error == OK and TwberEditTimeline.find(result.model, result.animation_id).sprite_keys.size() == 1,
		"Sprite-only takes import as compact native clips")
	var runtime := TwberRuntimeModel.new()
	root.add_child(runtime)
	runtime.set_model(model)
	runtime._process(1.0)
	var sprite := runtime._layer_nodes["sprite"] as AnimatedSprite2D
	expect(sprite.frame == 1 and is_zero_approx(sprite.frame_progress), "Looping uses relative duration totals")
	runtime.set_model(null)
	expect(runtime.get_sprite_states().is_empty() and not runtime.is_processing(), "Removing a model clears its clock")
	runtime.free()


func _remove_directory(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
