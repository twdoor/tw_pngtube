class_name TwberPackageSettingsControl extends VBoxContainer

@warning_ignore("unused_signal")
signal settings_changed(settings: Dictionary)

var package: TwberEnvironmentPackage
var provider: TwberInputProvider


func configure(value: TwberEnvironmentPackage, _settings: Dictionary = {}) -> void:
	package = value
	provider = value as TwberInputProvider


func get_settings() -> Dictionary:
	return {}
