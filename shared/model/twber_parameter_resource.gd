class_name TwberParameterResource extends Resource

enum ValueType {
	BOOL,
	INT,
	FLOAT,
	VECTOR2,
}

const CONTINUOUS_STEP := 0.05
const LEGACY_CONTINUOUS_STEP := 0.01
const DISCRETE_STEP := 1.0

@export var id := ""
@export var name := ""
@export var value_type := ValueType.FLOAT
@export var default_bool := false
@export var default_int := 0
@export var default_float := 0.0
@export var default_vector2 := Vector2.ZERO
@export var min_value := 0.0
@export var max_value := 1.0
@export var min_vector2 := Vector2(-1.0, -1.0)
@export var max_vector2 := Vector2(1.0, 1.0)
@export var step := CONTINUOUS_STEP
@export var positions: Array[TwberParameterPositionResource] = []


static func normalize_step_for_type(
		parameter_type: int,
		candidate_step: float,
		migrate_legacy_continuous_step := false,
) -> float:
	if parameter_type == ValueType.BOOL or parameter_type == ValueType.INT:
		return DISCRETE_STEP

	if candidate_step <= 0.0:
		return CONTINUOUS_STEP
	if (
		migrate_legacy_continuous_step
		and is_equal_approx(candidate_step, LEGACY_CONTINUOUS_STEP)
	):
		return CONTINUOUS_STEP

	return candidate_step


func get_default_value() -> Variant:
	match value_type:
		ValueType.BOOL:
			return default_bool
		ValueType.INT:
			return int(roundf(clamp_coordinate(Vector2(default_int, 0.0)).x))
		ValueType.VECTOR2:
			return clamp_coordinate(default_vector2)
		_:
			return clamp_coordinate(Vector2(default_float, 0.0)).x


func coordinate_from_value(value: Variant) -> Vector2:
	match value_type:
		ValueType.BOOL:
			return Vector2(1.0 if bool(value) else 0.0, 0.0)
		ValueType.VECTOR2:
			return clamp_coordinate(value if value is Vector2 else Vector2.ZERO)
		_:
			var scalar := float(value) if value is int or value is float else 0.0
			return clamp_coordinate(Vector2(scalar, 0.0))


func value_from_coordinate(coordinate: Vector2) -> Variant:
	var clamped_coordinate := clamp_coordinate(coordinate)
	match value_type:
		ValueType.BOOL:
			return clamped_coordinate.x >= 0.5
		ValueType.INT:
			return int(roundf(clamped_coordinate.x))
		ValueType.VECTOR2:
			return clamped_coordinate
		_:
			return clamped_coordinate.x


func clamp_coordinate(coordinate: Vector2) -> Vector2:
	match value_type:
		ValueType.BOOL:
			return Vector2(1.0 if coordinate.x >= 0.5 else 0.0, 0.0)
		ValueType.VECTOR2:
			var range_min := get_vector_min()
			var range_max := get_vector_max()
			return Vector2(
					_snap_and_clamp(coordinate.x, range_min.x, range_max.x),
					_snap_and_clamp(coordinate.y, range_min.y, range_max.y),
			)
		_:
			var range_min := get_scalar_min()
			var range_max := get_scalar_max()
			var scalar := _snap_and_clamp(coordinate.x, range_min, range_max)
			if value_type == ValueType.INT:
				scalar = clampf(roundf(scalar), range_min, range_max)
			return Vector2(scalar, 0.0)


func coordinates_equal(first: Vector2, second: Vector2) -> bool:
	var tolerance := maxf(absf(step) * 0.25, 0.0001)
	if value_type == ValueType.VECTOR2:
		return first.distance_squared_to(second) <= tolerance * tolerance

	return absf(first.x - second.x) <= tolerance


func get_scalar_min() -> float:
	return minf(min_value, max_value)


func get_scalar_max() -> float:
	return maxf(min_value, max_value)


func get_vector_min() -> Vector2:
	return Vector2(
			minf(min_vector2.x, max_vector2.x),
			minf(min_vector2.y, max_vector2.y),
	)


func get_vector_max() -> Vector2:
	return Vector2(
			maxf(min_vector2.x, max_vector2.x),
			maxf(min_vector2.y, max_vector2.y),
	)


func find_position(coordinate: Vector2) -> TwberParameterPositionResource:
	for parameter_position: TwberParameterPositionResource in positions:
		if parameter_position != null and coordinates_equal(parameter_position.coordinate, coordinate):
			return parameter_position

	return null


func get_bound_coordinates() -> PackedVector2Array:
	var output := PackedVector2Array()
	for parameter_position: TwberParameterPositionResource in positions:
		if parameter_position != null and not parameter_position.layer_states.is_empty():
			output.append(parameter_position.coordinate)

	return output


func _snap_value(value: float, origin: float) -> float:
	if step <= 0.0:
		return value

	return origin + roundf((value - origin) / step) * step


func _snap_and_clamp(value: float, minimum: float, maximum: float) -> float:
	var clamped_value := clampf(value, minimum, maximum)
	if is_equal_approx(clamped_value, minimum):
		return minimum
	if is_equal_approx(clamped_value, maximum):
		return maximum
	return clampf(_snap_value(clamped_value, minimum), minimum, maximum)
