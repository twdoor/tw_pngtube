extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var editor := load("res://editor/editor.tscn").instantiate() as TwberEditor
	var authored_workspace := editor.get_node("%Workspace") as TwberWorkspace
	_expect(authored_workspace != null, "Workspace is authored in the Editor scene")
	for controller: Node in editor.get_node("Controllers").get_children():
		_expect(controller is TwberEditorTool and not controller is Control,
			"Mode controllers do not retain hidden UI shells")
	var authored_tools := authored_workspace.get_node("%Tools") as TwberDockPanel
	_expect(authored_tools.get_node("Content/Body").get_child_count() == 4,
		"All tool variants exist before ready without runtime UI construction")
	root.add_child(editor)
	await _settle()
	var workspace := editor._workspace_binding.workspace
	_expect(not editor._unsaved_changes_dialog.visible, "Unsaved-changes dialog does not block the initial editor")
	workspace.reset_layout()
	var model := _model()
	editor._apply_opened_model(model, "")
	editor._mode_bar.current_tab = 0
	editor._editor_placer.select_document_layer("head")
	await _settle()
	var document := editor._document
	var revision := document.get_revision()
	var root_node := editor._model_root
	var layer := root_node.get_child(0)
	var camera := root_node.transform
	var panel_owner := editor._editor_placer._move_button.owner
	_expect(workspace.canvas.clip_contents, "Canvas clips artwork and tool overlays")
	_expect(workspace.canvas.get_global_rect().size.x >= 160, "Default layout leaves a usable canvas")
	_expect(root_node.get_parent() == workspace.canvas, "Artwork is inside the persistent canvas")
	workspace.move_panel("layers", "canvas", "right")
	workspace.move_panel("tools", "inspector", "center")
	await _settle()
	_expect(editor._editor_placer.get_panel_control("MoveButton") == editor._editor_placer._move_button and editor._editor_placer._move_button.owner == panel_owner,
		"Docking preserves panel scene ownership and unique-name references")
	_expect(root_node == editor._model_root and layer == root_node.get_child(0) and camera == root_node.transform,
		"Docking preserves render nodes and camera")
	_expect(document.get_revision() == revision and not editor.is_dirty(), "Layout changes never author a document or history entry")
	_expect(editor._editor_placer.get_selected_document_layer_id() == "head", "Docking preserves layer selection")
	var group := TwberWorkspace._find(workspace.layout, "inspector")
	_expect(group.panels == ["inspector", "tools"], "Center drop forms a tab group")
	workspace.set_panel_hidden("tools", true)
	_expect(editor._editor_placer.tool_active, "Hiding tools does not deactivate the authoring mode")
	workspace.set_panel_hidden("tools", false)
	var snapshot := workspace.capture_layout()
	workspace.reset_layout()
	_expect(workspace.restore_layout(snapshot), "Saved split/tab layouts can be restored")
	workspace.rebuild()
	_expect(workspace.capture_layout().tree == snapshot.tree, "Layout restoration retains placement and selected tabs")
	var malformed := snapshot.duplicate(true)
	malformed.tree = {"type": "split", "axis": "h", "ratio": NAN, "a": {}, "b": {}}
	_expect(not workspace.restore_layout(malformed) and workspace.capture_layout().tree == snapshot.tree,
		"Invalid layout data leaves the working arrangement intact")
	malformed = snapshot.duplicate(true)
	malformed.tree = {"type": "group", "id": "duplicate", "panels": ["layers", "layers"]}
	_expect(not workspace.restore_layout(malformed), "Duplicate panels and missing canvas are rejected")
	workspace.locked = true
	workspace.move_panel("layers", "canvas", "left")
	_expect(workspace.capture_layout().tree == snapshot.tree, "Layout lock prevents rearrangement")
	workspace.locked = false
	workspace.save_preset("Test layout")
	workspace.reset_layout()
	workspace.load_preset("Test layout")
	_expect(workspace.capture_layout().tree == snapshot.tree, "Named presets restore layout without changing modes")
	editor._mode_bar.current_tab = 1
	_expect(editor._editor_mesher._selected_node == layer and editor._editor_mesher.tool_active and not editor._editor_placer.tool_active,
		"Mode switches carry stable layer selection and explicitly activate one tool")
	editor._mode_bar.current_tab = 2
	var rig := editor._editor_rigger
	_expect(rig._selected_node == layer, "Selection follows the layer into Rig")
	rig.edit_pose({"position": Vector2(28, 10)})
	_expect(editor._has_pose_draft(), "Rig has a temporary pose draft")
	var pose := rig.pose_draft.pose().duplicate(true) as TwberLayerStateResource
	workspace.move_panel("parameters", "canvas", "bottom")
	workspace.set_panel_hidden("inspector", true)
	workspace.save_preset("Draft layout")
	workspace.load_preset("Draft layout")
	await _settle()
	_expect(rig.pose_draft.has_draft() and rig.pose_draft.pose().position == pose.position and document.get_revision() == revision,
		"Docking, hiding, and presets retain the unbound pose without committing it")
	editor._mode_bar.current_tab = 3
	_expect(not editor._has_pose_draft() and editor._editor_animator._selected_node == layer,
		"Authoring mode changes still discard drafts and retain selected layer")
	var animator := editor._editor_animator
	animator._playhead = 0.35
	animator._apply_animation_at_playhead()
	workspace.move_panel("timeline", "canvas", "bottom")
	_expect(is_equal_approx(animator._playhead, 0.35), "Moving timeline preserves its playhead")
	animator._toggle_playback()
	workspace.set_panel_hidden("timeline", true)
	_expect(animator._playing, "Hiding the timeline does not stop playback")
	animator.stop_and_restore()
	editor._mode_bar.current_tab = 2
	editor._toggle_parameter_recording()
	var take := editor._parameter_take
	workspace.move_panel("parameters", "canvas", "right")
	workspace.set_panel_hidden("parameters", true)
	_expect(take != null and editor._parameter_take == take, "Recording survives panel docking and hiding")
	editor._cancel_external_focus_edits()
	_expect(editor._parameter_take == null, "Actual application departure still cancels the editor take")
	workspace.reset_layout()
	workspace.save_layout()
	var saved: Variant = TwberAppSettings.get_value(TwberWorkspace.SECTION, "layout", {})
	_expect(saved is Dictionary and saved.get("version") == TwberWorkspace.VERSION, "Workspace settings use the shared settings service")
	await _test_panel_minimums(editor)
	await _test_compact_tools(editor)
	await _test_drag(editor)
	if DisplayServer.get_name() != "headless":
		await _test_windows(editor)
		await _test_canvas_pixels(editor)
		editor._mode_bar.current_tab = 0
		await _settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/twber-workspace.png")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	var tools_panel := workspace.panels.tools as TwberDockPanel
	tools_panel._on_grip_input(right_click)
	_expect(tools_panel.popup.visible and tools_panel.popup.item_count == 9, "Right-click exposes all panel actions without permanent chrome")
	tools_panel.popup.hide()
	var final_layout := workspace.capture_layout()
	editor.queue_free()
	await _settle()
	var reopened := load("res://editor/editor.tscn").instantiate() as TwberEditor
	root.add_child(reopened)
	await _settle()
	_expect(reopened._workspace_binding.workspace.capture_layout().tree == final_layout.tree,
		"A new editor session restores the saved layout")
	reopened.queue_free()
	await _settle()
	_expect(_failures.is_empty(), "Workspace checks complete")
	if _failures.is_empty():
		print("Twber workspace tests passed (%s)." % DisplayServer.get_name())
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _test_panel_minimums(editor: TwberEditor) -> void:
	var workspace := editor._workspace_binding.workspace
	for mode: int in 4:
		editor._mode_bar.current_tab = mode
		workspace.reset_layout()
		await _settle()
		for id: String in ["inspector", "clips", "timeline"]:
			if not workspace.is_available(id):
				continue
			var panel: TwberDockPanel = workspace.panels[id]
			var content: Control = panel.variants[mode]
			_expect(content is VBoxContainer, "%s uses its content minimum without an outer scroller" % id)
			var minimum := content.get_combined_minimum_size()
			_expect(panel.size.x >= minimum.x and panel.size.y >= minimum.y,
				"%s keeps every fixed control within its minimum size in mode %d" % [id, mode])
		_expect(workspace._groups.layers == workspace.panels.layers,
			"Standalone docks do not add a redundant tab container")
		_expect(root.min_size.x >= workspace.get_combined_minimum_size().x and root.min_size.y >= workspace.get_combined_minimum_size().y,
			"The main window respects the current workspace minimum")


func _test_compact_tools(editor: TwberEditor) -> void:
	var workspace := editor._workspace_binding.workspace
	workspace.reset_layout()
	var panel := workspace.panels.tools as TwberDockPanel
	_expect(panel.find_children("*", "MenuButton", true, false).is_empty(), "Panels have no permanent menu button")
	_expect(panel.body.find_children("*", "ScrollContainer", true, false).is_empty(), "Tools do not need scroll wrappers")
	for mode: int in 4:
		editor._mode_bar.current_tab = mode
		await _settle()
		workspace.move_panel("tools", "canvas", "top")
		await _settle()
		var strip := panel.variants[mode] as TwberToolStrip
		var first := strip.get_child(0) as Control
		var last := strip.get_child(strip.get_child_count() - 1) as Control
		_expect(panel.size.y <= 52 and is_equal_approx(first.position.y, last.position.y),
			"Mode %d tools fit a single horizontal row" % mode)
		_expect(last.position.x + last.size.x <= strip.size.x,
			"Horizontal tools remain accessible without scrolling in mode %d" % mode)
		workspace.move_panel("tools", "canvas", "left")
		await _settle()
		_expect(panel.size.x <= 52 and is_equal_approx(first.position.x, last.position.x),
			"Mode %d tools fit a single vertical column" % mode)
		_expect(is_equal_approx(first.position.x + first.size.x, strip.size.x),
			"A single tool column fills its width without an empty right gutter in mode %d" % mode)
		_expect(last.position.y + last.size.y <= strip.size.y,
			"Vertical tools remain accessible without scrolling in mode %d" % mode)
	workspace.reset_layout()


func _test_drag(_editor: TwberEditor) -> void:
	# An isolated viewport uses event coordinates rather than the OS cursor,
	# allowing the same real GUI drag/drop test on headless and Wayland backends.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var workspace := load("res://editor/workspace/workspace.tscn").instantiate() as TwberWorkspace
	(workspace.get_node("%Tools") as Control).size_flags_stretch_ratio = 0.1
	(workspace.get_node("%Tools").get_parent().get_child(1) as Control).size_flags_stretch_ratio = 0.9
	viewport.add_child(workspace)
	_expect(is_equal_approx(float(workspace.default_layout().ratio), 0.1),
		"Reset layout reads the authored scene's stretch ratios")
	workspace.initialize()
	workspace.set_mode(0)
	await _settle()
	var before: Dictionary = workspace.capture_layout().tree
	var panel: TwberDockPanel = workspace.panels.layers
	var data := {"type": "twber_workspace_panel", "host": workspace.get_instance_id(), "panel": "layers"}
	var origin := panel.grip.global_position + panel.grip.size * 0.5
	var enter := InputEventMouseMotion.new()
	enter.position = origin
	viewport.push_input(enter, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = origin
	viewport.push_input(press, true)
	var begin := InputEventMouseMotion.new()
	begin.position = origin + Vector2(20, 0)
	begin.relative = Vector2(20, 0)
	begin.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(begin, true)
	await process_frame
	_expect(workspace._drop_overlay.visible, "Dragging a panel grip exposes docking targets")
	var point := workspace.canvas.global_position + workspace.canvas.size * Vector2(0.95, 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(motion, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = point
	viewport.push_input(release, true)
	await _settle()
	_expect(workspace.capture_layout().tree != before, "A real GUI drop moves the panel beside the canvas")
	_expect(not workspace._drop_overlay.visible, "The drop preview clears after a completed drag")
	before = workspace.capture_layout().tree
	panel.force_drag(data, Label.new())
	await process_frame
	viewport.gui_cancel_drag()
	await _settle()
	_expect(workspace.capture_layout().tree == before, "Cancelling a drag leaves its source layout intact")
	_expect(not workspace._drop_overlay.visible, "Cancellation removes the docking overlay")
	viewport.queue_free()
	await process_frame


func _test_windows(editor: TwberEditor) -> void:
	var workspace := editor._workspace_binding.workspace
	editor._mode_bar.current_tab = 2
	workspace.reset_layout()
	root.grab_focus()
	await create_timer(0.2).timeout
	_expect(root.has_focus(), "Native focus test acquires the main editor window")
	editor._editor_rigger.edit_pose({"position": Vector2(35, 10)})
	workspace.float_panel("inspector")
	var window := workspace._windows.get("inspector") as Window
	_expect(window != null and window.visible, "Float creates a native panel window")
	window.grab_focus()
	await create_timer(0.2).timeout
	await _settle()
	_expect(editor._has_pose_draft(), "Focus moving into a floating Inspector preserves a pose draft")
	var minimum := (workspace.panels.inspector as Control).get_combined_minimum_size().ceil()
	_expect(window.min_size == Vector2i(minimum), "Floating Inspector enforces its content minimum")
	_expect((workspace.panels.inspector as Control).get_window() == window, "Floating mounts the existing panel instance")
	editor._toggle_parameter_recording()
	var take := editor._parameter_take
	workspace.redock_panel("inspector")
	root.grab_focus()
	await create_timer(0.2).timeout
	await _settle()
	_expect(editor._parameter_take == take and take != null, "Redocking returns focus without cancelling recording")
	editor._cancel_parameter_recording()
	workspace.float_panel("parameters")
	await _settle()
	window = workspace._windows.parameters
	window.close_requested.emit()
	await _settle()
	_expect(not workspace._windows.has("parameters") and not workspace.floating.has("parameters"), "Closing a native panel redocks it")


func _test_canvas_pixels(editor: TwberEditor) -> void:
	editor._mode_bar.current_tab = 0
	var workspace := editor._workspace_binding.workspace
	workspace.reset_layout()
	await _settle()
	var model_root := editor._model_root
	var camera := model_root.transform
	var anchor := model_root.to_global(Vector2(15, 5))
	editor._model_preview._zoom_model_at(anchor, 1.2)
	_expect(model_root.to_global(Vector2(15, 5)).is_equal_approx(anchor), "Zoom anchors remain correct under the canvas Control")
	model_root.scale = Vector2.ONE
	model_root.position = Vector2(-20, workspace.canvas.size.y * 0.5)
	editor._editor_placer.refresh_overlay()
	await _settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var edge := workspace.canvas.global_position + Vector2(0, workspace.canvas.size.y * 0.5 + 10)
	var inside := image.get_pixelv(Vector2i(edge + Vector2(5, 0)))
	var outside := image.get_pixelv(Vector2i(edge - Vector2(2, 0)))
	_expect(inside.g > 0.7 and inside.r < 0.4, "Artwork renders inside the docked canvas")
	_expect(outside.g < 0.7, "Artwork is clipped at the canvas edge")
	model_root.transform = camera
	editor._editor_placer.refresh_overlay()


func _model() -> TwberModelResource:
	var model := TwberModelResource.new()
	model.root_scale = Vector2.ONE
	var layer := TwberLayerResource.new()
	layer.id = "head"
	layer.name = "Head"
	layer.position = Vector2(10, 10)
	layer.type = TwberLayerResource.LayerType.SPRITE
	layer.texture_id = "art"
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color("40e5aa"))
	model.textures["art"] = ImageTexture.create_from_image(image)
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)
	var parameter := TwberParameterResource.new()
	parameter.id = "turn"
	parameter.name = "Head turn"
	model.parameters.append(parameter)
	var clip := TwberTimelineAnimationResource.new()
	clip.id = "idle"
	clip.name = "Idle"
	clip.duration = 2.0
	model.timeline_animations.append(clip)
	return model


func _settle() -> void:
	for index: int in 5:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
