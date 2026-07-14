class_name TwberParameterPositionResource extends Resource

@export var coordinate := Vector2.ZERO
@export var layer_states: Array[TwberLayerStateResource] = []


func find_state(layer_id: String) -> TwberLayerStateResource:
	if layer_id.is_empty():
		return null

	for state: TwberLayerStateResource in layer_states:
		if state != null and state.layer_id == layer_id:
			return state

	return null


func upsert_state(state: TwberLayerStateResource) -> TwberLayerStateResource:
	if state == null or state.layer_id.is_empty():
		return null

	var stored_state := find_state(state.layer_id)
	if stored_state == null:
		stored_state = TwberLayerStateResource.new()
		layer_states.append(stored_state)

	stored_state.copy_from(state)
	return stored_state


func remove_state(layer_id: String) -> bool:
	if layer_id.is_empty():
		return false

	for index: int in range(layer_states.size() - 1, -1, -1):
		var state := layer_states[index]
		if state != null and state.layer_id == layer_id:
			layer_states.remove_at(index)
			return true

	return false
