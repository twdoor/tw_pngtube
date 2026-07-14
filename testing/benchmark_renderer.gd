extends SceneTree

const LAYER_COUNT := 200
const GRID_SIZE := 8
const UPDATE_COUNT := 120


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		print("Twber renderer benchmark skipped: a real graphics backend is required.")
		quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)

	var texture_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	texture_image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(texture_image)
	var geometry := _create_grid_geometry()

	var direct_group := Node2D.new()
	viewport.add_child(direct_group)
	var direct_nodes: Array[TwberMeshSprite2D] = []
	for layer_index: int in LAYER_COUNT:
		var mesh_sprite := TwberMeshSprite2D.new()
		mesh_sprite.texture = texture
		mesh_sprite.mesh_data = TwberMeshResource.new()
		mesh_sprite.mesh_data.vertices = geometry["vertices"].duplicate()
		mesh_sprite.mesh_data.rest_vertices = geometry["vertices"].duplicate()
		mesh_sprite.mesh_data.uvs = geometry["uvs"].duplicate()
		mesh_sprite.mesh_data.triangles = geometry["triangles"].duplicate()
		mesh_sprite.position = _get_layer_position(layer_index)
		direct_group.add_child(mesh_sprite)
		direct_nodes.append(mesh_sprite)
	var batch_renderer := TwberModelBatchRenderer2D.attach_to(direct_group)
	batch_renderer.configure(direct_group)

	await process_frame
	await RenderingServer.frame_post_draw
	var direct_draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var direct_update_start := Time.get_ticks_usec()
	for update_index: int in UPDATE_COUNT:
		var offset := sin(float(update_index) * 0.1)
		for mesh_sprite: TwberMeshSprite2D in direct_nodes:
			mesh_sprite.mesh_data.vertices[0].y = offset
			mesh_sprite.sync_deformation()
		batch_renderer.update_dynamic_geometry()
	var direct_update_usec := Time.get_ticks_usec() - direct_update_start
	var one_dirty_node: Array[Node2D] = [direct_nodes[0]]
	var partial_update_start := Time.get_ticks_usec()
	for update_index: int in UPDATE_COUNT:
		direct_nodes[0].mesh_data.vertices[0].y = sin(float(update_index) * 0.1)
		direct_nodes[0].sync_deformation()
		batch_renderer.update_dynamic_geometry_for_nodes(one_dirty_node)
	var partial_update_usec := Time.get_ticks_usec() - partial_update_start
	var direct_node_count := direct_group.get_child_count() + 2
	direct_group.free()

	var polygon_group := Node2D.new()
	viewport.add_child(polygon_group)
	var polygon_nodes: Array[Polygon2D] = []
	var triangle_polygons: Array[PackedInt32Array] = []
	var triangle_indices: PackedInt32Array = geometry["triangles"]
	for triangle_start: int in range(0, triangle_indices.size() - 2, 3):
		triangle_polygons.append(PackedInt32Array([
			triangle_indices[triangle_start],
			triangle_indices[triangle_start + 1],
			triangle_indices[triangle_start + 2],
		]))
	for layer_index: int in LAYER_COUNT:
		var layer_root := Node2D.new()
		layer_root.position = _get_layer_position(layer_index)
		polygon_group.add_child(layer_root)
		var polygon := Polygon2D.new()
		polygon.texture = texture
		polygon.polygon = geometry["vertices"].duplicate()
		polygon.uv = geometry["uvs"].duplicate()
		polygon.polygons = triangle_polygons
		layer_root.add_child(polygon)
		polygon_nodes.append(polygon)

	await process_frame
	await RenderingServer.frame_post_draw
	var polygon_draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var polygon_update_start := Time.get_ticks_usec()
	for update_index: int in UPDATE_COUNT:
		var offset := sin(float(update_index) * 0.1)
		for polygon: Polygon2D in polygon_nodes:
			var vertices := polygon.polygon
			vertices[0].y = offset
			polygon.polygon = vertices
	var polygon_update_usec := Time.get_ticks_usec() - polygon_update_start
	var polygon_node_count := 1 + polygon_group.get_child_count() + polygon_nodes.size()

	print("Twber 2D renderer benchmark")
	print("  layers: %d, vertices/layer: %d" % [LAYER_COUNT, GRID_SIZE * GRID_SIZE])
	print("  batched canvas nodes: %d" % direct_node_count)
	print("  Polygon2D-path nodes: %d" % polygon_node_count)
	print("  batched dynamic update: %.3f ms/update" % (
		float(direct_update_usec) / 1000.0 / float(UPDATE_COUNT)
	))
	print("  one dirty-layer update: %.3f ms/update" % (
		float(partial_update_usec) / 1000.0 / float(UPDATE_COUNT)
	))
	print("  Polygon2D geometry scheduling: %.3f ms/update" % (
		float(polygon_update_usec) / 1000.0 / float(UPDATE_COUNT)
	))
	print("  observed batched draw calls: %d" % direct_draw_calls)
	print("  observed Polygon2D draw calls: %d" % polygon_draw_calls)

	polygon_group.free()
	viewport.free()
	quit(0)


func _create_grid_geometry() -> Dictionary:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var triangles := PackedInt32Array()
	for row: int in GRID_SIZE:
		for column: int in GRID_SIZE:
			var point := Vector2(column, row) * 2.0
			vertices.append(point)
			uvs.append(point)
	for row: int in GRID_SIZE - 1:
		for column: int in GRID_SIZE - 1:
			var top_left := row * GRID_SIZE + column
			var top_right := top_left + 1
			var bottom_left := top_left + GRID_SIZE
			var bottom_right := bottom_left + 1
			triangles.append_array(PackedInt32Array([
				top_left, bottom_left, top_right,
				top_right, bottom_left, bottom_right,
			]))
	return {"vertices": vertices, "uvs": uvs, "triangles": triangles}


func _get_layer_position(index: int) -> Vector2:
	return Vector2(index % 20, index / 20) * 20.0
