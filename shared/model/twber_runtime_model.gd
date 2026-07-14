class_name TwberRuntimeModel extends Node2D

signal model_loaded(model: TwberModelResource)
signal parameters_evaluated(affected_layer_ids: Array[String])

@export var enable_runtime_atlases := true
@export var runtime_atlas_compression_threshold_px := 1024

var model: TwberModelResource
var _parameters_by_id: Dictionary[String, TwberParameterResource] = {}
var _parameter_values := {}
var _base_states_by_layer_id: Dictionary[String, TwberLayerStateResource] = {}
var _evaluator := TwberParameterEvaluator.new()
var _evaluation_dirty := false
var _dirty_parameter_ids := {}
var _batch_renderer: TwberModelBatchRenderer2D
var _clip_controller: TwberAlphaClipController


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	evaluate_parameters()
	set_process(false)


func load_model(path: String) -> Error:
	var loaded_model := TwberModelCodec.load_model(path)
	if loaded_model == null:
		return ERR_FILE_CORRUPT
	set_model(loaded_model)
	return OK


func set_model(value: TwberModelResource) -> void:
	_ensure_batch_renderer()
	_ensure_clip_controller()
	_batch_renderer.clear()
	_clip_controller.clear()
	model = value
	_parameters_by_id.clear()
	_parameter_values.clear()
	_base_states_by_layer_id.clear()
	_dirty_parameter_ids.clear()
	_evaluation_dirty = false
	set_process(false)
	if model == null:
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		return

	TwberModelCodec.apply_to_model_root(model, self)
	if enable_runtime_atlases and not TwberTextureAtlasBuilder.model_root_uses_atlas_textures(self):
		TwberTextureAtlasBuilder.optimize_model_root(
				self,
				runtime_atlas_compression_threshold_px,
		)
	for parameter: TwberParameterResource in model.parameters:
		if parameter == null or parameter.id.is_empty():
			continue
		_parameters_by_id[parameter.id] = parameter
		_parameter_values[parameter.id] = parameter.get_default_value()
		_dirty_parameter_ids[parameter.id] = true

	_evaluator.configure(self, model.parameters)
	_capture_base_states()
	_evaluator.set_neutral_states(_base_states_by_layer_id)
	_clip_controller.configure(self)
	_batch_renderer.configure(self)
	if not _parameters_by_id.is_empty():
		evaluate_parameters()
	elif _batch_renderer.is_batching_active():
		_batch_renderer.rebuild_now()
	model_loaded.emit(model)


func set_parameter_value(parameter_id: String, value: Variant) -> bool:
	if not _parameters_by_id.has(parameter_id):
		return false
	var parameter: TwberParameterResource = _parameters_by_id[parameter_id]
	var normalized_value: Variant = parameter.value_from_coordinate(parameter.coordinate_from_value(value))
	if _parameter_values.has(parameter_id) and _values_equal(
			_parameter_values[parameter_id],
			normalized_value,
	):
		return false
	_parameter_values[parameter_id] = normalized_value
	_dirty_parameter_ids[parameter_id] = true
	_queue_evaluation()
	return true


func set_parameter_values(values: Dictionary) -> bool:
	var changed := false
	for parameter_key: Variant in values:
		changed = set_parameter_value(String(parameter_key), values[parameter_key]) or changed
	return changed


func reset_parameter_values() -> void:
	var changed := false
	for parameter_id: String in _parameters_by_id:
		var default_value: Variant = _parameters_by_id[parameter_id].get_default_value()
		if not _parameter_values.has(parameter_id) or not _values_equal(
				_parameter_values[parameter_id],
				default_value,
		):
			_parameter_values[parameter_id] = default_value
			_dirty_parameter_ids[parameter_id] = true
			changed = true
	if changed:
		_queue_evaluation()


func evaluate_parameters() -> Array[String]:
	if model == null:
		return []
	var changed_parameter_ids: Array[String] = []
	for parameter_id: Variant in _dirty_parameter_ids:
		changed_parameter_ids.append(String(parameter_id))
	var affected_layer_ids := _evaluator.apply_changed(
			_parameter_values,
			changed_parameter_ids,
	)
	if _clip_controller != null:
		_clip_controller.sync_now(affected_layer_ids)
	_dirty_parameter_ids.clear()
	if (
			_batch_renderer != null
			and _batch_renderer.is_batching_active()
			and not affected_layer_ids.is_empty()
	):
		var affected_nodes: Array[Node2D] = []
		var layer_nodes := _evaluator.get_layer_nodes()
		for layer_id: String in affected_layer_ids:
			var node := layer_nodes.get(layer_id) as Node2D
			if node != null:
				affected_nodes.append(node)
		_batch_renderer.update_dynamic_geometry_for_nodes(affected_nodes)
	_evaluation_dirty = false
	set_process(false)
	parameters_evaluated.emit(affected_layer_ids)
	return affected_layer_ids


func get_parameter_value(parameter_id: String) -> Variant:
	return _parameter_values.get(parameter_id)


func get_parameter_values() -> Dictionary:
	return _parameter_values.duplicate()


func get_performance_summary() -> Dictionary:
	var summary := TwberModelCodec.get_model_performance_summary(model)
	if _batch_renderer != null:
		summary["runtime_batching_active"] = _batch_renderer.is_batching_active()
		summary["runtime_batches"] = _batch_renderer.get_batch_count()
	return summary


func _ensure_batch_renderer() -> void:
	if _batch_renderer != null and is_instance_valid(_batch_renderer):
		return
	_batch_renderer = TwberModelBatchRenderer2D.attach_to(self)


func _ensure_clip_controller() -> void:
	if _clip_controller != null and is_instance_valid(_clip_controller):
		return
	_clip_controller = TwberAlphaClipController.attach_to(self)


func _queue_evaluation() -> void:
	if _evaluation_dirty:
		return
	_evaluation_dirty = true
	set_process(true)


func _capture_base_states() -> void:
	_base_states_by_layer_id.clear()
	var layer_nodes := _evaluator.get_layer_nodes()
	for layer_id: String in _evaluator.get_affected_layer_ids():
		var node: Node2D = layer_nodes.get(layer_id) as Node2D
		if node == null:
			continue
		var state := TwberLayerStateResource.new()
		state.capture_from_node(node)
		_base_states_by_layer_id[layer_id] = state


func _values_equal(first: Variant, second: Variant) -> bool:
	if first is float or second is float:
		return is_equal_approx(float(first), float(second))
	if first is Vector2 and second is Vector2:
		return first.is_equal_approx(second)
	return first == second
