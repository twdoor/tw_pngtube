class_name TwberInputSmoothing extends RefCounted

const DRAG := -30.0


static func advance(current: Variant, target: Variant, delta: float) -> Variant:
	var weight := 1.0 - exp(DRAG * maxf(delta, 0.0))
	var value: Variant = target
	if current is Vector2 and target is Vector2:
		value = (current as Vector2).lerp(target, weight)
	elif (current is float or current is int) and (target is float or target is int):
		value = lerpf(float(current), float(target), weight)
	return target if settled(value, target) else value


static func settled(value: Variant, target: Variant) -> bool:
	if value is Vector2 and target is Vector2:
		return (value as Vector2).distance_squared_to(target) <= 0.000001
	if (value is float or value is int) and (target is float or target is int):
		return absf(float(value) - float(target)) <= 0.0005
	return value == target
