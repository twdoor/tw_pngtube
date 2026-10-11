class_name TwberAppSettings extends RefCounted

const MODELS_DIRECTORY_NAME := "models"
const PACKAGES_DIRECTORY_NAME := "packages"
const AUTOSAVES_DIRECTORY_NAME := "autosaves"


static func service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("AppSettings")


static func get_value(section: String, key: String, default: Variant = null) -> Variant:
	var settings := service()
	return settings.get_value(section, key, default) if settings != null else default


static func set_value(
	section: String,
	key: String,
	value: Variant,
	save_immediately := true,
) -> Error:
	var settings := service()
	if settings == null:
		return ERR_UNAVAILABLE
	return settings.set_value(section, key, value, save_immediately)


static func save() -> Error:
	var settings := service()
	return settings.save() if settings != null else ERR_UNAVAILABLE


static func get_file_path(file_name: String) -> String:
	var settings := service()
	return settings.get_file_path(file_name) if settings != null else ""


static func get_directory_path(directory_name: String) -> String:
	var normalized_name := directory_name.simplify_path()
	if (
		normalized_name.is_empty()
		or normalized_name.is_absolute_path()
		or normalized_name == ".."
		or normalized_name.begins_with("../")
	):
		return ""
	return get_file_path(normalized_name)


static func ensure_directory(directory_name: String) -> Error:
	var directory_path := get_directory_path(directory_name)
	if directory_path.is_empty():
		return ERR_INVALID_PARAMETER
	var error := DirAccess.make_dir_recursive_absolute(directory_path)
	return OK if error == ERR_ALREADY_EXISTS else error


static func erase_section(section: String, save_immediately := true) -> Error:
	var settings := service()
	if settings == null:
		return ERR_UNAVAILABLE
	return settings.erase_section(section, save_immediately)
