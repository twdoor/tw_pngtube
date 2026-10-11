class_name TwberParameterKeyframeResource extends Resource

enum Interpolation { LINEAR, HOLD }

@export var parameter_id := ""
@export var time := 0.0
@export var coordinate := Vector2.ZERO
# Interpolation leaving this key. Bool/Int always hold until the next key.
@export var interpolation: Interpolation = Interpolation.LINEAR


static func sample(track: Array[TwberParameterKeyframeResource], time_position: float, parameter: TwberParameterResource) -> Variant:
	var first := track[0]
	if time_position <= first.time:
		return parameter.value_from_coordinate(first.coordinate)
	for index: int in range(1, track.size()):
		var next := track[index]
		if time_position >= next.time:
			continue
		var previous := track[index - 1]
		var coordinate := previous.coordinate
		if previous.interpolation == Interpolation.LINEAR and parameter.value_type not in [TwberParameterResource.ValueType.BOOL, TwberParameterResource.ValueType.INT]:
			coordinate = coordinate.lerp(next.coordinate, (time_position - previous.time) / (next.time - previous.time))
		return parameter.value_from_coordinate(coordinate)
	return parameter.value_from_coordinate(track[-1].coordinate)
