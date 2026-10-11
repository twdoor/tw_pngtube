class_name TwberWorkspaceBinding extends RefCounted

# Connects the scene-authored workspace to document and menu actions.
var editor: TwberEditor
var workspace: TwberWorkspace
var modes: TabBar
var context_label: Label
var view_menu: MenuButton
var workspace_menu: MenuButton
var _preset_dialog: ConfirmationDialog
var _preset_name: LineEdit


func setup(owner_editor: TwberEditor) -> void:
	editor = owner_editor
	workspace = editor.get_node("%Workspace") as TwberWorkspace
	modes = editor._mode_bar
	context_label = editor.get_node("%ContextLabel") as Label
	view_menu = editor.get_node("%ViewMenu") as MenuButton
	workspace_menu = editor.get_node("%WorkspaceMenu") as MenuButton
	_preset_dialog = editor.get_node("%WorkspacePresetDialog") as ConfirmationDialog
	_preset_name = editor.get_node("%PresetName") as LineEdit
	view_menu.get_popup().about_to_popup.connect(_refresh_view_menu)
	view_menu.get_popup().id_pressed.connect(func(id: int) -> void:
		if id == 100:
			editor._center_workspace_canvas()
			return
		var key := String(workspace.panels.keys()[id])
		workspace.set_panel_hidden(key, not workspace.hidden_panels.has(key))
	)
	workspace_menu.get_popup().about_to_popup.connect(_refresh_workspace_menu)
	workspace_menu.get_popup().id_pressed.connect(_workspace_action)
	for tool: TwberEditorTool in editor._controllers.get_children():
		tool.set_tool_active(tool.get_index() == modes.current_tab)
		tool.document_layer_selected.connect(editor._on_workspace_selection.bind(tool.get_index()))
	_preset_dialog.confirmed.connect(func() -> void: workspace.save_preset(_preset_name.text))
	workspace.owned_window_added.connect(editor._watch_workspace_window)
	workspace.notice.connect(editor._set_editor_status)
	workspace.initialize()
	set_mode(modes.current_tab)
	editor._initialize_canvas_camera.call_deferred()


func set_mode(index: int) -> void:
	modes.set_block_signals(true)
	modes.current_tab = index
	modes.set_block_signals(false)
	workspace.set_mode(index)
	context_label.text = ["Place · Rest artwork", "Mesh · Rest geometry", "Rig · Pose draft → Bind", "Animate · Pose draft → Add Point · Parameter values key immediately"][index]


func _refresh_view_menu() -> void:
	var popup := view_menu.get_popup()
	popup.clear()
	popup.add_item("Center canvas", 100)
	popup.add_separator()
	for id: String in workspace.panels:
		popup.add_check_item((workspace.panels[id] as TwberDockPanel).panel_title, workspace.panels.keys().find(id))
		var index := popup.item_count - 1
		popup.set_item_checked(index, not workspace.hidden_panels.has(id))
		popup.set_item_disabled(index, not workspace.is_available(id))


func _refresh_workspace_menu() -> void:
	var popup := workspace_menu.get_popup()
	popup.clear()
	popup.add_check_item("Lock layout", 0)
	popup.set_item_checked(0, workspace.locked)
	popup.add_item("Reset workspace", 1)
	popup.add_item("Save layout as…", 2)
	var index := 100
	for preset: String in workspace.preset_names():
		popup.add_item(preset, index)
		index += 1


func _workspace_action(id: int) -> void:
	match id:
		0: workspace.toggle_lock()
		1: workspace.reset_layout()
		2: _preset_dialog.popup_centered(Vector2i(330, 110))
		_:
			if id >= 100 and id - 100 < workspace.preset_names().size():
				workspace.load_preset(workspace.preset_names()[id - 100])
