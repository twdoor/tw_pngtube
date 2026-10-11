@tool
class_name TwberToolStrip extends Container

const BUTTON_SIZE := 32.0
const GAP := 2.0
var _columns := 1


func _cell_height() -> float:
	return maxf(BUTTON_SIZE, ceilf((size.x + GAP) / _columns) - GAP)


func _get_minimum_size() -> Vector2:
	var rows := maxi(1, ceili(float(get_child_count()) / _columns))
	return Vector2(BUTTON_SIZE, rows * (_cell_height() + GAP) - GAP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_columns = maxi(1, floori((size.x + GAP) / (BUTTON_SIZE + GAP)))
		update_minimum_size()
		queue_sort()
	elif what == NOTIFICATION_SORT_CHILDREN:
		var index := 0
		var pitch := (size.x + GAP) / _columns
		var height := _cell_height()
		for child: Node in get_children():
			if child is Control:
				var column := index % _columns
				var left := roundf(column * pitch)
				var right := roundf((column + 1) * pitch) - GAP
				var top := floori(float(index) / _columns) * (height + GAP)
				fit_child_in_rect(child, Rect2(left, top, right - left, height))
				index += 1
