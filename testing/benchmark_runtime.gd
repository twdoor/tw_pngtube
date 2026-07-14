extends SceneTree

const LAYER_COUNT := 40
const PARAMETER_COUNT := 8
const POSITIONS_PER_PARAMETER := 6
const LAYERS_PER_PARAMETER := 10
const VERTICES_PER_MESH := 64
const EVALUATION_COUNT := 120


func _init() -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	var parameters: Array[TwberParameterResource] = []
	var base_vertices := PackedVector2Array()
	var base_triangles := PackedInt32Array()
	for index: int in VERTICES_PER_MESH:
		base_vertices.append(Vector2(index % 8, index / 8))
	for row: int in 7:
		for column: int in 7:
			var top_left := row * 8 + column
			base_triangles.append_array(PackedInt32Array([
				top_left, top_left + 8, top_left + 1,
				top_left + 1, top_left + 8, top_left + 9,
			]))
	var texture_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	texture_image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(texture_image)

	for layer_index: int in LAYER_COUNT:
		var layer := TwberMeshSprite2D.new()
		layer.set_meta(TwberModelCodec.LAYER_ID_META, "layer_%03d" % layer_index)
		layer.mesh_data = TwberMeshResource.new()
		layer.mesh_data.vertices = base_vertices.duplicate()
		layer.mesh_data.rest_vertices = base_vertices.duplicate()
		layer.mesh_data.uvs = base_vertices.duplicate()
		layer.mesh_data.triangles = base_triangles.duplicate()
		layer.texture = texture
		root.add_child(layer)

	for parameter_index: int in PARAMETER_COUNT:
		var parameter := TwberParameterResource.new()
		parameter.id = "parameter_%03d" % parameter_index
		parameter.min_value = -1.0
		parameter.max_value = 1.0
		parameter.step = 0.001
		for position_index: int in POSITIONS_PER_PARAMETER:
			var parameter_position := TwberParameterPositionResource.new()
			parameter_position.coordinate = Vector2(
					lerpf(-1.0, 1.0, float(position_index) / float(POSITIONS_PER_PARAMETER - 1)),
					0.0,
			)
			for binding_index: int in LAYERS_PER_PARAMETER:
				var layer_index := (parameter_index * 5 + binding_index) % LAYER_COUNT
				var state := TwberLayerStateResource.new()
				state.channels = (
						TwberLayerStateResource.Channel.POSITION
						| TwberLayerStateResource.Channel.MESH
				)
				state.layer_id = "layer_%03d" % layer_index
				state.position = Vector2(parameter_position.coordinate.x, 0.0)
				state.mesh_vertices = base_vertices.duplicate()
				for vertex_index: int in state.mesh_vertices.size():
					state.mesh_vertices[vertex_index].y += parameter_position.coordinate.x
				parameter_position.layer_states.append(state)
			parameter.positions.append(parameter_position)
		parameters.append(parameter)

	var evaluator := TwberParameterEvaluator.new()
	var batch_renderer := TwberModelBatchRenderer2D.attach_to(root)
	batch_renderer.configure(root)
	var compile_start := Time.get_ticks_usec()
	evaluator.configure(root, parameters)
	var compile_usec := Time.get_ticks_usec() - compile_start
	var neutral_states := {}
	for layer_index: int in LAYER_COUNT:
		var layer_id := "layer_%03d" % layer_index
		var neutral_state := TwberLayerStateResource.new()
		neutral_state.capture_from_node(evaluator.get_layer_nodes()[layer_id])
		neutral_states[layer_id] = neutral_state
	evaluator.set_neutral_states(neutral_states)

	var values := {}
	var evaluation_only_start := Time.get_ticks_usec()
	for evaluation_index: int in EVALUATION_COUNT:
		for parameter_index: int in PARAMETER_COUNT:
			values["parameter_%03d" % parameter_index] = sin(
					float(evaluation_index + parameter_index) * 0.05
			)
		evaluator.apply(values)
	var evaluation_only_usec := Time.get_ticks_usec() - evaluation_only_start
	var render_update_start := Time.get_ticks_usec()
	for evaluation_index: int in EVALUATION_COUNT:
		batch_renderer.update_dynamic_geometry()
	var render_update_usec := Time.get_ticks_usec() - render_update_start
	var selective_start := Time.get_ticks_usec()
	for evaluation_index: int in EVALUATION_COUNT:
		values["parameter_000"] = sin(float(evaluation_index) * 0.05)
		var affected_layer_ids := evaluator.apply_changed(values, ["parameter_000"])
		var affected_nodes: Array[Node2D] = []
		for layer_id: String in affected_layer_ids:
			affected_nodes.append(evaluator.get_layer_nodes()[layer_id] as Node2D)
		batch_renderer.update_dynamic_geometry_for_nodes(affected_nodes)
	var selective_usec := Time.get_ticks_usec() - selective_start

	var evaluate_start := Time.get_ticks_usec()
	for evaluation_index: int in EVALUATION_COUNT:
		for parameter_index: int in PARAMETER_COUNT:
			values["parameter_%03d" % parameter_index] = sin(
					float(evaluation_index + parameter_index) * 0.05
			)
		evaluator.apply(values)
		batch_renderer.update_dynamic_geometry()
	var evaluate_usec := Time.get_ticks_usec() - evaluate_start

	print("Twber runtime benchmark")
	print("  layers: %d" % LAYER_COUNT)
	print("  parameters: %d × %d positions" % [PARAMETER_COUNT, POSITIONS_PER_PARAMETER])
	print("  bound layers per parameter: %d" % LAYERS_PER_PARAMETER)
	print("  mesh vertices per layer: %d" % VERTICES_PER_MESH)
	print("  render batches: %d" % batch_renderer.get_batch_count())
	print("  compile: %.2f ms" % (float(compile_usec) / 1000.0))
	print("  parameter evaluation: %.3f ms average" % (
		float(evaluation_only_usec) / 1000.0 / float(EVALUATION_COUNT)
	))
	print("  render-buffer update: %.3f ms average" % (
		float(render_update_usec) / 1000.0 / float(EVALUATION_COUNT)
	))
	print("  one changed parameter + dirty buffers: %.3f ms average" % (
		float(selective_usec) / 1000.0 / float(EVALUATION_COUNT)
	))
	print("  evaluation + render-buffer update: %.3f ms average (%d runs)" % [
		float(evaluate_usec) / 1000.0 / float(EVALUATION_COUNT),
		EVALUATION_COUNT,
	])

	root.free()
	quit(0)
