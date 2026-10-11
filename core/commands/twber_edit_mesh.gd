class_name TwberEditMesh extends TwberDocumentCommand

enum Operation { ADD_VERTEX, REMOVE_VERTEX, MOVE_VERTICES, CUT_EDGE, JOIN_EDGE, GRID }

var _id: String
var _operation: Operation
var _positions: Dictionary[int, Vector2] = {}
var _point := Vector2.ZERO
var _first := -1
var _second := -1
var _rect := Rect2i()


func _init(id: String, operation: Operation) -> void:
	_id = id
	_operation = operation
	layer_ids = [id]
	kinds = TwberDocumentChange.Kind.REST_POSE | TwberDocumentChange.Kind.RIG | TwberDocumentChange.Kind.ANIMATION
	label = ["Add mesh vertex", "Remove mesh vertex", "Move mesh vertices", "Cut mesh edge", "Join mesh edge", "Generate mesh grid"][operation]


static func add_vertex(id: String, point: Vector2) -> TwberEditMesh:
	var command := TwberEditMesh.new(id, Operation.ADD_VERTEX)
	command._point = point
	return command


static func remove_vertex(id: String, index: int) -> TwberEditMesh:
	var command := TwberEditMesh.new(id, Operation.REMOVE_VERTEX)
	command._first = index
	return command


static func move_vertices(id: String, positions: Dictionary[int, Vector2]) -> TwberEditMesh:
	var command := TwberEditMesh.new(id, Operation.MOVE_VERTICES)
	command._positions = positions.duplicate()
	return command


static func edge(id: String, first: int, second: int, join: bool) -> TwberEditMesh:
	var command := TwberEditMesh.new(id, Operation.JOIN_EDGE if join else Operation.CUT_EDGE)
	command._first = first
	command._second = second
	return command


static func grid(id: String, columns: int, rows: int, rect: Rect2i) -> TwberEditMesh:
	var command := TwberEditMesh.new(id, Operation.GRID)
	command._first = columns
	command._second = rows
	command._rect = rect
	return command


func apply(model: TwberModelResource) -> Error:
	did_change = false
	var layer := TwberLayerHierarchy.index(model).get(_id) as TwberLayerResource
	if layer == null:
		return ERR_DOES_NOT_EXIST
	if layer.type != TwberLayerResource.LayerType.MESH_SPRITE:
		if layer.type != TwberLayerResource.LayerType.SPRITE or _operation not in [Operation.ADD_VERTEX, Operation.GRID]:
			return ERR_INVALID_PARAMETER
		if layer.flip_h or layer.flip_v:
			error_message = "Mesh conversion of flipped sprites is not supported yet; remove the sprite flip before converting"
			return ERR_UNAVAILABLE
		layer.mesh = TwberMeshResource.new()
		layer.mesh.texture_origin = layer.offset
		var texture: Texture2D = model.textures.get(layer.texture_id)
		if layer.centered and texture != null:
			layer.mesh.texture_origin -= texture.get_size() * 0.5
		layer.type = TwberLayerResource.LayerType.MESH_SPRITE
		kinds |= TwberDocumentChange.Kind.STRUCTURE
	if layer.mesh == null:
		return ERR_INVALID_DATA
	var mesh := layer.mesh
	mesh.ensure_rest_vertices()
	if mesh.uvs.size() != mesh.vertices.size():
		mesh.uvs.clear()
		for vertex: Vector2 in mesh.vertices:
			mesh.uvs.append(vertex - mesh.texture_origin)
	var states: Array[TwberLayerStateResource] = []
	for state: TwberLayerStateResource in TwberSetRestTransform.collect_states(model.parameters, model.timeline_animations, _id):
		if state.has_channel(TwberLayerStateResource.Channel.MESH):
			states.append(state)
	match _operation:
		Operation.ADD_VERTEX:
			if not _point.is_finite():
				return ERR_INVALID_PARAMETER
			mesh.add_vertex(_point, _point - mesh.texture_origin)
			for state: TwberLayerStateResource in states:
				if not state.mesh_vertices.is_empty():
					state.mesh_vertices.append(_point)
		Operation.REMOVE_VERTEX:
			if not mesh._is_valid_vertex_index(_first):
				return ERR_INVALID_PARAMETER
			mesh.remove_vertex(_first)
			for state: TwberLayerStateResource in states:
				if not state.mesh_vertices.is_empty():
					state.mesh_vertices.remove_at(_first)
		Operation.MOVE_VERTICES:
			for index: int in _positions:
				if not mesh._is_valid_vertex_index(index) or not _positions[index].is_finite():
					return ERR_INVALID_PARAMETER
			for index: int in _positions:
				var delta := _positions[index] - mesh.vertices[index]
				if delta.is_zero_approx():
					continue
				did_change = true
				mesh.set_vertex(index, _positions[index])
				mesh.uvs[index] = _positions[index] - mesh.texture_origin
				for state: TwberLayerStateResource in states:
					if not state.mesh_vertices.is_empty():
						state.mesh_vertices[index] += delta
			if not did_change:
				return OK
		Operation.CUT_EDGE, Operation.JOIN_EDGE:
			if not mesh._is_valid_edge(_first, _second):
				return ERR_INVALID_PARAMETER
			if _operation == Operation.CUT_EDGE:
				if mesh.has_cut_edge(_first, _second):
					return OK
				mesh.add_cut_edge(_first, _second)
			else:
				if mesh.has_joined_edge(_first, _second):
					return OK
				mesh.add_joined_edge(_first, _second)
		Operation.GRID:
			if _first < 2 or _second < 2 or _first > 256 or _second > 256 or _rect.size.x <= 0 or _rect.size.y <= 0:
				return ERR_INVALID_PARAMETER
			TwberMeshGeometry.generate_grid(mesh, _first, _second, _rect)
			# Explicit topology replacement retains the existing reset policy.
			for state: TwberLayerStateResource in states:
				if not state.mesh_vertices.is_empty():
					state.mesh_vertices = mesh.vertices.duplicate()
	if _operation != Operation.GRID:
		TwberMeshGeometry.retriangulate(mesh)
	if mesh.vertices.is_empty():
		layer.type = TwberLayerResource.LayerType.SPRITE
		layer.offset = mesh.texture_origin
		layer.centered = true
		var texture: Texture2D = model.textures.get(layer.texture_id)
		if texture != null:
			layer.offset += texture.get_size() * 0.5
		layer.mesh = null
		kinds |= TwberDocumentChange.Kind.STRUCTURE
	did_change = true
	return OK
