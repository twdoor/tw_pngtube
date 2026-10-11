extends TwberInputMapping


func map_value(parameter: TwberParameterResource, configuration: Dictionary, value: Variant, _context: Dictionary = {}) -> Variant:
	if value is not float or parameter == null:
		return value
	if parameter.value_type == TwberParameterResource.ValueType.BOOL:
		return value >= float(configuration.get("threshold_db", -40.0))
	var first := float(configuration.get("minimum_db", -60.0))
	var second := float(configuration.get("maximum_db", -10.0))
	var minimum := minf(first, second)
	var maximum := maxf(first, second)
	# Equal endpoints act as a threshold rather than producing NaN.
	var amount := float(value >= maximum) if is_equal_approx(minimum, maximum) else clampf(inverse_lerp(minimum, maximum, value), 0.0, 1.0)
	var mapped := lerpf(parameter.get_scalar_min(), parameter.get_scalar_max(), amount)
	if parameter.value_type == TwberParameterResource.ValueType.INT:
		return int(roundf(mapped))
	return mapped
