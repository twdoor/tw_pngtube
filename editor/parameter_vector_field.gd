class_name ParameterVectorField extends Control

signal value_changed(value: Vector2)

const DEFAULT_MINIMUM_SIZE := Vector2(180.0, 150.0)
const HORIZONTAL_PADDING := 14.0
const TOP_PADDING := 20.0
const BOTTOM_PADDING := 24.0
const BOUND_MARKER_RADIUS := 4.0
const ACTIVE_MARKER_RADIUS := 7.0
const MARKER_SNAP_RADIUS := 10.0

var _minimum_value := Vector2(-1.0, -1.0)
var _maximum_value := Vector2.ONE
var _step := Vector2.ONE * TwberParameterResource.CONTINUOUS_STEP
var _integer_mode := false
var _active_value := Vector2.ZERO
var _bound_markers: Array[Vector2] = []
var _dragging := false


func _init() -> void:
	custom_minimum_size = DEFAULT_MINIMUM_SIZE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func configure(
		minimum_value: Vector2,
		maximum_value: Vector2,
		value_step: Variant = TwberParameterResource.CONTINUOUS_STEP,
		use_integers: bool = false,
) -> void:
	_integer_mode = use_integers
	_set_range_values(minimum_value, maximum_value)
	_set_step_value(value_step)
	_normalize_state()


func set_range(minimum_value: Vector2, maximum_value: Vector2) -> void:
	_set_range_values(minimum_value, maximum_value)
	_normalize_state()


func set_step(value_step: Variant) -> void:
	_set_step_value(value_step)
	_normalize_state()


func set_integer_mode(enabled: bool) -> void:
	if _integer_mode == enabled:
		return

	_integer_mode = enabled
	_set_range_values(_minimum_value, _maximum_value)
	_set_step_value(_step)
	_normalize_state()


func set_active_value(value: Vector2, emit_change := false) -> void:
	_update_active_value(value, emit_change, emit_change)


func get_active_value() -> Vector2:
	return _active_value


func set_bound_markers(markers: Variant) -> void:
	_bound_markers.clear()
	if markers is not Array and markers is not PackedVector2Array:
		_update_presentation()
		return

	for marker: Variant in markers:
		if marker is not Vector2:
			continue
		_append_unique_marker(_quantize_value(marker))

	_update_presentation()


func get_bound_markers() -> Array[Vector2]:
	return _bound_markers.duplicate()


func _draw() -> void:
	var background_color := _theme_color_or_default(
			&"base_color",
			&"Editor",
			Color(0.08, 0.09, 0.11, 0.92),
	)
	var border_color := _theme_color_or_default(
			&"font_disabled_color",
			&"Label",
			Color(0.52, 0.55, 0.62, 0.9),
	)
	var field_color := _theme_color_or_default(
			&"font_color",
			&"Label",
			Color(0.88, 0.9, 0.95),
	)
	var accent_color := _theme_color_or_default(
			&"accent_color",
			&"Editor",
			Color(0.25, 0.7, 1.0),
	)

	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)
	draw_rect(
			Rect2(Vector2(0.5, 0.5), (size - Vector2.ONE).max(Vector2.ZERO)),
			accent_color if has_focus() else border_color,
			false,
			2.0 if has_focus() else 1.0,
	)

	var field_rect := _get_field_rect()
	draw_rect(field_rect, field_color, false, 2.0)
	var guide_color := Color(field_color, 0.22)
	draw_line(
			Vector2(field_rect.position.x + field_rect.size.x * 0.5, field_rect.position.y),
			Vector2(field_rect.position.x + field_rect.size.x * 0.5, field_rect.end.y),
			guide_color,
			1.0,
	)
	draw_line(
			Vector2(field_rect.position.x, field_rect.position.y + field_rect.size.y * 0.5),
			Vector2(field_rect.end.x, field_rect.position.y + field_rect.size.y * 0.5),
			guide_color,
			1.0,
	)

	for marker: Vector2 in _bound_markers:
		draw_circle(_value_to_position(marker), BOUND_MARKER_RADIUS, accent_color, true, -1.0, true)

	var active_position := _value_to_position(_active_value)
	var active_is_bound := _has_bound_marker(_active_value)
	draw_circle(
			active_position,
			ACTIVE_MARKER_RADIUS,
			accent_color if active_is_bound else background_color,
			true,
			-1.0,
			true,
	)
	draw_arc(active_position, ACTIVE_MARKER_RADIUS, 0.0, TAU, 24, accent_color, 2.0, true)
	draw_circle(
			active_position,
			2.0,
			background_color if active_is_bound else accent_color,
			true,
			-1.0,
			true,
	)
	_draw_range_labels(field_rect)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			grab_focus()
			_set_value_from_pointer(event.position, true)
		accept_event()
		return

	if event is InputEventMouseMotion and _dragging:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_dragging = false
			return
		_set_value_from_pointer(event.position, false)
		accept_event()
		return

	if event is not InputEventKey or not event.pressed:
		return

	var keyboard_step := _get_keyboard_step()
	if event.shift_pressed:
		keyboard_step *= 10.0

	var next_value := _active_value
	var handled := true
	match event.keycode:
		KEY_LEFT:
			next_value.x -= keyboard_step.x
		KEY_RIGHT:
			next_value.x += keyboard_step.x
		KEY_DOWN:
			next_value.y -= keyboard_step.y
		KEY_UP:
			next_value.y += keyboard_step.y
		KEY_HOME:
			next_value = _minimum_value
		KEY_END:
			next_value = _maximum_value
		_:
			handled = false

	if handled:
		_update_active_value(next_value, true, true)
		accept_event()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_RESIZED, NOTIFICATION_THEME_CHANGED, NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
		queue_redraw()


func _set_range_values(minimum_value: Vector2, maximum_value: Vector2) -> void:
	_minimum_value = Vector2(
			minf(minimum_value.x, maximum_value.x),
			minf(minimum_value.y, maximum_value.y),
	)
	_maximum_value = Vector2(
			maxf(minimum_value.x, maximum_value.x),
			maxf(minimum_value.y, maximum_value.y),
	)
	if _integer_mode:
		_minimum_value = _minimum_value.round()
		_maximum_value = _maximum_value.round()


func _set_step_value(value_step: Variant) -> void:
	if value_step is Vector2:
		_step = Vector2(absf(value_step.x), absf(value_step.y))
	elif value_step is int or value_step is float:
		var scalar_step := absf(float(value_step))
		_step = Vector2(scalar_step, scalar_step)
	else:
		return

	if _integer_mode:
		_step = Vector2(
				maxf(roundf(_step.x), 1.0),
				maxf(roundf(_step.y), 1.0),
		)


func _normalize_state() -> void:
	_active_value = _quantize_value(_active_value)
	var previous_markers := _bound_markers.duplicate()
	_bound_markers.clear()
	for marker: Vector2 in previous_markers:
		_append_unique_marker(_quantize_value(marker))
	_update_presentation()


func _append_unique_marker(marker: Vector2) -> void:
	for existing_marker: Vector2 in _bound_markers:
		if existing_marker.is_equal_approx(marker):
			return
	_bound_markers.append(marker)


func _has_bound_marker(value: Vector2) -> bool:
	for marker: Vector2 in _bound_markers:
		if marker.is_equal_approx(value):
			return true
	return false


func _set_value_from_pointer(pointer_position: Vector2, emit_if_unchanged: bool) -> void:
	var snapped_marker: Variant = _get_nearby_marker(pointer_position)
	var value := _position_to_value(pointer_position)
	if snapped_marker is Vector2:
		value = snapped_marker
	_update_active_value(value, true, emit_if_unchanged)


func _get_nearby_marker(pointer_position: Vector2) -> Variant:
	var closest_marker: Variant = null
	var closest_distance := MARKER_SNAP_RADIUS
	for marker: Vector2 in _bound_markers:
		var distance := pointer_position.distance_to(_value_to_position(marker))
		if distance <= closest_distance:
			closest_marker = marker
			closest_distance = distance
	return closest_marker


func _update_active_value(value: Vector2, emit_change: bool, emit_if_unchanged: bool) -> void:
	var normalized_value := _quantize_value(value)
	var changed := not normalized_value.is_equal_approx(_active_value)
	_active_value = normalized_value
	_update_presentation()
	if emit_change and (changed or emit_if_unchanged):
		value_changed.emit(_active_value)


func _quantize_value(value: Vector2) -> Vector2:
	return Vector2(
			_quantize_component(value.x, _minimum_value.x, _maximum_value.x, _step.x),
			_quantize_component(value.y, _minimum_value.y, _maximum_value.y, _step.y),
	)


func _quantize_component(value: float, minimum: float, maximum: float, value_step: float) -> float:
	if is_equal_approx(minimum, maximum):
		return minimum

	var output := clampf(value, minimum, maximum)
	if is_equal_approx(output, minimum) or is_equal_approx(output, maximum):
		return output
	if value_step > 0.0:
		output = minimum + roundf((output - minimum) / value_step) * value_step
	if _integer_mode:
		output = roundf(output)
	return clampf(output, minimum, maximum)


func _position_to_value(pointer_position: Vector2) -> Vector2:
	var field_rect := _get_field_rect()
	var x_weight := 0.5
	var y_weight := 0.5
	if field_rect.size.x > 0.0:
		x_weight = inverse_lerp(field_rect.position.x, field_rect.end.x, clampf(
				pointer_position.x,
				field_rect.position.x,
				field_rect.end.x,
		))
	if field_rect.size.y > 0.0:
		y_weight = 1.0 - inverse_lerp(field_rect.position.y, field_rect.end.y, clampf(
				pointer_position.y,
				field_rect.position.y,
				field_rect.end.y,
		))
	return _quantize_value(Vector2(
			lerpf(_minimum_value.x, _maximum_value.x, x_weight),
			lerpf(_minimum_value.y, _maximum_value.y, y_weight),
	))


func _value_to_position(value: Vector2) -> Vector2:
	var field_rect := _get_field_rect()
	var x_weight := 0.5
	var y_weight := 0.5
	if not is_equal_approx(_minimum_value.x, _maximum_value.x):
		x_weight = inverse_lerp(
				_minimum_value.x,
				_maximum_value.x,
				clampf(value.x, _minimum_value.x, _maximum_value.x),
		)
	if not is_equal_approx(_minimum_value.y, _maximum_value.y):
		y_weight = inverse_lerp(
				_minimum_value.y,
				_maximum_value.y,
				clampf(value.y, _minimum_value.y, _maximum_value.y),
		)
	return Vector2(
			lerpf(field_rect.position.x, field_rect.end.x, x_weight),
			lerpf(field_rect.end.y, field_rect.position.y, y_weight),
	)


func _get_field_rect() -> Rect2:
	var left := minf(HORIZONTAL_PADDING, size.x * 0.5)
	var right := maxf(left, size.x - HORIZONTAL_PADDING)
	var top := minf(TOP_PADDING, size.y * 0.5)
	var bottom := maxf(top, size.y - BOTTOM_PADDING)
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _get_keyboard_step() -> Vector2:
	var fallback_step := Vector2(
			maxf(
					(_maximum_value.x - _minimum_value.x) / 100.0,
					TwberParameterResource.CONTINUOUS_STEP,
			),
			maxf(
					(_maximum_value.y - _minimum_value.y) / 100.0,
					TwberParameterResource.CONTINUOUS_STEP,
			),
	)
	return Vector2(
			_step.x if _step.x > 0.0 else (1.0 if _integer_mode else fallback_step.x),
			_step.y if _step.y > 0.0 else (1.0 if _integer_mode else fallback_step.y),
	)


func _draw_range_labels(field_rect: Rect2) -> void:
	var font := get_theme_default_font()
	if font == null:
		return

	var font_size := mini(get_theme_default_font_size(), 13)
	var label_color := _theme_color_or_default(
			&"font_color",
			&"Label",
			Color(0.88, 0.9, 0.95),
	)
	var half_width := maxf(field_rect.size.x * 0.5, 0.0)
	var top_baseline := maxf(float(font_size), field_rect.position.y - 5.0)
	var bottom_baseline := minf(size.y - 4.0, field_rect.end.y + float(font_size) + 4.0)
	draw_string(
			font,
			Vector2(field_rect.position.x, bottom_baseline),
			_format_value(_minimum_value),
			HORIZONTAL_ALIGNMENT_LEFT,
			half_width,
			font_size,
			label_color,
	)
	draw_string(
			font,
			Vector2(field_rect.position.x + half_width, top_baseline),
			_format_value(_maximum_value),
			HORIZONTAL_ALIGNMENT_RIGHT,
			half_width,
			font_size,
			label_color,
	)


func _format_value(value: Vector2) -> String:
	if _integer_mode:
		return "(%d, %d)" % [int(roundf(value.x)), int(roundf(value.y))]
	var decimal_places := 3
	if _step.x >= 1.0 and _step.y >= 1.0:
		decimal_places = 1
	elif _step.x >= 0.1 and _step.y >= 0.1:
		decimal_places = 2
	var format := "(%%.%df, %%.%df)" % [decimal_places, decimal_places]
	return format % [value.x, value.y]


func _update_presentation() -> void:
	tooltip_text = "Value: %s\nRange: %s to %s" % [
		_format_value(_active_value),
		_format_value(_minimum_value),
		_format_value(_maximum_value),
	]
	queue_redraw()


func _theme_color_or_default(
		color_name: StringName,
		theme_type: StringName,
		fallback: Color,
) -> Color:
	if has_theme_color(color_name, theme_type):
		return get_theme_color(color_name, theme_type)
	return fallback
