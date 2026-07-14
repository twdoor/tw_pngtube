class_name TwberEnvironmentSettings extends RefCounted

const CONFIG_PATH := "user://twber_environment_settings.cfg"
const PACKAGES_SECTION := "packages"
const STATES_KEY := "states"

var package_states: Dictionary[StringName, Dictionary] = {}


func load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	var saved_states: Variant = config.get_value(PACKAGES_SECTION, STATES_KEY, {})
	if saved_states is not Dictionary:
		return
	for package_key: Variant in saved_states:
		var package_id := StringName(package_key)
		var state: Variant = saved_states[package_key]
		if package_id.is_empty() or state is not Dictionary:
			continue
		package_states[package_id] = state.duplicate(true)


func save() -> Error:
	var config := ConfigFile.new()
	config.set_value(PACKAGES_SECTION, STATES_KEY, package_states)
	return config.save(CONFIG_PATH)


func get_package_state(package_id: StringName, default_enabled: bool) -> Dictionary:
	var state: Dictionary = package_states.get(package_id, {})
	var saved_settings: Variant = state.get("settings", {})
	return {
		"installed": true,
		"enabled": bool(state.get("enabled", default_enabled)),
		"settings": saved_settings.duplicate(true) if saved_settings is Dictionary else {},
	}


func set_package_state(
		package_id: StringName,
		enabled: bool,
		settings: Dictionary,
) -> void:
	package_states[package_id] = {
		"installed": true,
		"enabled": enabled,
		"settings": settings.duplicate(true),
	}


func mark_all_packages_uninstalled() -> void:
	for package_id: StringName in package_states:
		var state: Dictionary = package_states[package_id]
		state["installed"] = false
		package_states[package_id] = state
