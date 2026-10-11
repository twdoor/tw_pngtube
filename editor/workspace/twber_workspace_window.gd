extends Window


func _unhandled_key_input(event: InputEvent) -> void:
	var editor := get_meta("twber_editor") as TwberEditor
	if editor == null or event is not InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE or (event.is_command_or_control_pressed() and event.keycode in [KEY_Z, KEY_Y]):
		editor._unhandled_key_input(event)
		set_input_as_handled()
