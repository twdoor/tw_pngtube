class_name TwberMeshResource extends Resource

@export var texture_origin := Vector2.ZERO
@export var rest_vertices: PackedVector2Array = []
@export var vertices: PackedVector2Array = []
@export var uvs: PackedVector2Array = []
@export var triangles: PackedInt32Array = []


func ensure_rest_vertices() -> void:
	if rest_vertices.size() == vertices.size():
		return

	rest_vertices = vertices.duplicate()


func set_vertices(value: PackedVector2Array) -> void:
	vertices = value
	rest_vertices = value.duplicate()


func set_vertex(index: int, position: Vector2) -> void:
	if index < 0 or index >= vertices.size():
		return

	vertices[index] = position
	if rest_vertices.size() == vertices.size():
		rest_vertices[index] = position


func add_vertex(position: Vector2, uv_position: Vector2) -> void:
	vertices.append(position)
	rest_vertices.append(position)
	uvs.append(uv_position)


func remove_vertex(index: int) -> void:
	if index < 0 or index >= vertices.size():
		return

	vertices.remove_at(index)
	if index < rest_vertices.size():
		rest_vertices.remove_at(index)
	if index < uvs.size():
		uvs.remove_at(index)
