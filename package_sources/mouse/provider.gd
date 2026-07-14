extends TwberInputProvider

const POSITION_ID := &"position"
const HYPRLAND_POLL_INTERVAL_MSEC := 33
const HYPRLAND_MONITOR_REFRESH_POLLS := 60

var _enabled := true
var _last_position := Vector2.INF
var _hyprland_thread := Thread.new()
var _hyprland_mutex := Mutex.new()
var _hyprland_position := Vector2.INF
var _hyprland_position_available := false
var _hyprland_thread_should_stop := false
var _uses_hyprland_fallback := false
var _display_names: Array[String] = []
var _display_rects: Array[Rect2] = []


func _ready() -> void:
	_uses_hyprland_fallback = (
		OS.get_name() == "Linux"
		and OS.get_environment("XDG_SESSION_TYPE").to_lower() == "wayland"
		and not OS.get_environment("HYPRLAND_INSTANCE_SIGNATURE").is_empty()
	)
	if _uses_hyprland_fallback:
		_display_names = _read_xwayland_display_names()
		for display_index: int in DisplayServer.get_screen_count():
			_display_rects.append(Rect2(
				Vector2(DisplayServer.screen_get_position(display_index)),
				Vector2(DisplayServer.screen_get_size(display_index)),
			))
		var thread_error := _hyprland_thread.start(_poll_hyprland_cursor)
		if thread_error != OK:
			_uses_hyprland_fallback = false
			push_warning("Could not start Hyprland cursor tracking; using Godot mouse tracking instead.")
	set_process(_enabled)


func _process(_delta: float) -> void:
	var global_mouse_position := _get_global_mouse_position()
	if global_mouse_position.is_equal_approx(_last_position):
		return
	_last_position = global_mouse_position
	value_changed.emit(POSITION_ID, global_mouse_position)


func _exit_tree() -> void:
	if not _hyprland_thread.is_started():
		return
	_hyprland_mutex.lock()
	_hyprland_thread_should_stop = true
	_hyprland_mutex.unlock()
	_hyprland_thread.wait_to_finish()


func get_provider_id() -> StringName:
	return &"mouse"


func get_provider_name() -> String:
	return "Mouse Input"


func get_default_enabled() -> bool:
	return true


func is_provider_enabled() -> bool:
	return _enabled


func set_provider_enabled(value: bool) -> void:
	_hyprland_mutex.lock()
	_enabled = value
	_hyprland_mutex.unlock()
	set_process(_enabled)


func get_value_descriptors() -> Array[Dictionary]:
	return [{
		"id": POSITION_ID,
		"name": "Mouse position",
		"type": TYPE_VECTOR2,
		"binding_scene": "res://package_sources/mouse/binding_control.tscn",
	}]


func _get_global_mouse_position() -> Vector2:
	if not _uses_hyprland_fallback:
		return Vector2(DisplayServer.mouse_get_position())
	_hyprland_mutex.lock()
	var position := _hyprland_position
	var available := _hyprland_position_available
	_hyprland_mutex.unlock()
	return position if available else Vector2(DisplayServer.mouse_get_position())


func _poll_hyprland_cursor() -> void:
	var monitors: Array = []
	var poll_count := HYPRLAND_MONITOR_REFRESH_POLLS
	while true:
		_hyprland_mutex.lock()
		var should_stop := _hyprland_thread_should_stop
		var should_poll := _enabled
		_hyprland_mutex.unlock()
		if should_stop:
			return
		if not should_poll:
			OS.delay_msec(100)
			continue
		if poll_count >= HYPRLAND_MONITOR_REFRESH_POLLS:
			monitors = _read_hyprland_monitors()
			poll_count = 0

		var output: Array[String] = []
		var exit_code := OS.execute("hyprctl", PackedStringArray(["cursorpos", "-j"]), output, true)
		if exit_code == OK and not output.is_empty():
			var parsed: Variant = JSON.parse_string(output[0])
			if parsed is Dictionary and parsed.has("x") and parsed.has("y"):
				var compositor_position := Vector2(float(parsed["x"]), float(parsed["y"]))
				_hyprland_mutex.lock()
				_hyprland_position = _translate_hyprland_position(compositor_position, monitors)
				_hyprland_position_available = true
				_hyprland_mutex.unlock()
		poll_count += 1
		OS.delay_msec(HYPRLAND_POLL_INTERVAL_MSEC)


func _read_hyprland_monitors() -> Array:
	var output: Array[String] = []
	if OS.execute("hyprctl", PackedStringArray(["monitors", "-j"]), output, true) != OK or output.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(output[0])
	return parsed if parsed is Array else []


func _read_xwayland_display_names() -> Array[String]:
	var names: Array[String] = []
	names.resize(DisplayServer.get_screen_count())
	var output: Array[String] = []
	if OS.execute("xrandr", PackedStringArray(["--listmonitors"]), output, true) != OK or output.is_empty():
		return names
	var lines := output[0].split("\n", false)
	for line_index: int in range(1, lines.size()):
		var fields := String(lines[line_index]).strip_edges().split(" ", false)
		if fields.size() < 2:
			continue
		var index_text := String(fields[0]).trim_suffix(":")
		if not index_text.is_valid_int():
			continue
		var display_index := index_text.to_int()
		if display_index >= 0 and display_index < names.size():
			names[display_index] = String(fields[fields.size() - 1])
	return names


func _translate_hyprland_position(position: Vector2, monitors: Array) -> Vector2:
	for monitor_value: Variant in monitors:
		if monitor_value is not Dictionary:
			continue
		var monitor := monitor_value as Dictionary
		var scale := maxf(float(monitor.get("scale", 1.0)), 0.01)
		var compositor_rect := Rect2(
			Vector2(float(monitor.get("x", 0.0)), float(monitor.get("y", 0.0))),
			Vector2(float(monitor.get("width", 0.0)), float(monitor.get("height", 0.0))) / scale,
		)
		if not compositor_rect.has_point(position):
			continue
		var display_index := _display_names.find(String(monitor.get("name", "")))
		if display_index < 0:
			display_index = int(monitor.get("id", -1))
		if display_index < 0 or display_index >= _display_rects.size():
			return position
		var amount := (position - compositor_rect.position) / compositor_rect.size
		var display_rect := _display_rects[display_index]
		return display_rect.position + amount * display_rect.size
	return position
