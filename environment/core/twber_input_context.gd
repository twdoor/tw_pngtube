class_name TwberInputContext extends RefCounted


static func capture_displays() -> Dictionary:
	var displays: Array[Rect2] = []
	for index: int in DisplayServer.get_screen_count():
		displays.append(Rect2(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index)))
	return {"display_rects": displays, "current_display": DisplayServer.window_get_current_screen()}
