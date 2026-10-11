class_name TwberMeshSprite2D extends Node2D

signal render_data_changed(topology_changed: bool)

@export var texture: Texture2D:
	set(value):
		if texture == value:
			return
		texture = value
		_render_mapping_dirty = true
		_request_render_refresh(true)

@export var mesh_data: TwberMeshResource:
	set(value):
		if mesh_data == value:
			return
		mesh_data = value
		_render_mapping_dirty = true
		_request_render_refresh(true)

var standalone_rendering_enabled := true:
	set(value):
		if standalone_rendering_enabled == value:
			return
		standalone_rendering_enabled = value
		queue_redraw()

var _render_mapping_dirty := true
var _cached_render_texture: Texture2D
var _cached_render_uvs := PackedVector2Array()
var _cached_source_texture_id := 0
var _cached_atlas_texture_id := 0
var _cached_atlas_region := Rect2()


func _ready() -> void:
	_remove_legacy_polygon_child()
	sync_mesh()


func _draw() -> void:
	if not standalone_rendering_enabled:
		return
	if texture == null:
		return

	if _can_draw_mesh():
		_draw_mesh_triangles()
		return
	if mesh_data != null and mesh_data.vertices.size() >= 3 and not mesh_data.cut_edges.is_empty():
		return

	draw_texture(texture, get_texture_origin())


func has_mesh_points() -> bool:
	return mesh_data != null and mesh_data.vertices.size() > 0


func get_texture_origin() -> Vector2:
	if mesh_data != null:
		return mesh_data.texture_origin
	if texture == null:
		return Vector2.ZERO

	return TwberTextureUtils.get_logical_texture_origin(texture)


func reset_texture_origin_from_texture() -> void:
	_ensure_mesh_data()
	if texture == null:
		mesh_data.texture_origin = Vector2.ZERO
	else:
		mesh_data.texture_origin = TwberTextureUtils.get_logical_texture_origin(texture)
	queue_redraw()


func replace_texture(value: Texture2D) -> void:
	var previous_default_origin := TwberTextureUtils.get_logical_texture_origin(texture)
	texture = value
	if mesh_data == null:
		reset_texture_origin_from_texture()
		sync_mesh()
		return

	var next_default_origin := TwberTextureUtils.get_logical_texture_origin(texture)
	var custom_origin_delta := mesh_data.texture_origin - previous_default_origin
	mesh_data.texture_origin = next_default_origin + custom_origin_delta
	mesh_data.uvs = PackedVector2Array()
	var uv_vertices := (
			mesh_data.rest_vertices
			if mesh_data.rest_vertices.size() == mesh_data.vertices.size()
			else mesh_data.vertices
	)
	for vertex: Vector2 in uv_vertices:
		mesh_data.uvs.append(vertex - mesh_data.texture_origin)
	sync_mesh()


func shift_local_geometry(offset: Vector2) -> void:
	if mesh_data == null:
		return

	mesh_data.texture_origin += offset
	for index: int in mesh_data.vertices.size():
		mesh_data.vertices[index] += offset
	for index: int in mesh_data.rest_vertices.size():
		mesh_data.rest_vertices[index] += offset
	sync_mesh()


func add_vertex(vertex_position: Vector2) -> void:
	_ensure_mesh_data()
	mesh_data.add_vertex(vertex_position, get_uv_for_position(vertex_position))
	_retriangulate()
	sync_mesh()


func generate_grid_mesh(horizontal_vertices: int, vertical_vertices: int, texture_rect: Rect2i) -> void:
	if texture == null:
		return
	_ensure_mesh_data()
	TwberMeshGeometry.generate_grid(mesh_data, horizontal_vertices, vertical_vertices, texture_rect)
	sync_mesh()


func remove_vertex(index: int) -> void:
	if mesh_data == null:
		return

	mesh_data.remove_vertex(index)
	_retriangulate()
	sync_mesh()


func set_vertex(index: int, vertex_position: Vector2) -> void:
	if mesh_data == null:
		return

	mesh_data.set_vertex(index, vertex_position)
	if index >= 0 and index < mesh_data.uvs.size():
		mesh_data.uvs[index] = get_uv_for_position(vertex_position)
	_retriangulate()
	sync_mesh()


func set_deformed_vertex(index: int, vertex_position: Vector2) -> void:
	if mesh_data == null:
		return
	if index < 0 or index >= mesh_data.vertices.size():
		return
	if mesh_data.vertices[index].is_equal_approx(vertex_position):
		return

	mesh_data.set_deformed_vertex(index, vertex_position)
	sync_deformation()


func reset_deformed_vertex(index: int) -> void:
	if mesh_data == null:
		return
	if (
			index < 0
			or index >= mesh_data.vertices.size()
			or index >= mesh_data.rest_vertices.size()
			or mesh_data.vertices[index].is_equal_approx(mesh_data.rest_vertices[index])
	):
		return

	mesh_data.reset_deformed_vertex(index)
	sync_deformation()


func reset_deformation() -> void:
	if mesh_data == null:
		return
	mesh_data.ensure_rest_vertices()
	var changed := false
	for index: int in mesh_data.vertices.size():
		if not mesh_data.vertices[index].is_equal_approx(mesh_data.rest_vertices[index]):
			changed = true
			break
	if not changed:
		return

	mesh_data.reset_deformation()
	sync_deformation()


func cut_edge(vertex_a: int, vertex_b: int) -> void:
	if mesh_data == null:
		return

	mesh_data.add_cut_edge(vertex_a, vertex_b)
	_retriangulate()
	sync_mesh()


func join_edge(vertex_a: int, vertex_b: int) -> void:
	if mesh_data == null:
		return

	mesh_data.add_joined_edge(vertex_a, vertex_b)
	_retriangulate()
	sync_mesh()


func has_mesh_edge(vertex_a: int, vertex_b: int) -> bool:
	if mesh_data == null:
		return false

	return mesh_data.has_joined_edge(vertex_a, vertex_b) or TwberMeshGeometry._edge_exists_in_triangles(mesh_data, vertex_a, vertex_b)


func get_vertex_count() -> int:
	if mesh_data == null:
		return 0

	return mesh_data.vertices.size()


func get_vertex(index: int) -> Vector2:
	if mesh_data == null or index < 0 or index >= mesh_data.vertices.size():
		return Vector2.ZERO

	return mesh_data.vertices[index]


func get_uv_for_position(vertex_position: Vector2) -> Vector2:
	return vertex_position - get_texture_origin()


func sync_mesh() -> void:
	_ensure_mesh_data()
	mesh_data.ensure_rest_vertices()
	mesh_data.sanitize_topology()
	_render_mapping_dirty = true
	_request_render_refresh(true)


func sync_visual_state() -> void:
	# This node owns the triangle draw command, so CanvasItem modulation and
	# visibility are applied directly without rebuilding geometry.
	render_data_changed.emit(false)


func sync_deformation() -> void:
	_ensure_mesh_data()
	_request_render_refresh(false)


func _request_render_refresh(topology_changed: bool) -> void:
	if standalone_rendering_enabled:
		queue_redraw()
	render_data_changed.emit(topology_changed)


func _ensure_mesh_data() -> void:
	if mesh_data == null:
		mesh_data = TwberMeshResource.new()


func _retriangulate() -> void:
	TwberMeshGeometry.retriangulate(mesh_data)

func _can_draw_mesh() -> bool:
	return (
			get_render_texture() != null
			and mesh_data != null
			and mesh_data.vertices.size() >= 3
			and mesh_data.triangles.size() >= 3
	)


func _draw_mesh_triangles() -> void:
	var uvs := mesh_data.uvs
	if uvs.size() != mesh_data.vertices.size():
		uvs = PackedVector2Array()
		for vertex: Vector2 in mesh_data.vertices:
			uvs.append(get_uv_for_position(vertex))
		mesh_data.uvs = uvs
		_render_mapping_dirty = true

	RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(),
			mesh_data.triangles,
			mesh_data.vertices,
			PackedColorArray([Color.WHITE]),
			get_render_uvs(),
			PackedInt32Array(),
			PackedFloat32Array(),
			get_render_texture().get_rid(),
			-1,
	)


func get_render_texture() -> Texture2D:
	_update_render_mapping_cache()
	return _cached_render_texture


func get_render_uvs() -> PackedVector2Array:
	_update_render_mapping_cache()
	return _cached_render_uvs


func _update_render_mapping_cache() -> void:
	var source_texture_id := texture.get_instance_id() if texture != null else 0
	var atlas_texture_id := 0
	var atlas_region := Rect2()
	if texture is AtlasTexture:
		var atlas_texture: AtlasTexture = texture
		atlas_region = atlas_texture.region
		if atlas_texture.atlas != null:
			atlas_texture_id = atlas_texture.atlas.get_instance_id()

	if (
			not _render_mapping_dirty
			and source_texture_id == _cached_source_texture_id
			and atlas_texture_id == _cached_atlas_texture_id
			and atlas_region == _cached_atlas_region
	):
		return

	_cached_source_texture_id = source_texture_id
	_cached_atlas_texture_id = atlas_texture_id
	_cached_atlas_region = atlas_region
	_cached_render_texture = texture
	var uv_offset := Vector2.ZERO
	if texture is AtlasTexture:
		var atlas_texture: AtlasTexture = texture
		_cached_render_texture = atlas_texture.atlas
		uv_offset = atlas_texture.region.position
	_cached_render_uvs = PackedVector2Array()
	if mesh_data != null and _cached_render_texture != null:
		var render_texture_size := _cached_render_texture.get_size()
		if render_texture_size.x > 0.0 and render_texture_size.y > 0.0:
			_cached_render_uvs.resize(mesh_data.uvs.size())
			for index: int in mesh_data.uvs.size():
				_cached_render_uvs[index] = (
						(mesh_data.uvs[index] + uv_offset)
						/ render_texture_size
				)
	_render_mapping_dirty = false


func _remove_legacy_polygon_child() -> void:
	var legacy_polygon := get_node_or_null("MeshPolygon")
	if legacy_polygon is not Polygon2D:
		return
	remove_child(legacy_polygon)
	legacy_polygon.queue_free()
