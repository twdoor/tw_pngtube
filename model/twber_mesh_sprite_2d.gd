class_name TwberMeshSprite2D extends Node2D

const TwberMeshResourceScript := preload("res://model/twber_mesh_resource.gd")

@export var texture: Texture2D
@export var mesh_data: TwberMeshResource

var _mesh_polygon: Polygon2D


func _ready() -> void:
	_ensure_mesh_data()
	_ensure_mesh_polygon()
	sync_mesh()


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
	queue_redraw()


func _ensure_mesh_data() -> void:
	if mesh_data == null:
		mesh_data = TwberMeshResourceScript.new()


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

	if mesh_data.vertices.size() < 3:
		mesh_data.triangles = PackedInt32Array()
		return

	mesh_data.triangles = Geometry2D.triangulate_delaunay(mesh_data.vertices)


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


func _triangles_to_polygons(triangles: PackedInt32Array) -> Array:
	var output: Array = []
	for index: int in range(0, triangles.size() - 2, 3):
		output.append(PackedInt32Array([
			triangles[index],
			triangles[index + 1],
			triangles[index + 2],
		]))

	return output
