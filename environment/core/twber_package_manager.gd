class_name TwberPackageManager extends Node

signal package_loaded(package_id: StringName, manifest: Dictionary, package: TwberEnvironmentPackage)
signal package_failed(path: String, reason: String)
signal discovery_finished()

const PACKAGE_API_VERSION := 1
const BUNDLED_PACKAGE_PATH := "res://packages"
const COPY_BUFFER_SIZE := 1024 * 1024
const SEMANTIC_VERSION := preload("res://addons/version_manager/semantic_version.gd")

var _packages: Dictionary[StringName, Dictionary] = {}
var _package_directory_path := ""
var _bundled_package_ids: Dictionary[StringName, bool] = {}


func discover_packages() -> void:
	_package_directory_path = TwberAppSettings.get_directory_path(
		TwberAppSettings.PACKAGES_DIRECTORY_NAME
	)
	if _package_directory_path.is_empty():
		package_failed.emit("", "Twber application-data directory is unavailable")
		discovery_finished.emit()
		return
	var directory_error := TwberAppSettings.ensure_directory(
		TwberAppSettings.PACKAGES_DIRECTORY_NAME
	)
	if directory_error != OK:
		package_failed.emit(
			_package_directory_path,
			"Could not create package directory: %s" % error_string(directory_error),
		)
		discovery_finished.emit()
		return
	_synchronize_bundled_packages(_package_directory_path)
	_load_packs_from_directory(_package_directory_path)
	discovery_finished.emit()


func get_packages() -> Dictionary:
	return _packages.duplicate()


func get_package_directory_path() -> String:
	if _package_directory_path.is_empty():
		_package_directory_path = TwberAppSettings.get_directory_path(
			TwberAppSettings.PACKAGES_DIRECTORY_NAME
		)
	return _package_directory_path


func install_package(source_path: String) -> Dictionary:
	var normalized_source := ProjectSettings.globalize_path(source_path).simplify_path()
	if not FileAccess.file_exists(normalized_source):
		return {"success": false, "error": "The selected package does not exist."}
	if normalized_source.get_extension().to_lower() != "pck":
		return {"success": false, "error": "Twber packages must use the .pck extension."}
	var package_id := normalized_source.get_file().get_basename()
	if not _is_valid_package_id(package_id):
		return {
			"success": false,
			"error": "The PCK filename must be a lowercase package id.",
		}
	if is_bundled_package(package_id):
		return {
			"success": false,
			"error": "Bundled packages are updated together with Twber.",
		}
	var directory_error := TwberAppSettings.ensure_directory(
		TwberAppSettings.PACKAGES_DIRECTORY_NAME
	)
	if directory_error != OK:
		return {
			"success": false,
			"error": "Could not create the package directory: %s" % error_string(directory_error),
		}
	var destination_path := get_package_directory_path().path_join(
		normalized_source.get_file()
	)
	var source_hash := FileAccess.get_sha256(normalized_source)
	var destination_existed := FileAccess.file_exists(destination_path)
	if (
		destination_existed
		and not source_hash.is_empty()
		and FileAccess.get_sha256(destination_path) == source_hash
	):
		return {
			"success": true,
			"package_id": package_id,
			"restart_required": false,
			"message": "%s is already installed." % normalized_source.get_file(),
		}
	var copy_error := _copy_package_if_changed(normalized_source, destination_path)
	if copy_error != OK:
		return {
			"success": false,
			"error": "Could not install the package: %s" % error_string(copy_error),
		}

	# Godot resource packs cannot be unloaded. Replacing any package that may
	# already be mounted therefore takes effect at the next application start.
	if destination_existed or _packages.has(StringName(package_id)):
		return {
			"success": true,
			"package_id": package_id,
			"restart_required": true,
			"message": "%s was updated." % normalized_source.get_file(),
		}
	_load_package_pack(destination_path, package_id)
	if not _packages.has(StringName(package_id)):
		DirAccess.remove_absolute(destination_path)
		return {
			"success": false,
			"restart_required": true,
			"error": "The package failed validation and was not kept.",
		}
	return {
		"success": true,
		"package_id": package_id,
		"restart_required": false,
		"message": "%s was installed." % normalized_source.get_file(),
	}


func remove_package(package_id: StringName) -> Dictionary:
	if package_id.is_empty() or not _is_valid_package_id(String(package_id)):
		return {"success": false, "error": "Invalid package id."}
	if is_bundled_package(package_id):
		return {
			"success": false,
			"error": "Bundled packages are part of Twber and cannot be removed.",
		}
	var package_path := get_package_directory_path().path_join("%s.pck" % package_id)
	if not FileAccess.file_exists(package_path):
		return {"success": false, "error": "The package file is already missing."}
	var error := DirAccess.remove_absolute(package_path)
	if error != OK:
		return {
			"success": false,
			"error": "Could not remove the package: %s" % error_string(error),
		}
	return {
		"success": true,
		"package_id": String(package_id),
		"restart_required": _packages.has(package_id),
		"message": "%s.pck was removed." % package_id,
	}


func is_bundled_package(package_id: Variant) -> bool:
	return _bundled_package_ids.has(StringName(package_id))


func open_package_directory() -> Error:
	var error := TwberAppSettings.ensure_directory(
		TwberAppSettings.PACKAGES_DIRECTORY_NAME
	)
	if error == OK:
		OS.shell_show_in_file_manager(get_package_directory_path(), true)
	return error


func _synchronize_bundled_packages(destination_directory: String) -> void:
	var source_directory := _find_bundled_package_source()
	if source_directory.is_empty():
		return
	var source := DirAccess.open(source_directory)
	if source == null:
		package_failed.emit(source_directory, "Could not open bundled package directory")
		return
	var files := source.get_files()
	files.sort()
	for file_name: String in files:
		if file_name.get_extension().to_lower() != "pck":
			continue
		_bundled_package_ids[StringName(file_name.get_basename())] = true
		var source_path := source_directory.path_join(file_name)
		var destination_path := destination_directory.path_join(file_name)
		var copy_error := _copy_package_if_changed(source_path, destination_path)
		if copy_error != OK:
			package_failed.emit(
				source_path,
				"Could not synchronize bundled package: %s" % error_string(copy_error),
			)


func _find_bundled_package_source() -> String:
	var executable_packages := OS.get_executable_path().get_base_dir().path_join(
		TwberAppSettings.PACKAGES_DIRECTORY_NAME
	)
	var candidates: Array[String] = [BUNDLED_PACKAGE_PATH]
	if not OS.has_feature("editor"):
		candidates.push_front(executable_packages)
	for candidate: String in candidates:
		var directory := DirAccess.open(candidate)
		if directory == null:
			continue
		for file_name: String in directory.get_files():
			if file_name.get_extension().to_lower() == "pck":
				return candidate
	return ""


func _copy_package_if_changed(source_path: String, destination_path: String) -> Error:
	var source_hash := FileAccess.get_sha256(source_path)
	if source_hash.is_empty():
		return ERR_FILE_CANT_READ
	if (
		FileAccess.file_exists(destination_path)
		and FileAccess.get_sha256(destination_path) == source_hash
	):
		return OK

	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return FileAccess.get_open_error()
	var temporary_path := destination_path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		var remove_error := DirAccess.remove_absolute(temporary_path)
		if remove_error != OK:
			source.close()
			return remove_error
	var destination := FileAccess.open(temporary_path, FileAccess.WRITE)
	if destination == null:
		var open_error := FileAccess.get_open_error()
		source.close()
		return open_error
	while source.get_position() < source.get_length():
		var remaining := source.get_length() - source.get_position()
		destination.store_buffer(source.get_buffer(mini(COPY_BUFFER_SIZE, remaining)))
	source.close()
	destination.close()
	if FileAccess.get_sha256(temporary_path) != source_hash:
		DirAccess.remove_absolute(temporary_path)
		return ERR_FILE_CORRUPT
	var backup_path := destination_path + ".bak"
	if FileAccess.file_exists(backup_path):
		var backup_remove_error := DirAccess.remove_absolute(backup_path)
		if backup_remove_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return backup_remove_error
	var had_destination := FileAccess.file_exists(destination_path)
	if had_destination:
		var backup_error := DirAccess.rename_absolute(destination_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return backup_error
	var install_error := DirAccess.rename_absolute(temporary_path, destination_path)
	if install_error != OK:
		if had_destination:
			DirAccess.rename_absolute(backup_path, destination_path)
		DirAccess.remove_absolute(temporary_path)
		return install_error
	if had_destination:
		DirAccess.remove_absolute(backup_path)
	return OK


func _load_packs_from_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	var files := directory.get_files()
	files.sort()
	for file_name: String in files:
		if file_name.get_extension().to_lower() != "pck":
			continue
		_load_package_pack(directory_path.path_join(file_name), file_name.get_basename())


func _load_package_pack(pack_path: String, expected_id: String) -> void:
	if not _is_valid_package_id(expected_id):
		package_failed.emit(pack_path, "PCK filename is not a valid package id")
		return
	if _packages.has(StringName(expected_id)):
		return
	if not ProjectSettings.load_resource_pack(pack_path, false):
		package_failed.emit(pack_path, "Could not mount resource pack")
		return
	var manifest_path := "res://twber_packages/%s/package.json" % expected_id
	if not FileAccess.file_exists(manifest_path):
		package_failed.emit(pack_path, "Missing %s" % manifest_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if parsed is not Dictionary:
		package_failed.emit(pack_path, "Package manifest is not valid JSON")
		return
	var manifest: Dictionary = parsed
	var package_id := StringName(manifest.get("id", ""))
	if package_id.is_empty() or String(package_id) != expected_id:
		package_failed.emit(pack_path, "Manifest id must match the PCK filename")
		return
	if int(manifest.get("api_version", 0)) != PACKAGE_API_VERSION:
		package_failed.emit(pack_path, "Unsupported package API version")
		return
	if String(manifest.get("name", "")).strip_edges().is_empty():
		package_failed.emit(pack_path, "Package manifest requires a name")
		return
	if not bool(SEMANTIC_VERSION.parse(String(manifest.get("version", ""))).get(
		"valid",
		false,
	)):
		package_failed.emit(pack_path, "Package version must use semantic versioning")
		return
	if _packages.has(package_id):
		package_failed.emit(pack_path, "Package id is already loaded")
		return

	var package_namespace := "res://twber_packages/%s/" % package_id
	var entry_scene_path := String(manifest.get("entry_scene", ""))
	if not entry_scene_path.begins_with(package_namespace):
		package_failed.emit(pack_path, "Entry scene must be inside the package namespace")
		return
	var settings_scene_path := String(manifest.get("settings_scene", ""))
	if not settings_scene_path.is_empty() and not settings_scene_path.begins_with(package_namespace):
		package_failed.emit(pack_path, "Settings scene must be inside the package namespace")
		return
	var entry_scene := load(entry_scene_path) as PackedScene
	if entry_scene == null:
		package_failed.emit(pack_path, "Could not load package entry scene")
		return
	var instance := entry_scene.instantiate()
	if instance is not TwberEnvironmentPackage:
		instance.free()
		package_failed.emit(pack_path, "Entry scene must extend TwberEnvironmentPackage")
		return
	var package := instance as TwberEnvironmentPackage
	if package is TwberInputProvider:
		for descriptor: Dictionary in (package as TwberInputProvider).get_value_descriptors():
			var binding_scene_path := String(descriptor.get("binding_scene", ""))
			if not binding_scene_path.is_empty() and not binding_scene_path.begins_with(package_namespace):
				package.free()
				package_failed.emit(pack_path, "Binding scenes must be inside the package namespace")
				return
	add_child(package)
	_packages[package_id] = {
		"manifest": manifest,
		"package": package,
		"pack_path": pack_path,
		"bundled": is_bundled_package(package_id),
	}
	package_loaded.emit(package_id, manifest, package)


func _is_valid_package_id(package_id: String) -> bool:
	if package_id.is_empty() or package_id != package_id.to_lower():
		return false
	for character: String in package_id:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true
