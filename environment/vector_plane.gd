class_name TwberVectorPlane extends Control

signal value_changed(value: Vector2)

const PADDING := 12.0
const GRID_DIVISIONS := 4

var _minimum := Vector2(-1.0, -1.0)
var _maximum := Vector2.ONE
var _step := 0.05
var _value := Vector2.ZERO
var _editable := true
var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 132.0)
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func configure(minimum: Vector2, maximum: Vector2, value_step: float) -> void:
	_minimum = minimum
	_maximum = maximum
	_step = maxf(value_step, 0.0001)
	set_value(_value)


func set_value(value: Vector2, emit_change := false) -> void:
	var next_value := Vector2(
		_quantize(value.x, _minimum.x, _maximum.x),
		_quantize(value.y, _minimum.y, _maximum.y),
	)
	if next_value.is_equal_approx(_value):
		return
	_value = next_value
	queue_redraw()
	if emit_change:
		value_changed.emit(_value)


func set_editable(value: bool) -> void:
	_editable = value
	mouse_default_cursor_shape = Control.CURSOR_CROSS if value else Control.CURSOR_ARROW
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not _editable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			grab_focus()
			_set_value_from_position(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_value_from_position(event.position)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var change := Vector2.ZERO
		match event.keycode:
			KEY_LEFT:
				change.x = -_step
			KEY_RIGHT:
				change.x = _step
			KEY_UP:
				change.y = _step
			KEY_DOWN:
				change.y = -_step
			_:
				return
		set_value(_value + change, true)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	var plane := Rect2(
		Vector2(PADDING, PADDING),
		Vector2(maxf(size.x - PADDING * 2.0, 1.0), maxf(size.y - PADDING * 2.0, 1.0)),
	)
	draw_rect(plane, Color(0.055, 0.06, 0.07, 1.0), true)
	draw_rect(plane, Color(0.26, 0.28, 0.32, 1.0), false, 1.0)

	for index: int in range(1, GRID_DIVISIONS):
		var amount := float(index) / float(GRID_DIVISIONS)
		var vertical_x := lerpf(plane.position.x, plane.end.x, amount)
		var horizontal_y := lerpf(plane.position.y, plane.end.y, amount)
		draw_line(Vector2(vertical_x, plane.position.y), Vector2(vertical_x, plane.end.y), Color(0.16, 0.17, 0.19, 1.0))
		draw_line(Vector2(plane.position.x, horizontal_y), Vector2(plane.end.x, horizontal_y), Color(0.16, 0.17, 0.19, 1.0))

	if _minimum.x <= 0.0 and _maximum.x >= 0.0:
		var zero_x := lerpf(plane.position.x, plane.end.x, inverse_lerp(_minimum.x, _maximum.x, 0.0))
		draw_line(Vector2(zero_x, plane.position.y), Vector2(zero_x, plane.end.y), Color(0.34, 0.36, 0.4, 1.0), 1.0)
	if _minimum.y <= 0.0 and _maximum.y >= 0.0:
		var zero_y := lerpf(plane.end.y, plane.position.y, inverse_lerp(_minimum.y, _maximum.y, 0.0))
		draw_line(Vector2(plane.position.x, zero_y), Vector2(plane.end.x, zero_y), Color(0.34, 0.36, 0.4, 1.0), 1.0)

	var point := _value_to_position(_value, plane)
	var point_color := Color(0.45, 0.75, 1.0, 1.0) if _editable else Color(0.58, 0.63, 0.7, 1.0)
	draw_circle(point, 7.0, Color(0.03, 0.035, 0.04, 0.9))
	draw_circle(point, 4.5, point_color)

	var value_text := "(%s, %s)" % [_format_number(_value.x), _format_number(_value.y)]
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text_size := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var text_position := Vector2(plane.end.x - text_size.x - 6.0, plane.end.y - 6.0)
	draw_string(font, text_position, value_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.68, 0.71, 0.76, 1.0))


func _set_value_from_position(pointer_position: Vector2) -> void:
	var plane := Rect2(
		Vector2(PADDING, PADDING),
		Vector2(maxf(size.x - PADDING * 2.0, 1.0), maxf(size.y - PADDING * 2.0, 1.0)),
	)
	var amount_x := clampf((pointer_position.x - plane.position.x) / plane.size.x, 0.0, 1.0)
	var amount_y := clampf((pointer_position.y - plane.position.y) / plane.size.y, 0.0, 1.0)
	set_value(Vector2(
		lerpf(_minimum.x, _maximum.x, amount_x),
		lerpf(_maximum.y, _minimum.y, amount_y),
	), true)


func _value_to_position(value: Vector2, plane: Rect2) -> Vector2:
	return Vector2(
		lerpf(plane.position.x, plane.end.x, inverse_lerp(_minimum.x, _maximum.x, value.x)),
		lerpf(plane.end.y, plane.position.y, inverse_lerp(_minimum.y, _maximum.y, value.y)),
	)


func _quantize(value: float, minimum: float, maximum: float) -> float:
	return clampf(minimum + roundf((value - minimum) / _step) * _step, minimum, maximum)


func _format_number(value: float) -> String:
	var decimals := clampi(int(ceil(-log(_step) / log(10.0))), 0, 3) if _step < 1.0 else 0
	var result := String.num(value, decimals)
	if result.contains("."):
		while result.ends_with("0"):
			result = result.trim_suffix("0")
		result = result.trim_suffix(".")
	return result
