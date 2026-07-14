class_name TwberPackageManager extends Node

signal package_loaded(package_id: StringName, manifest: Dictionary, package: TwberEnvironmentPackage)
signal package_failed(path: String, reason: String)
signal discovery_finished()

const PACKAGE_API_VERSION := 1
const BUILTIN_PACKAGE_PATH := "res://packages"
const USER_PACKAGE_PATH := "user://packages"

var _packages: Dictionary[StringName, Dictionary] = {}


func discover_packages() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_PACKAGE_PATH))
	_load_packs_from_directory(USER_PACKAGE_PATH)
	var executable_package_path := OS.get_executable_path().get_base_dir().path_join("packages")
	_load_packs_from_directory(executable_package_path)
	_load_packs_from_directory(BUILTIN_PACKAGE_PATH)
	discovery_finished.emit()


func get_packages() -> Dictionary:
	return _packages.duplicate()


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
	}
	package_loaded.emit(package_id, manifest, package)


func _is_valid_package_id(package_id: String) -> bool:
	if package_id.is_empty() or package_id != package_id.to_lower():
		return false
	for character: String in package_id:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true
