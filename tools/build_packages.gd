@tool
extends SceneTree

const DEFAULT_SOURCE_ROOT := "res://package_sources"
const DEFAULT_OUTPUT_ROOT := "res://packages"
const VIRTUAL_ROOT := "res://twber_packages"
const STAGING_ROOT := "user://twber_package_build"
const TEXT_EXTENSIONS := [
	"cfg", "csv", "gd", "gdshader", "ini", "json", "md", "shader", "tres", "tscn", "txt",
]

var _source_root := DEFAULT_SOURCE_ROOT
var _output_root := DEFAULT_OUTPUT_ROOT
var _requested_package_ids: Array[String] = []


func _run() -> void:
	_build.call_deferred()


func _build() -> void:
	if not _parse_arguments():
		quit(1)
		return
	var package_ids := _requested_package_ids if not _requested_package_ids.is_empty() else _discover_package_ids()
	if package_ids.is_empty():
		push_error("No package folders containing package.json were found in %s." % _source_root)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(_globalize(_output_root))
	var failed := false
	for package_id: String in package_ids:
		var error := _build_package(package_id)
		if error != OK:
			push_error("Could not build %s.pck: %s" % [package_id, error_string(error)])
			failed = true
		else:
			print("Built %s" % _output_root.path_join("%s.pck" % package_id))
	quit(1 if failed else 0)


func _parse_arguments() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			_source_root = argument.trim_prefix("--source-root=").trim_suffix("/")
		elif argument.begins_with("--output-root="):
			_output_root = argument.trim_prefix("--output-root=").trim_suffix("/")
		elif argument.begins_with("--"):
			push_error("Unknown package builder option: %s" % argument)
			return false
		else:
			_requested_package_ids.append(argument)
	if not _source_root.begins_with("res://"):
		push_error("The package source root must be inside the Godot project (res://).")
		return false
	return true


func _discover_package_ids() -> Array[String]:
	var package_ids: Array[String] = []
	var directory := DirAccess.open(_source_root)
	if directory == null:
		return package_ids
	var child_directories := directory.get_directories()
	child_directories.sort()
	for child_directory: String in child_directories:
		if FileAccess.file_exists(_source_root.path_join(child_directory).path_join("package.json")):
			package_ids.append(child_directory)
	return package_ids


func _build_package(package_id: String) -> Error:
	if not _is_valid_package_id(package_id):
		push_error("Package folder names may contain only lowercase letters, numbers, underscores, and hyphens.")
		return ERR_INVALID_PARAMETER
	var source_directory := _source_root.path_join(package_id)
	var manifest_path := source_directory.path_join("package.json")
	if not FileAccess.file_exists(manifest_path):
		push_error("%s does not contain package.json." % source_directory)
		return ERR_FILE_NOT_FOUND
	var source_files := _collect_files(source_directory)
	if source_files.is_empty():
		return ERR_FILE_NOT_FOUND

	var virtual_directory := VIRTUAL_ROOT.path_join(package_id)
	var manifest_error := _validate_manifest(manifest_path, package_id, source_directory, virtual_directory)
	if manifest_error != OK:
		return manifest_error

	var staging_directory := STAGING_ROOT.path_join(package_id)
	_remove_tree(staging_directory)
	DirAccess.make_dir_recursive_absolute(_globalize(staging_directory))
	var staged_files := PackedStringArray()
	for source_path: String in source_files:
		var relative_path := source_path.trim_prefix(source_directory).trim_prefix("/")
		var staged_path := staging_directory.path_join(relative_path)
		var stage_error := _stage_file(source_path, staged_path, source_directory, virtual_directory)
		if stage_error != OK:
			_remove_tree(staging_directory)
			return stage_error
		staged_files.append(staged_path)

	var output_path := _globalize(_output_root.path_join("%s.pck" % package_id))
	var packer := PCKPacker.new()
	var error := packer.pck_start(output_path)
	if error == OK:
		for staged_path: String in staged_files:
			var relative_path := staged_path.trim_prefix(staging_directory).trim_prefix("/")
			var virtual_path := virtual_directory.path_join(relative_path)
			error = packer.add_file(virtual_path, _globalize(staged_path))
			if error != OK:
				break
	if error == OK:
		error = packer.flush()
	_remove_tree(staging_directory)
	return error


func _validate_manifest(
	manifest_path: String,
	package_id: String,
	source_directory: String,
	virtual_directory: String,
) -> Error:
	var manifest_text := FileAccess.get_file_as_string(manifest_path).replace(source_directory, virtual_directory)
	var parsed: Variant = JSON.parse_string(manifest_text)
	if parsed is not Dictionary:
		push_error("%s is not valid JSON." % manifest_path)
		return ERR_PARSE_ERROR
	var manifest := parsed as Dictionary
	if String(manifest.get("id", "")) != package_id:
		push_error("The manifest id must match its folder name: %s." % package_id)
		return ERR_INVALID_DATA
	if int(manifest.get("api_version", 0)) <= 0:
		push_error("The manifest must provide a positive api_version.")
		return ERR_INVALID_DATA
	var namespace_prefix := "%s/" % virtual_directory
	var entry_scene := String(manifest.get("entry_scene", ""))
	if not entry_scene.begins_with(namespace_prefix):
		push_error("The manifest entry_scene must point inside %s." % source_directory)
		return ERR_INVALID_DATA
	var settings_scene := String(manifest.get("settings_scene", ""))
	if not settings_scene.is_empty() and not settings_scene.begins_with(namespace_prefix):
		push_error("The manifest settings_scene must point inside %s." % source_directory)
		return ERR_INVALID_DATA
	return OK


func _stage_file(
	source_path: String,
	staged_path: String,
	source_directory: String,
	virtual_directory: String,
) -> Error:
	DirAccess.make_dir_recursive_absolute(_globalize(staged_path.get_base_dir()))
	if source_path.get_extension().to_lower() not in TEXT_EXTENSIONS:
		return DirAccess.copy_absolute(_globalize(source_path), _globalize(staged_path))
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return FileAccess.get_open_error()
	var transformed_text := source_file.get_as_text().replace(source_directory, virtual_directory)
	var staged_file := FileAccess.open(staged_path, FileAccess.WRITE)
	if staged_file == null:
		return FileAccess.get_open_error()
	staged_file.store_string(transformed_text)
	return OK


func _collect_files(directory_path: String) -> PackedStringArray:
	var output := PackedStringArray()
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return output
	var files := directory.get_files()
	files.sort()
	for file_name: String in files:
		if file_name == ".gdignore" or file_name.ends_with(".uid"):
			continue
		output.append(directory_path.path_join(file_name))
	var directories := directory.get_directories()
	directories.sort()
	for child_directory: String in directories:
		output.append_array(_collect_files(directory_path.path_join(child_directory)))
	return output


func _remove_tree(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(_globalize(directory_path.path_join(file_name)))
	for child_directory: String in directory.get_directories():
		var child_path := directory_path.path_join(child_directory)
		_remove_tree(child_path)
		DirAccess.remove_absolute(_globalize(child_path))
	DirAccess.remove_absolute(_globalize(directory_path))


func _globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path


func _is_valid_package_id(package_id: String) -> bool:
	if package_id.is_empty() or package_id != package_id.to_lower():
		return false
	for character: String in package_id:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true
