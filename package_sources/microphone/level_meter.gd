extends Control

var _level_db := -80.0
var _threshold_db := -40.0
var _show_threshold := false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 18.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_level_db(value: float) -> void:
	_level_db = value
	queue_redraw()


func set_threshold_db(value: float, visible := true) -> void:
	_threshold_db = value
	_show_threshold = visible
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var track := Rect2(Vector2(0.0, 3.0), Vector2(size.x, maxf(size.y - 6.0, 1.0)))
	draw_rect(track, Color(0.13, 0.14, 0.16, 1.0), true)
	var amount := clampf(inverse_lerp(-80.0, 0.0, _level_db), 0.0, 1.0)
	var fill := Rect2(track.position, Vector2(track.size.x * amount, track.size.y))
	var fill_color := Color(0.38, 0.72, 0.95, 1.0)
	if _level_db > -10.0:
		fill_color = Color(0.94, 0.49, 0.37, 1.0)
	draw_rect(fill, fill_color, true)
	if _show_threshold:
		var threshold_x := lerpf(track.position.x, track.end.x, clampf(inverse_lerp(-80.0, 0.0, _threshold_db), 0.0, 1.0))
		draw_line(Vector2(threshold_x, 0.0), Vector2(threshold_x, size.y), Color(1.0, 0.82, 0.35, 1.0), 2.0)
	draw_rect(track, Color(0.29, 0.31, 0.35, 1.0), false, 1.0)
