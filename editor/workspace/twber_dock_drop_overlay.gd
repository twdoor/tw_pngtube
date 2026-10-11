class_name TwberDockDropOverlay extends Control

var workspace: TwberWorkspace
var target: Dictionary = {}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if workspace.locked or not data is Dictionary or data.get("type") != "twber_workspace_panel" or data.get("host") != workspace.get_instance_id():
		return false
	target = workspace.drop_target(at + global_position)
	queue_redraw()
	return not target.is_empty()


func _drop_data(_at: Vector2, data: Variant) -> void:
	if not target.is_empty():
		workspace.move_panel(String(data.panel), String(target.id), String(target.side), int(target.get("tab_index", -1)))
	target.clear()
	queue_redraw()


func _draw() -> void:
	if target.is_empty():
		return
	var rect: Rect2 = target.rect
	rect.position -= global_position
	draw_rect(rect, Color(0.25, 0.65, 0.95, 0.25))
	draw_rect(rect, Color(0.4, 0.75, 1.0), false, 2.0)
