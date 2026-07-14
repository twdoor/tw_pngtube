class_name TwberInputProvider extends TwberEnvironmentPackage

# Providers emit this from their own scripts; the base contract intentionally
# does not emit a sample itself.
@warning_ignore("unused_signal")
signal value_changed(value_id: StringName, value: Variant)


func get_provider_id() -> StringName:
	return &""


func get_provider_name() -> String:
	return String(get_provider_id())


func get_provider_description() -> String:
	return ""


func get_package_name() -> String:
	return get_provider_name()


func get_package_description() -> String:
	return get_provider_description()


func is_provider_enabled() -> bool:
	return true


func set_provider_enabled(_enabled: bool) -> void:
	pass


func is_package_enabled() -> bool:
	return is_provider_enabled()


func set_package_enabled(enabled: bool) -> void:
	set_provider_enabled(enabled)


func get_default_enabled() -> bool:
	return false


func get_package_settings() -> Dictionary:
	return {}


func apply_package_settings(_settings: Dictionary) -> void:
	pass


func get_value_descriptors() -> Array[Dictionary]:
	return []
