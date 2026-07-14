class_name ParameterScalarTrack extends Control

signal value_changed(value: float)

const DEFAULT_MINIMUM_SIZE := Vector2(180.0, 58.0)
const HORIZONTAL_PADDING := 14.0
const TRACK_HEIGHT_RATIO := 0.4
const BOUND_MARKER_RADIUS := 4.0
const ACTIVE_MARKER_RADIUS := 7.0
const MARKER_SNAP_RADIUS := 10.0

var _minimum_value := 0.0
var _maximum_value := 1.0
var _step := TwberParameterResource.CONTINUOUS_STEP
var _integer_mode := false
var _active_value := 0.0
var _bound_markers: Array[float] = []
var _dragging := false


func _init() -> void:
	custom_minimum_size = DEFAULT_MINIMUM_SIZE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func configure(
		minimum_value: float,
		maximum_value: float,
		value_step: float = TwberParameterResource.CONTINUOUS_STEP,
		use_integers: bool = false,
) -> void:
	_integer_mode = use_integers
	_set_range_values(minimum_value, maximum_value)
	_set_step_value(value_step)
	_normalize_state()


func set_range(minimum_value: float, maximum_value: float) -> void:
	_set_range_values(minimum_value, maximum_value)
	_normalize_state()


func set_step(value_step: float) -> void:
	_set_step_value(value_step)
	_normalize_state()


func set_integer_mode(enabled: bool) -> void:
	if _integer_mode == enabled:
		return

	_integer_mode = enabled
	_set_range_values(_minimum_value, _maximum_value)
	_set_step_value(_step)
	_normalize_state()


func set_active_value(value: float, emit_change := false) -> void:
	_update_active_value(value, emit_change, emit_change)


func get_active_value() -> float:
	return _active_value


func set_bound_markers(markers: Variant) -> void:
	_bound_markers.clear()
	if markers is not Array and markers is not PackedFloat32Array and markers is not PackedFloat64Array:
		_update_presentation()
		return

	for marker: Variant in markers:
		if marker is not int and marker is not float:
			continue
		_append_unique_marker(_quantize_value(float(marker)))

	_bound_markers.sort()
	_update_presentation()


func get_bound_markers() -> Array[float]:
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
	var track_color := _theme_color_or_default(
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

	var track_start := _get_track_start()
	var track_end := _get_track_end()
	draw_line(track_start, track_end, track_color, 2.0, true)
	draw_line(track_start - Vector2(0.0, 4.0), track_start + Vector2(0.0, 4.0), track_color, 1.0, true)
	draw_line(track_end - Vector2(0.0, 4.0), track_end + Vector2(0.0, 4.0), track_color, 1.0, true)

	for marker: float in _bound_markers:
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
	_draw_range_labels(track_start.x, track_end.x, track_end.y)


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
		KEY_LEFT, KEY_DOWN:
			next_value -= keyboard_step
		KEY_RIGHT, KEY_UP:
			next_value += keyboard_step
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


func _set_range_values(minimum_value: float, maximum_value: float) -> void:
	_minimum_value = minf(minimum_value, maximum_value)
	_maximum_value = maxf(minimum_value, maximum_value)
	if _integer_mode:
		_minimum_value = roundf(_minimum_value)
		_maximum_value = roundf(_maximum_value)


func _set_step_value(value_step: float) -> void:
	_step = absf(value_step)
	if _integer_mode:
		_step = maxf(roundf(_step), 1.0)


func _normalize_state() -> void:
	_active_value = _quantize_value(_active_value)
	var previous_markers := _bound_markers.duplicate()
	_bound_markers.clear()
	for marker: float in previous_markers:
		_append_unique_marker(_quantize_value(marker))
	_bound_markers.sort()
	_update_presentation()


func _append_unique_marker(marker: float) -> void:
	for existing_marker: float in _bound_markers:
		if is_equal_approx(existing_marker, marker):
			return
	_bound_markers.append(marker)


func _has_bound_marker(value: float) -> bool:
	for marker: float in _bound_markers:
		if is_equal_approx(marker, value):
			return true
	return false


func _set_value_from_pointer(pointer_position: Vector2, emit_if_unchanged: bool) -> void:
	var snapped_marker: Variant = _get_nearby_marker(pointer_position)
	var value := _position_to_value(pointer_position.x)
	if snapped_marker != null:
		value = float(snapped_marker)
	_update_active_value(value, true, emit_if_unchanged)


func _get_nearby_marker(pointer_position: Vector2) -> Variant:
	var closest_marker: Variant = null
	var closest_distance := MARKER_SNAP_RADIUS
	for marker: float in _bound_markers:
		var distance := pointer_position.distance_to(_value_to_position(marker))
		if distance <= closest_distance:
			closest_marker = marker
			closest_distance = distance
	return closest_marker


func _update_active_value(value: float, emit_change: bool, emit_if_unchanged: bool) -> void:
	var normalized_value := _quantize_value(value)
	var changed := not is_equal_approx(normalized_value, _active_value)
	_active_value = normalized_value
	_update_presentation()
	if emit_change and (changed or emit_if_unchanged):
		value_changed.emit(_active_value)


func _quantize_value(value: float) -> float:
	if is_equal_approx(_minimum_value, _maximum_value):
		return _minimum_value

	var output := clampf(value, _minimum_value, _maximum_value)
	if is_equal_approx(output, _minimum_value) or is_equal_approx(output, _maximum_value):
		return output
	if _step > 0.0:
		output = _minimum_value + roundf((output - _minimum_value) / _step) * _step
	if _integer_mode:
		output = roundf(output)
	return clampf(output, _minimum_value, _maximum_value)


func _position_to_value(pointer_x: float) -> float:
	var track_start := _get_track_start().x
	var track_end := _get_track_end().x
	if is_equal_approx(track_start, track_end):
		return _minimum_value
	return _quantize_value(lerpf(
			_minimum_value,
			_maximum_value,
			inverse_lerp(track_start, track_end, clampf(pointer_x, track_start, track_end)),
	))


func _value_to_position(value: float) -> Vector2:
	var track_start := _get_track_start()
	var track_end := _get_track_end()
	var weight := 0.5
	if not is_equal_approx(_minimum_value, _maximum_value):
		weight = inverse_lerp(_minimum_value, _maximum_value, clampf(value, _minimum_value, _maximum_value))
	return track_start.lerp(track_end, weight)


func _get_track_start() -> Vector2:
	var y := clampf(size.y * TRACK_HEIGHT_RATIO, 14.0, maxf(14.0, size.y - 22.0))
	return Vector2(minf(HORIZONTAL_PADDING, size.x * 0.5), y)


func _get_track_end() -> Vector2:
	var start := _get_track_start()
	return Vector2(maxf(start.x, size.x - HORIZONTAL_PADDING), start.y)


func _get_keyboard_step() -> float:
	if _step > 0.0:
		return _step
	if _integer_mode:
		return 1.0
	return maxf(
			(_maximum_value - _minimum_value) / 100.0,
			TwberParameterResource.CONTINUOUS_STEP,
	)


func _draw_range_labels(left: float, right: float, track_y: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		return

	var font_size := mini(get_theme_default_font_size(), 13)
	var label_color := _theme_color_or_default(
			&"font_color",
			&"Label",
			Color(0.88, 0.9, 0.95),
	)
	var label_y := minf(size.y - 4.0, track_y + float(font_size) + 13.0)
	var half_width := maxf((right - left) * 0.5, 0.0)
	draw_string(
			font,
			Vector2(left, label_y),
			_format_value(_minimum_value),
			HORIZONTAL_ALIGNMENT_LEFT,
			half_width,
			font_size,
			label_color,
	)
	draw_string(
			font,
			Vector2(left + half_width, label_y),
			_format_value(_maximum_value),
			HORIZONTAL_ALIGNMENT_RIGHT,
			half_width,
			font_size,
			label_color,
	)


func _format_value(value: float) -> String:
	if _integer_mode:
		return str(int(roundf(value)))
	if _step >= 1.0:
		return "%.1f" % value
	if _step >= 0.1:
		return "%.2f" % value
	return "%.3f" % value


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
