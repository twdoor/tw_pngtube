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
	_expect(package_list.get_child_count() == 2, "Environment auto-generates cards for both PCK packages")
	var open_button := environment.get_node("%OpenModelButton") as Button
	var open_dialog := environment.get_node("%OpenModelDialog") as FileDialog
	open_button.pressed.emit()
	await process_frame
	_expect(open_dialog.visible, "Environment opens its embedded model dialog")
	open_dialog.hide()

	var model := _create_test_model()
	var model_path := "user://twber_environment_test.tres"
	MODEL_INPUT_PROFILE.clear_bindings(model_path)
	_expect(TwberModelCodec.save_resource(model, model_path) == OK, "Environment fixture saves")
	_expect(environment.load_model(model_path) == OK, "Environment loads a model resource")
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
	var runtime_model := environment.get_node("%RuntimeModel") as TwberRuntimeModel
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
			is_equal_approx(float(runtime_model.get_parameter_value("volume")), 0.5),
			"Microphone dB range maps to its bound float parameter",
	)
	_expect(environment.load_model(model_path) == OK, "Environment reloads a model profile")
	parameter_list = environment.get_node("%ParameterList") as VBoxContainer
	volume_control = parameter_list.get_child(1) as TwberEnvironmentParameterControl
	volume_source_option = volume_control.get_node("%SourceOption") as OptionButton
	_expect(
			StringName(volume_source_option.get_item_metadata(volume_source_option.selected)) == &"microphone.level_db",
			"Environment restores the saved parameter source",
	)
	microphone_provider.value_changed.emit(&"level_db", -35.0)
	runtime_model = environment.get_node("%RuntimeModel") as TwberRuntimeModel
	_expect(
			is_equal_approx(float(runtime_model.get_parameter_value("volume")), 0.5),
			"Environment restores the saved dB mapping range",
	)

	environment.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(model_path))
	MODEL_INPUT_PROFILE.clear_bindings(model_path)
	_finish()


func _create_test_model() -> TwberModelResource:
	var model := TwberModelResource.new()

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
