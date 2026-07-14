extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_texture_trimming()
	_test_compiled_parameter_evaluation()
	_test_sparse_parameter_states()
	_test_mesh_atlas_uv_mapping()
	_test_editor_atlas_builder()
	_test_batch_renderer_fallback()
	_test_batch_renderer_viewport_mask_lifecycle()
	_test_runtime_model_evaluation()
	_test_archive_and_legacy_round_trip()
	await _test_editor_model_open_and_reset()

	if _failures.is_empty():
		print("Twber tests passed.")
		quit(0)
		return

	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_texture_trimming() -> void:
	var image := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in range(3, 9):
		for x: int in range(4, 11):
			image.set_pixel(x, y, Color(1.0, 0.5, 0.25, 1.0))
	image.set_pixel(1, 1, Color(1.0, 1.0, 1.0, 0.0005))

	var prepared := TwberTextureUtils.prepare_image(image, true, 0.001, 2)
	_expect(prepared["original_size"] == Vector2i(16, 12), "Trim keeps original canvas size metadata")
	_expect(prepared["trim_rect"] == Rect2i(2, 1, 11, 10), "Trim uses visible alpha plus padding")
	_expect(prepared["visible_rect"] == Rect2i(2, 2, 7, 6), "Visible rect is relative to trimmed texture")

	var texture := ImageTexture.create_from_image(prepared["image"])
	TwberTextureUtils.apply_metadata(texture, prepared)
	_expect(texture.get_size() == Vector2(11, 10), "Trim does not rescale visible pixels")
	_expect(
		TwberTextureUtils.get_logical_texture_origin(texture).is_equal_approx(Vector2(-6.0, -5.0)),
		"Trim preserves original logical placement",
	)

	var source_path := "user://twber_authoring_pixels_test.png"
	var source_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	source_image.fill(Color.TRANSPARENT)
	source_image.set_pixel(3, 4, Color(0.2, 0.7, 0.4, 0.2))
	_expect(source_image.save_png(source_path) == OK, "Authoring-pixel fixture saves")
	var runtime_image := source_image.duplicate()
	_expect(
			runtime_image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC) == OK,
			"Authoring-pixel fixture compresses for runtime",
	)
	var runtime_texture := ImageTexture.create_from_image(runtime_image)
	runtime_texture.set_meta(TwberTextureUtils.SOURCE_PATH_META, source_path)
	TwberTextureUtils.apply_metadata(runtime_texture, {
		"original_size": Vector2i(8, 8),
		"trim_rect": Rect2i(0, 0, 8, 8),
		"visible_rect": Rect2i(3, 4, 1, 1),
		"alpha_threshold": 0.001,
	})
	var recovered_source := TwberTextureUtils.get_authoring_image(runtime_texture)
	_expect(recovered_source != null, "Compressed runtime texture recovers its lossless authoring source")
	if recovered_source != null:
		_expect(
				recovered_source.get_pixel(3, 4).is_equal_approx(source_image.get_pixel(3, 4)),
				"Alpha-sensitive tools read source pixels instead of compression artifacts",
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))


func _test_compiled_parameter_evaluation() -> void:
	var root := Node2D.new()
	var layer := Node2D.new()
	layer.set_meta(TwberModelCodec.LAYER_ID_META, "layer_001")
	root.add_child(layer)

	var parameter := TwberParameterResource.new()
	parameter.id = "test"
	parameter.default_float = 0.0
	parameter.min_value = 0.0
	parameter.max_value = 1.0
	parameter.step = 0.01
	var position := TwberParameterPositionResource.new()
	position.coordinate = Vector2(1.0, 0.0)
	var state := TwberLayerStateResource.new()
	state.layer_id = "layer_001"
	state.position = Vector2(10.0, 4.0)
	position.layer_states.append(state)
	parameter.positions.append(position)

	var evaluator := TwberParameterEvaluator.new()
	var parameters: Array[TwberParameterResource] = [parameter]
	evaluator.configure(root, parameters)
	var affected := evaluator.apply({"test": 0.5})
	_expect(affected == ["layer_001"], "Compiled evaluator reports affected layer")
	_expect(layer.position.is_equal_approx(Vector2(5.0, 2.0)), "Compiled scalar parameter blends from neutral")

	layer.position = Vector2.ZERO
	var vector_parameter := TwberParameterResource.new()
	vector_parameter.id = "vector_test"
	vector_parameter.value_type = TwberParameterResource.ValueType.VECTOR2
	for coordinate: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, -1)]:
		var vector_position := TwberParameterPositionResource.new()
		vector_position.coordinate = coordinate
		var vector_state := TwberLayerStateResource.new()
		vector_state.channels = TwberLayerStateResource.Channel.POSITION
		vector_state.layer_id = "layer_001"
		vector_state.position = coordinate * 10.0
		vector_position.layer_states.append(vector_state)
		vector_parameter.positions.append(vector_position)
	var vector_parameters: Array[TwberParameterResource] = [vector_parameter]
	evaluator.configure(root, vector_parameters)
	evaluator.apply({"vector_test": Vector2(0.25, 0.25)})
	_expect(layer.position.is_equal_approx(Vector2(2.5, 2.5)), "Compiled vector parameter uses cached triangulation")

	# Runtime evaluation supplies an immutable neutral state and uses the
	# allocation-reduced sampling path. It must remain bit-for-bit equivalent to
	# the general editor evaluator for vector samples as well as scalar ones.
	layer.position = Vector2.ZERO
	evaluator.configure(root, vector_parameters)
	var neutral_state := TwberLayerStateResource.new()
	neutral_state.capture_from_node(layer)
	evaluator.set_neutral_states({"layer_001": neutral_state})
	evaluator.apply({"vector_test": Vector2(0.25, 0.25)})
	_expect(
			layer.position.is_equal_approx(Vector2(2.5, 2.5)),
			"Runtime-optimized vector evaluation matches the general evaluator",
	)

	root.free()


func _test_archive_and_legacy_round_trip() -> void:
	var model := TwberModelResource.new()
	for index: int in 3:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(1.0 if index != 1 else 0.0, 0.0, 1.0 if index == 1 else 0.0, 1.0))
		if index == 0:
			image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC)
		var texture := ImageTexture.create_from_image(image)
		texture.set_meta(TwberModelCodec.TEXTURE_SOURCE_PATH_META, "test_%d.png" % index)
		TwberTextureUtils.apply_metadata(texture, {
			"original_size": Vector2i(8, 8),
			"trim_rect": Rect2i(0, 0, 8, 8),
			"visible_rect": Rect2i(0, 0, 8, 8),
			"alpha_threshold": 0.001,
		})
		var texture_id := "texture_%03d" % (index + 1)
		model.textures[texture_id] = texture
		model.texture_sources[texture_id] = "test_%d.png" % index

		var layer := TwberLayerResource.new()
		layer.id = "layer_%03d" % (index + 1)
		layer.name = "Layer %d" % index
		layer.type = TwberLayerResource.LayerType.SPRITE
		layer.texture_id = texture_id
		model.layers.append(layer)
		model.root_layer_ids.append(layer.id)

	var archive_path := "user://twber_codec_test.twber"
	var error := TwberModelCodec.export_twber(model, archive_path)
	_expect(error == OK, "Archive export succeeds: %s" % error_string(error))
	var archive := ZIPReader.new()
	_expect(archive.open(archive_path) == OK, "Export is a readable ZIP archive")
	if archive.get_files().has(TwberModelCodec.PACKAGE_MANIFEST_PATH):
		var manifest_text := archive.read_file(TwberModelCodec.PACKAGE_MANIFEST_PATH).get_string_from_utf8()
		_expect(not manifest_text.contains("\"png\":"), "Archive manifest does not contain base64 textures")
		var manifest: Dictionary = JSON.parse_string(manifest_text)
		_expect(
				int((manifest.get("summary", {}) as Dictionary).get("estimated_draw_calls", 0)) == 1,
				"Archive performance summary reflects atlas batching",
		)
	_expect(archive.get_files().has("textures/atlas_000.png"), "Two compatible textures share an atlas")
	_expect(archive.get_files().has("textures/atlas_000.s3tc"), "Archive contains a desktop GPU-compressed atlas variant")
	archive.close()
	_expect(TwberModelCodec.export_twber(model, archive_path) == OK, "Atomic export safely replaces an existing package")

	var loaded := TwberModelCodec.load_twber(archive_path)
	_expect(loaded != null, "Archive loads")
	if loaded != null:
		_expect(loaded.layers.size() == 3, "Archive retains layers")
		var first: Texture2D = loaded.textures.get("texture_001") as Texture2D
		var second: Texture2D = loaded.textures.get("texture_002") as Texture2D
		var third: Texture2D = loaded.textures.get("texture_003") as Texture2D
		_expect(first is AtlasTexture and second is AtlasTexture, "Archive restores atlas regions")
		if first is AtlasTexture and second is AtlasTexture:
			_expect(first.atlas == second.atlas, "Atlas regions share one GPU texture object")
			if OS.has_feature("pc"):
				_expect(first.atlas.get_image().is_compressed(), "Desktop loader uses GPU-compressed texture variant")
		if first is AtlasTexture and third is AtlasTexture:
			_expect(first.region == third.region, "Identical texture content shares one atlas region")
		_expect(TwberTextureUtils.get_original_size(first) == Vector2i(8, 8), "Texture metadata survives archive")
		_expect(
				second != null and second.has_meta(TwberTextureUtils.PACKAGE_TEXTURE_FILE_META),
				"Compressed package texture retains a lazy lossless-source locator",
		)
		var packaged_authoring_image := TwberTextureUtils.get_authoring_image(second)
		_expect(
				packaged_authoring_image != null and not packaged_authoring_image.is_compressed(),
				"Editor tools lazily recover the packaged lossless PNG",
		)
		if packaged_authoring_image != null:
			var package_pixel := packaged_authoring_image.get_pixel(2, 2)
			_expect(
					package_pixel.b > 0.99 and package_pixel.r < 0.01,
					"Packaged authoring image uses the correct atlas region",
			)
		var loaded_again := TwberModelCodec.load_twber(archive_path)
		var again_first: Texture2D = loaded_again.textures.get("texture_001") as Texture2D
		if first is AtlasTexture and again_first is AtlasTexture:
			_expect(first.atlas == again_first.atlas, "Separate model loads share cached GPU texture content")
		var runtime := TwberRuntimeModel.new()
		get_root().add_child(runtime)
		runtime.set_model(loaded)
		var runtime_summary := runtime.get_performance_summary()
		_expect(bool(runtime_summary.get("runtime_batching_active", false)), "Runtime model enables compatible batching")
		_expect(int(runtime_summary.get("runtime_batches", 0)) == 1, "Runtime model renders the atlas in one batch")
		runtime.free()

	var legacy_path := "user://twber_codec_legacy_test.twber"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(TwberModelCodec.to_dictionary(model, true)))
	legacy_file.close()
	var legacy_loaded := TwberModelCodec.load_twber(legacy_path)
	_expect(legacy_loaded != null and legacy_loaded.textures.size() == 3, "Legacy JSON package still loads")

	var resource_path := "user://twber_codec_resource_test.tres"
	var resource_error := TwberModelCodec.save_resource(model, resource_path)
	_expect(resource_error == OK, "Editable resource saves")
	var resource_loaded := TwberModelCodec.load_model(resource_path)
	_expect(resource_loaded != null and resource_loaded.textures.size() == 3, "Editable resource reloads")
	if resource_loaded != null:
		_expect(
				TwberTextureUtils.get_original_size(resource_loaded.textures["texture_001"]) == Vector2i(8, 8),
				"Editable resource retains texture metadata",
		)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(resource_path))
	TwberTextureUtils.clear_package_image_cache()


func _test_runtime_model_evaluation() -> void:
	var model := TwberModelResource.new()
	var layer_resource := TwberLayerResource.new()
	layer_resource.id = "runtime_layer"
	layer_resource.name = "Runtime Layer"
	model.layers.append(layer_resource)
	model.root_layer_ids.append(layer_resource.id)
	var second_layer_resource := TwberLayerResource.new()
	second_layer_resource.id = "runtime_layer_2"
	second_layer_resource.name = "Runtime Layer 2"
	model.layers.append(second_layer_resource)
	model.root_layer_ids.append(second_layer_resource.id)

	var parameter := TwberParameterResource.new()
	parameter.id = "runtime_parameter"
	parameter.min_value = 0.0
	parameter.max_value = 1.0
	parameter.default_float = 0.0
	var position := TwberParameterPositionResource.new()
	position.coordinate = Vector2(1.0, 0.0)
	var state := TwberLayerStateResource.from_layer_resource(layer_resource)
	state.position = Vector2(12.0, 0.0)
	position.layer_states.append(state)
	parameter.positions.append(position)
	model.parameters.append(parameter)
	var second_parameter := TwberParameterResource.new()
	second_parameter.id = "runtime_parameter_2"
	second_parameter.min_value = 0.0
	second_parameter.max_value = 1.0
	second_parameter.default_float = 0.0
	var second_position := TwberParameterPositionResource.new()
	second_position.coordinate = Vector2(1.0, 0.0)
	var second_state := TwberLayerStateResource.from_layer_resource(second_layer_resource)
	second_state.position = Vector2(0.0, 8.0)
	second_position.layer_states.append(second_state)
	second_parameter.positions.append(second_position)
	model.parameters.append(second_parameter)

	var runtime := TwberRuntimeModel.new()
	get_root().add_child(runtime)
	runtime.set_model(model)
	_expect(runtime.set_parameter_value("runtime_parameter", 0.5), "Runtime accepts changed parameter value")
	var affected := runtime.evaluate_parameters()
	var runtime_layer := runtime.get_child(0) as Node2D
	_expect(affected == ["runtime_layer"], "Runtime reports evaluated layer")
	_expect(runtime_layer.position.is_equal_approx(Vector2(6.0, 0.0)), "Runtime evaluates compiled parameter")
	runtime.evaluate_parameters()
	_expect(runtime_layer.position.is_equal_approx(Vector2(6.0, 0.0)), "Runtime evaluation does not accumulate")
	_expect(not runtime.set_parameter_value("runtime_parameter", 0.5), "Runtime skips unchanged parameter value")
	_expect(runtime.set_parameter_value("runtime_parameter_2", 0.5), "Runtime accepts a second parameter value")
	var second_affected := runtime.evaluate_parameters()
	var second_runtime_layer := runtime.get_child(1) as Node2D
	_expect(second_affected == ["runtime_layer_2"], "Runtime evaluates only layers touched by changed parameters")
	_expect(second_runtime_layer.position.is_equal_approx(Vector2(0.0, 4.0)), "Selective evaluation applies the changed layer")
	_expect(runtime_layer.position.is_equal_approx(Vector2(6.0, 0.0)), "Selective evaluation preserves other parameter results")
	runtime.free()


func _test_sparse_parameter_states() -> void:
	var base := TwberLayerStateResource.new()
	base.layer_id = "sparse_layer"
	for index: int in 128:
		base.mesh_vertices.append(Vector2(index, index))
	var current: TwberLayerStateResource = base.duplicate(true)
	var other: TwberLayerStateResource = base.duplicate(true)
	current.position = Vector2(4.0, 2.0)

	var isolated := TwberLayerStateResource.isolate_contribution(base, current, other)
	_expect(
			isolated.channels == TwberLayerStateResource.Channel.POSITION,
			"Binding records only the changed parameter channel",
	)
	_expect(isolated.mesh_vertices.is_empty(), "Unchanged mesh arrays are not copied into sparse state")
	var materialized := isolated.materialized(base)
	_expect(materialized.mesh_vertices.size() == 128, "Sparse state materializes neutral mesh for evaluation")
	_expect(materialized.position == Vector2(4.0, 2.0), "Sparse changed channel survives materialization")


func _test_mesh_atlas_uv_mapping() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var base_texture := ImageTexture.create_from_image(image)
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = base_texture
	atlas_texture.region = Rect2(8, 12, 8, 8)

	var mesh_sprite := TwberMeshSprite2D.new()
	mesh_sprite.texture = atlas_texture
	mesh_sprite.mesh_data = TwberMeshResource.new()
	mesh_sprite.mesh_data.vertices = PackedVector2Array([
		Vector2(0, 0), Vector2(8, 0), Vector2(0, 8),
	])
	mesh_sprite.mesh_data.rest_vertices = mesh_sprite.mesh_data.vertices.duplicate()
	mesh_sprite.mesh_data.uvs = mesh_sprite.mesh_data.vertices.duplicate()
	mesh_sprite.mesh_data.triangles = PackedInt32Array([0, 1, 2])
	get_root().add_child(mesh_sprite)
	mesh_sprite.sync_mesh()
	_expect(mesh_sprite.get_node_or_null("MeshPolygon") == null, "Mesh renderer creates no Polygon2D child")
	_expect(mesh_sprite.get_render_texture() == base_texture, "Mesh renderer binds the shared atlas texture")
	_expect(
			mesh_sprite.get_render_uvs()[0].is_equal_approx(Vector2(0.25, 0.375)),
			"Mesh UVs are normalized and offset into the atlas region",
	)
	mesh_sprite.free()


func _test_editor_atlas_builder() -> void:
	var model_root := Node2D.new()
	for index: int in 2:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color.RED if index == 0 else Color.BLUE)
		var texture := ImageTexture.create_from_image(image)
		texture.set_meta(TwberTextureUtils.SOURCE_PATH_META, "preview_%d.png" % index)
		TwberTextureUtils.apply_metadata(texture, {
			"original_size": Vector2i(8, 8),
			"trim_rect": Rect2i(0, 0, 8, 8),
			"visible_rect": Rect2i(0, 0, 8, 8),
			"alpha_threshold": 0.001,
		})
		var sprite := Sprite2D.new()
		sprite.texture = texture
		model_root.add_child(sprite)
	var result := TwberTextureAtlasBuilder.optimize_model_root(model_root, -1)
	var first := model_root.get_child(0) as Sprite2D
	var second := model_root.get_child(1) as Sprite2D
	_expect(result.get("atlas_pages", 0) == 1, "Editor preview builds one shared atlas page")
	_expect(first.texture is AtlasTexture and second.texture is AtlasTexture, "Editor textures become atlas regions")
	if first.texture is AtlasTexture and second.texture is AtlasTexture:
		_expect(first.texture.atlas == second.texture.atlas, "Editor atlas regions share one GPU texture")
		_expect(
				String(first.texture.get_meta(TwberTextureUtils.SOURCE_PATH_META, "")) == "preview_0.png",
				"Editor atlas wrapper preserves source metadata",
		)
	model_root.free()


func _test_batch_renderer_fallback() -> void:
	var model_root := Node2D.new()
	for index: int in 2:
		var sprite := Sprite2D.new()
		if index == 0:
			sprite.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		model_root.add_child(sprite)
	var renderer := TwberModelBatchRenderer2D.attach_to(model_root)
	_expect(not renderer.configure(model_root), "Clipped model safely falls back from flat batching")
	_expect(not renderer.is_batching_active(), "Fallback leaves batching disabled")
	_expect((model_root.get_child(0) as CanvasItem).visibility_layer == 1, "Fallback preserves source visibility")
	model_root.free()

	var interleaved_root := Node2D.new()
	for index: int in 2:
		var sprite := Sprite2D.new()
		sprite.texture = _make_test_texture(Color.WHITE)
		interleaved_root.add_child(sprite)
		if index == 0:
			interleaved_root.add_child(Line2D.new())
	var interleaved_renderer := TwberModelBatchRenderer2D.attach_to(interleaved_root)
	_expect(
			not interleaved_renderer.configure(interleaved_root),
			"Unsupported interleaved draw nodes create a safe batching barrier",
	)
	interleaved_root.free()


func _test_batch_renderer_viewport_mask_lifecycle() -> void:
	var viewport := SubViewport.new()
	get_root().add_child(viewport)
	var original_mask := viewport.canvas_cull_mask
	var roots: Array[Node2D] = []
	var renderers: Array[TwberModelBatchRenderer2D] = []
	var texture := _make_test_texture(Color.WHITE)
	for root_index: int in 2:
		var model_root := Node2D.new()
		viewport.add_child(model_root)
		roots.append(model_root)
		for sprite_index: int in 2:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			model_root.add_child(sprite)
		var renderer := TwberModelBatchRenderer2D.attach_to(model_root)
		_expect(renderer.configure(model_root), "Compatible model activates batching")
		renderers.append(renderer)

	_expect(
			(viewport.canvas_cull_mask & TwberModelBatchRenderer2D.SOURCE_VISIBILITY_LAYER) == 0,
			"Active batches hide their editable source canvas layer",
	)
	renderers[0].clear()
	_expect(
			(viewport.canvas_cull_mask & TwberModelBatchRenderer2D.SOURCE_VISIBILITY_LAYER) == 0,
			"One runtime model cannot reveal another model's batch sources",
	)
	renderers[1].clear()
	_expect(
			viewport.canvas_cull_mask == original_mask,
			"Last batch restores the viewport cull mask",
	)
	for model_root: Node2D in roots:
		model_root.free()
	viewport.free()


func _test_editor_model_open_and_reset() -> void:
	var model := TwberModelResource.new()
	for index: int in 2:
		var texture_id := "editor_texture_%d" % index
		model.textures[texture_id] = _make_test_texture(Color.RED if index == 0 else Color.BLUE)
		var layer := TwberLayerResource.new()
		layer.id = "editor_layer_%d" % index
		layer.name = "Editor Layer %d" % index
		layer.type = TwberLayerResource.LayerType.SPRITE
		layer.texture_id = texture_id
		model.layers.append(layer)
		model.root_layer_ids.append(layer.id)
	var model_path := "user://twber_editor_integration_test.tres"
	_expect(TwberModelCodec.save_resource(model, model_path) == OK, "Editor integration fixture saves")

	var editor_scene := load("res://editor/editor.tscn") as PackedScene
	var editor := editor_scene.instantiate()
	get_root().add_child(editor)
	await process_frame
	editor.call("_open_model", model_path)
	var model_root := editor.get_node("ModelPreview/Textures") as Node2D
	var renderer := TwberModelBatchRenderer2D.find_on(model_root)
	_expect(model_root.get_child_count() == 2, "Editor opens both model layers")
	_expect(
			renderer is TwberModelBatchRenderer2D and renderer.is_batching_active(),
			"Editor model open enables atlas-backed batching",
	)
	if renderer is TwberModelBatchRenderer2D:
		_expect(renderer.get_batch_count() == 1, "Editor preview uses one atlas render batch")

	editor.call("_new_model")
	renderer = TwberModelBatchRenderer2D.find_on(model_root)
	_expect(model_root.get_child_count() == 0, "New model removes editable layers")
	_expect(
			renderer is TwberModelBatchRenderer2D and not renderer.is_batching_active(),
			"New model keeps the internal renderer ready without stale geometry",
	)

	var clipped_model := TwberModelResource.new()
	clipped_model.textures["mask_texture"] = _make_test_texture(Color.WHITE)
	clipped_model.textures["child_texture"] = _make_test_texture(Color.RED)
	var mask_layer := TwberLayerResource.new()
	mask_layer.id = "editor_mask"
	mask_layer.name = "Editor Mask"
	mask_layer.type = TwberLayerResource.LayerType.SPRITE
	mask_layer.texture_id = "mask_texture"
	mask_layer.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask_layer.modulate = Color(1.0, 1.0, 1.0, 0.65)
	mask_layer.children.append("editor_mask_child")
	var child_layer := TwberLayerResource.new()
	child_layer.id = "editor_mask_child"
	child_layer.name = "Editor Mask Child"
	child_layer.type = TwberLayerResource.LayerType.SPRITE
	child_layer.texture_id = "child_texture"
	clipped_model.layers.assign([mask_layer, child_layer])
	clipped_model.root_layer_ids.append(mask_layer.id)
	var clipped_model_path := "user://twber_editor_clip_integration_test.tres"
	_expect(
		TwberModelCodec.save_resource(clipped_model, clipped_model_path) == OK,
		"Editor clipping integration fixture saves",
	)
	editor.call("_open_model", clipped_model_path)
	var preview_mask := model_root.get_child(0) as CanvasItem
	_expect(
		preview_mask.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED,
		"Editor preview replaces built-in clipping with alpha-safe clipping",
	)
	_expect(
		TwberAlphaClipController.get_authored_clip_mode(preview_mask) == CanvasItem.CLIP_CHILDREN_ONLY,
		"Editor tools retain the authored clip mode while alpha-safe preview is active",
	)
	_expect(
		is_equal_approx(TwberAlphaClipController.get_authored_self_modulate(preview_mask).a, 0.65),
		"Editor tools retain the authored mask opacity while the clip-only mask is hidden",
	)
	var edited_color := TwberAlphaClipController.get_authored_self_modulate(preview_mask)
	edited_color.a = 0.35
	TwberAlphaClipController.set_authored_self_modulate(preview_mask, edited_color)
	var rig_capture := TwberLayerStateResource.new()
	rig_capture.capture_from_node(preview_mask as Node2D)
	_expect(
		is_equal_approx(rig_capture.self_modulate.a, 0.35),
		"Rigger captures edited authored opacity instead of the hidden preview opacity",
	)
	TwberAlphaClipController.set_authored_self_modulate(
		preview_mask,
		Color(1.0, 1.0, 1.0, 0.65),
	)
	var rigger := editor.get_node(
		"PanelContainer/MarginContainer/VBoxContainer/Menus/EditorRigger",
	) as EditorRigger
	rigger.reload_from_preview(preview_mask as Node2D)
	rigger.call("_on_create_parameter_pressed", TwberParameterResource.ValueType.FLOAT)
	rigger.call("_on_opacity_slider_value_changed", 0.35)
	rigger.call("_on_bind_position_button_pressed")
	var rig_parameters: Array[TwberParameterResource] = []
	for value: Variant in model_root.get_meta(TwberModelCodec.MODEL_PARAMETERS_META, []):
		if value is TwberParameterResource:
			rig_parameters.append(value)
	var bound_opacity := -1.0
	if not rig_parameters.is_empty() and not rig_parameters[0].positions.is_empty():
		var bound_state := rig_parameters[0].positions[0].find_state("editor_mask")
		if bound_state != null:
			bound_opacity = bound_state.self_modulate.a
	_expect(
		is_equal_approx(bound_opacity, 0.35),
		"Rigger binds clip-mask opacity to the selected parameter position",
	)
	rigger.call("_on_create_parameter_pressed", TwberParameterResource.ValueType.BOOL)
	var bool_parameter := rig_parameters[0]
	for value: Variant in model_root.get_meta(TwberModelCodec.MODEL_PARAMETERS_META, []):
		if value is TwberParameterResource and value.value_type == TwberParameterResource.ValueType.BOOL:
			bool_parameter = value
			break
	var parameter_controls := rigger.get("_parameter_value_controls") as Dictionary
	var bool_control := parameter_controls.get(bool_parameter.id) as HBoxContainer
	var false_button := bool_control.get_node_or_null("FalseButton") as Button
	var true_button := bool_control.get_node_or_null("TrueButton") as Button
	_expect(
		false_button != null and true_button != null,
		"Rigger bool parameters use visible False and True buttons",
	)
	_expect(
		false_button != null
		and true_button != null
		and false_button.button_group == true_button.button_group
		and false_button.button_pressed
		and not true_button.button_pressed,
		"Rigger bool buttons form one exclusive group with the default value selected",
	)
	if true_button != null:
		true_button.button_pressed = true
	var preview_values := rigger.get("_parameter_preview_values") as Dictionary
	_expect(
		bool(preview_values.get(bool_parameter.id, false)),
		"Selecting True updates the bool parameter preview value",
	)
	if false_button != null:
		false_button.button_pressed = true
	_expect(
		false_button != null
		and true_button != null
		and false_button.button_pressed
		and not true_button.button_pressed
		and not bool(preview_values.get(bool_parameter.id, true)),
		"Selecting False updates the preview and unpresses True",
	)
	var captured_model := editor.call("_create_model_resource_from_base_state") as TwberModelResource
	var captured_mask: TwberLayerResource
	for captured_layer: TwberLayerResource in captured_model.layers:
		if captured_layer.id == "editor_mask":
			captured_mask = captured_layer
			break
	_expect(
		captured_mask != null and captured_mask.clip_children == CanvasItem.CLIP_CHILDREN_ONLY,
		"Editor save capture preserves the authored clip mode",
	)
	_expect(
		captured_mask != null and is_equal_approx(captured_mask.modulate.a, 0.65),
		"Editor save capture preserves the authored mask opacity",
	)
	_expect(
		preview_mask.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED,
		"Editor restores alpha-safe clipping after save capture",
	)
	editor.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(model_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(clipped_model_path))


func _make_test_texture(color: Color) -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
