class_name TwberEnvironmentPackage extends Node

var stage_api: TwberStageApi


func set_stage_api(value: TwberStageApi) -> void:
	stage_api = value


func get_package_name() -> String:
	return name


func get_package_description() -> String:
	return ""


func is_package_enabled() -> bool:
	return true


func set_package_enabled(_enabled: bool) -> void:
	pass


func get_default_enabled() -> bool:
	return false


func get_package_settings() -> Dictionary:
	return {}


func apply_package_settings(_settings: Dictionary) -> void:
	pass
