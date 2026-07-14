class_name TwberInputBindingControl extends VBoxContainer

@warning_ignore("unused_signal")
signal configuration_changed(configuration: Dictionary)

var parameter: TwberParameterResource


func configure(value: TwberParameterResource, _configuration: Dictionary = {}) -> void:
	parameter = value


func get_configuration() -> Dictionary:
	return {}


func apply_source_value(value: Variant) -> Variant:
	return value


func set_preview(_raw_value: Variant, _mapped_value: Variant) -> void:
	pass

