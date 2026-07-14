class_name TwberPackageCard extends PanelContainer

signal package_state_changed(package_id: StringName, enabled: bool, settings: Dictionary)

@onready var _name_label: Label = %PackageName
@onready var _version_label: Label = %PackageVersion
@onready var _description_label: Label = %PackageDescription
@onready var _outputs_label: Label = %PackageOutputs
@onready var _enabled_button: CheckButton = %PackageEnabled
@onready var _settings_button: Button = %PackageSettingsButton
@onready var _settings_host: VBoxContainer = %PackageSettingsHost

var _package_id := StringName()
var _provider: TwberInputProvider
var _settings_control: TwberPackageSettingsControl
var _updating := false


func _ready() -> void:
	_enabled_button.toggled.connect(_on_enabled_toggled)
	_settings_button.toggled.connect(_on_settings_toggled)


func configure(
		manifest: Dictionary,
		provider: TwberInputProvider,
		enabled: bool,
		settings: Dictionary,
) -> void:
	_package_id = StringName(manifest.get("id", ""))
	_provider = provider
	_name_label.text = String(manifest.get("name", provider.get_provider_name()))
	_version_label.text = "v%s" % String(manifest.get("version", "0.0.0"))
	_description_label.text = String(manifest.get("description", provider.get_provider_description()))
	var outputs := PackedStringArray()
	for descriptor: Dictionary in provider.get_value_descriptors():
		outputs.append(String(descriptor.get("name", descriptor.get("id", "Value"))))
	_outputs_label.text = "Outputs: %s" % ", ".join(outputs)
	_updating = true
	_enabled_button.button_pressed = enabled
	_updating = false
	_provider.apply_package_settings(settings)
	_provider.set_provider_enabled(enabled)
	_create_settings_control(String(manifest.get("settings_scene", "")), settings)


func _create_settings_control(scene_path: String, settings: Dictionary) -> void:
	_settings_host.visible = false
	_settings_button.visible = not scene_path.is_empty()
	if scene_path.is_empty():
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var instance := scene.instantiate()
	if instance is not TwberPackageSettingsControl:
		instance.free()
		return
	_settings_control = instance as TwberPackageSettingsControl
	_settings_host.add_child(_settings_control)
	_settings_control.configure(_provider, settings)
	_settings_control.settings_changed.connect(_on_settings_changed)


func _on_enabled_toggled(enabled: bool) -> void:
	if _updating or _provider == null:
		return
	_provider.set_provider_enabled(enabled)
	_emit_state()


func _on_settings_toggled(expanded: bool) -> void:
	_settings_host.visible = expanded


func _on_settings_changed(settings: Dictionary) -> void:
	if _provider == null:
		return
	_provider.apply_package_settings(settings)
	_emit_state()


func _emit_state() -> void:
	var settings := _settings_control.get_settings() if _settings_control != null else _provider.get_package_settings()
	package_state_changed.emit(_package_id, _enabled_button.button_pressed, settings)

