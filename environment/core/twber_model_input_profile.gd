class_name TwberModelInputProfile extends RefCounted

const PROFILE_PATH := "user://twber_environment_profiles.cfg"


static func load_bindings(model_path: String) -> Dictionary:
	if model_path.is_empty():
		return {}
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) != OK:
		return {}
	var bindings: Variant = config.get_value(_section_name(model_path), "bindings", {})
	return bindings.duplicate(true) if bindings is Dictionary else {}


static func save_bindings(model_path: String, bindings: Dictionary) -> Error:
	if model_path.is_empty():
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	var section := _section_name(model_path)
	config.set_value(section, "model_path", model_path)
	config.set_value(section, "bindings", bindings.duplicate(true))
	return config.save(PROFILE_PATH)


static func clear_bindings(model_path: String) -> Error:
	if model_path.is_empty():
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) != OK:
		return OK
	var section := _section_name(model_path)
	if config.has_section(section):
		config.erase_section(section)
	return config.save(PROFILE_PATH)


static func _section_name(model_path: String) -> String:
	return "model_%s" % model_path.md5_text()
