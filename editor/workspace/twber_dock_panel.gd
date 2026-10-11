class_name TwberDockPanel extends PanelContainer

@export var panel_id := ""
@export var panel_title := ""
var workspace: TwberWorkspace
@onready var body: VBoxContainer = %Body
@onready var grip: Control = %DockGrip
@onready var popup: PopupMenu = %PanelMenu
var variants: Dictionary = {}
var modes: Array[int] = []


func setup(id: String, title: String, host: TwberWorkspace) -> void:
	panel_id = id
	panel_title = title
	workspace = host
	grip.tooltip_text = "%s — drag to dock; right-click for panel options" % title


func _ready() -> void:
	for content: Control in body.get_children():
		var mode := int(content.get_meta("workspace_mode", 0))
		modes.append(mode)
		variants[mode] = content
	grip.set_drag_forwarding(_drag, Callable(), Callable())
	grip.gui_input.connect(_on_grip_input)
	grip.draw.connect(_draw_grip)
	grip.resized.connect(grip.queue_redraw)
	popup.id_pressed.connect(func(index: int) -> void:
		if index < 4:
			workspace.move_panel(panel_id, "canvas", ["left", "right", "top", "bottom"][index])
		elif index == 4:
			workspace.float_panel(panel_id)
		elif index == 5:
			workspace.set_panel_hidden(panel_id, true)
		elif index < 8:
			workspace.reorder_panel(panel_id, -1 if index == 6 else 1)
		else:
			workspace.redock_panel(panel_id)
	)
	popup.about_to_popup.connect(func() -> void:
		for index: int in popup.item_count:
			popup.set_item_disabled(index, workspace.locked and index != 5)
		popup.set_item_disabled(8, workspace.locked or not workspace.floating.has(panel_id))
	)


func _draw_grip() -> void:
	var center := grip.size * 0.5
	var along := Vector2(minf(10, grip.size.x * 0.3), 0)
	var across := Vector2(0, 1.5)
	for sign_value: float in [-1.0, 1.0]:
		grip.draw_line(center - along + across * sign_value, center + along + across * sign_value, Color("596170"))


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		show_panel_menu()
		grip.accept_event()


func show_panel_menu() -> void:
	popup.position = Vector2i(get_screen_transform() * get_local_mouse_position())
	popup.popup()


func show_mode(mode: int) -> void:
	for key: int in variants:
		(variants[key] as Control).visible = key == mode


func _drag(_position: Vector2) -> Variant:
	if workspace.locked or get_viewport() != workspace.get_viewport():
		return null
	var preview := Label.new()
	preview.text = panel_title
	set_drag_preview(preview)
	return {"type": "twber_workspace_panel", "host": workspace.get_instance_id(), "panel": panel_id}
