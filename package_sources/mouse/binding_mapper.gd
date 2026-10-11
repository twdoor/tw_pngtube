extends TwberInputMapping


func map_value(_parameter: TwberParameterResource, configuration: Dictionary, value: Variant, context: Dictionary = {}) -> Variant:
	if value is not Vector2:
		return value
	var displays: Array = context.get("display_rects", [])
	if displays.is_empty():
		return Vector2.ZERO
	var index := -1
	if str(configuration.get("display_mode", "automatic")) == "fixed":
		index = int(configuration.get("display_index", -1))
	if index < 0 or index >= displays.size():
		index = clampi(int(context.get("current_display", 0)), 0, displays.size() - 1)
		for candidate: int in displays.size():
			if (displays[candidate] as Rect2).has_point(value):
				index = candidate
				break
	var rect: Rect2 = displays[index]
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ZERO
	var local: Vector2 = value - rect.position
	return Vector2(local.x / rect.size.x * 2.0 - 1.0, 1.0 - local.y / rect.size.y * 2.0).clamp(-Vector2.ONE, Vector2.ONE)
