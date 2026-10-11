class_name TwberRuntimeModel extends Node2D

signal model_changing
signal performance_evaluated(values: Dictionary, playheads: Dictionary, sprites: Dictionary)

signal parameter_input_changed(parameter_id: String, value: Variant)

signal model_loaded(model: TwberModelResource)
signal parameters_evaluated(affected_layer_ids: Array[String])

@export var enable_runtime_atlases := true
@export var runtime_atlas_compression_threshold_px := 1024

var model: TwberModelResource
var _parameters_by_id: Dictionary[String, TwberParameterResource] = {}
var _parameter_values := {}
var _layer_nodes: Dictionary = {}
var _sprite_clock := TwberSpriteClock.new()
var _sprite_timeline := TwberSpriteTimeline.new()
var _pose_evaluator := TwberModelEvaluator.new()
var _evaluation_dirty := false
var _advancing_frame := false
var _dirty_parameter_ids := {}
var _batch_renderer: TwberModelBatchRenderer2D
var _clip_controller: TwberAlphaClipController
var _timeline_animations_by_id: Dictionary[String, TwberTimelineAnimationResource] = {}
var _active_animation_playheads: Dictionary[String, float] = {}


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_advancing_frame = true
	_sprite_clock.advance(delta)
	if _evaluation_dirty:
		evaluate_parameters()
	_refresh_active_timeline_animations()
	if not _active_animation_playheads.is_empty():
		_advance_timeline_animations(delta)
	_apply_sprite_clock()
	set_process(_evaluation_dirty or not _active_animation_playheads.is_empty() or not _sprite_clock.is_empty())
	_advancing_frame = false
	_publish_performance()


func load_model(path: String) -> Error:
	var loaded_model := TwberModelCodec.load_model(path)
	if loaded_model == null:
		return ERR_FILE_CORRUPT
	set_model(loaded_model)
	return OK


func set_model(value: TwberModelResource) -> void:
	model_changing.emit()
	_ensure_batch_renderer()
	_ensure_clip_controller()
	_batch_renderer.clear()
	_clip_controller.clear()
	model = value
	_parameters_by_id.clear()
	_parameter_values.clear()
	_layer_nodes.clear()
	_dirty_parameter_ids.clear()
	_timeline_animations_by_id.clear()
	_active_animation_playheads.clear()
	_evaluation_dirty = false
	set_process(false)
	if model == null:
		var empty := TwberModelResource.new()
		_sprite_clock.configure(empty)
		_sprite_timeline.configure(empty)
		_pose_evaluator.configure(empty)
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		model_loaded.emit(null)
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
	for animation: TwberTimelineAnimationResource in model.timeline_animations:
		if animation != null and not animation.id.is_empty():
			_timeline_animations_by_id[animation.id] = animation

	_layer_nodes = TwberParameterMapper.get_layer_nodes_by_id(self)
	_sprite_clock.configure(model)
	_sprite_timeline.configure(model)
	_pose_evaluator.configure(model)
	_clip_controller.configure(self)
	_batch_renderer.configure(self)
	if not _parameters_by_id.is_empty():
		evaluate_parameters()
	elif _batch_renderer.is_batching_active():
		_batch_renderer.rebuild_now()
	_apply_sprite_clock()
	set_process(_evaluation_dirty or not _active_animation_playheads.is_empty() or not _sprite_clock.is_empty())
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
	parameter_input_changed.emit(parameter_id, normalized_value)
	return true


func set_parameter_values(values: Dictionary) -> bool:
	var changed := false
	for parameter_key: Variant in values:
		changed = set_parameter_value(String(parameter_key), values[parameter_key]) or changed
	return changed


func reset_parameter_values() -> void:
	for parameter_id: String in _parameters_by_id:
		set_parameter_value(parameter_id, _parameters_by_id[parameter_id].get_default_value())


func evaluate_parameters() -> Array[String]:
	if model == null:
		return []
	var had_active_timelines := not _active_animation_playheads.is_empty()
	_refresh_active_timeline_animations()
	var changed_parameter_ids: Array[String] = []
	for parameter_id: Variant in _dirty_parameter_ids:
		changed_parameter_ids.append(String(parameter_id))
	var affected_layer_ids: Array[String] = []
	var targets := _pose_evaluator.layers_for_parameters(changed_parameter_ids)
	if had_active_timelines or not _active_animation_playheads.is_empty():
		affected_layer_ids = _project_pose(_pose_evaluator.evaluate(_parameter_values, _active_animation_playheads))
	elif not targets.is_empty():
		affected_layer_ids = _project_pose(_pose_evaluator.evaluate(_parameter_values, {}, targets))
	_dirty_parameter_ids.clear()
	_evaluation_dirty = false
	set_process(not _active_animation_playheads.is_empty() or not _sprite_clock.is_empty())
	_publish_performance()
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


func _refresh_active_timeline_animations() -> void:
	var should_be_active := {}
	for parameter_id: String in _parameters_by_id:
		var parameter: TwberParameterResource = _parameters_by_id[parameter_id]
		var coordinate := parameter.coordinate_from_value(_parameter_values.get(
				parameter_id,
				parameter.get_default_value(),
		))
		for binding: TwberAnimationBindingResource in parameter.animation_bindings:
			if (
				binding != null
				and _timeline_animations_by_id.has(binding.animation_id)
				and parameter.coordinates_equal(binding.coordinate, coordinate)
			):
				should_be_active[binding.animation_id] = true
	for animation_id: Variant in _active_animation_playheads.keys():
		if not should_be_active.has(animation_id):
			_active_animation_playheads.erase(animation_id)
	for animation_id: Variant in should_be_active:
		if not _active_animation_playheads.has(animation_id):
			_active_animation_playheads[animation_id] = 0.0


func _advance_timeline_animations(delta: float) -> void:
	for animation_id: String in _active_animation_playheads:
		var animation: TwberTimelineAnimationResource = _timeline_animations_by_id.get(animation_id)
		if animation == null:
			continue
		var next_time := float(_active_animation_playheads[animation_id]) + delta
		if animation.loop:
			next_time = fmod(next_time, maxf(animation.duration, 0.01))
		else:
			next_time = minf(next_time, animation.duration)
		_active_animation_playheads[animation_id] = next_time
	_apply_timeline_animations()


func _apply_timeline_animations() -> void:
	_project_pose(_pose_evaluator.evaluate(_parameter_values, _active_animation_playheads))
	_publish_performance()


func get_animation_playheads() -> Dictionary:
	return _active_animation_playheads.duplicate()


func _publish_performance() -> void:
	if not _advancing_frame and performance_evaluated.has_connections():
		performance_evaluated.emit(get_parameter_values(), get_animation_playheads(), get_sprite_states())


func _project_pose(poses: Dictionary) -> Array[String]:
	_sprite_clock.sync(poses)
	var affected: Array[String] = []
	var nodes: Array[Node2D] = []
	var layer_nodes := _layer_nodes
	for id: String in poses:
		var node := layer_nodes.get(id) as Node2D
		if node == null:
			continue
		var state: TwberLayerStateResource = poses[id]
		state.apply_to_node(node)
		TwberAlphaClipController.set_authored_self_modulate(node, state.self_modulate)
		affected.append(id)
		nodes.append(node)
	TwberSpriteFrameSampler.apply(_layer_nodes, get_sprite_states())
	if _clip_controller != null:
		_clip_controller.sync_now(affected)
	if _batch_renderer != null and _batch_renderer.is_batching_active() and not nodes.is_empty():
		_batch_renderer.update_dynamic_geometry_for_nodes(nodes)
	return affected


func _values_equal(first: Variant, second: Variant) -> bool:
	if first is float or second is float:
		return is_equal_approx(float(first), float(second))
	if first is Vector2 and second is Vector2:
		return first.is_equal_approx(second)
	return first == second


# Offline/explicit playback bypasses live trigger clocks. The caller supplies an
# exact time; sampling never advances from a previous wall-clock frame.
func seek_animation(animation_id: String, time: float) -> Error:
	if not _timeline_animations_by_id.has(animation_id) or not is_finite(time) or time < 0.0:
		return ERR_INVALID_PARAMETER
	time = minf(time, _timeline_animations_by_id[animation_id].duration)
	set_process(false)
	_active_animation_playheads.clear()
	_evaluation_dirty = false
	_dirty_parameter_ids.clear()
	_project_pose(_pose_evaluator.evaluate({}, {animation_id: time}))
	_sprite_clock.restore(_sprite_timeline.seek(animation_id, time))
	TwberSpriteFrameSampler.apply(_layer_nodes, _sprite_clock.states())
	if _batch_renderer != null and _batch_renderer.is_batching_active():
		_batch_renderer.update_dynamic_geometry()
	return OK


func get_sprite_states() -> Dictionary:
	var states := _sprite_clock.states()
	var clips: Array[TwberTimelineAnimationResource] = []
	for id: String in _active_animation_playheads:
		var clip: TwberTimelineAnimationResource = _timeline_animations_by_id[id]
		if not clip.sprite_keys.is_empty():
			clips.append(clip)
	clips.sort_custom(func(a: TwberTimelineAnimationResource, b: TwberTimelineAnimationResource) -> bool:
		return a.priority < b.priority if a.priority != b.priority else a.id < b.id)
	for clip: TwberTimelineAnimationResource in clips:
		var sampled := _sprite_timeline.seek(clip.id, _active_animation_playheads[clip.id])
		for key: TwberSpriteKeyframeResource in clip.sprite_keys:
			if sampled.has(key.layer_id):
				states[key.layer_id] = sampled[key.layer_id]
	return states


func _apply_sprite_clock() -> void:
	if _sprite_clock.is_empty():
		return
	TwberSpriteFrameSampler.apply(_layer_nodes, get_sprite_states())
	if _batch_renderer != null and _batch_renderer.is_batching_active():
		_batch_renderer.update_dynamic_geometry()
