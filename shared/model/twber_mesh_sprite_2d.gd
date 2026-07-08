class_name TwberMeshSprite2D extends Node2D

@export var texture: Texture2D
@export var mesh_data: TwberMeshResource

var _mesh_polygon: Polygon2D


func _ready() -> void:
	_ensure_mesh_data()
	_ensure_mesh_polygon()
	sync_mesh()
	set_process(true)


func _process(_delta: float) -> void:
	if _mesh_polygon != null and is_instance_valid(_mesh_polygon):
		if _mesh_polygon.self_modulate != self_modulate:
			sync_visual_state()


func _draw() -> void:
	if texture == null:
		return

	if mesh_data != null and mesh_data.vertices.size() >= 3:
		return

	draw_texture(texture, get_texture_origin())


func has_mesh_points() -> bool:
	return mesh_data != null and mesh_data.vertices.size() > 0


func get_texture_origin() -> Vector2:
	if mesh_data != null:
		return mesh_data.texture_origin
	if texture == null:
		return Vector2.ZERO

	return -texture.get_size() * 0.5


func reset_texture_origin_from_texture() -> void:
	_ensure_mesh_data()
	if texture == null:
		mesh_data.texture_origin = Vector2.ZERO
	else:
		mesh_data.texture_origin = -texture.get_size() * 0.5
	queue_redraw()


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
	sync_mesh()


func set_deformed_vertex(index: int, vertex_position: Vector2) -> void:
	if mesh_data == null:
		return

	mesh_data.set_deformed_vertex(index, vertex_position)
	sync_mesh()


func reset_deformed_vertex(index: int) -> void:
	if mesh_data == null:
		return

	mesh_data.reset_deformed_vertex(index)
	sync_mesh()


func reset_deformation() -> void:
	if mesh_data == null:
		return

	mesh_data.reset_deformation()
	sync_mesh()


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

	return mesh_data.has_joined_edge(vertex_a, vertex_b) or _edge_exists_in_triangles(vertex_a, vertex_b)


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
	_ensure_mesh_polygon()
	mesh_data.ensure_rest_vertices()
	_sync_mesh_polygon()
	_sync_visual_state()
	queue_redraw()


func sync_visual_state() -> void:
	_ensure_mesh_polygon()
	_sync_visual_state()
	queue_redraw()


func _ensure_mesh_data() -> void:
	if mesh_data == null:
		mesh_data = TwberMeshResource.new()


func _ensure_mesh_polygon() -> void:
	if _mesh_polygon != null and is_instance_valid(_mesh_polygon):
		return

	var existing_polygon := get_node_or_null("MeshPolygon")
	if existing_polygon is Polygon2D:
		_mesh_polygon = existing_polygon
		return

	_mesh_polygon = Polygon2D.new()
	_mesh_polygon.name = "MeshPolygon"
	_mesh_polygon.show_behind_parent = false
	_mesh_polygon.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	add_child(_mesh_polygon, false, Node.INTERNAL_MODE_BACK)


func _retriangulate() -> void:
	if mesh_data == null:
		return

	mesh_data.sanitize_topology()
	if mesh_data.vertices.size() < 3:
		mesh_data.triangles = PackedInt32Array()
		return

	mesh_data.triangles = Geometry2D.triangulate_delaunay(mesh_data.vertices)
	_apply_topology_constraints()


func _sync_mesh_polygon() -> void:
	if mesh_data.vertices.size() < 3 or mesh_data.triangles.size() < 3 or texture == null:
		_mesh_polygon.visible = false
		return

	var uvs := mesh_data.uvs
	if uvs.size() != mesh_data.vertices.size():
		uvs = PackedVector2Array()
		for vertex: Vector2 in mesh_data.vertices:
			uvs.append(get_uv_for_position(vertex))
		mesh_data.uvs = uvs

	_mesh_polygon.texture = texture
	_mesh_polygon.polygon = mesh_data.vertices
	_mesh_polygon.uv = mesh_data.uvs
	_mesh_polygon.polygons = _triangles_to_polygons(mesh_data.triangles)
	_mesh_polygon.visible = true


func _sync_visual_state() -> void:
	if _mesh_polygon == null or not is_instance_valid(_mesh_polygon):
		return

	_mesh_polygon.self_modulate = self_modulate


func _triangles_to_polygons(triangles: PackedInt32Array) -> Array:
	var output: Array = []
	for index: int in range(0, triangles.size() - 2, 3):
		output.append(PackedInt32Array([
			triangles[index],
			triangles[index + 1],
			triangles[index + 2],
		]))

	return output


func _apply_topology_constraints() -> void:
	var next_triangles := PackedInt32Array()
	for index: int in range(0, mesh_data.triangles.size() - 2, 3):
		var vertex_a := int(mesh_data.triangles[index])
		var vertex_b := int(mesh_data.triangles[index + 1])
		var vertex_c := int(mesh_data.triangles[index + 2])
		if _triangle_has_cut_edge(vertex_a, vertex_b, vertex_c):
			continue
		next_triangles.append(vertex_a)
		next_triangles.append(vertex_b)
		next_triangles.append(vertex_c)

	mesh_data.triangles = next_triangles
	_add_missing_joined_edge_triangles()


func _triangle_has_cut_edge(vertex_a: int, vertex_b: int, vertex_c: int) -> bool:
	return (
			mesh_data.has_cut_edge(vertex_a, vertex_b)
			or mesh_data.has_cut_edge(vertex_b, vertex_c)
			or mesh_data.has_cut_edge(vertex_c, vertex_a)
	)


func _add_missing_joined_edge_triangles() -> void:
	for index: int in range(0, mesh_data.joined_edges.size() - 1, 2):
		var vertex_a := int(mesh_data.joined_edges[index])
		var vertex_b := int(mesh_data.joined_edges[index + 1])
		if _edge_exists_in_triangles(vertex_a, vertex_b):
			continue

		var vertex_c := _find_join_triangle_vertex(vertex_a, vertex_b)
		if vertex_c == -1 or _triangle_exists(vertex_a, vertex_b, vertex_c):
			continue

		mesh_data.triangles.append(vertex_a)
		mesh_data.triangles.append(vertex_b)
		mesh_data.triangles.append(vertex_c)


func _find_join_triangle_vertex(vertex_a: int, vertex_b: int) -> int:
	if vertex_a < 0 or vertex_b < 0 or vertex_a >= mesh_data.vertices.size() or vertex_b >= mesh_data.vertices.size():
		return -1

	var point_a := mesh_data.vertices[vertex_a]
	var point_b := mesh_data.vertices[vertex_b]
	var segment := point_b - point_a
	var midpoint := (point_a + point_b) * 0.5
	var best_index := -1
	var best_score := INF

	for index: int in mesh_data.vertices.size():
		if index == vertex_a or index == vertex_b:
			continue
		if mesh_data.has_cut_edge(vertex_a, index) or mesh_data.has_cut_edge(vertex_b, index):
			continue
		if absf(segment.cross(mesh_data.vertices[index] - point_a)) < 0.001:
			continue

		var score := midpoint.distance_squared_to(mesh_data.vertices[index])
		if score < best_score:
			best_score = score
			best_index = index

	return best_index


func _edge_exists_in_triangles(vertex_a: int, vertex_b: int) -> bool:
	for index: int in range(0, mesh_data.triangles.size() - 2, 3):
		if _triangle_contains_edge(index, vertex_a, vertex_b):
			return true

	return false


func _triangle_contains_edge(triangle_start: int, vertex_a: int, vertex_b: int) -> bool:
	var triangle_a := int(mesh_data.triangles[triangle_start])
	var triangle_b := int(mesh_data.triangles[triangle_start + 1])
	var triangle_c := int(mesh_data.triangles[triangle_start + 2])
	return (
			_edges_match(triangle_a, triangle_b, vertex_a, vertex_b)
			or _edges_match(triangle_b, triangle_c, vertex_a, vertex_b)
			or _edges_match(triangle_c, triangle_a, vertex_a, vertex_b)
	)


func _edges_match(first_a: int, first_b: int, second_a: int, second_b: int) -> bool:
	return (
			(first_a == second_a and first_b == second_b)
			or (first_a == second_b and first_b == second_a)
	)


func _triangle_exists(vertex_a: int, vertex_b: int, vertex_c: int) -> bool:
	for index: int in range(0, mesh_data.triangles.size() - 2, 3):
		if _triangles_match(
				vertex_a,
				vertex_b,
				vertex_c,
				int(mesh_data.triangles[index]),
				int(mesh_data.triangles[index + 1]),
				int(mesh_data.triangles[index + 2])
		):
			return true

	return false


func _triangles_match(
		first_a: int,
		first_b: int,
		first_c: int,
		second_a: int,
		second_b: int,
		second_c: int,
) -> bool:
	var first := [first_a, first_b, first_c]
	var second := [second_a, second_b, second_c]
	first.sort()
	second.sort()
	return first[0] == second[0] and first[1] == second[1] and first[2] == second[2]
