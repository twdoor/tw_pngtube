class_name TwberMeshResource extends Resource

@export var texture_origin := Vector2.ZERO
@export var rest_vertices: PackedVector2Array = []
@export var vertices: PackedVector2Array = []
@export var uvs: PackedVector2Array = []
@export var triangles: PackedInt32Array = []
@export var cut_edges: PackedInt32Array = []
@export var joined_edges: PackedInt32Array = []


func ensure_rest_vertices() -> void:
	if rest_vertices.size() == vertices.size():
		return

	rest_vertices = vertices.duplicate()


func set_vertices(value: PackedVector2Array) -> void:
	vertices = value
	rest_vertices = value.duplicate()
	sanitize_topology()


func set_vertex(index: int, position: Vector2) -> void:
	if not _is_valid_vertex_index(index):
		return

	vertices[index] = position
	if rest_vertices.size() == vertices.size():
		rest_vertices[index] = position


func set_deformed_vertex(index: int, vertex_position: Vector2) -> void:
	if not _is_valid_vertex_index(index):
		return

	ensure_rest_vertices()
	vertices[index] = vertex_position


func reset_deformed_vertex(index: int) -> void:
	if not _is_valid_vertex_index(index):
		return

	ensure_rest_vertices()
	vertices[index] = rest_vertices[index]


func reset_deformation() -> void:
	ensure_rest_vertices()
	vertices = rest_vertices.duplicate()


func add_vertex(position: Vector2, uv_position: Vector2) -> void:
	vertices.append(position)
	rest_vertices.append(position)
	uvs.append(uv_position)


func remove_vertex(index: int) -> void:
	if not _is_valid_vertex_index(index):
		return

	vertices.remove_at(index)
	if index < rest_vertices.size():
		rest_vertices.remove_at(index)
	if index < uvs.size():
		uvs.remove_at(index)

	_remove_topology_edges_for_vertex(index)


func add_cut_edge(vertex_a: int, vertex_b: int) -> void:
	if not _is_valid_edge(vertex_a, vertex_b):
		return

	joined_edges = _remove_edge(joined_edges, vertex_a, vertex_b)
	if not has_cut_edge(vertex_a, vertex_b):
		cut_edges = _append_edge(cut_edges, vertex_a, vertex_b)


func add_joined_edge(vertex_a: int, vertex_b: int) -> void:
	if not _is_valid_edge(vertex_a, vertex_b):
		return

	cut_edges = _remove_edge(cut_edges, vertex_a, vertex_b)
	if not has_joined_edge(vertex_a, vertex_b):
		joined_edges = _append_edge(joined_edges, vertex_a, vertex_b)


func has_cut_edge(vertex_a: int, vertex_b: int) -> bool:
	return _has_edge(cut_edges, vertex_a, vertex_b)


func has_joined_edge(vertex_a: int, vertex_b: int) -> bool:
	return _has_edge(joined_edges, vertex_a, vertex_b)


func sanitize_topology() -> void:
	triangles = _sanitize_triangles(triangles)
	joined_edges = _sanitize_edges(joined_edges)
	cut_edges = _sanitize_edges(cut_edges)

	var next_cut_edges := PackedInt32Array()
	for index: int in range(0, cut_edges.size() - 1, 2):
		var vertex_a := int(cut_edges[index])
		var vertex_b := int(cut_edges[index + 1])
		if has_joined_edge(vertex_a, vertex_b):
			continue
		next_cut_edges.append(vertex_a)
		next_cut_edges.append(vertex_b)
	cut_edges = next_cut_edges


func _remove_topology_edges_for_vertex(removed_index: int) -> void:
	cut_edges = _remove_or_shift_edges_for_vertex(cut_edges, removed_index)
	joined_edges = _remove_or_shift_edges_for_vertex(joined_edges, removed_index)


func _is_valid_edge(vertex_a: int, vertex_b: int) -> bool:
	return (
			vertex_a != vertex_b
			and _is_valid_vertex_index(vertex_a)
			and _is_valid_vertex_index(vertex_b)
	)


func _is_valid_vertex_index(index: int) -> bool:
	return index >= 0 and index < vertices.size()


func _append_edge(edges: PackedInt32Array, vertex_a: int, vertex_b: int) -> PackedInt32Array:
	edges.append(mini(vertex_a, vertex_b))
	edges.append(maxi(vertex_a, vertex_b))
	return edges


func _has_edge(edges: PackedInt32Array, vertex_a: int, vertex_b: int) -> bool:
	var first := mini(vertex_a, vertex_b)
	var second := maxi(vertex_a, vertex_b)
	for index: int in range(0, edges.size() - 1, 2):
		if int(edges[index]) == first and int(edges[index + 1]) == second:
			return true

	return false


func _remove_edge(edges: PackedInt32Array, vertex_a: int, vertex_b: int) -> PackedInt32Array:
	var first := mini(vertex_a, vertex_b)
	var second := maxi(vertex_a, vertex_b)
	var output := PackedInt32Array()
	for index: int in range(0, edges.size() - 1, 2):
		var edge_a := int(edges[index])
		var edge_b := int(edges[index + 1])
		if edge_a == first and edge_b == second:
			continue
		output.append(edge_a)
		output.append(edge_b)

	return output


func _sanitize_edges(edges: PackedInt32Array) -> PackedInt32Array:
	var output := PackedInt32Array()
	for index: int in range(0, edges.size() - 1, 2):
		var vertex_a := int(edges[index])
		var vertex_b := int(edges[index + 1])
		if not _is_valid_edge(vertex_a, vertex_b):
			continue
		if _has_edge(output, vertex_a, vertex_b):
			continue
		output = _append_edge(output, vertex_a, vertex_b)

	return output


func _sanitize_triangles(value: PackedInt32Array) -> PackedInt32Array:
	var output := PackedInt32Array()
	for index: int in range(0, value.size() - 2, 3):
		var vertex_a := int(value[index])
		var vertex_b := int(value[index + 1])
		var vertex_c := int(value[index + 2])
		if (
				not _is_valid_vertex_index(vertex_a)
				or not _is_valid_vertex_index(vertex_b)
				or not _is_valid_vertex_index(vertex_c)
				or vertex_a == vertex_b
				or vertex_b == vertex_c
				or vertex_c == vertex_a
		):
			continue

		output.append(vertex_a)
		output.append(vertex_b)
		output.append(vertex_c)

	return output


func _remove_or_shift_edges_for_vertex(edges: PackedInt32Array, removed_index: int) -> PackedInt32Array:
	var output := PackedInt32Array()
	for index: int in range(0, edges.size() - 1, 2):
		var vertex_a := int(edges[index])
		var vertex_b := int(edges[index + 1])
		if vertex_a == removed_index or vertex_b == removed_index:
			continue
		if vertex_a > removed_index:
			vertex_a -= 1
		if vertex_b > removed_index:
			vertex_b -= 1
		if vertex_a == vertex_b:
			continue
		if _has_edge(output, vertex_a, vertex_b):
			continue
		output = _append_edge(output, vertex_a, vertex_b)

	return output
