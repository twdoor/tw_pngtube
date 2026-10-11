class_name TwberTimelineKeyframeResource extends Resource

enum Interpolation { LINEAR, HOLD }

@export var interpolation := Interpolation.LINEAR
@export var time := 0.0
@export var layer_state: TwberLayerStateResource


func capture(node: Node2D, key_time: float) -> void:
	time = maxf(key_time, 0.0)
	layer_state = TwberLayerStateResource.new()
	layer_state.capture_from_node(node)

