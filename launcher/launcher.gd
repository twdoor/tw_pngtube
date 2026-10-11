class_name TwberLauncher extends Control

const EDITOR_SCENE := "res://editor/editor.tscn"
const ENVIRONMENT_SCENE := "res://environment/environment.tscn"
const VERSION_SETTING := "application/config/version"
const UPDATE_SECTION := "application"
const CHECK_UPDATES_KEY := "check_updates_on_startup"

@onready var _version_label: Label = %VersionLabel
@onready var _status_label: Label = %StatusLabel
@onready var _editor_button: Button = %EditorButton
@onready var _environment_button: Button = %EnvironmentButton
@onready var _check_updates_button: Button = %CheckUpdatesButton
@onready var _open_data_button: Button = %OpenDataButton
@onready var _automatic_updates_check: CheckBox = %AutomaticUpdatesCheck
@onready var _update_dialog: ConfirmationDialog = %UpdateDialog
@onready var _update_progress: ProgressBar = %UpdateProgress
@onready var _message_dialog: AcceptDialog = %MessageDialog

var _pending_update: Dictionary = {}
var _prepared_update: Dictionary = {}
var _checking_for_updates := false
var _download_active := false


func _ready() -> void:
	_version_label.text = "Version %s" % str(ProjectSettings.get_setting(
		VERSION_SETTING,
		"development",
	))
	_editor_button.pressed.connect(_open_editor)
	_environment_button.pressed.connect(_open_environment)
	_check_updates_button.pressed.connect(_check_for_updates.bind(true))
	_open_data_button.pressed.connect(_open_data_directory)
	_automatic_updates_check.set_pressed_no_signal(bool(
		AppSettings.get_value(UPDATE_SECTION, CHECK_UPDATES_KEY, true)
	))
	_automatic_updates_check.toggled.connect(_on_automatic_updates_toggled)
	_update_dialog.confirmed.connect(_on_update_confirmed)
	_update_dialog.canceled.connect(_on_update_cancelled)
	_connect_version_manager()
	var user_arguments := OS.get_cmdline_user_args()
	if "--editor" in user_arguments:
		_open_editor.call_deferred()
		return
	if "--environment" in user_arguments:
		_open_environment.call_deferred()
		return

	if _automatic_updates_check.button_pressed and not OS.has_feature("editor"):
		_check_for_updates.call_deferred(false)


func _open_editor() -> void:
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _open_environment() -> void:
	get_tree().change_scene_to_file(ENVIRONMENT_SCENE)


func _open_data_directory() -> void:
	var error := AppSettings.open_config_directory()
	_status_label.text = (
		"Opened Twber data folder: %s" % AppSettings.config_directory_path
		if error == OK
		else "Could not open the Twber data folder: %s" % error_string(error)
	)


func _on_automatic_updates_toggled(enabled: bool) -> void:
	var error := AppSettings.set_value(UPDATE_SECTION, CHECK_UPDATES_KEY, enabled)
	if error != OK:
		_status_label.text = "Could not save update preference: %s" % error_string(error)


func _connect_version_manager() -> void:
	if VersionManager.has_signal("update_download_progress"):
		VersionManager.update_download_progress.connect(_on_update_download_progress)


func _check_for_updates(show_current_result := true) -> void:
	if _checking_for_updates or _download_active:
		return
	_checking_for_updates = true
	_check_updates_button.disabled = true
	_status_label.text = "Checking for updates…"
	var result: Dictionary = await VersionManager.check_for_updates()
	_checking_for_updates = false
	_check_updates_button.disabled = false

	if not bool(result.get("success", false)):
		_status_label.text = str(result.get("error", "Update check failed."))
		return
	if not bool(result.get("update_available", false)):
		_status_label.text = "Twber is up to date."
		if show_current_result:
			_show_message("No Update Available", _status_label.text)
		return

	_pending_update = result.duplicate(true)
	_prepared_update.clear()
	_show_available_update()


func _show_available_update() -> void:
	var version := str(_pending_update.get("latest_version", ""))
	var install_supported := bool(_pending_update.get("install_supported", false))
	_update_progress.visible = false
	_update_dialog.get_ok_button().disabled = false
	if install_supported:
		var asset: Dictionary = _pending_update.get("asset", {})
		_update_dialog.ok_button_text = "Download Update"
		_update_dialog.dialog_text = (
			"Twber %s is available.\n\nDownload and verify %s?"
			% [version, str(asset.get("name", "the platform build"))]
		)
	else:
		_update_dialog.ok_button_text = "Open Release Page"
		_update_dialog.dialog_text = (
			"Twber %s is available.\n\n%s"
			% [version, str(_pending_update.get(
				"install_error",
				"Automatic installation is unavailable.",
			))]
		)
	_update_dialog.popup_centered(Vector2i(520, 210))


func _on_update_confirmed() -> void:
	if not _prepared_update.is_empty():
		_install_prepared_update()
	elif bool(_pending_update.get("install_supported", false)):
		_download_update()
	else:
		_open_release_page()


func _download_update() -> void:
	if _download_active:
		return
	_download_active = true
	_check_updates_button.disabled = true
	_update_dialog.get_ok_button().disabled = true
	_update_progress.visible = true
	_update_progress.value = 0.0
	_update_dialog.dialog_text = "Downloading and verifying the update…"
	_update_dialog.popup_centered(Vector2i(520, 210))

	var result: Dictionary = await VersionManager.download_and_prepare_update(
		_pending_update
	)
	_download_active = false
	_check_updates_button.disabled = false
	if bool(result.get("cancelled", false)):
		_status_label.text = "Update download cancelled."
		return
	if not bool(result.get("success", false)):
		_update_progress.visible = false
		_show_message("Update Failed", str(result.get("error", "Unknown update error.")))
		return

	_prepared_update = result
	_update_progress.value = 100.0
	_update_dialog.get_ok_button().disabled = false
	_update_dialog.ok_button_text = "Install and Restart"
	_update_dialog.dialog_text = (
		"Twber %s was downloaded and verified.\n\nInstall it and restart now?"
		% str(result.get("version", ""))
	)
	_update_dialog.popup_centered(Vector2i(520, 210))


func _install_prepared_update() -> void:
	var result: Dictionary = VersionManager.launch_prepared_update(_prepared_update)
	if not bool(result.get("success", false)):
		_show_message("Update Failed", str(result.get("error", "Could not install update.")))
		return
	get_tree().quit()


func _on_update_cancelled() -> void:
	if _download_active:
		VersionManager.cancel_update_download()


func _on_update_download_progress(downloaded_bytes: int, total_bytes: int) -> void:
	if not _download_active:
		return
	if total_bytes > 0:
		_update_progress.value = clampf(
			float(downloaded_bytes) / float(total_bytes) * 100.0,
			0.0,
			100.0,
		)


func _open_release_page() -> void:
	var release_url := str(_pending_update.get("release_url", ""))
	if not release_url.is_empty():
		OS.shell_open(release_url)


func _show_message(title: String, message: String) -> void:
	_message_dialog.title = title
	_message_dialog.dialog_text = message
	_message_dialog.popup_centered(Vector2i(500, 180))
