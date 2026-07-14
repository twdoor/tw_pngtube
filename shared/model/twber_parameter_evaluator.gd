class_name TwberParameterEvaluator extends RefCounted

var _model_root: Node
var _parameters: Array[TwberParameterResource] = []
var _compiled_data: Dictionary = {}
var _layer_nodes: Dictionary = {}
var _neutral_states_by_layer_id: Dictionary = {}


func configure(
		model_root: Node,
		parameters: Array[TwberParameterResource],
) -> void:
	_model_root = model_root
	_parameters = parameters
	_layer_nodes = TwberParameterMapper.get_layer_nodes_by_id(model_root)
	_compiled_data = TwberParameterMapper.compile_parameters(parameters)
	_neutral_states_by_layer_id.clear()


func update_parameters(parameters: Array[TwberParameterResource]) -> void:
	_parameters = parameters
	_compiled_data = TwberParameterMapper.compile_parameters(parameters)


func refresh_layer_nodes() -> void:
	_layer_nodes = TwberParameterMapper.get_layer_nodes_by_id(_model_root)


func set_neutral_states(states_by_layer_id: Dictionary) -> void:
	# Runtime models own immutable neutral states. Reusing them avoids capturing
	# every affected node and allocating another full mesh snapshot each frame.
	_neutral_states_by_layer_id = states_by_layer_id


func clear_neutral_states() -> void:
	_neutral_states_by_layer_id.clear()


func apply(parameter_values: Dictionary, excluded_parameter_id := "") -> Array[String]:
	if _model_root == null:
		return []
	return TwberParameterMapper.apply_compiled_parameters(
			_compiled_data,
			parameter_values,
			_layer_nodes,
			excluded_parameter_id,
			_neutral_states_by_layer_id,
	)


func apply_changed(
		parameter_values: Dictionary,
		changed_parameter_ids: Array[String],
) -> Array[String]:
	if changed_parameter_ids.is_empty():
		return []
	if _neutral_states_by_layer_id.is_empty():
		return apply(parameter_values)

	var changed_ids := {}
	for parameter_id: String in changed_parameter_ids:
		changed_ids[parameter_id] = true
	var target_layer_ids := {}
	for entry: Dictionary in _compiled_data.get("entries", []):
		var parameter := entry.get("parameter") as TwberParameterResource
		if parameter == null or not changed_ids.has(parameter.id):
			continue
		for layer_id: Variant in (entry.get("layers", {}) as Dictionary):
			target_layer_ids[String(layer_id)] = true
	if target_layer_ids.is_empty():
		return []

	return TwberParameterMapper.apply_compiled_parameters(
			_compiled_data,
			parameter_values,
			_layer_nodes,
			"",
			_neutral_states_by_layer_id,
			target_layer_ids,
	)


func get_layer_nodes() -> Dictionary:
	return _layer_nodes


func get_compiled_data() -> Dictionary:
	return _compiled_data


func get_affected_layer_ids() -> Array[String]:
	var output: Array[String] = []
	for layer_id: Variant in _compiled_data.get("affected_layer_ids", []):
		output.append(String(layer_id))
	return output
