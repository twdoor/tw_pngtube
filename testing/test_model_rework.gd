extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_pose_edit_sessions()
	_test_native_pivot_and_mirror()
	_test_layer_settings_and_assets()
	_test_timeline_commands()
	_test_parameter_commands()
	_test_document_transactions()
	_test_document_validation()
	_test_hierarchy_commands()
	_test_native_mesh_commands_and_sessions()
	_test_document_projection()
	_test_sparse_timeline_composition()
	await _test_editor_pose_drafts()
	await _test_editor_native_layer_edits()
	await _test_editor_native_timeline()
	await _test_editor_native_parameters()
	await _test_editor_preview_ownership()
	await _test_editor_history_and_saves()
	await _test_editor_mesh_history()
	await _test_editor_native_hierarchy()
	await _test_editor_mesh_gestures()
	await _test_mesh_conversion_gesture()
	if _failures.is_empty():
		print("Twber model rework tests passed.")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_document_transactions() -> void:
	var source := _make_rigged_model()
	var document := TwberModelDocument.new()
	_expect(document.replace_model(source) == OK, "Document accepts a valid authored model")
	source.layers[0].position = Vector2(999, 999)
	source.parameters[0].positions[0].layer_states[0].position = Vector2(999, 999)
	var initial := document.snapshot()
	var initial_model := initial.to_model_resource()
	_expect(initial_model.layers[0].position == Vector2(10, 20)
		and initial_model.parameters[0].positions[0].layer_states[0].position == Vector2(30, 20),
		"Document owns detached layers and nested rig resources")
	initial_model.layers[0].position = Vector2(-999, 0)
	_expect(initial.to_model_resource().layers[0].position == Vector2(10, 20),
		"Snapshot consumers cannot mutate the captured revision")
	var changes: Array[TwberDocumentChange] = []
	document.changed.connect(func(change: TwberDocumentChange) -> void: changes.append(change))
	_expect(document.execute(TwberSetRestTransform.new("layer_001", Vector2(50, 20), 0.0, Vector2.ONE)) == OK,
		"Rest transforms execute without a scene tree")
	var moved := document.snapshot().to_model_resource()
	_expect(moved.layers[0].position == Vector2(50, 20)
		and moved.parameters[0].positions[0].layer_states[0].position == Vector2(70, 20)
		and moved.timeline_animations[0].keyframes[0].layer_state.position == Vector2(55, 20),
		"Rest edits rebase both parameter poses and timeline keys")
	_expect(changes.size() == 1 and changes[0].layer_ids == ["layer_001"]
		and (changes[0].kinds & TwberDocumentChange.Kind.ANIMATION) != 0,
		"Committed commands publish one typed change set")
	_expect(document.is_dirty(), "A committed edit is dirty")
	_expect(document.can_undo() and not document.can_redo(), "History availability follows a committed edit")
	var moved_snapshot := document.snapshot()
	_expect(document.mark_saved(moved_snapshot) and not document.is_dirty(), "Save checkpoint marks its state clean")
	_expect(document.undo() and document.is_dirty(), "Undo away from the save checkpoint is dirty")
	_expect(not document.can_undo() and document.can_redo(), "History availability follows Undo")
	_expect(document.snapshot().to_model_resource().parameters[0].positions[0].layer_states[0].position == Vector2(30, 20),
		"Undo restores dependent rig data exactly")
	_expect(document.redo() and not document.is_dirty(), "Redo back to the save checkpoint is clean")
	var revision := document.get_revision()
	document.execute(TwberSetRestTransform.new("layer_001", Vector2(50, 20), 0.0, Vector2.ONE))
	_expect(document.get_revision() == revision, "No-op commands do not create undo history")
	var commands: Array[TwberDocumentCommand] = [
		TwberSetRestTransform.new("layer_001", Vector2(60, 20), 0.0, Vector2.ONE),
		TwberSetRestTransform.new("missing", Vector2.ZERO, 0.0, Vector2.ONE),
	]
	_expect(document.execute(TwberCompoundCommand.new("Fail atomically", commands)) == ERR_DOES_NOT_EXIST,
		"Invalid compound command reports the failed operation")
	_expect(document.get_revision() == revision and not document.is_dirty()
		and document.snapshot().to_model_resource().layers[0].position == Vector2(50, 20),
		"Failed compound commands publish no partial edits or history")
	commands[1] = TwberSetRestTransform.new("layer_001", Vector2(80, 20), 0.25, Vector2.ONE)
	_expect(document.execute(TwberCompoundCommand.new("Compound transform", commands)) == OK,
		"Valid compound command commits")
	_expect(document.undo() and document.snapshot().to_model_resource().layers[0].position == Vector2(50, 20),
		"One Undo reverses the entire compound command")
	# Branching from the same history depth must not reuse a saved state's identity.
	document.undo()
	document.execute(TwberSetRestTransform.new("layer_001", Vector2(90, 20), 0.0, Vector2.ONE))
	_expect(document.is_dirty() and not document.redo(), "Editing after Undo invalidates Redo without confusing save identity")
	_expect(document.mark_saved(moved_snapshot) and document.is_dirty(),
		"Completion of an older save never marks newer edits clean")
	var stale := document.snapshot()
	document.replace_model(_make_model())
	_expect(not document.mark_saved(stale) and not document.is_dirty(),
		"A previous document's save completion cannot affect a newly opened document")
	# The producer may reuse or alter its command after execution.
	var command := TwberSetRestTransform.new("layer_001", Vector2(25, 20), 0.0, Vector2.ONE)
	document.execute(command)
	command.position = Vector2(777, 0)
	document.undo()
	document.redo()
	_expect(document.snapshot().to_model_resource().layers[0].position == Vector2(25, 20),
		"History is isolated from later command mutation")


func _test_document_validation() -> void:
	var document := TwberModelDocument.new()
	document.replace_model(_make_model())
	var revision := document.get_revision()
	var invalid := _make_model()
	invalid.layers[0].children.append("layer_001")
	_expect(document.replace_model(invalid) == ERR_INVALID_DATA and not document.get_diagnostics().is_empty(),
		"Document rejects a cyclic hierarchy with diagnostics")
	_expect(document.get_revision() == revision and not document.is_dirty(), "Invalid replacement keeps the open document intact")
	invalid = _make_model()
	invalid.layers.append(invalid.layers[0].duplicate(true))
	_expect(not TwberDocumentValidator.validate(invalid).is_empty(), "Duplicate IDs are rejected")
	invalid = _make_rigged_model()
	invalid.parameters[0].positions[0].layer_states[0].layer_id = "missing"
	_expect(not TwberDocumentValidator.validate(invalid).is_empty(), "Dangling rig references are rejected")
	_expect(document.execute(TwberSetRestTransform.new("layer_001", Vector2(INF, 0), 0.0, Vector2.ONE)) == ERR_INVALID_PARAMETER,
		"Non-finite authored transforms are rejected")
	_expect(document.get_revision() == revision, "Rejected commands do not increment revision")


func _test_document_projection() -> void:
	var document := TwberModelDocument.new()
	document.replace_model(_make_rigged_model())
	var first := TwberDocumentPreview.new()
	var second := TwberDocumentPreview.new()
	root.add_child(first)
	root.add_child(second)
	first.bind_document(document)
	second.bind_document(document)
	first.set_parameter_value("move", 1.0)
	first.evaluate_parameters()
	_expect((first.get_child(0) as Node2D).position == Vector2(30, 20)
		and (second.get_child(0) as Node2D).position == Vector2(10, 20),
		"Document previews own independent parameter poses")
	document.execute(TwberSetRestTransform.new("layer_001", Vector2(50, 20), 0.0, Vector2.ONE))
	_expect((first.get_child(0) as Node2D).position == Vector2(70, 20)
		and (second.get_child(0) as Node2D).position == Vector2(50, 20),
		"Document changes update both projections while preserving their own inputs")
	(first.get_child(0) as Node2D).position = Vector2(999, 999)
	var snapshot := document.snapshot()
	_expect(snapshot.to_model_resource().layers[0].position == Vector2(50, 20),
		"Render-node edits cannot change authored data")
	var path := "user://twber_document_snapshot_test.res"
	_expect(ResourceSaver.save(snapshot.to_model_resource(), path) == OK,
		"A snapshot saves directly without scene capture or preview restoration")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TwberModelResource
	_expect(loaded != null and loaded.layers[0].position == Vector2(50, 20),
		"Saved snapshot retains the authored transform rather than the displayed pose")
	_expect(document.mark_saved(snapshot) and not document.is_dirty(), "Persisted snapshot advances the checkpoint")
	document.undo()
	_expect((first.get_child(0) as Node2D).position == Vector2(30, 20)
		and document.snapshot().to_model_resource().layers[0].position == Vector2(10, 20),
		"Undo projects document data even after arbitrary render-node mutation")
	first.bind_document(null)
	_expect(first.get_child_count() == 0, "Unbinding releases the projected model")
	first.free()
	second.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _make_rigged_model() -> TwberModelResource:
	var model := _make_model()
	var parameter := TwberParameterResource.new()
	parameter.id = "move"
	var sample := TwberParameterPositionResource.new()
	sample.coordinate = Vector2(1, 0)
	var state := TwberLayerStateResource.from_layer_resource(model.layers[0])
	state.channels = TwberLayerStateResource.Channel.POSITION
	state.position = Vector2(30, 20)
	sample.layer_states.append(state)
	parameter.positions.append(sample)
	model.parameters.append(parameter)
	var animation := TwberTimelineAnimationResource.new()
	animation.id = "move_clip"
	var key := TwberTimelineKeyframeResource.new()
	key.layer_state = TwberLayerStateResource.from_layer_resource(model.layers[0])
	key.layer_state.channels = TwberLayerStateResource.Channel.POSITION
	key.layer_state.position = Vector2(15, 20)
	animation.keyframes.append(key)
	model.timeline_animations.append(animation)
	return model


func _test_sparse_timeline_composition() -> void:
	var model := _make_model()
	var move := TwberParameterResource.new()
	move.id = "move"
	var sample := TwberParameterPositionResource.new()
	sample.coordinate = Vector2(1, 0)
	var pose := TwberLayerStateResource.from_layer_resource(model.layers[0])
	pose.channels = TwberLayerStateResource.Channel.POSITION
	pose.position = Vector2(100, 20)
	sample.layer_states.append(pose)
	move.positions.append(sample)
	model.parameters.append(move)
	var trigger := TwberParameterResource.new()
	trigger.id = "fade"
	trigger.value_type = TwberParameterResource.ValueType.BOOL
	var binding := TwberAnimationBindingResource.new()
	binding.animation_id = "fade"
	binding.coordinate = Vector2(1, 0)
	trigger.animation_bindings.append(binding)
	model.parameters.append(trigger)
	var animation := TwberTimelineAnimationResource.new()
	animation.id = "fade"
	for index: int in 2:
		var key := TwberTimelineKeyframeResource.new()
		key.time = float(index)
		key.layer_state = TwberLayerStateResource.from_layer_resource(model.layers[0])
		key.layer_state.channels = TwberLayerStateResource.Channel.COLOR
		key.layer_state.self_modulate.a = 1.0 - float(index)
		animation.keyframes.append(key)
	model.timeline_animations.append(animation)
	var neutral := TwberLayerStateResource.from_layer_resource(model.layers[0])
	for time_position: float in [0.0, 0.5, 1.0]:
		var sampled := animation.sample_layer("layer_001", time_position, neutral)
		_expect(sampled.channels == TwberLayerStateResource.Channel.COLOR,
			"Timeline endpoints and interpolation preserve the authored channel mask")
	var runtime := TwberRuntimeModel.new()
	runtime.enable_runtime_atlases = false
	root.add_child(runtime)
	runtime.set_model(model)
	runtime.set_parameter_values({"move": 1.0, "fade": true})
	runtime._process(0.5)
	var layer := runtime.get_child(0) as Node2D
	_expect(layer.position.is_equal_approx(Vector2(100, 20)),
		"Color-only timeline preserves parameter-driven position")
	_expect(is_equal_approx(layer.self_modulate.a, 0.5), "Color timeline interpolates opacity")
	runtime._process(0.1)
	_expect(layer.position.is_equal_approx(Vector2(100, 20)),
		"Repeated playback preserves disjoint parameter channels")
	runtime.set_parameter_value("fade", false)
	runtime._process(0.0)
	_expect(layer.position.is_equal_approx(Vector2(100, 20)) and layer.self_modulate == Color.WHITE,
		"Releasing the timeline restores the parameter pose")
	runtime.free()


func _test_editor_preview_ownership() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor.call("_apply_opened_model", _make_rigged_model(), "")
	var model_root := editor.get_node("ModelPreview/Textures") as Node2D
	var layer := model_root.get_child(0) as Node2D
	var placer := editor.get("_editor_placer") as EditorPlacer
	var animator := editor.get("_editor_animator") as EditorAnimator
	var menus := placer.get_parent() as TabContainer
	menus.current_tab = placer.get_index()
	await process_frame
	var layers: Dictionary = placer.get("_layers_by_id")
	for layer_id: Variant in layers:
		if layers[layer_id]["node"] == layer:
			placer.call("_set_selected_layer", layer_id)
	_move_in_placer(placer, layer, Vector2(40, 0))
	var expected := layer.position
	_expect(expected.is_equal_approx(Vector2(50, 20)), "Place drag moves the selected layer")
	var captured := editor.call("_create_model_resource_from_base_state") as TwberModelResource
	_expect(captured.layers[0].position.is_equal_approx(expected) and layer.position.is_equal_approx(expected),
		"Save capture preserves Place edits while Animate is inactive")
	_expect(captured.parameters[0].positions[0].layer_states[0].position == Vector2(70, 20)
		and captured.timeline_animations[0].keyframes[0].layer_state.position == Vector2(55, 20),
		"Place uses the shared transform rules for parameter samples and timeline keys")
	menus.current_tab = animator.get_index()
	await process_frame
	animator.reload_from_preview(layer)
	layer.position += Vector2(0, 60)
	menus.current_tab = placer.get_index()
	await process_frame
	_expect(layer.position.is_equal_approx(expected), "Leaving Animate restores only its active preview")
	# A second Place edit must not be overwritten by Animate's previous session.
	placer.reload_from_preview()
	layers = placer.get("_layers_by_id")
	for layer_id: Variant in layers:
		if layers[layer_id]["node"] == layer:
			placer.call("_set_selected_layer", layer_id)
	_move_in_placer(placer, layer, Vector2(15, 0))
	expected = layer.position
	menus.current_tab = 1 # Mesh also leaves the inactive animator alone.
	await process_frame
	_expect(layer.position.is_equal_approx(expected), "Tab changes preserve edits after an animation session")
	var path := "user://twber_rework_preview_test.twber"
	_expect(editor.call("_save_model_to_path", path, true) == OK, "Edited document saves")
	var loaded := TwberModelCodec.load_model(path)
	_expect(loaded != null and loaded.layers[0].position.is_equal_approx(expected),
		"Saved archive contains the latest authored Place transform")
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_editor_history_and_saves() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_make_rigged_model(), "")
	var model_root := editor.get_node("ModelPreview/Textures") as Node2D
	var placer := editor._editor_placer
	var animator := editor._editor_animator
	var rigger := editor._editor_rigger
	var document := editor._document
	editor._menus.current_tab = placer.get_index()
	placer.select_document_layer("layer_001")
	var layer := model_root.get_child(0) as Node2D
	var revision := document.get_revision()
	var start := layer.get_global_transform_with_canvas().origin
	placer._begin_transform_drag(start, EditorPlacer.TransformMode.MOVE)
	placer._update_transform_drag(start + Vector2(20, 0))
	placer._update_transform_drag(start + Vector2(40, 0))
	_expect(document.get_revision() == revision, "Drag motion does not create history entries")
	placer.finish_transform_drag()
	_expect(document.get_revision() == revision + 1 and editor.is_dirty(), "Drag release commits exactly once")
	_expect(editor.undo_document() and not editor.is_dirty(), "Editor Undo returns to clean loaded state")
	_expect((model_root.get_child(0) as Node2D).position == Vector2(10, 20)
		and placer.get_selected_document_layer_id() == "layer_001", "Undo restores the scene and stable layer selection")
	_expect(editor.redo_document(), "Editor Redo reapplies the transaction")
	layer = model_root.get_child(0) as Node2D
	var path := "user://twber_history_save.twber"
	_expect(editor._save_model_to_path(path, true) == OK and not editor.is_dirty(), "Save marks the committed history state clean")
	_expect(editor.undo_document() and editor.is_dirty(), "Undo away from a saved state becomes dirty")
	_expect(editor.redo_document() and not editor.is_dirty(), "Redo back to saved state becomes clean")
	layer = model_root.get_child(0) as Node2D
	start = layer.get_global_transform_with_canvas().origin
	revision = document.get_revision()
	placer._begin_transform_drag(start, EditorPlacer.TransformMode.MOVE)
	placer._update_transform_drag(start + Vector2(100, 0))
	_expect(editor.undo_document() and document.get_revision() == revision
		and layer.position == Vector2(50, 20), "Undo during a drag cancels only the unfinished gesture")
	# A view change must not leak into authored settings or history projection.
	var authored_root := document.snapshot().to_model_resource().root_position
	model_root.position += Vector2(90, 80)
	var camera_position := model_root.position
	placer._on_show_behind_parent_toggled(true)
	_expect(editor._finish_pending_authoring() == OK, "Inspector changes use native commands")
	var captured := document.snapshot().to_model_resource()
	_expect(captured.layers[0].show_behind_parent and captured.root_position == authored_root,
		"Inspector transaction excludes camera movement")
	_expect(editor.undo_document() and model_root.position == camera_position,
		"Undo preserves camera position")
	_expect(editor.redo_document(), "Inspector changes support Redo")
	# Editing animation metadata while its pose is displayed must retain neutral rest data.
	editor._menus.current_tab = animator.get_index()
	animator._select_animation_index(0)
	animator._toggle_playback()
	animator._rename_animation("Motion")
	layer = model_root.get_child(0) as Node2D
	var displayed := layer.position
	_expect(await editor._save_model_to_path_async(path, true) == OK, "Background save flushes pending animation edits")
	_expect(animator._playing and layer.position == displayed, "Save does not stop or restore active playback")
	var loaded := TwberModelCodec.load_model(path)
	_expect(loaded.layers[0].position == Vector2(50, 20)
		and loaded.timeline_animations[0].name == "Motion"
		and loaded.timeline_animations[0].keyframes[0].layer_state.position == Vector2(55, 20),
		"Archive stores rest pose and animation edits independently")
	editor._menus.current_tab = rigger.get_index()
	rigger._on_parameter_value_changed(rigger._get_model_parameters()[0], 1.0)
	layer = model_root.get_child(0) as Node2D
	displayed = layer.position
	rigger._on_create_parameter_pressed(TwberParameterResource.ValueType.FLOAT)
	_expect(editor._finish_pending_authoring() == OK, "Rig authoring commits while parameter preview is active")
	captured = document.snapshot().to_model_resource()
	_expect(captured.layers[0].position == Vector2(50, 20) and captured.parameters.size() == 2,
		"Rig authoring keeps preview transforms out of rest data")
	_expect(editor.undo_document() and document.snapshot().to_model_resource().parameters.size() == 1,
		"Undo removes a newly authored parameter")
	editor._menus.current_tab = placer.get_index()
	placer.select_document_layer("layer_001")
	placer._on_delete_button_pressed()
	_expect(editor._finish_pending_authoring() == OK, "Deleting a rigged and animated layer commits successfully")
	captured = document.snapshot().to_model_resource()
	_expect(captured.layers.is_empty() and captured.timeline_animations[0].keyframes.is_empty(),
		"Layer deletion removes dependent timeline keys")
	_expect(editor.undo_document(), "Undo restores deleted layers and their dependent authoring data")
	captured = document.snapshot().to_model_resource()
	_expect(captured.layers.size() == 1 and captured.timeline_animations[0].keyframes.size() == 1
		and captured.parameters[0].positions.size() == 1, "Deletion Undo restores both rig poses and timeline keys")
	var invalid := _make_model()
	invalid.layers[0].position.x = INF
	revision = document.get_revision()
	_expect(editor._apply_opened_model(invalid, "invalid.twber") == ERR_INVALID_DATA
		and document.get_revision() == revision and editor.get_current_model_path() == path,
		"Invalid open preserves the current document and file identity")
	# Autosave runs from an isolated snapshot. A replacement invalidates its completion.
	placer.select_document_layer("layer_001")
	placer._on_visible_check_box_toggled(false)
	editor._write_autosave()
	_expect(editor._autosave_active, "Autosave starts in the background")
	editor._new_model()
	while editor._autosave_active:
		await process_frame
	_expect(not editor._owns_recovery and not FileAccess.file_exists(editor._recovery_model_path())
		and not editor.is_dirty(), "An old autosave cannot publish recovery for a new document")
	editor._clear_recovery(true)
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _make_mesh_model() -> TwberModelResource:
	var model := _make_rigged_model()
	var layer := model.layers[0]
	layer.type = TwberLayerResource.LayerType.MESH_SPRITE
	layer.mesh = TwberMeshResource.new()
	layer.mesh.set_vertices(PackedVector2Array([Vector2.ZERO, Vector2(40, 0), Vector2(0, 40)]))
	layer.mesh.uvs = layer.mesh.vertices.duplicate()
	layer.mesh.triangles = PackedInt32Array([0, 1, 2])
	for state: TwberLayerStateResource in TwberSetRestTransform.collect_states(model.parameters, model.timeline_animations, layer.id):
		state.channels |= TwberLayerStateResource.Channel.MESH
		state.mesh_vertices = layer.mesh.vertices.duplicate()
		state.mesh_vertices[1] += Vector2(5, 0)
	return model


func _test_editor_mesh_history() -> void:
	var model := _make_mesh_model()
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(model, "")
	editor._menus.current_tab = editor._editor_mesher.get_index()
	var mesh := editor._model_root.get_child(0) as TwberMeshSprite2D
	editor._editor_mesher.reload_from_preview(mesh)
	editor._editor_mesher._add_point_at(mesh.get_global_transform_with_canvas() * Vector2(40, 40))
	_expect(editor._finish_pending_authoring() == OK, "Mesh vertex insertion commits with dependent timeline topology")
	var edited := editor._document.snapshot().to_model_resource()
	_expect(edited.layers[0].mesh.vertices.size() == 4
		and edited.parameters[0].positions[0].layer_states[0].mesh_vertices.size() == 4
		and edited.timeline_animations[0].keyframes[0].layer_state.mesh_vertices.size() == 4,
		"Mesh vertex insertion updates both rig and timeline samples")
	_expect(editor.undo_document(), "Mesh authoring supports document Undo")
	edited = editor._document.snapshot().to_model_resource()
	_expect(edited.layers[0].mesh.vertices.size() == 3
		and edited.timeline_animations[0].keyframes[0].layer_state.mesh_vertices[1] == Vector2(45, 0),
		"Mesh Undo restores topology and the authored deformation")
	editor.free()


func _make_hierarchy_model() -> TwberModelResource:
	var model := _make_rigged_model()
	var group := TwberLayerResource.new()
	group.id = "group"
	group.name = "Group"
	group.position = Vector2(100, 60)
	group.rotation = 0.3
	group.scale = Vector2(2, 2)
	var child := TwberLayerResource.new()
	child.id = "child"
	child.name = "Child"
	child.position = Vector2(3, 7)
	model.layers[0].children.append(child.id)
	model.layers.append(child)
	model.layers.append(group)
	model.root_layer_ids.append(group.id)
	var child_pose := TwberLayerStateResource.from_layer_resource(child)
	child_pose.channels = TwberLayerStateResource.Channel.COLOR
	child_pose.self_modulate = Color.RED
	model.parameters[0].positions[0].layer_states.append(child_pose)
	return model


func _test_hierarchy_commands() -> void:
	var document := TwberModelDocument.new()
	var model := _make_hierarchy_model()
	document.replace_model(model)
	var duplicate := TwberDuplicateLayers.new(["layer_001", "child"])
	_expect(document.execute(duplicate) == OK and duplicate.duplicated_root_ids.size() == 1,
		"Duplicate filters descendants of selected groups")
	var copied := document.snapshot().to_model_resource()
	var copy_id := duplicate.id_mapping["layer_001"]
	var child_copy_id := duplicate.id_mapping["child"]
	var copied_layers := TwberLayerHierarchy.index(copied)
	_expect(copied.root_layer_ids == ["layer_001", copy_id, "group"]
		and copied_layers[copy_id].children == [child_copy_id], "Duplicate remaps an entire subtree beside its source")
	var sample := copied.parameters[0].positions[0]
	_expect(sample.find_state(copy_id).position == Vector2(30, 20)
		and sample.find_state(child_copy_id).channels == TwberLayerStateResource.Channel.COLOR
		and copied.timeline_animations[0].keyframes.size() == 2,
		"Duplicate retains sparse rig samples and timeline keys for the copied subtree")
	var duplicate_snapshot := document.snapshot()
	_expect(document.undo() and document.redo(), "Hierarchy duplication is one reversible transaction")
	_expect(document.snapshot().to_model_resource().root_layer_ids == copied.root_layer_ids,
		"Redo preserves allocated IDs")
	_expect(document.execute(TwberDeleteLayers.new([copy_id, child_copy_id])) == OK,
		"Delete handles overlapping parent and child selection")
	var deleted := document.snapshot().to_model_resource()
	_expect(deleted.layers.size() == model.layers.size()
		and deleted.timeline_animations[0].keyframes.size() == 1
		and deleted.parameters[0].positions[0].layer_states.size() == 2,
		"Delete removes only the selected subtree and its dependent data")
	document.undo()
	document.mark_saved(duplicate_snapshot)
	_expect(not document.is_dirty(), "Undo deletion returns to an identical saved hierarchy state")

	document.replace_model(model)
	var move := TwberReparentLayers.new(["layer_001"], "group")
	_expect(document.execute(move) == OK, "Reparent accepts a representable coordinate conversion")
	var moved := document.snapshot().to_model_resource()
	var layers := TwberLayerHierarchy.index(moved)
	var parents := TwberLayerHierarchy.parents(moved)
	var world := TwberLayerHierarchy.global_transform("layer_001", layers, parents)
	_expect(world.is_equal_approx(TwberLayerHierarchy.local_transform(model.layers[0])),
		"Reparent keeps rest artwork fixed in model space")
	var parent_world := TwberLayerHierarchy.global_transform("group", layers, parents)
	var rig_pose := moved.parameters[0].positions[0].find_state("layer_001")
	var clip_pose := moved.timeline_animations[0].keyframes[0].layer_state
	_expect((parent_world * rig_pose.position).is_equal_approx(Vector2(30, 20))
		and (parent_world * clip_pose.position).is_equal_approx(Vector2(15, 20)),
		"Reparent converts both parameter positions and timeline positions")
	_expect(rig_pose.channels == TwberLayerStateResource.Channel.POSITION
		and moved.parameters[0].positions[0].find_state("child").channels == TwberLayerStateResource.Channel.COLOR,
		"Reparent preserves disjoint sparse channels")
	var revision := document.get_revision()
	_expect(document.execute(TwberReparentLayers.new(["group"], "child")) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "Cycle rejection publishes no partial hierarchy changes")
	_expect(document.execute(TwberReparentLayers.new(["layer_001"], "group")) == OK
		and document.get_revision() == revision, "Dropping a layer back in its existing position is a no-op")
	_expect(document.execute(TwberReparentLayers.new(["layer_001"], "", "group")) == OK,
		"Layers can move back to root before a stable sibling ID")
	_expect(document.snapshot().to_model_resource().layers[0].position.is_equal_approx(Vector2(10, 20)),
		"Reparent round trip restores original local geometry")

	# Nonuniform scale plus rotation would need a skew channel absent from v9.
	model.layers[2].scale = Vector2(2, 1)
	document.replace_model(model)
	revision = document.get_revision()
	_expect(document.execute(TwberReparentLayers.new(["layer_001"], "group")) == ERR_INVALID_DATA
		and document.get_revision() == revision and not document.is_dirty(),
		"Unrepresentable shear is rejected atomically instead of distorting artwork")
	model.layers[2].scale = Vector2.ZERO
	document.replace_model(model)
	_expect(document.execute(TwberReparentLayers.new(["layer_001"], "group")) == ERR_INVALID_DATA,
		"Reparent rejects a singular destination transform")
	_expect(document.execute(TwberDeleteLayers.new(["missing"])) == ERR_DOES_NOT_EXIST,
		"Hierarchy commands reject missing IDs")

	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var sprite := TwberLayerResource.new()
	sprite.type = TwberLayerResource.LayerType.SPRITE
	sprite.name = "Head"
	sprite.texture_id = "local"
	var create := TwberCreateLayer.new(sprite, "", {"local": texture})
	document.replace_model(_make_model())
	_expect(document.execute(create) == OK, "Layer creation imports a detached resource and texture payload")
	var created := document.snapshot().to_model_resource()
	var created_layer := TwberLayerHierarchy.index(created)[create.created_layer_id]
	_expect(created_layer.id != "layer_001" and created_layer.name == "Head 2"
		and created.textures.has(created_layer.texture_id), "Creation allocates unique layer/asset IDs and sibling names")
	sprite.name = "Externally mutated"
	document.undo()
	document.redo()
	_expect(TwberLayerHierarchy.index(document.snapshot().to_model_resource())[create.created_layer_id].name == "Head 2",
		"Created history is isolated from later payload changes")


func _test_editor_native_hierarchy() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_make_hierarchy_model(), "")
	var placer := editor._editor_placer
	editor._menus.current_tab = placer.get_index()
	var original := TwberParameterMapper.get_layer_nodes_by_id(editor._model_root)
	var revision := editor._document.get_revision()
	placer.select_document_layer("layer_001")
	placer._on_duplicate_button_pressed()
	var copy_id := placer.get_selected_document_layer_id()
	_expect(editor._document.get_revision() == revision + 1
		and editor._document.get_undo_label() == "Duplicate layers", "Place duplication executes a native command once")
	var nodes := TwberParameterMapper.get_layer_nodes_by_id(editor._model_root)
	_expect(nodes["layer_001"] == original["layer_001"] and nodes["child"] == original["child"],
		"Native hierarchy projection preserves surviving node identities")
	var saved := editor._document.snapshot().to_model_resource()
	_expect(saved.parameters[0].positions[0].find_state(copy_id) != null, "The duplicate's rig data reaches the document")
	placer._on_delete_button_pressed()
	_expect(not TwberLayerHierarchy.index(editor._document.snapshot().to_model_resource()).has(copy_id), "Place deletion bypasses legacy scene capture")
	_expect(editor.undo_document() and TwberLayerHierarchy.index(editor._document.snapshot().to_model_resource()).has(copy_id),
		"Editor Undo restores the duplicated subtree")
	placer._create_layer(EditorPlacer.PlacerItemType.EMPTY, "New group")
	var created_id := placer.get_selected_document_layer_id()
	_expect(not created_id.is_empty() and editor._document.get_undo_label() == "Create layer", "Place creation commits a native resource command")
	var source_local_id := -1
	var parent_local_id := -1
	for id: int in placer._layers_by_id:
		var node := placer._layers_by_id[id]["node"] as Node2D
		var document_id := String(node.get_meta(TwberModelCodec.LAYER_ID_META))
		if document_id == "layer_001":
			source_local_id = id
		elif document_id == created_id:
			parent_local_id = id
	placer._move_layers([source_local_id], parent_local_id, 0)
	_expect(TwberLayerHierarchy.parents(editor._document.snapshot().to_model_resource())["layer_001"] == created_id
		and editor._document.get_undo_label() == "Move layers",
		"Place drag/drop commits a native hierarchy transaction")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var texture := ImageTexture.create_from_image(image)
	placer._create_layer(EditorPlacer.PlacerItemType.LAYER, "Imported art", [texture])
	var sprite_id := placer.get_selected_document_layer_id()
	placer._create_layer(EditorPlacer.PlacerItemType.ANIMATION_LAYER, "Frames", [texture, texture])
	var animated_id := placer.get_selected_document_layer_id()
	var payload := editor._document.snapshot().to_model_resource()
	var payload_layers := TwberLayerHierarchy.index(payload)
	_expect(payload.textures.has(payload_layers[sprite_id].texture_id)
		and payload_layers[animated_id].animations[0].frame_texture_ids.size() == 2,
		"Native Place creation preserves imported sprite and animated-frame assets")
	var path := "user://twber_hierarchy_round_trip.twber"
	_expect(editor._save_model_to_path(path, true) == OK, "Native hierarchy and imported assets save together")
	var loaded := TwberModelCodec.load_model(path)
	_expect(loaded != null and TwberLayerHierarchy.parents(loaded)["layer_001"] == created_id
		and TwberLayerHierarchy.index(loaded)[animated_id].animations[0].frame_texture_ids.size() == 2,
		"Hierarchy and animated assets survive archive round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var final_revision := editor._document.get_revision()
	await process_frame
	_expect(editor._document.get_revision() == final_revision, "Native hierarchy operations do not queue a second transaction")
	editor.free()


func _test_native_mesh_commands_and_sessions() -> void:
	var document := TwberModelDocument.new()
	document.replace_model(_make_mesh_model())
	var before := document.snapshot()
	var session := TwberDocumentEditSession.new(document, "Move mesh vertices")
	for x: float in [42.0, 45.0, 50.0]:
		_expect(session.update(TwberEditMesh.move_vertices("layer_001", {1: Vector2(x, 0)}), true) == OK,
			"Mesh drag updates an isolated command draft")
	_expect(document.get_revision() == before.get_revision() and not document.is_dirty()
		and document.snapshot().to_model_resource().layers[0].mesh.vertices[1] == Vector2(40, 0),
		"Gesture previews do not mutate document history or snapshots")
	var draft := session.to_model_resource()
	_expect(draft.layers[0].mesh.uvs[1] == Vector2(50, 0)
		and draft.parameters[0].positions[0].layer_states[0].mesh_vertices[1] == Vector2(55, 0)
		and draft.timeline_animations[0].keyframes[0].layer_state.mesh_vertices[1] == Vector2(55, 0),
		"Mesh movement preserves rig and timeline deformation offsets without cumulative drift")
	draft.layers[0].mesh.vertices[1] = Vector2(999, 0)
	_expect(session.update(TwberEditMesh.move_vertices("layer_001", {900: Vector2.ZERO}), true) == ERR_INVALID_PARAMETER,
		"Invalid draft commands are rejected")
	_expect(session.commit() == OK and document.get_revision() == before.get_revision() + 1,
		"A gesture publishes exactly one history entry")
	_expect(document.snapshot().to_model_resource().layers[0].mesh.vertices[1] == Vector2(50, 0),
		"Failed updates and mutated draft exports cannot alter the committed preview")
	_expect(document.undo() and not document.is_dirty()
		and document.snapshot().to_model_resource().layers[0].mesh.vertices[1] == Vector2(40, 0),
		"One Undo reverses the whole gesture")
	_expect(document.redo(), "Mesh gesture supports Redo")
	var revision := document.get_revision()
	session = TwberDocumentEditSession.new(document, "No movement")
	session.update(TwberEditMesh.move_vertices("layer_001", {1: Vector2(80, 0)}), true)
	session.update(TwberEditMesh.move_vertices("layer_001", {1: Vector2(50, 0)}), true)
	_expect(session.commit() == OK and document.get_revision() == revision,
		"Returning a drag to its starting position creates no history entry")
	session = TwberDocumentEditSession.new(document, "Cancelled")
	session.update(TwberEditMesh.remove_vertex("layer_001", 1))
	session.cancel()
	_expect(document.get_revision() == revision and session.commit() == ERR_BUSY,
		"A cancelled draft cannot be committed")
	session = TwberDocumentEditSession.new(document, "Stale")
	session.update(TwberEditMesh.remove_vertex("layer_001", 1))
	document.execute(TwberSetRestTransform.new("layer_001", Vector2(70, 20), 0.0, Vector2.ONE))
	_expect(session.commit() == ERR_BUSY and document.snapshot().to_model_resource().layers[0].mesh.vertices.size() == 3,
		"Stale gesture completion cannot overwrite a newer document edit")

	document.replace_model(_make_mesh_model())
	_expect(document.execute(TwberEditMesh.edge("layer_001", 0, 1, false)) == OK
		and document.snapshot().to_model_resource().layers[0].mesh.triangles.is_empty(),
		"Native cut applies topology constraints without scene nodes")
	revision = document.get_revision()
	document.execute(TwberEditMesh.edge("layer_001", 0, 1, false))
	_expect(document.get_revision() == revision, "Repeated cuts do not create duplicate history")
	document.execute(TwberEditMesh.edge("layer_001", 0, 1, true))
	_expect(document.snapshot().to_model_resource().layers[0].mesh.triangles.size() == 3,
		"Native join restores a drawable constrained triangle")
	document.execute(TwberEditMesh.add_vertex("layer_001", Vector2(40, 40)))
	document.execute(TwberEditMesh.remove_vertex("layer_001", 0))
	var edited := document.snapshot().to_model_resource()
	_expect(edited.layers[0].mesh.vertices[0] == Vector2(40, 0)
		and edited.parameters[0].positions[0].layer_states[0].mesh_vertices[0] == Vector2(45, 0)
		and edited.timeline_animations[0].keyframes[0].layer_state.mesh_vertices.size() == 3,
		"Vertex removal preserves corresponding pose indices")
	_expect(document.execute(TwberEditMesh.grid("layer_001", 3, 2, Rect2i(0, 0, 40, 40))) == OK,
		"Native grid generation is an atomic topology replacement")
	edited = document.snapshot().to_model_resource()
	_expect(edited.layers[0].mesh.vertices.size() == 6 and edited.layers[0].mesh.triangles.size() == 12
		and edited.timeline_animations[0].keyframes[0].layer_state.mesh_vertices == edited.layers[0].mesh.vertices,
		"Grid replacement consistently resets existing mesh poses")
	revision = document.get_revision()
	_expect(document.execute(TwberEditMesh.move_vertices("layer_001", {0: Vector2(NAN, 1)})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "Non-finite mesh edits are rejected atomically")


func _mesh_motion(mesher: EditorMesher, position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	mesher._handle_mouse_motion(event, position)


func _test_editor_mesh_gestures() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_make_mesh_model(), "")
	var mesher := editor._editor_mesher
	editor._menus.current_tab = mesher.get_index()
	var mesh := editor._model_root.get_child(0) as TwberMeshSprite2D
	mesher.reload_from_preview(mesh)
	var start := mesh.get_global_transform_with_canvas() * mesh.get_vertex(1)
	var revision := editor._document.get_revision()
	mesher._begin_vertex_drag(mesh, 1, start)
	_mesh_motion(mesher, start + Vector2(4, 0))
	_mesh_motion(mesher, start + Vector2(10, 0))
	_expect(mesh.get_vertex(1) == Vector2(50, 0) and editor._document.get_revision() == revision, "Editor drag previews through native commands without a legacy commit")
	_expect(editor.undo_document() and mesh.get_vertex(1) == Vector2(40, 0)
		and editor._document.get_revision() == revision and not editor.is_dirty(),
		"Undo during a mesh drag cancels only the draft")
	mesher._begin_vertex_drag(mesh, 1, start)
	_mesh_motion(mesher, start + Vector2(12, 0))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	mesher._input(release)
	_expect(editor._mesh_edit_session == null and editor._document.get_revision() == revision + 1
		and editor._document.get_undo_label() == "Move mesh vertices", "Release outside the overlay commits the gesture once")
	_expect(editor.undo_document() and not editor.is_dirty(), "Completed mesh drag is one Undo step")
	_expect(editor.redo_document(), "Editor can redo the completed mesh gesture")
	mesh = editor._model_root.get_child(0) as TwberMeshSprite2D
	start = mesh.get_global_transform_with_canvas() * mesh.get_vertex(1)
	mesher._begin_vertex_drag(mesh, 1, start)
	_mesh_motion(mesher, start + Vector2(20, 0))
	revision = editor._document.get_revision()
	_expect(await editor._write_autosave() == ERR_BUSY and editor._document.get_revision() == revision,
		"Autosave defers while a mesh gesture is unfinished")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._unhandled_key_input(escape)
	_expect(editor._mesh_edit_session == null and mesh.get_vertex(1) == Vector2(52, 0),
		"Escape restores the last committed mesh")
	mesher._begin_vertex_drag(mesh, 1, start)
	_mesh_motion(mesher, start + Vector2(7, 0))
	var path := "user://twber_mesh_gesture_save.twber"
	_expect(editor._save_model_to_path(path, true) == OK and editor._mesh_edit_session == null
		and not editor.is_dirty(), "Save closes a mesh gesture before capturing its document snapshot")
	var loaded := TwberModelCodec.load_model(path)
	_expect(loaded.layers[0].mesh.vertices[1] == Vector2(59, 0)
		and loaded.timeline_animations[0].keyframes[0].layer_state.mesh_vertices[1] == Vector2(64, 0),
		"Saving mid-gesture persists mesh and dependent keys together")
	start = mesh.get_global_transform_with_canvas() * mesh.get_vertex(1)
	mesher._begin_vertex_drag(mesh, 1, start)
	_mesh_motion(mesher, start + Vector2(9, 0))
	editor._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_expect(mesh.get_vertex(1) == Vector2(59, 0) and editor._mesh_edit_session == null,
		"Losing window focus cancels an unfinished mesh gesture")
	mesher._begin_vertex_drag(mesh, 1, start)
	_mesh_motion(mesher, start + Vector2(3, 0))
	editor._menus.current_tab = editor._editor_placer.get_index()
	_expect(editor._mesh_edit_session == null and editor._document.snapshot().to_model_resource().layers[0].mesh.vertices[1] == Vector2(62, 0),
		"Changing workspace finishes the active mesh gesture")
	editor._menus.current_tab = mesher.get_index()
	mesher.reload_from_preview(mesh)
	revision = editor._document.get_revision()
	mesher._start_gesture("Remove mesh vertices")
	mesher._remove_point_at(mesh.get_global_transform_with_canvas() * mesh.get_vertex(0))
	mesher._remove_point_at(mesh.get_global_transform_with_canvas() * mesh.get_vertex(0))
	_expect(editor._document.get_revision() == revision and mesh.get_vertex_count() == 1,
		"A remove stroke accumulates multiple vertex deletions in a draft")
	mesher._stop_pointer_actions()
	_expect(editor._document.get_revision() == revision + 1 and editor.undo_document(),
		"A remove stroke commits and undoes as one operation")
	_expect(editor._document.snapshot().to_model_resource().layers[0].mesh.vertices.size() == 3,
		"Undo restores all vertices removed by the stroke")
	editor._clear_recovery(true)
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_mesh_conversion_gesture() -> void:
	var model := _make_hierarchy_model()
	var layer := model.layers[0]
	layer.type = TwberLayerResource.LayerType.SPRITE
	layer.offset = Vector2(5, 3)
	layer.texture_id = "art"
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	model.textures["art"] = ImageTexture.create_from_image(image)
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(model, "")
	var mesher := editor._editor_mesher
	editor._menus.current_tab = mesher.get_index()
	var sprite := editor._model_root.get_child(0) as Sprite2D
	var child := sprite.get_child(0) as Node2D
	var child_world := child.global_transform
	mesher.reload_from_preview(sprite)
	mesher._add_point_at(sprite.get_global_transform_with_canvas() * Vector2(2, 4))
	var mesh := mesher._selected_node as TwberMeshSprite2D
	_expect(mesh != null and mesh.get_texture_origin() == Vector2(-3, -1)
		and mesh.mesh_data.uvs[0] == Vector2(5, 5) and child.get_parent() == mesh
		and child.global_transform.is_equal_approx(child_world),
		"Native sprite conversion preserves image origin, UVs, and child transforms")
	var revision := editor._document.get_revision()
	mesher._start_gesture("Remove mesh vertices")
	mesher._remove_point_at(mesh.get_global_transform_with_canvas() * mesh.get_vertex(0))
	_expect(mesher._selected_node is Sprite2D and editor._mesh_edit_session != null
		and editor._document.get_revision() == revision,
		"Removing the last vertex previews sprite conversion without prematurely committing")
	editor.undo_document()
	mesh = mesher._selected_node as TwberMeshSprite2D
	_expect(mesh != null and mesh.get_vertex_count() == 1 and child.get_parent() == mesh,
		"Cancelling last-vertex removal restores the mesh and its children")
	mesher._start_gesture("Remove mesh vertices")
	mesher._remove_point_at(mesh.get_global_transform_with_canvas() * mesh.get_vertex(0))
	mesher._stop_pointer_actions()
	var restored_sprite := mesher._selected_node as Sprite2D
	_expect(restored_sprite != null and restored_sprite.offset == Vector2(5, 3)
		and editor._document.get_revision() == revision + 1,
		"Last-vertex removal commits the original sprite placement as one operation")
	mesher._horizontal_vertices.value = 3
	mesher._vertical_vertices.value = 2
	mesher._on_generate_grid_button_pressed()
	mesh = mesher._selected_node as TwberMeshSprite2D
	_expect(mesh != null and mesh.get_vertex_count() == 6
		and editor._document.get_undo_label() == "Generate mesh grid",
		"Fast Mesh converts sprites through a native command")
	# Switching selection must close the old gesture before targeting another layer.
	var start := mesh.get_global_transform_with_canvas() * mesh.get_vertex(0)
	mesher._begin_vertex_drag(mesh, 0, start)
	_mesh_motion(mesher, start + Vector2(4, 0))
	mesher._select_node(child)
	_expect(editor._mesh_edit_session == null and mesher._selected_node == child,
		"Changing selected layers commits the previous layer's gesture")
	mesher._select_node(mesh)
	mesher._begin_vertex_drag(mesh, 0, mesh.get_global_transform_with_canvas() * mesh.get_vertex(0))
	_mesh_motion(mesher, start + Vector2(10, 0))
	editor._new_model()
	_expect(editor._mesh_edit_session == null and editor._document.snapshot().to_model_resource().layers.is_empty()
		and not editor.is_dirty(), "Document replacement discards any remaining mesh draft")
	editor.free()


func _move_in_placer(placer: EditorPlacer, layer: Node2D, delta: Vector2) -> void:
	var start := layer.get_global_transform_with_canvas().origin
	placer.call("_begin_transform_drag", start, EditorPlacer.TransformMode.MOVE)
	placer.call("_update_transform_drag", start + delta)
	placer.call("_finish_transform_drag")


func _make_model() -> TwberModelResource:
	var model := TwberModelResource.new()
	var layer := TwberLayerResource.new()
	layer.id = "layer_001"
	layer.name = "Head"
	layer.position = Vector2(10, 20)
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)
	return model


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_parameter_commands() -> void:
	var document := TwberModelDocument.new()
	var model := _make_mesh_model()
	document.replace_model(model)
	var created: Array[String] = []
	for type: int in [TwberParameterResource.ValueType.BOOL, TwberParameterResource.ValueType.INT, TwberParameterResource.ValueType.FLOAT, TwberParameterResource.ValueType.VECTOR2]:
		var command := TwberEditParameter.new(TwberEditParameter.Operation.CREATE, "", {"value_type": type})
		_expect(document.execute(command) == OK, "Every parameter type can be created without scene nodes")
		created.append(command.parameter_id)
	var id := created[2]
	var edited := TwberLayerStateResource.from_layer_resource(model.layers[0])
	# The existing parameter contributes +20 position and +5 mesh at this input.
	edited.position = Vector2(37, 20)
	edited.mesh_vertices[1] += Vector2(8, 0)
	var bind := TwberEditParameter.new(TwberEditParameter.Operation.BIND_POSE, id, {
		"coordinate": Vector2(0.5, 99), "pose": edited, "values": {"move": 1.0},
	})
	edited.position = Vector2(999, 999)
	_expect(document.execute(bind) == OK, "Binding accepts an isolated input pose")
	var captured := document.snapshot().to_model_resource()
	var sample := TwberEditParameter.find(captured, id).positions[0]
	var pose := sample.layer_states[0]
	_expect(sample.coordinate == Vector2(0.5, 0) and pose.position == Vector2(17, 20)
		and pose.mesh_vertices[1] == Vector2(43, 0)
		and pose.channels == (TwberLayerStateResource.Channel.POSITION | TwberLayerStateResource.Channel.MESH),
		"Binding subtracts other parameters, owns its input copy, and retains sparse channels")
	_expect(captured.layers[0].position == Vector2(10, 20)
		and captured.layers[0].mesh.vertices[1] == Vector2(40, 0), "Binding cannot change rest geometry")
	var revision := document.get_revision()
	_expect(document.execute(bind) == OK and document.get_revision() == revision, "Repeated Bind creates no extra Undo step")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, id, {"max_value": 0.4})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "A range cannot displace an existing pose")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, id, {"step": 0.3})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "A step change cannot move authored coordinates")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, id, {"max_value": INF})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "Invalid settings publish no partial edit")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, id, {"name": "  Smile  ", "default_float": 20.0})) == OK,
		"Parameter settings can update names and defaults")
	captured = document.snapshot().to_model_resource()
	_expect(TwberEditParameter.find(captured, id).name == "Smile" and TwberEditParameter.find(captured, id).default_float == 1.0,
		"Names are trimmed and defaults stay in range")
	var trigger_id := created[1]
	var trigger := TwberEditParameter.new(TwberEditParameter.Operation.BIND_ANIMATION, trigger_id, {"animation_id": "move_clip", "coordinate": Vector2(8, 0)})
	_expect(document.execute(trigger) == OK, "Integer parameters can trigger authored clips")
	revision = document.get_revision()
	_expect(document.execute(trigger) == OK and document.get_revision() == revision, "Duplicate triggers are a no-op")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, trigger_id, {"max_value": 7.0})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "Range validation protects animation triggers too")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.BIND_ANIMATION, id, {"animation_id": "move_clip"})) == ERR_INVALID_PARAMETER,
		"Continuous parameters cannot acquire discrete animation triggers")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.DELETE, trigger_id)) == OK,
		"A parameter and its triggers are deleted in one command")
	_expect(document.undo() and TwberEditParameter.find(document.snapshot().to_model_resource(), trigger_id).animation_bindings.size() == 1,
		"Undo restores a deleted parameter's triggers")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.REMOVE_ANIMATION, trigger_id, {"animation_id": "move_clip", "coordinate": Vector2(8, 0)})) == OK,
		"Animation triggers can be removed independently of their clips")
	_expect(document.snapshot().to_model_resource().timeline_animations.size() == 1, "Removing triggers keeps the authored clip")
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.REMOVE_POSE, id, {"layer_id": "layer_001", "coordinate": Vector2(0.5, 0)})) == OK,
		"Bound poses can be removed by stable layer ID")
	_expect(TwberEditParameter.find(document.snapshot().to_model_resource(), id).positions.is_empty(), "Removing a final pose prunes its empty sample")
	_expect(document.undo() and TwberEditParameter.find(document.snapshot().to_model_resource(), id).positions.size() == 1,
		"Undo restores the removed pose")
	# Sampling must reproduce the displayed pixel-snapped contribution.
	model.parameters[0].positions[0].layer_states[0].position = Vector2(30.4, 20.2)
	document.replace_model(model)
	var create := TwberEditParameter.new(TwberEditParameter.Operation.CREATE, "", {"value_type": TwberParameterResource.ValueType.FLOAT})
	document.execute(create)
	edited = TwberLayerStateResource.from_layer_resource(model.layers[0])
	edited.position = Vector2(37, 20)
	edited.mesh_vertices[1] += Vector2(5, 0)
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.BIND_POSE, create.parameter_id, {
		"pose": edited, "values": {"move": 1.0}, "snap": {"pixels": true},
	})) == OK, "Binding can reproduce preview snapping from document data")
	pose = TwberEditParameter.find(document.snapshot().to_model_resource(), create.parameter_id).positions[0].layer_states[0]
	_expect(pose.position == Vector2(17, 20) and pose.channels == TwberLayerStateResource.Channel.POSITION,
		"Snapped contributions are isolated without accidentally binding mesh channels")
	revision = document.get_revision()
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.BIND_POSE, create.parameter_id, {
		"pose": edited, "values": {"move": NAN},
	})) == ERR_INVALID_PARAMETER and document.get_revision() == revision, "Nonfinite preview input is rejected atomically")
	var parameter := model.parameters[0]
	parameter.max_value = 0.1
	parameter.positions[0].coordinate = Vector2(0.1, 0)
	var second := parameter.positions[0].duplicate(true) as TwberParameterPositionResource
	second.coordinate = Vector2.ZERO
	parameter.positions.append(second)
	document.replace_model(model)
	revision = document.get_revision()
	_expect(document.execute(TwberEditParameter.new(TwberEditParameter.Operation.UPDATE, parameter.id, {"step": 1.0})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "A larger step cannot merge distinct range endpoint samples")


func _test_editor_native_parameters() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_make_rigged_model(), "")
	var rig := editor._editor_rigger
	var document := editor._document
	editor._menus.current_tab = rig.get_index()
	var node := editor._model_root.get_child(0) as Node2D
	rig._select_node(node)
	rig._on_parameter_value_changed(rig._get_model_parameters()[0], 1.0)
	var revision := document.get_revision()
	rig._on_create_parameter_pressed(TwberParameterResource.ValueType.FLOAT)
	var parameter := rig._get_selected_parameter()
	var id := parameter.id
	_expect(document.get_revision() == revision + 1
		and document.get_undo_label() == "Create parameter", "Rig creation commits directly through native history")
	rig._on_parameter_value_changed(parameter, 1.0)
	rig.edit_pose({"position": node.position + Vector2(7, 0)})
	rig._on_bind_position_button_pressed()
	_expect(node.position == Vector2(37, 20),
		"Native Bind leaves the composed pose displayed without a legacy capture")
	_expect(editor.undo_document(), "Native pose binding supports Undo")
	node = editor._model_root.get_child(0) as Node2D
	_expect(node.position == Vector2(30, 20) and rig._selected_parameter_id == id
		and rig._parameter_preview_values[id] == 1.0, "Undo retains rig selection and preview inputs")
	_expect(editor.redo_document(), "Native pose binding supports Redo")
	node = editor._model_root.get_child(0) as Node2D
	parameter = rig._get_selected_parameter()
	var min_edit := SpinBox.new()
	var max_edit := SpinBox.new()
	rig._on_scalar_range_changed(parameter, false, 2.0, min_edit, max_edit)
	_expect(rig._get_selected_parameter() == parameter and parameter.max_value == 2.0
		and document.get_undo_label() == "Change parameter settings", "Range editing preserves focused parameter projection identity")
	min_edit.free()
	max_edit.free()
	# Name typing is a draft; Enter, save, or tab departure commits it once.
	# Select the name field by its parameter card, since several cards exist.
	var card := rig._parameter_list.get_node("ParameterCard_" + id)
	var name_edit := _find_line_edit(card)
	revision = document.get_revision()
	name_edit.text = "S"
	name_edit.text_changed.emit(name_edit.text)
	name_edit.text = "Smile"
	name_edit.text_changed.emit(name_edit.text)
	rig.edit_pose({"position": node.position + Vector2(9, 0)}) # An unbound pose must survive a metadata rename.
	_expect(document.get_revision() == revision, "Typing a name does not create per-keystroke history")
	name_edit.text_submitted.emit(name_edit.text)
	_expect(document.get_revision() == revision + 1 and parameter.name == "Smile"
		and node.position == Vector2(46, 20), "Enter commits one rename without discarding an unbound pose")
	name_edit.focus_exited.emit()
	_expect(document.get_revision() == revision + 1, "Focus loss after Enter does not duplicate a rename")
	name_edit.text = "Saved smile"
	name_edit.text_changed.emit(name_edit.text)
	var path := "user://twber_native_rig_test.twber"
	_expect(await editor._save_model_to_path_async(path, true) == OK, "Background save finishes an active parameter name edit")
	var saved := TwberModelCodec.load_model(path)
	_expect(TwberEditParameter.find(saved, id).name == "Saved smile" and saved.layers[0].position == Vector2(10, 20)
		and TwberEditParameter.find(saved, id).positions[0].layer_states[0].position == Vector2(17, 20),
		"Saving stores the committed name and bound pose, excluding the unbound preview")
	rig._delete_parameter(id)
	_expect(document.get_undo_label() == "Delete parameter", "Parameter deletion has its own native history entry")
	_expect(editor.undo_document() and TwberEditParameter.find(document.snapshot().to_model_resource(), id).positions.size() == 1,
		"Editor Undo restores a parameter together with its poses")
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _find_line_edit(node: Node) -> LineEdit:
	if node is LineEdit:
		return node as LineEdit
	for child: Node in node.get_children():
		var result := _find_line_edit(child)
		if result != null:
			return result
	return null


func _make_triggered_timeline_model() -> TwberModelResource:
	var model := _make_mesh_model()
	var parameter := TwberParameterResource.new()
	parameter.id = "play"
	parameter.value_type = TwberParameterResource.ValueType.BOOL
	parameter.step = 1.0
	var binding := TwberAnimationBindingResource.new()
	binding.animation_id = "move_clip"
	binding.coordinate = Vector2(1, 0)
	parameter.animation_bindings.append(binding)
	model.parameters.append(parameter)
	return model


func _test_timeline_commands() -> void:
	var document := TwberModelDocument.new()
	var model := _make_triggered_timeline_model()
	document.replace_model(model)
	var create := TwberEditTimeline.new(TwberEditTimeline.Operation.CREATE)
	_expect(document.execute(create) == OK and not create.animation_id.is_empty(), "Timeline creation runs without scene nodes")
	var next := TwberEditTimeline.new(TwberEditTimeline.Operation.CREATE)
	document.execute(next)
	_expect(next.animation_id != create.animation_id, "Created clips receive independent stable IDs")
	var id := create.animation_id
	var pose := TwberLayerStateResource.from_layer_resource(model.layers[0])
	pose.channels = TwberLayerStateResource.Channel.COLOR
	pose.self_modulate = Color.RED
	var key := TwberEditTimeline.new(TwberEditTimeline.Operation.SET_KEY, id, {"time": 0.5, "pose": pose})
	pose.self_modulate = Color.BLUE
	_expect(document.execute(key) == OK, "Timeline keys accept detached pose inputs")
	var captured := document.snapshot().to_model_resource()
	var animation := TwberEditTimeline.find(captured, id)
	_expect(animation.keyframes[0].layer_state.self_modulate == Color.RED
		and animation.keyframes[0].layer_state.channels == TwberLayerStateResource.Channel.COLOR,
		"Timeline commands preserve sparse channel ownership and isolate caller mutations")
	var revision := document.get_revision()
	_expect(document.execute(key) == OK and document.get_revision() == revision, "Recording the same key twice creates no history step")
	_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, id, {"name": "Wrong", "duration": 0.25})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision and TwberEditTimeline.find(document.snapshot().to_model_resource(), id).name != "Wrong",
		"Shortening across authored keys rejects the entire settings edit")
	for invalid_time: float in [-1.0, INF, NAN, 2.0]:
		_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.SET_KEY, id, {"time": invalid_time, "pose": pose})) == ERR_INVALID_PARAMETER
			and document.get_revision() == revision, "Invalid key times cannot enter history")
	for invalid_fps: float in [0.0, -1.0, INF, NAN]:
		_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, id, {"fps": invalid_fps})) == ERR_INVALID_PARAMETER
			and document.get_revision() == revision, "Invalid frame rates cannot enter history")
	var broken := pose.duplicate(true) as TwberLayerStateResource
	broken.channels = TwberLayerStateResource.Channel.MESH
	broken.mesh_vertices = PackedVector2Array([Vector2.ZERO])
	_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.SET_KEY, id, {"time": 0.2, "pose": broken})) == ERR_INVALID_DATA
		and document.get_revision() == revision, "Keys with incompatible mesh topology are rejected atomically")
	_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.SET_KEY, id, {"time": 0.51, "pose": pose})) == OK,
		"Recording within half a frame replaces the nearby key")
	animation = TwberEditTimeline.find(document.snapshot().to_model_resource(), id)
	_expect(animation.keyframes.size() == 1 and animation.keyframes[0].time == 0.51
		and animation.keyframes[0].layer_state.self_modulate == Color.BLUE, "Near-key replacement stores the requested pose and time")
	_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, id, {"name": "  Wink  ", "duration": 2.0, "fps": 60.0, "loop": false})) == OK,
		"Timeline metadata updates through a single command")
	animation = TwberEditTimeline.find(document.snapshot().to_model_resource(), id)
	_expect(animation.name == "Wink" and animation.duration == 2.0 and animation.fps == 60.0
		and not animation.loop and animation.keyframes[0].time == 0.51, "FPS and duration changes do not retime keys")
	_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.REMOVE_KEY, id, {"time": 0.51, "layer_id": "layer_001"})) == OK,
		"Key removal uses a stable clip and layer target")
	revision = document.get_revision()
	_expect(document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.REMOVE_KEY, id, {"time": 0.51, "layer_id": "layer_001"})) == OK
		and document.get_revision() == revision, "Removing an absent key is a no-op")
	_expect(document.undo() and TwberEditTimeline.find(document.snapshot().to_model_resource(), id).keyframes.size() == 1,
		"One Undo restores the removed key")
	var delete := TwberEditTimeline.new(TwberEditTimeline.Operation.DELETE, "move_clip")
	_expect(document.execute(delete) == OK and (delete.kinds & TwberDocumentChange.Kind.RIG) != 0,
		"Deleting a triggered clip publishes both animation and rig changes")
	captured = document.snapshot().to_model_resource()
	_expect(TwberEditParameter.find(captured, "play").animation_bindings.is_empty()
		and captured.parameters[0].positions.size() == 1 and TwberEditTimeline.find(captured, id) != null,
		"Clip deletion removes only its triggers, preserving poses and other clips")
	_expect(document.undo(), "Clip deletion is one reversible transaction")
	captured = document.snapshot().to_model_resource()
	_expect(TwberEditParameter.find(captured, "play").animation_bindings.size() == 1
		and TwberEditTimeline.find(captured, "move_clip").keyframes.size() == 1,
		"Undo restores a clip's keys and parameter triggers together")
	# At low FPS, legacy keys can share a frame: choose nearest, then earlier.
	animation = TwberTimelineAnimationResource.new()
	animation.fps = 1.0
	for time: float in [0.5, 0.0]:
		var item := TwberTimelineKeyframeResource.new()
		item.time = time
		item.layer_state = pose.duplicate(true)
		animation.keyframes.append(item)
	_expect(TwberEditTimeline.find_key(animation, "layer_001", 0.25) == 1
		and TwberEditTimeline.find_key(animation, "layer_001", 0.4) == 0,
		"Nearest-key targeting is deterministic for overlapping frame tolerances")


func _test_editor_native_timeline() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_make_triggered_timeline_model(), "")
	var animator := editor._editor_animator
	var document := editor._document
	editor._menus.current_tab = animator.get_index()
	var node := editor._model_root.get_child(0) as Node2D
	animator._select_node(node)
	animator._playhead = 0.5
	animator._apply_animation_at_playhead()
	animator.edit_pose({"position": Vector2(25, 20)})
	var revision := document.get_revision()
	animator._add_point()
	_expect(document.get_revision() == revision + 1 and document.get_undo_label() == "Set animation key", "Adding a point goes directly into native history")
	var model := document.snapshot().to_model_resource()
	_expect(model.layers[0].position == Vector2(10, 20) and model.timeline_animations[0].keyframes.size() == 2,
		"Recording a displayed pose leaves document rest geometry untouched")
	animator._add_point()
	_expect(document.get_revision() == revision + 1, "Repeated editor recording is a no-op")
	_expect(editor.undo_document(), "Editor Undo reverses key insertion")
	node = editor._model_root.get_child(0) as Node2D
	_expect(animator._playhead == 0.5 and animator._selected_animation_id == "move_clip"
		and node.position == Vector2(15, 20), "Key Undo preserves timeline selection and playhead")
	_expect(editor.redo_document(), "Editor Redo restores the key")
	node = editor._model_root.get_child(0) as Node2D
	var projected := animator._get_selected_animation()
	revision = document.get_revision()
	animator._change_duration(0.25)
	_expect(document.get_revision() == revision and animator._duration_spin_box.value == 1.0
		and node.position == Vector2(25, 20), "Rejected duration restores the control without altering keys or preview")
	animator._change_fps(60.0)
	_expect(animator._get_selected_animation() == projected and projected.fps == 60.0,
		"Timeline projection preserves surviving clip resource identity")
	revision = document.get_revision()
	animator._name_edit.text = "W"
	animator._name_edit.text_changed.emit("W")
	animator._name_edit.text = "Wave"
	animator._name_edit.text_changed.emit("Wave")
	animator.edit_pose({"position": node.position + Vector2(9, 0)})
	_expect(document.get_revision() == revision, "Animation name typing creates no per-character history")
	animator._name_edit.text_submitted.emit("Wave")
	animator._name_edit.focus_exited.emit()
	_expect(document.get_revision() == revision + 1 and projected.name == "Wave" and node.position == Vector2(34, 20),
		"A name commits once and preserves an unrecorded pose")
	animator._name_edit.text = "Saved wave"
	animator._name_edit.text_changed.emit("Saved wave")
	var path := "user://twber_native_timeline.twber"
	_expect(await editor._save_model_to_path_async(path, true) == OK, "Background save finishes an active animation name edit")
	model = TwberModelCodec.load_model(path)
	_expect(model.timeline_animations[0].name == "Saved wave" and model.layers[0].position == Vector2(10, 20)
		and model.timeline_animations[0].keyframes[1].layer_state.position == Vector2(25, 20),
		"Archive includes authored metadata and keys, excluding unrecorded poses")
	revision = document.get_revision()
	animator._toggle_playback()
	animator._process(0.1)
	animator._toggle_playback()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(20, 0)
	animator._on_timeline_gui_input(event)
	_expect(document.get_revision() == revision and not editor.is_dirty(), "Playback and timeline scrubbing never dirty the document")
	animator._delete_animation()
	_expect(document.get_undo_label() == "Delete animation"
		and editor._editor_rigger._find_parameter_by_id("play").animation_bindings.is_empty(),
		"Clip deletion updates projected parameter triggers in the same transaction")
	_expect(editor.undo_document(), "Editor Undo restores deleted timeline data")
	_expect(editor._editor_rigger._find_parameter_by_id("play").animation_bindings.size() == 1
		and animator._get_selected_animation().keyframes.size() == 2, "Clip deletion Undo restores keys and triggers in both projections")
	animator._create_animation()
	var new_id := animator._selected_animation_id
	animator._name_edit.text = "Idle"
	animator._name_edit.text_changed.emit("Idle")
	editor._menus.current_tab = editor._editor_placer.get_index()
	_expect(TwberEditTimeline.find(document.snapshot().to_model_resource(), new_id).name == "Idle"
		and document.get_undo_label() == "Change animation settings", "Leaving Animate finishes its pending name edit")
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_native_pivot_and_mirror() -> void:
	var model := _make_mesh_model()
	var layer := model.layers[0]
	layer.rotation = 0.3
	layer.scale = Vector2(2, 1)
	layer.mesh.ensure_rest_vertices()
	var child := TwberLayerResource.new()
	child.id = "child"
	child.position = Vector2(3, 7)
	layer.children.append(child.id)
	model.layers.append(child)
	var parameter := model.parameters[0]
	parameter.value_type = TwberParameterResource.ValueType.INT
	parameter.step = 1.0
	var sample := parameter.positions[0].layer_states[0]
	sample.channels = TwberLayerStateResource.Channel.ROTATION | TwberLayerStateResource.Channel.MESH
	sample.rotation = 0.8
	var key := model.timeline_animations[0].keyframes[0].layer_state
	key.channels = TwberLayerStateResource.Channel.SCALE | TwberLayerStateResource.Channel.MESH
	key.scale = Vector2(1.5, 0.8)
	var binding := TwberAnimationBindingResource.new()
	binding.animation_id = "move_clip"
	binding.coordinate = Vector2(1, 0)
	parameter.animation_bindings.append(binding)
	var document := TwberModelDocument.new()
	document.replace_model(model)
	var pivot := Vector2(5, 4)
	_expect(document.execute(TwberSetPivot.new(layer.id, pivot)) == OK, "One pivot command handles rest, rig, timeline and children")
	var changed := document.snapshot().to_model_resource()
	var moved := changed.layers[0]
	var before_rest := TwberLayerStateResource.from_layer_resource(layer)
	var after_rest := TwberLayerStateResource.from_layer_resource(moved)
	_expect(_pose_point(before_rest, layer.mesh.vertices[1]).is_equal_approx(_pose_point(after_rest, moved.mesh.vertices[1]))
		and _pose_point(before_rest, child.position).is_equal_approx(_pose_point(after_rest, changed.layers[1].position)),
		"Pivot preserves rest artwork and direct-child world placement with nonuniform scale")
	var moved_sample := changed.parameters[0].positions[0].layer_states[0]
	var moved_key := changed.timeline_animations[0].keyframes[0].layer_state
	_expect(moved_sample.has_channel(TwberLayerStateResource.Channel.POSITION)
		and moved_key.has_channel(TwberLayerStateResource.Channel.POSITION),
		"Rotation-only and scale-only samples gain the positional correction they need")
	_expect(_pose_point(sample.materialized(before_rest), sample.mesh_vertices[1]).is_equal_approx(
		_pose_point(moved_sample.materialized(after_rest), moved_sample.mesh_vertices[1]))
		and _pose_point(key.materialized(before_rest), key.mesh_vertices[1]).is_equal_approx(
		_pose_point(moved_key.materialized(after_rest), moved_key.mesh_vertices[1])),
		"Pivot preserves both rig sample and timeline key artwork endpoints")
	_expect(moved.mesh.uvs == layer.mesh.uvs and moved.mesh.rest_vertices[1] == layer.mesh.rest_vertices[1] - pivot,
		"Pivot shifts mesh rest coordinates without changing UVs")
	var revision := document.get_revision()
	_expect(document.execute(TwberSetPivot.new(layer.id, Vector2.ZERO)) == OK and document.get_revision() == revision,
		"A zero pivot offset creates no history")
	_expect(document.execute(TwberSetPivot.new(layer.id, Vector2(INF, 0))) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision, "Nonfinite pivots fail without partial edits")
	_expect(document.undo() and document.snapshot().to_model_resource().layers[0].mesh.vertices == layer.mesh.vertices,
		"One Undo restores pivot geometry and dependent states")
	var mirror := TwberMirrorLayers.new([layer.id, child.id], {"geometry_x": true, "bindings_x": true, "new_parameter": true})
	_expect(document.execute(mirror) == OK and mirror.duplicated_root_ids.size() == 1,
		"Mirror filters overlapping parent/child selections and allocates one subtree")
	changed = document.snapshot().to_model_resource()
	var layers := TwberLayerHierarchy.index(changed)
	var copy: TwberLayerResource = layers[mirror.id_mapping[layer.id]]
	var copied_child: TwberLayerResource = layers[mirror.id_mapping[child.id]]
	_expect(copy.position == Vector2(-layer.position.x, layer.position.y)
		and copy.mesh.vertices[1] == Vector2(-layer.mesh.vertices[1].x, layer.mesh.vertices[1].y)
		and copy.mesh.uvs == layer.mesh.uvs and copied_child.position == Vector2(-3, 7),
		"Mirror reflects nested mesh coordinates while preserving UVs")
	_expect(changed.timeline_animations[0].keyframes.size() == 2
		and changed.timeline_animations[0].keyframes[1].layer_state.layer_id == copy.id
		and changed.timeline_animations[0].keyframes[1].layer_state.mesh_vertices[1] == Vector2(-key.mesh_vertices[1].x, key.mesh_vertices[1].y),
		"Mirror copies and reflects timeline keys to stable duplicated layer IDs")
	var mirrored_parameter := changed.parameters[-1]
	_expect(changed.parameters.size() == 2 and mirrored_parameter.id != parameter.id
		and mirrored_parameter.positions[0].coordinate == Vector2.ZERO
		and mirrored_parameter.positions[0].layer_states[0].layer_id == copy.id
		and mirrored_parameter.default_int == 1 and mirrored_parameter.animation_bindings[0].coordinate == Vector2.ZERO,
		"Separate mirrored parameters reverse samples, defaults and discrete trigger inputs together")
	_expect(changed.parameters[0].positions[0].layer_states.size() == 1
		and changed.parameters[0].positions[0].coordinate == Vector2(1, 0), "Mirror leaves source rig data untouched")
	_expect(document.undo() and document.snapshot().to_model_resource().layers.size() == 2
		and document.snapshot().to_model_resource().timeline_animations[0].keyframes.size() == 1,
		"Mirror Undo removes the subtree and all copied authoring data")
	_expect(document.redo() and TwberLayerHierarchy.index(document.snapshot().to_model_resource()).has(copy.id),
		"Mirror Redo retains allocated identities")


func _pose_point(state: TwberLayerStateResource, point: Vector2) -> Vector2:
	return state.position + (point * state.scale).rotated(state.rotation)


func _make_sprite_animation_model() -> TwberModelResource:
	var model := _make_rigged_model()
	var layer := model.layers[0]
	layer.type = TwberLayerResource.LayerType.ANIMATED_SPRITE
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	model.textures["base"] = ImageTexture.create_from_image(image)
	var animation := TwberAnimationResource.new()
	animation.name = "Idle"
	animation.frame_texture_ids = ["base"]
	animation.frame_durations = [1.0]
	layer.current_animation = "Idle"
	layer.animations.append(animation)
	var other := animation.duplicate(true) as TwberAnimationResource
	other.name = "Talk"
	layer.animations.append(other)
	for state: TwberLayerStateResource in TwberSetRestTransform.collect_states(model.parameters, model.timeline_animations, layer.id):
		state.channels |= TwberLayerStateResource.Channel.ANIMATION
		state.animation_name = "Idle"
	return model


func _test_layer_settings_and_assets() -> void:
	var document := TwberModelDocument.new()
	var model := _make_sprite_animation_model()
	document.replace_model(model)
	var settings := TwberEditLayer.new("layer_001", TwberEditLayer.Operation.SETTINGS, {
		"name": "Face", "visible": false, "opacity": 0.4, "clip_children": CanvasItem.CLIP_CHILDREN_ONLY, "show_behind_parent": true,
	})
	_expect(document.execute(settings) == OK, "Inspector settings execute against document data")
	var layer := document.snapshot().to_model_resource().layers[0]
	_expect(layer.name == "Face" and not layer.visible and is_equal_approx(layer.modulate.a, 0.4)
		and layer.clip_children == CanvasItem.CLIP_CHILDREN_ONLY and layer.show_behind_parent, "Inspector command stores authored render properties")
	var revision := document.get_revision()
	_expect(document.execute(settings) == OK and document.get_revision() == revision, "Repeated settings create no extra Undo step")
	_expect(document.execute(TwberEditLayer.new("layer_001", TwberEditLayer.Operation.SETTINGS, {"name": "Wrong", "opacity": NAN})) == ERR_INVALID_PARAMETER
		and document.get_revision() == revision and document.snapshot().to_model_resource().layers[0].name == "Face",
		"Invalid settings publish no partial changes")
	_expect(document.execute(TwberEditLayer.new("layer_001", TwberEditLayer.Operation.RENAME_ANIMATION, {"animation": "Idle", "name": "Blink"})) == OK,
		"Sprite animation renaming is a native operation")
	var changed := document.snapshot().to_model_resource()
	_expect(changed.layers[0].current_animation == "Blink"
		and changed.parameters[0].positions[0].layer_states[0].animation_name == "Blink"
		and changed.timeline_animations[0].keyframes[0].layer_state.animation_name == "Blink",
		"Sprite animation rename updates parameter and timeline references")
	_expect(document.execute(TwberEditLayer.new("layer_001", TwberEditLayer.Operation.DELETE_ANIMATION, {"animation": "Blink"})) == OK,
		"Deleting a sprite animation uses a valid remaining fallback")
	changed = document.snapshot().to_model_resource()
	_expect(changed.layers[0].current_animation == "Talk"
		and changed.parameters[0].positions[0].layer_states[0].animation_name == "Talk"
		and changed.timeline_animations[0].keyframes[0].layer_state.animation_name == "Talk", "Deleting sprite animations leaves no dangling pose references")
	_expect(document.execute(TwberEditLayer.new("layer_001", TwberEditLayer.Operation.DELETE_ANIMATION)) == ERR_INVALID_PARAMETER,
		"The final sprite animation cannot be deleted")
	_expect(document.undo() and document.snapshot().to_model_resource().parameters[0].positions[0].layer_states[0].animation_name == "Blink",
		"Sprite deletion Undo restores dependent references")
	_expect(document.execute(TwberEditLayer.new("layer_001", TwberEditLayer.Operation.CREATE_ANIMATION, {"name": "Talk"})) == OK,
		"Creating a sprite animation copies the active frames under a unique name")
	changed = document.snapshot().to_model_resource()
	_expect(changed.layers[0].current_animation == "Talk 2" and changed.layers[0].animations[-1].frame_texture_ids == ["base"],
		"New sprite animation keeps its frame assets")
	var replacement := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	replacement.fill(Color.RED)
	var texture := ImageTexture.create_from_image(replacement)
	_expect(document.execute(TwberEditLayer.new("layer_001", TwberEditLayer.Operation.REPLACE_FRAMES, {}, [texture, texture])) == OK,
		"Frame replacement imports assets within the document transaction")
	changed = document.snapshot().to_model_resource()
	_expect(changed.layers[0].animations[-1].frame_texture_ids.size() == 2
		and changed.textures[changed.layers[0].animations[-1].frame_texture_ids[0]].get_size() == Vector2(32, 16),
		"Replacement frame IDs resolve to the imported payload")
	document.replace_model(_make_mesh_model())
	var before := document.snapshot().to_model_resource()
	_expect(document.execute(TwberEditLayer.new("layer_001", TwberEditLayer.Operation.REPLACE_TEXTURE, {}, [texture])) == OK,
		"Mesh texture replacement preserves authored deformation topology")
	changed = document.snapshot().to_model_resource()
	_expect(changed.layers[0].mesh.vertices == before.layers[0].mesh.vertices
		and changed.parameters[0].positions[0].layer_states[0].mesh_vertices == before.parameters[0].positions[0].layer_states[0].mesh_vertices
		and changed.layers[0].mesh.uvs[1] == changed.layers[0].mesh.vertices[1] - changed.layers[0].mesh.texture_origin,
		"Mesh replacement updates UVs without overwriting rest or posed vertices")


func _test_editor_native_layer_edits() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_make_sprite_animation_model(), "")
	var placer := editor._editor_placer
	var rig := editor._editor_rigger
	var animator := editor._editor_animator
	var document := editor._document
	editor._menus.current_tab = placer.get_index()
	placer.select_document_layer("layer_001")
	var node := editor._model_root.get_child(0) as AnimatedSprite2D
	var revision := document.get_revision()
	placer._on_opacity_slider_value_changed(0.4)
	placer._on_opacity_slider_value_changed(0.4)
	_expect(document.get_revision() == revision + 1 and document.get_undo_label() == "Change layer settings"
		and editor._model_root.get_child(0) == node, "Place settings commit once and preserve node identity")
	placer._rename_animation_on_sprite(node, &"Idle", "Blink")
	_expect(node.sprite_frames.has_animation("Blink")
		and rig._get_model_parameters()[0].positions[0].layer_states[0].animation_name == "Blink"
		and animator._get_animations()[0].keyframes[0].layer_state.animation_name == "Blink",
		"Sprite rename projects frame assets and dependent rig/timeline references")
	var path := "user://twber_native_layers.twber"
	_expect(editor._save_model_to_path(path, true) == OK, "Native layer properties and assets save")
	var saved := TwberModelCodec.load_model(path)
	_expect(saved.layers[0].current_animation == "Blink" and is_equal_approx(saved.layers[0].modulate.a, 0.4)
		and saved.timeline_animations[0].keyframes[0].layer_state.animation_name == "Blink", "Archive round trip preserves dependent animation names and opacity")
	# Every workspace uses the same pivot command and keeps authored endpoints fixed.
	var origin := node.position + node.offset
	placer._change_selected_pivot(node.get_global_transform_with_canvas() * Vector2(4, 2))
	_expect(document.get_undo_label() == "Change layer pivot" and (node.position + node.offset).is_equal_approx(origin),
		"Place pivot preserves artwork with one native transaction")
	editor._menus.current_tab = rig.get_index()
	rig._select_node(node)
	rig._on_parameter_value_changed(rig._get_model_parameters()[0], 1.0)
	origin = node.position + node.offset
	var input := rig._parameter_preview_values.duplicate()
	rig._change_node_pivot(node, node.get_global_transform_with_canvas() * Vector2(3, 1))
	_expect((node.position + node.offset).is_equal_approx(origin) and rig._parameter_preview_values == input
		and document.get_undo_label() == "Change layer pivot", "Rig pivot retains preview inputs and authored pose placement")
	editor._menus.current_tab = animator.get_index()
	animator._select_node(node)
	animator._playhead = 0.0
	animator._apply_animation_at_playhead()
	origin = node.position + node.offset
	animator._change_node_pivot(node.get_global_transform_with_canvas() * Vector2(2, 3))
	_expect((node.position + node.offset).is_equal_approx(origin) and document.get_undo_label() == "Change layer pivot",
		"Animate pivot rebases its displayed key through the shared command")
	var after_pivot := document.snapshot().to_model_resource()
	_expect(editor.undo_document() and editor.redo_document(), "Pivot edits support editor Undo/Redo")
	_expect(document.snapshot().to_model_resource().layers[0].position == after_pivot.layers[0].position,
		"Pivot Redo restores the same rest origin")
	editor._menus.current_tab = placer.get_index()
	placer.select_document_layer("layer_001")
	var selection := placer._selected_layer_id
	revision = document.get_revision()
	placer._mirror_layers({"geometry_x": true}, [selection])
	var mirrored_id := placer.get_selected_document_layer_id()
	_expect(document.get_revision() == revision + 1 and document.get_undo_label() == "Mirror layers"
		and document.snapshot().to_model_resource().timeline_animations[0].keyframes.size() == 2,
		"Mirror commits geometry and timeline copies as one editor action")
	await process_frame
	_expect(document.get_revision() == revision + 1, "No deferred scene capture follows native layer edits")
	_expect(editor.undo_document() and not TwberLayerHierarchy.index(document.snapshot().to_model_resource()).has(mirrored_id),
		"Mirror Undo removes exactly the newly authored subtree")
	# A save cannot turn arbitrary mutations of render nodes into authoring data.
	node = editor._model_root.get_child(0) as AnimatedSprite2D
	node.position = Vector2(999, 999)
	node.self_modulate = Color.BLACK
	_expect(editor._save_model_to_path(path, true) == OK, "Save remains available after preview-only mutations")
	saved = TwberModelCodec.load_model(path)
	_expect(saved.layers[0].position == after_pivot.layers[0].position
		and is_equal_approx(saved.layers[0].modulate.a, 0.4), "Save uses committed layer data rather than recapturing render nodes")
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_pose_edit_sessions() -> void:
	var document := TwberModelDocument.new()
	document.replace_model(_make_mesh_model())
	var revision := document.get_revision()
	var context := {"mode": "rig", "parameter_id": "move", "coordinate": Vector2(1, 0), "values": {"move": 1.0}}
	var session := TwberPoseEditSession.new(document, "layer_001", context)
	context["coordinate"] = Vector2.ZERO
	context["values"]["move"] = 0.0
	var pose := session.get_pose()
	_expect(pose.position == Vector2(30, 20) and pose.mesh_vertices[1] == Vector2(45, 0),
		"Pose sessions sample their baseline from document rig data")
	pose.position += Vector2(7, 0)
	pose.mesh_vertices[1] += Vector2(3, 0)
	_expect(session.update(pose) == OK and document.get_revision() == revision and not document.is_dirty(),
		"Editing a pose buffer cannot mutate document state or history")
	pose.position.x = NAN
	_expect(session.update(pose) == ERR_INVALID_DATA and session.get_pose().position == Vector2(37, 20),
		"Invalid pose updates are atomic and input poses remain detached")
	var command := session.make_command()
	_expect(document.execute(command) == OK and document.get_revision() == revision + 1,
		"Bind publishes one native command for an accumulated draft")
	var authored := document.snapshot().to_model_resource()
	_expect(authored.layers[0].position == Vector2(10, 20)
		and authored.parameters[0].positions[0].coordinate == Vector2(1, 0)
		and authored.parameters[0].positions[0].layer_states[0].position == Vector2(37, 20),
		"Draft binding uses captured target coordinates and keeps rest data separate")
	_expect(session.make_command() == null and session.update(session.get_baseline()) == ERR_BUSY,
		"A changed document invalidates the old session and prevents a second commit")
	session.cancel()
	_expect(not session.is_current() and session.get_pose() == null, "Cancelled sessions cannot be reused")
	document.undo()
	var clip_context := {"mode": "timeline", "animation_id": "move_clip", "time": 0.5}
	session = TwberPoseEditSession.new(document, "layer_001", clip_context)
	clip_context["time"] = 1.0
	pose = session.get_pose()
	_expect(pose.position == Vector2(15, 20), "Timeline drafts sample the selected clip without baking rig preview inputs")
	pose.position = Vector2(22, 20)
	session.update(pose)
	_expect(document.execute(session.make_command()) == OK, "Recording a pose creates a native timeline key")
	authored = document.snapshot().to_model_resource()
	_expect(authored.timeline_animations[0].keyframes[1].time == 0.5
		and authored.timeline_animations[0].keyframes[1].layer_state.position == Vector2(22, 20),
		"A draft keeps its clip and playhead target isolated from later caller changes")


func _test_editor_pose_drafts() -> void:
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(editor)
	await process_frame
	editor._apply_opened_model(_make_mesh_model(), "")
	var rig := editor._editor_rigger
	var animator := editor._editor_animator
	var document := editor._document
	editor._menus.current_tab = rig.get_index()
	var node := editor._model_root.get_child(0) as TwberMeshSprite2D
	rig._select_node(node)
	rig._on_parameter_value_changed(rig._get_selected_parameter(), 1.0)
	var revision := document.get_revision()
	var start := node.get_global_transform_with_canvas().origin
	rig._begin_layer_transform_at(start, EditorRigger.RigMode.TRANSFORM_LAYER)
	rig._update_layer_transform(start + Vector2(10, 0))
	rig._update_layer_transform(start + Vector2(20, 0))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	rig._input(release)
	_expect(node.position == Vector2(50, 20) and rig.pose_draft.has_draft() and not rig._dragging_layer_transform
		and document.get_revision() == revision and not editor.is_dirty(), "Outside release keeps an unbound draft without publishing history")
	_expect(editor.undo_document() and not rig.pose_draft.has_draft() and node.position == Vector2(30, 20)
		and document.get_revision() == revision, "Undo discards the draft before touching committed history")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	rig.edit_pose({"position": Vector2(41, 20)})
	editor._unhandled_key_input(escape)
	_expect(node.position == Vector2(30, 20) and not editor._has_pose_draft(), "Escape restores the evaluated baseline")
	# Data lives in the draft even if a renderer node is changed independently.
	rig.edit_pose({"position": Vector2(42, 20)})
	node.position = Vector2(999, 999)
	rig._on_bind_position_button_pressed()
	_expect(document.get_revision() == revision + 1 and node.position == Vector2(42, 20)
		and document.snapshot().to_model_resource().parameters[0].positions[0].layer_states[0].position == Vector2(42, 20),
		"Bind commits the resource draft, ignoring arbitrary render-node mutations")
	_expect(editor.undo_document(), "One Undo reverses the entire bound draft")
	node = editor._model_root.get_child(0) as TwberMeshSprite2D
	var vertices := node.mesh_data.vertices.duplicate()
	rig._begin_vertex_drag(node, 1, node.get_global_transform_with_canvas() * node.get_vertex(1))
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	rig._handle_mouse_motion(motion, node.get_global_transform_with_canvas() * (vertices[1] + Vector2(6, 0)))
	_expect(node.get_vertex(1) == vertices[1] + Vector2(6, 0), "Rig mesh gestures project detached draft vertices")
	editor._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_expect(node.mesh_data.vertices == vertices and not rig.pose_draft.has_draft(), "Focus loss cancels mesh deformation without history")
	rig.edit_pose({"visible": false})
	rig._on_parameter_value_changed(rig._get_selected_parameter(), 0.0)
	_expect(not rig.pose_draft.has_draft() and node.visible, "Changing parameter input discards the old pose target")
	rig.edit_pose({"position": Vector2(77, 20)})
	var path := "user://twber_pose_draft_save.twber"
	_expect(await editor._save_model_to_path_async(path, true) == OK and rig.pose_draft.has_draft()
		and node.position == Vector2(77, 20), "Saving leaves the unbound draft available without authoring it")
	var saved := TwberModelCodec.load_model(path)
	_expect(saved.layers[0].position == Vector2(10, 20) and saved.parameters[0].positions[0].layer_states[0].position == Vector2(30, 20),
		"Save excludes draft rest and binding changes")
	editor._menus.current_tab = animator.get_index()
	_expect(not rig.pose_draft.has_draft(), "Leaving Rig discards its draft before the next tool samples neutral data")
	animator._select_node(node)
	animator._move_button.button_pressed = true
	start = node.get_global_transform_with_canvas().origin
	revision = document.get_revision()
	animator._begin_tool_drag(start, false)
	animator._update_tool_drag(start + Vector2(9, 0))
	animator._input(release)
	_expect(node.position == Vector2(24, 20) and animator.pose_draft.has_draft() and not animator._dragging
		and document.get_revision() == revision, "Animate release leaves the pose unrecorded")
	animator._add_point()
	_expect(document.get_revision() == revision + 1 and not animator.pose_draft.has_draft()
		and document.get_undo_label() == "Set animation key", "Add Point commits the complete draft exactly once")
	animator.edit_pose({"position": Vector2(80, 20)})
	animator._toggle_playback()
	_expect(not animator.pose_draft.has_draft() and animator._playing, "Playback discards an unrecorded edit before running")
	animator._toggle_playback()
	animator.edit_pose({"position": Vector2(80, 20)})
	animator._playhead = 0.5
	animator._apply_animation_at_playhead()
	_expect(not animator.pose_draft.has_draft() and node.position == Vector2(24, 20), "Scrubbing cannot carry a draft to a different time")
	animator.edit_pose({"position": Vector2(90, 20)})
	# Even direct external commands invalidate a pose; it cannot overwrite them.
	document.execute(TwberEditTimeline.new(TwberEditTimeline.Operation.UPDATE, "move_clip", {"duration": 2.0}))
	_expect(not animator.pose_draft.has_draft(), "An external document revision invalidates unrecorded poses")
	editor._apply_opened_model(_make_sprite_animation_model(), "")
	editor._menus.current_tab = rig.get_index()
	var sprite := editor._model_root.get_child(0) as AnimatedSprite2D
	rig._select_node(sprite)
	rig._on_animation_frame_rate_value_changed(18.0)
	_expect(sprite.sprite_frames.get_animation_speed("Idle") == 18.0, "Sprite rate edits preview through a pose draft")
	rig.cancel_pose_draft()
	_expect(sprite.sprite_frames.get_animation_speed("Idle") == 4.0, "Cancelling restores the authored sprite frame rates")
	rig._on_opacity_slider_value_changed(0.2)
	rig._select_node(null)
	_expect(not rig.pose_draft.has_draft() and is_equal_approx(sprite.self_modulate.a, 1.0), "Changing selection restores the previous layer's draft")
	rig._select_node(sprite)
	rig.edit_pose({"position": Vector2(123, 123)})
	editor._new_model()
	_expect(not rig.pose_draft.has_draft() and not editor.is_dirty(), "New model discards all pose drafts")
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
