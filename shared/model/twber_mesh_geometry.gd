class_name TwberMeshGeometry extends RefCounted

# Shared authoring geometry, independent of scene nodes and rendering.
static func retriangulate(mesh_data: TwberMeshResource) -> void:
	if mesh_data == null:
		return

	mesh_data.sanitize_topology()
	if mesh_data.vertices.size() < 3:
		mesh_data.triangles = PackedInt32Array()
		return

	mesh_data.triangles = Geometry2D.triangulate_delaunay(mesh_data.vertices)
	_apply_topology_constraints(mesh_data)


static func generate_grid(
		mesh_data: TwberMeshResource,
		horizontal_vertices: int,
		vertical_vertices: int,
		texture_rect: Rect2i,
) -> void:
	var columns := maxi(horizontal_vertices, 2)
	var rows := maxi(vertical_vertices, 2)
	var origin := mesh_data.texture_origin + Vector2(texture_rect.position)
	var extent := Vector2(texture_rect.size)
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var triangles := PackedInt32Array()

	for row: int in rows:
		var y := origin.y + extent.y * float(row) / float(rows - 1)
		for column: int in columns:
			var x := origin.x + extent.x * float(column) / float(columns - 1)
			var vertex_position := Vector2(x, y)
			vertices.append(vertex_position)
			uvs.append(vertex_position - mesh_data.texture_origin)

	for row: int in rows - 1:
		for column: int in columns - 1:
			var top_left := row * columns + column
			var top_right := top_left + 1
			var bottom_left := top_left + columns
			var bottom_right := bottom_left + 1
			triangles.append_array(PackedInt32Array([top_left, bottom_left, top_right]))
			triangles.append_array(PackedInt32Array([top_right, bottom_left, bottom_right]))

	mesh_data.set_vertices(vertices)
	mesh_data.uvs = uvs
	mesh_data.triangles = triangles
	mesh_data.cut_edges = PackedInt32Array()
	mesh_data.joined_edges = PackedInt32Array()


static func _apply_topology_constraints(mesh_data: TwberMeshResource) -> void:
	var next_triangles := PackedInt32Array()
	for index: int in range(0, mesh_data.triangles.size() - 2, 3):
		var vertex_a := int(mesh_data.triangles[index])
		var vertex_b := int(mesh_data.triangles[index + 1])
		var vertex_c := int(mesh_data.triangles[index + 2])
		if _triangle_has_cut_edge(mesh_data, vertex_a, vertex_b, vertex_c):
			continue
		next_triangles.append(vertex_a)
		next_triangles.append(vertex_b)
		next_triangles.append(vertex_c)

	mesh_data.triangles = next_triangles
	_add_missing_joined_edge_triangles(mesh_data)


static func _triangle_has_cut_edge(mesh_data: TwberMeshResource, vertex_a: int, vertex_b: int, vertex_c: int) -> bool:
	return (
			mesh_data.has_cut_edge(vertex_a, vertex_b)
			or mesh_data.has_cut_edge(vertex_b, vertex_c)
			or mesh_data.has_cut_edge(vertex_c, vertex_a)
	)


static func _add_missing_joined_edge_triangles(mesh_data: TwberMeshResource) -> void:
	for index: int in range(0, mesh_data.joined_edges.size() - 1, 2):
		var vertex_a := int(mesh_data.joined_edges[index])
		var vertex_b := int(mesh_data.joined_edges[index + 1])
		if _edge_exists_in_triangles(mesh_data, vertex_a, vertex_b):
			continue

		var vertex_c := _find_join_triangle_vertex(mesh_data, vertex_a, vertex_b)
		if vertex_c == -1:
			continue

		mesh_data.triangles.append(vertex_a)
		mesh_data.triangles.append(vertex_b)
		mesh_data.triangles.append(vertex_c)


static func _find_join_triangle_vertex(mesh_data: TwberMeshResource, vertex_a: int, vertex_b: int) -> int:
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


static func _edge_exists_in_triangles(mesh_data: TwberMeshResource, vertex_a: int, vertex_b: int) -> bool:
	for index: int in range(0, mesh_data.triangles.size() - 2, 3):
		if _triangle_contains_edge(mesh_data, index, vertex_a, vertex_b):
			return true

	return false


static func _triangle_contains_edge(mesh_data: TwberMeshResource, triangle_start: int, vertex_a: int, vertex_b: int) -> bool:
	var triangle_a := int(mesh_data.triangles[triangle_start])
	var triangle_b := int(mesh_data.triangles[triangle_start + 1])
	var triangle_c := int(mesh_data.triangles[triangle_start + 2])
	return (
			_edges_match(mesh_data, triangle_a, triangle_b, vertex_a, vertex_b)
			or _edges_match(mesh_data, triangle_b, triangle_c, vertex_a, vertex_b)
			or _edges_match(mesh_data, triangle_c, triangle_a, vertex_a, vertex_b)
	)


static func _edges_match(mesh_data: TwberMeshResource, first_a: int, first_b: int, second_a: int, second_b: int) -> bool:
	return (
			(first_a == second_a and first_b == second_b)
			or (first_a == second_b and first_b == second_a)
	)
