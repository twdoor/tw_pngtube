class_name TwberWorkspace extends Control

signal notice(message: String)
signal layout_changed
signal owned_window_added(window: Window)

const SECTION := "editor.workspace"
const VERSION := 1
var panels: Dictionary = {}
var layout: Dictionary = {}
var hidden_panels: Array[String] = []
var locked := false
var mode := 0
@onready var canvas: Control = %Canvas
var floating: Dictionary = {}
var _windows: Dictionary = {}
@onready var _holding: Control = %Holding
@onready var _layout_host: Control = %Layout
@onready var _layout_root: Control = $Layout/Default
var _canvas_slot: Control
var _groups: Dictionary = {}
@onready var _drop_overlay: TwberDockDropOverlay = %DropOverlay
@onready var _save_timer: Timer = %SaveTimer
var _rebuilding := false
var _next_group := 0
var _presets: Dictionary = {}
var _default_layout: Dictionary = {}


func _ready() -> void:
	_default_layout = _read_scene_layout(_layout_root)
	for child: Node in find_children("*", "PanelContainer", true, false):
		if child is TwberDockPanel:
			panels[child.panel_id] = child
			child.setup(child.panel_id, child.panel_title, self)
			child.minimum_size_changed.connect(_sync_window_minimum.bind(child.panel_id))
	_drop_overlay.workspace = self
	_save_timer.timeout.connect(save_layout)
	resized.connect(_sync_canvas.call_deferred)



func _get_minimum_size() -> Vector2:
	return _layout_root.get_combined_minimum_size() if is_instance_valid(_layout_root) else Vector2.ZERO


func _sync_window_minimum(id: String) -> void:
	if _windows.has(id):
		(_windows[id] as Window).min_size = Vector2i((panels[id] as Control).get_combined_minimum_size().ceil())


func default_layout() -> Dictionary:
	return _default_layout.duplicate(true)


func _read_scene_layout(node: Control) -> Dictionary:
	if node == canvas:
		return {"type": "canvas", "id": "canvas"}
	if node is TwberDockPanel:
		return _group(node.panel_id, [node.panel_id])
	if node is TabContainer:
		var ids: Array = []
		for panel: TwberDockPanel in node.get_children():
			ids.append(panel.panel_id)
		var group := _group(String(node.name).to_snake_case(), ids)
		group.active = ids[maxi(node.current_tab, 0)]
		return group
	assert(node is SplitContainer and node.get_child_count() == 2,
		"Default workspace layout must contain splits, dock panels, tabs, or the canvas.")
	var a := node.get_child(0) as Control
	var b := node.get_child(1) as Control
	var ratio := a.size_flags_stretch_ratio / (a.size_flags_stretch_ratio + b.size_flags_stretch_ratio)
	return _split("v" if node is VSplitContainer else "h", ratio, _read_scene_layout(a), _read_scene_layout(b))


func initialize() -> void:
	# The scene shows the default arrangement in Godot. Keep its canvas alive
	# while the runtime split tree is rebuilt for user layouts.
	canvas.reparent(self, false)
	move_child(canvas, _drop_overlay.get_index())
	layout = default_layout()
	var saved: Variant = TwberAppSettings.get_value(SECTION, "layout", {})
	if saved is Dictionary and not saved.is_empty():
		if not restore_layout(saved):
			notice.emit("Workspace layout could not be restored. Using the default layout.")
	var presets: Variant = TwberAppSettings.get_value(SECTION, "presets", {})
	if presets is Dictionary:
		_presets = presets.duplicate(true)
	rebuild()


func set_mode(value: int) -> void:
	mode = value
	for panel: TwberDockPanel in panels.values():
		panel.show_mode(mode)
	rebuild()


func is_available(id: String) -> bool:
	return panels.has(id) and (panels[id] as TwberDockPanel).modes.has(mode)


func reset_layout() -> void:
	layout = default_layout()
	hidden_panels.clear()
	floating.clear()
	locked = false
	rebuild()
	_changed()


func set_panel_hidden(id: String, value: bool) -> void:
	if not panels.has(id):
		return
	if value and not hidden_panels.has(id):
		hidden_panels.append(id)
	elif not value:
		hidden_panels.erase(id)
	rebuild()
	_changed()


func toggle_lock() -> void:
	locked = not locked
	rebuild()
	_changed()


func move_panel(id: String, target_id: String, side: String, tab_index := -1) -> void:
	if locked or not panels.has(id) or not ["left", "right", "top", "bottom", "center"].has(side):
		return
	var target := _find(layout, target_id)
	if target.is_empty():
		return
	if side == "center" and target.type == "canvas":
		side = "right"
	# Capture the target dictionary before removal; prune only after insertion.
	_remove_panel(layout, id)
	hidden_panels.erase(id)
	floating.erase(id)
	if side == "center":
		if tab_index < 0:
			target.panels.append(id)
		else:
			target.panels.insert(clampi(tab_index, 0, target.panels.size()), id)
		target.active = id
	else:
		_next_group += 1
		var fresh := _group("dock_%d_%d" % [Time.get_ticks_usec(), _next_group], [id])
		var previous := target.duplicate(true)
		var first := side in ["left", "top"]
		var fraction := 0.3
		if id == "tools":
			var destination: Control = canvas if target_id == "canvas" else _groups.get(target_id, canvas)
			var length := destination.size.x if side in ["left", "right"] else destination.size.y
			fraction = clampf(48.0 / maxf(length, 1.0), 0.01, 0.5)
		target.clear()
		target.merge(_split("h" if side in ["left", "right"] else "v", fraction if first else 1.0 - fraction,
			fresh if first else previous, previous if first else fresh))
	layout = _prune(layout)
	rebuild()
	_changed()


func rebuild() -> void:
	if not is_node_ready():
		return
	_rebuilding = true
	for panel: TwberDockPanel in panels.values():
		panel.reparent(_holding, false)
		panel.show_mode(mode)
		panel.grip.tooltip_text = "%s — drag to dock; right-click for panel options" % panel.panel_title
	for id: String in _windows.keys():
		if not floating.has(id) or not is_available(id) or hidden_panels.has(id):
			var window: Window = _windows[id]
			_windows.erase(id)
			window.hide()
			window.queue_free()
	if is_instance_valid(_layout_root):
		_layout_host.remove_child(_layout_root)
		_layout_root.queue_free()
	_groups.clear()
	_canvas_slot = null
	_layout_root = _build(layout)
	if _layout_root != null:
		_layout_host.add_child(_layout_root)
		_layout_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_layout_root.minimum_size_changed.connect(update_minimum_size)
	for id: String in floating:
		if is_available(id) and not hidden_panels.has(id):
			_mount_window(id)
	_rebuilding = false
	update_minimum_size()
	_sync_canvas.call_deferred()


func _build(entry: Dictionary) -> Control:
	if entry.type == "canvas":
		_canvas_slot = Control.new()
		_canvas_slot.custom_minimum_size = Vector2(160, 120)
		_canvas_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas_slot.resized.connect(_sync_canvas.call_deferred)
		_canvas_slot.item_rect_changed.connect(_sync_canvas.call_deferred)
		_groups["canvas"] = _canvas_slot
		return _canvas_slot
	if entry.type == "group":
		var ids: Array[String] = []
		for id: String in entry.panels:
			if is_available(id) and not hidden_panels.has(id) and not floating.has(id):
				ids.append(id)
		if ids.is_empty():
			return null
		if ids.size() == 1:
			var panel: TwberDockPanel = panels[ids[0]]
			_holding.remove_child(panel)
			panel.show()
			_groups[String(entry.id)] = panel
			return panel
		var tabs := TabContainer.new()
		tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tabs.get_tab_bar().gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				var index := tabs.get_tab_bar().get_tab_idx_at_point(event.position)
				if index >= 0:
					(panels[ids[index]] as TwberDockPanel).show_panel_menu()
		)
		_groups[String(entry.id)] = tabs
		for id: String in ids:
			var panel: TwberDockPanel = panels[id]
			panel.reparent(tabs, false)
			tabs.set_tab_title(panel.get_index(), panel.panel_title)
		if ids.has(String(entry.get("active", ""))):
			tabs.current_tab = ids.find(String(entry.active))
		tabs.tab_changed.connect(func(index: int) -> void:
			entry.active = ids[index]
			if not _rebuilding:
				_changed()
		)
		tabs.get_tab_bar().set_drag_forwarding(func(at: Vector2) -> Variant:
			var index := tabs.get_tab_bar().get_tab_idx_at_point(at)
			return (panels[ids[index]] as TwberDockPanel)._drag(at) if index >= 0 else null,
			Callable(), Callable())
		return tabs
	var a := _build(entry.a)
	var b := _build(entry.b)
	if a == null:
		return b
	if b == null:
		return a
	var split: SplitContainer
	if entry.axis == "h":
		split = HSplitContainer.new()
	else:
		split = VSplitContainer.new()
	split.dragging_enabled = not locked
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 6)
	split.add_child(a)
	split.add_child(b)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	a.size_flags_stretch_ratio = float(entry.ratio)
	b.size_flags_stretch_ratio = 1.0 - float(entry.ratio)
	split.dragged.connect(func(_offset: int) -> void:
		var length := split.size.x if entry.axis == "h" else split.size.y
		var first_length := a.size.x if entry.axis == "h" else a.size.y
		if length > 0:
			entry.ratio = clampf(first_length / length, 0.01, 0.99)
		_changed()
	)
	return split


func _sync_canvas() -> void:
	if is_instance_valid(_canvas_slot) and _canvas_slot.is_inside_tree():
		canvas.position = _canvas_slot.global_position - global_position
		canvas.size = _canvas_slot.size


func drop_target(point: Vector2) -> Dictionary:
	for id: String in _groups:
		var control: Control = _groups[id]
		var rect := control.get_global_rect()
		if not rect.has_point(point):
			continue
		var normalized := (point - rect.position) / rect.size
		var side := "center"
		var tab_index := -1
		if normalized.x < 0.23:
			side = "left"
		elif normalized.x > 0.77:
			side = "right"
		elif normalized.y < 0.23:
			side = "top"
		elif normalized.y > 0.77:
			side = "bottom"
		if control is TabContainer and control.tabs_visible:
			var bar := control.get_tab_bar() as TabBar
			if bar.get_global_rect().has_point(point):
				side = "center"
				tab_index = bar.get_tab_idx_at_point(point - bar.global_position)
		if id == "canvas" and side == "center":
			side = "right"
		match side:
			"left": rect.size.x *= 0.3
			"right":
				rect.position.x += rect.size.x * 0.7
				rect.size.x *= 0.3
			"top": rect.size.y *= 0.3
			"bottom":
				rect.position.y += rect.size.y * 0.7
				rect.size.y *= 0.3
		return {"id": id, "side": side, "rect": rect, "tab_index": tab_index}
	return {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN and is_node_ready():
		var data: Variant = get_viewport().gui_get_drag_data()
		_drop_overlay.visible = data is Dictionary and data.get("type") == "twber_workspace_panel" and data.get("host") == get_instance_id()
	elif what == NOTIFICATION_DRAG_END and is_node_ready():
		_drop_overlay.hide()
		_drop_overlay.target.clear()


func _changed() -> void:
	layout_changed.emit()
	_save_timer.start()


func capture_layout() -> Dictionary:
	for id: String in _windows:
		var window: Window = _windows[id]
		floating[id] = {"position": window.position, "size": window.size}
	return {"version": VERSION, "tree": layout.duplicate(true), "hidden": hidden_panels.duplicate(),
		"floating": floating.duplicate(true), "locked": locked}


func save_layout() -> void:
	var error := TwberAppSettings.set_value(SECTION, "layout", capture_layout())
	if error != OK:
		notice.emit("Could not save workspace layout: %s" % error_string(error))


func save_preset(preset_name: String) -> void:
	if preset_name.strip_edges().is_empty():
		return
	_presets[preset_name.strip_edges()] = capture_layout()
	TwberAppSettings.set_value(SECTION, "presets", _presets)


func preset_names() -> Array:
	return _presets.keys()


func load_preset(preset_name: String) -> void:
	if _presets.has(preset_name) and restore_layout(_presets[preset_name]):
		rebuild()
		_changed()


func restore_layout(saved: Dictionary) -> bool:
	if saved.get("version") != VERSION or not saved.get("tree") is Dictionary:
		return false
	var seen := {"panels": {}, "groups": {}, "canvas": 0}
	if not _validate(saved.tree, seen, 0) or seen.canvas != 1:
		return false
	if not saved.get("hidden", []) is Array or not saved.get("floating", {}) is Dictionary:
		return false
	layout = saved.tree.duplicate(true)
	# Register new panels in their own group without dropping a user's layout.
	for id: String in panels:
		if not seen.panels.has(id):
			layout = _split("h", 0.8, layout, _group("new_" + id, [id]))
	hidden_panels.clear()
	for id: Variant in saved.get("hidden", []):
		if id is String and panels.has(id) and not hidden_panels.has(id):
			hidden_panels.append(id)
	floating.clear()
	for id: Variant in saved.get("floating", {}):
		var geometry: Variant = saved.floating[id]
		if id is String and panels.has(id) and geometry is Dictionary and geometry.get("position") is Vector2i and geometry.get("size") is Vector2i:
			floating[id] = geometry.duplicate()
	locked = saved.get("locked", false) == true
	return true


func _validate(entry: Dictionary, seen: Dictionary, depth: int) -> bool:
	if depth > 24:
		return false
	match entry.get("type"):
		"canvas":
			seen.canvas += 1
			return entry.get("id") == "canvas"
		"group":
			if not entry.get("id") is String or entry.id == "canvas" or seen.groups.has(entry.id) or not entry.get("panels") is Array:
				return false
			if entry.has("active") and not entry.active is String:
				return false
			seen.groups[entry.id] = true
			for id: Variant in entry.panels:
				if not id is String or seen.panels.has(id):
					return false
				seen.panels[id] = true
			return true
		"split":
			var ratio: Variant = entry.get("ratio")
			return entry.get("axis") in ["h", "v"] and (ratio is float or ratio is int) and is_finite(float(ratio)) and ratio > 0.0 and ratio < 1.0 and entry.get("a") is Dictionary and entry.get("b") is Dictionary and _validate(entry.a, seen, depth + 1) and _validate(entry.b, seen, depth + 1)
	return false


func float_panel(id: String) -> void:
	if locked or not panels.has(id):
		return
	hidden_panels.erase(id)
	floating[id] = {"position": get_window().position + Vector2i(80, 80), "size": Vector2i(420, 44) if id == "tools" else Vector2i(380, 520)}
	rebuild()
	_changed()


func redock_panel(id: String) -> void:
	floating.erase(id)
	rebuild()
	_changed()


func _mount_window(id: String) -> void:
	var window: Window = _windows.get(id)
	if window == null:
		window = Window.new()
		window.visible = false
		window.title = "%s — Twber" % (panels[id] as TwberDockPanel).panel_title
		window.transient = true
		var minimum := Vector2i((panels[id] as Control).get_combined_minimum_size().ceil())
		window.min_size = minimum
		add_child(window)
		_windows[id] = window
		var geometry: Dictionary = floating[id]
		var screen := DisplayServer.screen_get_usable_rect(get_window().current_screen)
		if screen.size.x <= 0:
			screen = Rect2i(0, 0, 1280, 720)
		var requested: Vector2i = geometry.position
		for index: int in DisplayServer.get_screen_count():
			var available := DisplayServer.screen_get_usable_rect(index)
			if available.has_point(requested):
				screen = available
		window.size = Vector2i(clampi(geometry.size.x, minimum.x, maxi(screen.size.x, minimum.x)), clampi(geometry.size.y, minimum.y, maxi(screen.size.y, minimum.y)))
		window.position = Vector2i(clampi(requested.x, screen.position.x, screen.end.x - window.size.x), clampi(requested.y, screen.position.y, screen.end.y - window.size.y))
		window.close_requested.connect(redock_panel.bind(id))
		window.size_changed.connect(func() -> void:
			if not _rebuilding:
				_changed()
		)
		owned_window_added.emit(window)
	var panel: TwberDockPanel = panels[id]
	panel.reparent(window, false)
	panel.grip.tooltip_text = "Right-click for panel options. Close the window or choose Return to dock to redock."
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.show()
	window.show()


static func _split(axis: String, ratio: float, a: Dictionary, b: Dictionary) -> Dictionary:
	return {"type": "split", "axis": axis, "ratio": ratio, "a": a, "b": b}


static func _group(id: String, ids: Array) -> Dictionary:
	return {"type": "group", "id": id, "panels": ids, "active": ids[0] if not ids.is_empty() else ""}


static func _find(entry: Dictionary, id: String) -> Dictionary:
	if entry.get("id", "") == id:
		return entry
	if entry.get("type") == "split":
		var found := _find(entry.a, id)
		return found if not found.is_empty() else _find(entry.b, id)
	return {}


static func _remove_panel(entry: Dictionary, id: String) -> void:
	if entry.type == "group":
		entry.panels.erase(id)
	elif entry.type == "split":
		_remove_panel(entry.a, id)
		_remove_panel(entry.b, id)


static func _prune(entry: Dictionary) -> Dictionary:
	if entry.type == "group":
		return entry if not entry.panels.is_empty() else {}
	if entry.type == "split":
		entry.a = _prune(entry.a)
		entry.b = _prune(entry.b)
		if entry.a.is_empty():
			return entry.b
		if entry.b.is_empty():
			return entry.a
	return entry


func reorder_panel(id: String, direction: int) -> void:
	if locked:
		return
	var group := _panel_group(layout, id)
	if group.is_empty():
		return
	var old_index: int = group.panels.find(id)
	var new_index := clampi(old_index + direction, 0, group.panels.size() - 1)
	if new_index == old_index:
		return
	group.panels.remove_at(old_index)
	group.panels.insert(new_index, id)
	rebuild()
	_changed()


static func _panel_group(entry: Dictionary, id: String) -> Dictionary:
	if entry.type == "group" and entry.panels.has(id):
		return entry
	if entry.type == "split":
		var found := _panel_group(entry.a, id)
		return found if not found.is_empty() else _panel_group(entry.b, id)
	return {}
