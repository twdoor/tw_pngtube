class_name TwberInputProvider extends Node

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


func is_provider_enabled() -> bool:
	return true


func set_provider_enabled(_enabled: bool) -> void:
	pass


func get_default_enabled() -> bool:
	return false


func get_package_settings() -> Dictionary:
	return {}


func apply_package_settings(_settings: Dictionary) -> void:
	pass


func get_value_descriptors() -> Array[Dictionary]:
	return []
