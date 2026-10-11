class_name TwberModelInputProfile extends RefCounted

static func load_bindings(model_path: String) -> Dictionary:
	if model_path.is_empty():
		return {}
	var bindings: Variant = TwberAppSettings.get_value(
		_section_name(model_path),
		"bindings",
		{},
	)
	return bindings.duplicate(true) if bindings is Dictionary else {}


static func save_bindings(model_path: String, bindings: Dictionary) -> Error:
	if model_path.is_empty():
		return ERR_INVALID_PARAMETER
	var section := _section_name(model_path)
	var error := TwberAppSettings.set_value(section, "model_path", model_path, false)
	if error != OK:
		return error
	error = TwberAppSettings.set_value(
		section,
		"bindings",
		bindings.duplicate(true),
		false,
	)
	return TwberAppSettings.save() if error == OK else error


static func clear_bindings(model_path: String) -> Error:
	if model_path.is_empty():
		return ERR_INVALID_PARAMETER
	return TwberAppSettings.erase_section(_section_name(model_path))


static func _section_name(model_path: String) -> String:
	return "model_profile.%s" % model_path.md5_text()
