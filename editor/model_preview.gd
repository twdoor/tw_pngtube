class_name ModelPreview extends Node

signal view_changed

const ZOOM_STEP := 1.2

@export var _model_root: Node2D
@export var canvas_control: Control
@export var min_zoom := 0.01
@export var max_zoom := 32.0

var _panning := false


func _unhandled_input(event: InputEvent) -> void:
	if _model_root == null:
		return

	if event is InputEventMouseButton:
		if canvas_control != null and not canvas_control.get_global_rect().has_point(event.position):
			if event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
				_panning = false
			return
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _panning:
		_pan_model(event.relative)
		get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_model_at(event.position, ZOOM_STEP)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_model_at(event.position, 1.0 / ZOOM_STEP)
				get_viewport().set_input_as_handled()


func _pan_model(delta: Vector2) -> void:
	_model_root.position += delta
	view_changed.emit()


func _zoom_model_at(mouse_position: Vector2, zoom_factor: float) -> void:
	var current_zoom := absf(_model_root.scale.x)
	if is_zero_approx(current_zoom):
		var recovered_zoom := maxf(min_zoom, 0.000001)
		var y_sign := -1.0 if _model_root.scale.y < 0.0 else 1.0
		_model_root.scale = Vector2(recovered_zoom, recovered_zoom * y_sign)
		view_changed.emit()
		return

	var next_zoom := clampf(current_zoom * zoom_factor, min_zoom, max_zoom)
	if is_equal_approx(next_zoom, current_zoom):
		return

	var local_position := _model_root.to_local(mouse_position)
	var before_zoom := _model_root.to_global(local_position)
	var applied_factor := next_zoom / current_zoom
	_model_root.scale *= applied_factor
	var after_zoom := _model_root.to_global(local_position)
	_model_root.global_position += before_zoom - after_zoom
	view_changed.emit()
