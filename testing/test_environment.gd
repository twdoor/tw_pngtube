extends SceneTree

const MODEL_INPUT_PROFILE := preload("res://environment/core/twber_model_input_profile.gd")

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var environment_scene := load("res://environment/environment.tscn") as PackedScene
	_expect(environment_scene != null, "Environment scene loads")
	if environment_scene == null:
		_finish()
		return

	var environment := environment_scene.instantiate() as TwberEnvironment
	get_root().add_child(environment)
	await process_frame
	var package_list := environment.get_node("%PackageList") as VBoxContainer
	_expect(package_list.get_child_count() == 4, "Environment auto-generates cards for all PCK packages")
	var open_button := environment.get_node("%OpenModelButton") as Button
	var open_dialog := environment.get_node("%OpenModelDialog") as FileDialog
	_expect(
		not environment.get_viewport().gui_embed_subwindows,
		"Environment dialogs use separate windows",
	)
	open_button.pressed.emit()
	await process_frame
	_expect(open_dialog.visible, "Environment opens its model dialog")
	open_dialog.hide()
	var error_dialog := environment.get_node("%ErrorDialog") as AcceptDialog
	environment.call("_show_error", "Test error", "Test message")
	await process_frame
	_expect(error_dialog.visible, "Environment opens its error dialog")
	error_dialog.hide()
	var embedded_dock := environment.get_node("%EmbeddedDock") as PanelContainer
	var control_dock := environment.get_node("%ControlDock") as VBoxContainer
	var detach_button := environment.get_node("%DetachControlsButton") as Button
	var detached_window := environment.get_node("%DetachedControlsWindow") as Window
	var detached_host := environment.get_node("%DetachedDockMargin") as MarginContainer
	detach_button.pressed.emit()
	await process_frame
	_expect(
		control_dock.get_parent() == detached_host
		and detached_window.visible
		and not embedded_dock.visible,
		"Environment controls detach into their own window",
	)
	detached_window.close_requested.emit()
	await process_frame
	_expect(
		control_dock.get_parent() != detached_host
		and not detached_window.visible
		and embedded_dock.visible,
		"Closing the detached controls window embeds the dock again",
	)
	var package_manager := environment.get_node("%PackageManager") as TwberPackageManager

	var model := _create_test_model()
	var model_path := "user://twber_environment_test.tres"
	MODEL_INPUT_PROFILE.clear_bindings(model_path)
	_expect(TwberModelCodec.save_resource(model, model_path) == OK, "Environment fixture saves")
	var load_error: Error = await environment.load_model_async(model_path)
	_expect(
		load_error == OK
		and not environment.is_busy()
		and environment.get_model_count() == 1
		and (environment.get_node("%OperationStatusLabel") as Label).text.begins_with("Loaded "),
		"Environment loads a model resource in the background",
	)
	_expect(environment.get_current_model_path() == model_path, "Environment remembers the model path")

	var parameter_list := environment.get_node("%ParameterList") as VBoxContainer
	_expect(parameter_list.get_child_count() == 3, "Environment creates one scene-backed control per parameter")
	var bool_control := parameter_list.get_child(0) as TwberEnvironmentParameterControl
	var bool_source_option := bool_control.get_node("%SourceOption") as OptionButton
	_expect(bool_source_option.item_count == 2, "Bool parameters discover the microphone level source")
	if bool_source_option.item_count == 2:
		bool_source_option.select(1)
		bool_source_option.item_selected.emit(1)
		_expect(not (bool_control.get_node("%BoolEditor") as CheckButton).visible, "Bound bool parameters hide their manual control")
	var volume_control := parameter_list.get_child(1) as TwberEnvironmentParameterControl
	var volume_source_option := volume_control.get_node("%SourceOption") as OptionButton
	_expect(volume_source_option.item_count == 2, "Float parameters discover the microphone volume source")
	if volume_source_option.item_count == 2:
		volume_source_option.select(1)
		volume_source_option.item_selected.emit(1)
		_expect(not (volume_control.get_node("%ScalarEditor") as HBoxContainer).visible, "Bound scalar parameters hide their manual control")

	var vector_control := parameter_list.get_child(2) as TwberEnvironmentParameterControl
	var source_option := vector_control.get_node("%SourceOption") as OptionButton
	_expect(source_option.item_count == 2, "Vector parameters discover the mouse position source")
	if source_option.item_count == 2:
		source_option.select(1)
		source_option.item_selected.emit(1)
		_expect((vector_control.get_node("%BindingHost") as VBoxContainer).get_child_count() == 1, "Mouse binding UI loads from its PCK")
		var mouse_binding := (vector_control.get_node("%BindingHost") as VBoxContainer).get_child(0)
		var display_option := mouse_binding.get_node("%DisplayOption") as OptionButton
		_expect(int(display_option.get_item_metadata(display_option.selected)) == -1, "Mouse bindings default to automatic display tracking")

	var mouse_provider := environment.get_package_provider(&"mouse")
	_expect(mouse_provider != null, "Mouse provider loads from mouse.pck")
	var tracked_screen := maxi(DisplayServer.get_screen_count() - 1, 0)
	var tracked_display := Rect2i(
		DisplayServer.screen_get_position(tracked_screen),
		DisplayServer.screen_get_size(tracked_screen),
	)
	var source_value := Vector2(tracked_display.get_center())
	mouse_provider.value_changed.emit(&"position", source_value)
	var runtime_model := environment.get_selected_model()
	_expect(
		runtime_model.name == "TwberEnvironmentTest",
		"Environment names model nodes from their source file",
	)
	_expect(
			runtime_model.get_parameter_value("look").is_equal_approx(Vector2.ZERO),
		"Automatic mouse tracking maps the pointer relative to its current display",
	)
	var microphone_provider := environment.get_package_provider(&"microphone")
	_expect(microphone_provider != null, "Microphone provider loads from microphone.pck")
	microphone_provider.value_changed.emit(&"level_db", -45.0)
	_expect(runtime_model.get_parameter_value("enabled") == false, "Microphone bool threshold rejects quiet audio")
	microphone_provider.value_changed.emit(&"level_db", -35.0)
	_expect(runtime_model.get_parameter_value("enabled") == true, "Microphone bool threshold enables loud audio")
	_expect(
		float(runtime_model.get_parameter_value("volume")) < 0.5,
		"Continuous package inputs do not jump directly to their target",
	)
	environment.call("_process", 0.25)
	_expect(
		is_equal_approx(float(runtime_model.get_parameter_value("volume")), 0.5),
		"Microphone dB range eases to its bound float parameter",
	)
	var first_runtime_model := runtime_model
	_expect(environment.load_model(model_path) == OK, "Environment adds another model with its saved profile")
	_expect(environment.get_model_count() == 2, "Environment keeps multiple model instances on stage")
	_expect(
		environment.get_selected_model().name == "TwberEnvironmentTest2",
		"Duplicate model instances receive readable numbered names",
	)
	var model_stage := environment.get_node("%ModelStage") as Node2D
	environment.call("_select_model", first_runtime_model)
	_expect(
		model_stage.get_child(model_stage.get_child_count() - 1) == first_runtime_model,
		"Selecting an older model brings it in front of newer stage items",
	)
	environment.call("_select_model", environment.call("_get_stage_items")[0])
	runtime_model = environment.get_selected_model()
	parameter_list = environment.get_node("%ParameterList") as VBoxContainer
	volume_control = parameter_list.get_child(1) as TwberEnvironmentParameterControl
	volume_source_option = volume_control.get_node("%SourceOption") as OptionButton
	_expect(
			StringName(volume_source_option.get_item_metadata(volume_source_option.selected)) == &"microphone.level_db",
			"Environment restores the saved parameter source",
	)
	microphone_provider.value_changed.emit(&"level_db", -35.0)
	runtime_model = environment.get_selected_model()
	_expect(
		is_equal_approx(float(runtime_model.get_parameter_value("volume")), 0.5),
		"Environment restores the saved dB mapping range",
	)
	_expect(
		is_equal_approx(float(first_runtime_model.get_parameter_value("volume")), 0.5),
		"One input source updates every model instance with that binding",
	)
	var original_position := runtime_model.position
	var animated_sprite := AnimatedSprite2D.new()
	animated_sprite.sprite_frames = SpriteFrames.new()
	animated_sprite.sprite_frames.clear(&"default")
	var animated_image := Image.create(24, 18, false, Image.FORMAT_RGBA8)
	animated_image.fill(Color.WHITE)
	animated_sprite.sprite_frames.add_frame(
		&"default",
		ImageTexture.create_from_image(animated_image),
	)
	runtime_model.add_child(animated_sprite)
	var animated_bounds: Rect2 = environment.call("_get_model_global_bounds", runtime_model)
	_expect(
		animated_bounds.has_area() and animated_bounds.has_point(animated_sprite.global_position),
		"Stage selection calculates AnimatedSprite2D bounds from its current frame",
	)
	_expect(
		environment.call(
			"_get_model_attachment_anchor",
			runtime_model,
			animated_sprite.global_position,
		) == animated_sprite,
		"Animated sprite attachment targets sample the current frame without crashing",
	)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = runtime_model.global_position
	environment.call("_on_preview_gui_input", press)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(25.0, -10.0)
	environment.call("_on_preview_gui_input", drag)
	_expect(
		runtime_model.position.is_equal_approx(original_position + drag.relative),
		"Dragging moves only the selected model",
	)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	environment.call("_on_preview_gui_input", wheel)
	_expect(runtime_model.scale.x > 1.0, "Mouse wheel scales the selected model")
	var stage_api: TwberStageApi = environment.get("_stage_api") as TwberStageApi
	var target_bounds: Rect2 = environment.call("_get_model_global_bounds", first_runtime_model)
	_expect(
		stage_api.get_attachment_anchor(first_runtime_model, target_bounds.position + Vector2.ONE) == null,
		"Transparent pixels are not valid attachment targets",
	)
	runtime_model.global_position = first_runtime_model.global_position
	stage_api.item_drag_ended.emit(runtime_model)
	await process_frame
	var attached_position := runtime_model.global_position
	var parent_motion := Vector2(18.0, 12.0)
	first_runtime_model.global_position += parent_motion
	await process_frame
	_expect(
		runtime_model.global_position.is_equal_approx(attached_position + parent_motion),
		"Attachment package makes a dropped model follow its parent model",
	)
	var target_layer := _find_layer_node(first_runtime_model, "stage_test_layer")
	var before_layer_motion := runtime_model.global_position
	var layer_motion := Vector2(7.0, -4.0)
	target_layer.position += layer_motion
	await process_frame
	_expect(
		runtime_model.global_position.is_equal_approx(before_layer_motion + layer_motion),
		"An attachment follows the moving model layer under its drop point",
	)
	var attached_scale := runtime_model.scale * 1.1
	runtime_model.scale = attached_scale
	await process_frame
	_expect(
		runtime_model.scale.is_equal_approx(attached_scale),
		"An attached model can still be scaled independently",
	)
	environment.call("_select_model", first_runtime_model)
	_expect(
		model_stage.get_child(model_stage.get_child_count() - 1) == runtime_model,
		"Selecting an attachment parent also brings its attached items forward",
	)
	stage_api.item_drag_started.emit(runtime_model)
	var detached_position := runtime_model.global_position
	first_runtime_model.global_position += parent_motion
	await process_frame
	_expect(
		runtime_model.global_position.is_equal_approx(detached_position),
		"Dragging an attached model detaches it",
	)
	var selector := environment.get_node("%ModelSelector") as OptionButton
	selector.select(0)
	selector.item_selected.emit(0)
	_expect(environment.get_selected_model() == first_runtime_model, "Model selector changes the active model")
	environment.remove_selected_model()
	_expect(
		environment.get_model_count() == 1
		and environment.get_selected_model() == runtime_model
		and selector.item_count == 1,
		"Removing the selected model keeps the remaining stage model active",
	)
	var asset_path := "user://twber_environment_asset_test.png"
	var asset_image := Image.create(20, 12, false, Image.FORMAT_RGBA8)
	asset_image.fill(Color(0.8, 0.2, 0.4, 1.0))
	_expect(asset_image.save_png(asset_path) == OK, "Image asset fixture saves")
	var background_record: Dictionary = package_manager.get_packages().get(&"background", {})
	var background_package := background_record.get("package") as TwberEnvironmentPackage
	var background_color := Color(0.12, 0.34, 0.56, 0.78)
	background_package.apply_package_settings({"mode": "color", "color": background_color})
	_expect(
		(environment.get_node("%BackgroundColor") as ColorRect).color.is_equal_approx(background_color)
		and not (environment.get_node("%BackgroundImage") as TextureRect).visible,
		"Background package applies a solid color",
	)
	background_package.apply_package_settings({"mode": "image", "image_path": asset_path})
	_expect(
		(environment.get_node("%BackgroundImage") as TextureRect).visible
		and (environment.get_node("%BackgroundImage") as TextureRect).texture != null,
		"Background package loads a custom image",
	)
	var attachment_record: Dictionary = package_manager.get_packages().get(&"attachment", {})
	var attachment_package := attachment_record.get("package") as TwberEnvironmentPackage
	attachment_package.call("_on_files_dropped", PackedStringArray([asset_path]))
	await process_frame
	while environment.is_busy():
		await process_frame
	_expect(
		environment.get_model_count() == 2
		and environment.get_selected_model().name == "TwberEnvironmentAssetTest",
		"Dropping an image file into the app adds it as an attachment asset",
	)

	await process_frame
	environment.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(model_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(asset_path))
	MODEL_INPUT_PROFILE.clear_bindings(model_path)
	_finish()


func _create_test_model() -> TwberModelResource:
	var model := TwberModelResource.new()
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in range(8, 24):
		for x: int in range(8, 24):
			image.set_pixel(x, y, Color.WHITE)
	model.textures["stage_test_texture"] = ImageTexture.create_from_image(image)
	var layer := TwberLayerResource.new()
	layer.id = "stage_test_layer"
	layer.name = "Stage Test Layer"
	layer.type = TwberLayerResource.LayerType.SPRITE
	layer.texture_id = "stage_test_texture"
	model.layers.append(layer)
	model.root_layer_ids.append(layer.id)

	var enabled := TwberParameterResource.new()
	enabled.id = "enabled"
	enabled.name = "Enabled"
	enabled.value_type = TwberParameterResource.ValueType.BOOL
	model.parameters.append(enabled)

	var volume := TwberParameterResource.new()
	volume.id = "volume"
	volume.name = "Volume"
	volume.value_type = TwberParameterResource.ValueType.FLOAT
	volume.min_value = 0.0
	volume.max_value = 1.0
	model.parameters.append(volume)

	var look := TwberParameterResource.new()
	look.id = "look"
	look.name = "Look"
	look.value_type = TwberParameterResource.ValueType.VECTOR2
	look.min_vector2 = Vector2(-1.0, -1.0)
	look.max_vector2 = Vector2.ONE
	model.parameters.append(look)

	return model


func _find_layer_node(parent: Node, layer_id: String) -> Node2D:
	for child: Node in parent.get_children():
		if child is Node2D and String(child.get_meta(TwberModelCodec.LAYER_ID_META, "")) == layer_id:
			return child as Node2D
		var nested := _find_layer_node(child, layer_id)
		if nested != null:
			return nested
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Twber environment test passed.")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
