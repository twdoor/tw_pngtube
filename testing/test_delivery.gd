extends SceneTree

const AppSettingsRuntime = preload(
	"res://addons/app_settings/app_settings_runtime.gd"
)
const VersionManagerRuntime = preload(
	"res://addons/version_manager/version_manager_runtime.gd"
)

var _failures: Array[String] = []
var _settings_directory := OS.get_temp_dir().path_join(
	"twber-delivery-test-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_application_directories()
	await _test_launcher_scene()
	_test_release_asset_selection()
	_test_application_settings()
	_cleanup()
	if _failures.is_empty():
		print("Twber delivery tests passed.")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_launcher_scene() -> void:
	var launcher_scene := load("res://launcher/launcher.tscn") as PackedScene
	_expect(launcher_scene != null, "Launcher scene loads")
	if launcher_scene == null:
		return
	var launcher := launcher_scene.instantiate()
	root.add_child(launcher)
	_expect(launcher.get_node_or_null("%EditorButton") is Button, "Launcher has an editor mode node")
	_expect(
		launcher.get_node_or_null("%EnvironmentButton") is Button,
		"Launcher has an environment mode node",
	)
	_expect(
		launcher.get_node_or_null("%OpenDataButton") is Button,
		"Launcher has a scene-backed Twber data-folder action",
	)
	_expect(
		launcher.get_node_or_null("%RecentModels") == null,
		"Launcher stays focused on choosing an application mode",
	)
	launcher.queue_free()
	await process_frame


func _test_release_asset_selection() -> void:
	var linux_assets := [
		{"name": "Twber.AppImage"},
		{"name": "Twber.x86_64"},
	]
	var windows_assets := [{"name": "Twber-windows-x86_64.zip"}]
	_expect(
		str(VersionManagerRuntime._select_release_asset(
			linux_assets, "Linux", "x86_64", "Twber.AppImage", "Twber"
		).get("name", "")) == "Twber.AppImage",
		"Updater selects the Twber AppImage",
	)
	_expect(
		str(VersionManagerRuntime._select_release_asset(
			windows_assets, "Windows", "x86_64", "Twber.exe", "Twber"
		).get("name", "")) == "Twber-windows-x86_64.zip",
		"Updater selects the complete Twber Windows package",
	)
	_expect(
		VersionManagerRuntime._select_release_asset(
			linux_assets, "Linux", "arm64", "Twber.AppImage", "Twber"
		).is_empty(),
		"Updater rejects unpublished architectures",
	)


func _test_application_directories() -> void:
	_expect(
		TwberAppSettings.ensure_directory(TwberAppSettings.MODELS_DIRECTORY_NAME) == OK,
		"Central model directory is available",
	)


func _test_application_settings() -> void:
	var override_name := str(ProjectSettings.get_setting(
		"app_settings/override_environment_variable",
		"TWBER_CONFIG_DIR",
	))
	var previous_override := OS.get_environment(override_name)
	OS.set_environment(override_name, _settings_directory)
	var settings := AppSettingsRuntime.new()
	_expect(settings.config_directory_path == _settings_directory, "Settings honor the Twber override path")
	_expect(settings.set_value("editor.appearance", "test", Color.RED) == OK, "Settings save atomically")
	var reloaded := AppSettingsRuntime.new()
	_expect(
		reloaded.get_value("editor.appearance", "test") == Color.RED,
		"Settings values survive reload",
	)
	settings.free()
	reloaded.free()
	OS.set_environment(override_name, previous_override)


func _cleanup() -> void:
	if not DirAccess.dir_exists_absolute(_settings_directory):
		return
	for file_name: String in DirAccess.get_files_at(_settings_directory):
		DirAccess.remove_absolute(_settings_directory.path_join(file_name))
	DirAccess.remove_absolute(_settings_directory)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
