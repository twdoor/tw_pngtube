class_name TwberEnvironmentSettings extends RefCounted

const PACKAGES_SECTION := "packages"
const STATES_KEY := "states"
const WORKSPACE_SECTION := "workspace"
const WORKSPACE_ENTRIES_KEY := "entries"
const WORKSPACE_SELECTED_KEY := "selected"

var package_states: Dictionary[StringName, Dictionary] = {}
var workspace_entries: Array[Dictionary] = []
var workspace_selected := -1


func load() -> void:
	package_states.clear()
	workspace_entries.clear()
	workspace_selected = -1
	var saved_states: Variant = TwberAppSettings.get_value(
		"environment.%s" % PACKAGES_SECTION,
		STATES_KEY,
		{},
	)
	if saved_states is Dictionary:
		for package_key: Variant in saved_states:
			var package_id := StringName(package_key)
			var state: Variant = saved_states[package_key]
			if package_id.is_empty() or state is not Dictionary:
				continue
			package_states[package_id] = state.duplicate(true)

	var saved_entries: Variant = TwberAppSettings.get_value(
		"environment.%s" % WORKSPACE_SECTION,
		WORKSPACE_ENTRIES_KEY,
		[],
	)
	if saved_entries is Array:
		for entry: Variant in saved_entries:
			if entry is Dictionary:
				workspace_entries.append((entry as Dictionary).duplicate(true))
	workspace_selected = int(TwberAppSettings.get_value(
		"environment.%s" % WORKSPACE_SECTION,
		WORKSPACE_SELECTED_KEY,
		-1,
	))


func save() -> Error:
	var error := TwberAppSettings.set_value(
		"environment.%s" % PACKAGES_SECTION,
		STATES_KEY,
		package_states,
		false,
	)
	if error != OK:
		return error
	error = TwberAppSettings.set_value(
		"environment.%s" % WORKSPACE_SECTION,
		WORKSPACE_ENTRIES_KEY,
		workspace_entries,
		false,
	)
	if error != OK:
		return error
	error = TwberAppSettings.set_value(
		"environment.%s" % WORKSPACE_SECTION,
		WORKSPACE_SELECTED_KEY,
		workspace_selected,
		false,
	)
	return TwberAppSettings.save() if error == OK else error


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


func set_workspace(entries: Array[Dictionary], selected_index: int) -> void:
	workspace_entries.clear()
	for entry: Dictionary in entries:
		workspace_entries.append(entry.duplicate(true))
	workspace_selected = selected_index


func get_workspace() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in workspace_entries:
		entries.append(entry.duplicate(true))
	return {"entries": entries, "selected": workspace_selected}
