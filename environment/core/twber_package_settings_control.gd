class_name TwberPackageSettingsControl extends VBoxContainer

@warning_ignore("unused_signal")
signal settings_changed(settings: Dictionary)

var provider: TwberInputProvider


func configure(value: TwberInputProvider, _settings: Dictionary = {}) -> void:
	provider = value


func get_settings() -> Dictionary:
	return {}

