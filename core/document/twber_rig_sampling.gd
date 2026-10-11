class_name TwberRigSampling extends RefCounted

# Uses the same compiled sampling/composition rules as the current preview,
# without restoring or evaluating scene nodes during a Bind operation.
static func sample_others(model: TwberModelResource, layer: TwberLayerResource, values: Dictionary, excluded: String, snap: Dictionary = {}) -> TwberLayerStateResource:
	var base := TwberLayerStateResource.from_layer_resource(layer)
	var compiled := TwberParameterMapper.compile_parameters(model.parameters)
	var poses := TwberParameterMapper.sample_compiled_parameters(compiled, values, {layer.id: base}, excluded, {layer.id: true})
	var result: TwberLayerStateResource = poses.get(layer.id, base)
	if poses.has(layer.id) and bool(snap.get("pixels", false)):
		result.position = result.position.round()
		result.rotation = snappedf(result.rotation, float(snap.get("rotation", deg_to_rad(15.0))))
		result.scale = result.scale.snapped(Vector2.ONE * float(snap.get("scale", 0.05)))
		if layer.mesh != null:
			for index: int in result.mesh_vertices.size():
				result.mesh_vertices[index] = (result.mesh_vertices[index] - layer.mesh.texture_origin).round() + layer.mesh.texture_origin
	return result
