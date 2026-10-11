extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_test_recording()
		await _test_editor_recording()
	else:
		await _test_pixels()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Twber recording/export tests passed (%s)." % DisplayServer.get_name())
	quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _model() -> TwberModelResource:
	var model := TwberModelResource.new()
	var layer := TwberLayerResource.new()
	layer.id = "face"
	layer.name = "Face"
	layer.type = TwberLayerResource.LayerType.ANIMATED_SPRITE
	layer.centered = false
	layer.current_animation = "Idle"
	var animation := TwberAnimationResource.new()
	animation.name = "Idle"
	animation.speed = 4.0
	animation.frame_texture_ids.assign(["red", "blue"])
	animation.frame_durations.assign([1.0, 2.0])
	layer.animations.append(animation)
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)
	for color_name: String in ["red", "blue"]:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.RED if color_name == "red" else Color.BLUE)
		model.textures[color_name] = ImageTexture.create_from_image(image)
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


func _recorded_model() -> TwberModelResource:
	var model := _model()
	var take := TwberParameterTake.new(model.parameters)
	take.sample(0, {"move": 0.0})
	take.sample(0.25, {"move": 1.0})
	var clip := take.to_clip(0.5, 4.0)
	clip.id = "take"
	model.timeline_animations.append(clip)
	return model


func _test_recording() -> void:
	var model := _model()
	var recorder := TwberParameterTake.new(model.parameters)
	expect(recorder.sample(0.1, {}) == ERR_INVALID_PARAMETER, "Takes require an initial sample at zero")
	expect(recorder.sample(0.0, {}) == OK, "Missing initial inputs use parameter defaults")
	expect(recorder.sample(0.125, {"move": 0.5}) == OK, "Fractional event timestamps are retained")
	expect(recorder.sample(0.125, {"move": 0.75}) == OK, "Same-timestamp input updates coalesce")
	expect(recorder.sample(0.1, {"move": 0.25}) == ERR_INVALID_PARAMETER, "Out-of-order events fail atomically")
	expect(recorder.sample(0.25, {"move": NAN}) == ERR_INVALID_PARAMETER, "Invalid values fail atomically")
	expect(recorder.sample(0.25, {"move": 2.0}) == OK, "Recorded inputs normalize to parameter limits")
	expect(recorder.sample(0.3, {"move": 1.0}) == OK, "Unchanged samples do not add keys")
	expect(recorder.sample(0.4, {}) == OK, "Partial input updates retain previous values for missing parameters")
	var clip := recorder.to_clip(0.5, 30)
	expect(clip.parameter_keys.size() == 3 and clip.parameter_keys[1].time == 0.125
		and clip.parameter_keys[1].coordinate.x == 0.75, "Takes retain timestamps and compact unchanged inputs")
	clip.id = "take"
	model.timeline_animations.append(clip)
	var evaluator := TwberModelEvaluator.new()
	evaluator.configure(model)
	for pair: Vector2 in [Vector2(0, 0), Vector2(0.124, 0), Vector2(0.125, 0.75), Vector2(0.24, 0.75), Vector2(0.25, 1), Vector2(0.5, 1)]:
		var live: TwberLayerStateResource = evaluator.evaluate({"move": pair.y})["face"].duplicate(true)
		var played: TwberLayerStateResource = evaluator.evaluate({}, {"take": pair.x})["face"]
		expect(TwberLayerStateResource.same_pose(live, played), "Recorded playback reproduces normalized live inputs at %s" % pair.x)
	var document := TwberModelDocument.new()
	document.replace_model(_model())
	var command := TwberImportParameterTake.new(clip)
	clip.parameter_keys[0].coordinate.x = 1
	expect(document.execute(command) == OK and document.get_undo_label() == "Record parameter take", "A detached take commits in one transaction")
	var saved := document.snapshot().to_model_resource()
	expect(saved.timeline_animations[0].parameter_keys[0].coordinate.x == 0, "Caller mutations cannot change the committed take")
	expect(document.undo() and document.snapshot().to_model_resource().timeline_animations.is_empty(), "One Undo removes the entire take")
	expect(document.redo() and document.snapshot().to_model_resource().timeline_animations[0].id == command.animation_id, "Redo retains the take ID")
	var path := "user://twber_recorded_take.twber"
	expect(TwberModelCodec.export_twber(saved, path) == OK, "Recorded takes save")
	var loaded := TwberModelCodec.load_model(path)
	expect(loaded.timeline_animations[0].parameter_keys[1].time == 0.125, "Archive round trips preserve event timestamps")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	expect(TwberFrameExporter.frame_count(0.5, 4) == 2 and TwberFrameExporter.frame_count(0.07, 100) == 7
		and TwberFrameExporter.frame_count(INF, 30) == 0, "Export schedules use exact half-open frame intervals and reject invalid lengths")


func _test_editor_recording() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_model(), "")
	var rig := editor._editor_rigger
	var sprite := editor._model_root.get_child(0) as AnimatedSprite2D
	editor._mode_bar.current_tab = editor._editor_animator.get_index()
	expect(not sprite.is_playing(), "Explicit Animate preview does not advance sprite frames on the wall clock")
	editor._mode_bar.current_tab = rig.get_index()
	expect(sprite.is_playing(), "Leaving Animate restores the sprite's prior playing state")
	var revision := editor._document.get_revision()
	editor._toggle_parameter_recording()
	rig._on_parameter_value_changed(rig._get_model_parameters()[0], 1.0)
	expect(editor._parameter_take != null and not editor.is_dirty() and editor._document.get_revision() == revision,
		"Recording changes preview inputs without authoring the document")
	var path := "user://twber_unfinished_take.twber"
	editor._save_model_to_path(path, true)
	expect(TwberModelCodec.load_model(path).timeline_animations.is_empty(), "Saving excludes unfinished takes")
	expect(editor._finish_parameter_recording() == OK and editor._document.get_revision() == revision + 1,
		"Finish creates one authored take and opens Animate")
	var animator := editor._editor_animator
	expect(editor._mode_bar.current_tab == animator.get_index() and animator._get_selected_animation() != null, "The recorded clip is immediately available for playback/export")
	animator._playhead = animator._get_selected_animation().duration
	animator._apply_animation_at_playhead()
	expect(editor._model_root.get_child(0).position == Vector2(8, 0), "Recorded parameter playback matches the last live input")
	expect(editor.undo_document() and editor._document.snapshot().to_model_resource().timeline_animations.is_empty(), "Editor Undo removes the take")
	editor._mode_bar.current_tab = rig.get_index()
	editor._toggle_parameter_recording()
	expect(editor.undo_document() and editor._parameter_take == null and editor._document.get_revision() == revision + 2,
		"Undo discards an active recording before committed history")
	editor._toggle_parameter_recording()
	editor._cancel_external_focus_edits()
	expect(editor._parameter_take == null, "Focus loss cancels recording")
	editor._toggle_parameter_recording()
	editor._document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, "move", {"name": "New name"}))
	expect(editor._parameter_take == null, "Document changes invalidate the old recording definition")
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_pixels() -> void:
	var base := ProjectSettings.globalize_path("user://twber_export_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base)
	var model := _recorded_model()
	var exporter := TwberFrameExporter.new()
	var first := base.path_join("first")
	expect(await exporter.export_sequence(root, model, "take", first, Vector2i(32, 32), 4.0) == OK, "PNG sequence exports through the real renderer")
	var frame0 := Image.load_from_file(first.path_join("frame_000000.png"))
	var frame1 := Image.load_from_file(first.path_join("frame_000001.png"))
	if frame0 == null or frame1 == null:
		expect(false, "Export contains its scheduled PNG frames")
		_remove_directory(base)
		return
	expect(frame0.get_pixel(17, 17).r > 0.9 and frame0.get_pixel(0, 0).a < 0.01,
		"The first exported frame preserves the sprite and transparent canvas")
	expect(frame1.get_pixel(25, 17).b > 0.9 and frame1.get_pixel(17, 17).a < 0.01,
		"The next frame applies recorded motion and deterministic sprite phase")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first.path_join("sequence.json")))
	expect(manifest.frame_times == [0.0, 0.25] and not FileAccess.file_exists(first.path_join("frame_000002.png")), "Manifest records the exact frame schedule without a duplicate endpoint")
	var second := base.path_join("second")
	expect(await exporter.export_sequence(root, model, "take", second, Vector2i(32, 32), 4.0) == OK,
		"The same clip can be exported again")
	expect(Image.load_from_file(second.path_join("frame_000001.png")).get_data() == frame1.get_data(),
		"Repeated exports agree pixel-for-pixel regardless of wall-clock sprite playback")
	expect(await exporter.export_sequence(root, model, "take", first, Vector2i(32, 32), 4.0) == ERR_ALREADY_EXISTS
		and Image.load_from_file(first.path_join("frame_000000.png")).get_data() == frame0.get_data(), "Existing output is never overwritten")
	var cancel_job := TwberFrameExporter.new()
	var cancel_callback := func(_done: int, _total: int) -> void: cancel_job.cancel()
	cancel_job.progress.connect(cancel_callback)
	expect(await cancel_job.export_sequence(root, model, "take", base.path_join("cancelled"), Vector2i(32, 32), 4.0) == ERR_SKIP
		and not DirAccess.dir_exists_absolute(base.path_join("cancelled")), "Cancellation publishes no partial output")
	cancel_job.progress.disconnect(cancel_callback)
	for directory: String in DirAccess.get_directories_at(base):
		expect(not directory.contains(".partial-"), "Cancelled staging folders are removed")
	# Mutating the source after the first frame cannot affect the job snapshot.
	var snapshot_job := TwberFrameExporter.new()
	snapshot_job.progress.connect(func(_done: int, _total: int) -> void:
		model.parameters[0].positions[0].layer_states[0].position = Vector2(999, 999))
	var snapshot_path := base.path_join("snapshot")
	expect(await snapshot_job.export_sequence(root, model, "take", snapshot_path, Vector2i(32, 32), 4.0) == OK
		and Image.load_from_file(snapshot_path.path_join("frame_000001.png")).get_data() == frame1.get_data(), "An export owns an immutable model snapshot for its entire run")
	var owner := Node.new()
	root.add_child(owner)
	var owner_job := TwberFrameExporter.new()
	owner_job.progress.connect(func(_done: int, _total: int) -> void: owner.free(), CONNECT_ONE_SHOT)
	expect(await owner_job.export_sequence(owner, _recorded_model(), "take", base.path_join("closed"), Vector2i(32, 32), 4.0) == ERR_SKIP,
		"Closing the export owner cancels and cleans up the job")
	_remove_directory(base)


func _remove_directory(path: String) -> void:
	for child: String in DirAccess.get_directories_at(path):
		_remove_directory(path.path_join(child))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
