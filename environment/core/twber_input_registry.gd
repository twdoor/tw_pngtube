class_name TwberInputRegistry extends Node

signal value_changed(source_id: StringName, value: Variant)

var _providers: Dictionary[StringName, TwberInputProvider] = {}
var _descriptors: Dictionary[StringName, Dictionary] = {}
var _latest_values: Dictionary[StringName, Variant] = {}


func _ready() -> void:
	for child: Node in get_children():
		if child is TwberInputProvider:
			register_provider(child)


func register_provider(provider: TwberInputProvider) -> bool:
	var provider_id := provider.get_provider_id()
	if provider_id.is_empty() or _providers.has(provider_id):
		return false

	_providers[provider_id] = provider
	for descriptor: Dictionary in provider.get_value_descriptors():
		var value_id := StringName(descriptor.get("id", ""))
		if value_id.is_empty():
			continue
		var source_id := _make_source_id(provider_id, value_id)
		var registered_descriptor := descriptor.duplicate()
		registered_descriptor["source_id"] = source_id
		registered_descriptor["provider_id"] = provider_id
		registered_descriptor["provider_name"] = provider.get_provider_name()
		_descriptors[source_id] = registered_descriptor

	provider.value_changed.connect(_on_provider_value_changed.bind(provider_id))
	return true


func get_compatible_sources(parameter: TwberParameterResource) -> Array[Dictionary]:
	var compatible: Array[Dictionary] = []
	if parameter == null:
		return compatible

	for source_id: StringName in _descriptors:
		var descriptor: Dictionary = _descriptors[source_id]
		if not _is_source_compatible(parameter.value_type, int(descriptor.get("type", TYPE_NIL))):
			continue
		compatible.append(descriptor.duplicate())

	compatible.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("name", "")) < String(second.get("name", ""))
	)
	return compatible


func get_latest_value(source_id: StringName) -> Variant:
	return _latest_values.get(source_id)


func get_provider(provider_id: StringName) -> TwberInputProvider:
	return _providers.get(provider_id)


func _on_provider_value_changed(
		value_id: StringName,
		value: Variant,
		provider_id: StringName,
) -> void:
	var source_id := _make_source_id(provider_id, value_id)
	if not _descriptors.has(source_id):
		return
	_latest_values[source_id] = value
	value_changed.emit(source_id, value)


func _make_source_id(provider_id: StringName, value_id: StringName) -> StringName:
	return StringName("%s.%s" % [provider_id, value_id])


func _is_source_compatible(parameter_type: int, source_type: int) -> bool:
	if source_type == TYPE_FLOAT:
		return parameter_type in [
			TwberParameterResource.ValueType.BOOL,
			TwberParameterResource.ValueType.INT,
			TwberParameterResource.ValueType.FLOAT,
		]
	if source_type == TYPE_VECTOR2:
		return parameter_type == TwberParameterResource.ValueType.VECTOR2
	return source_type == TYPE_BOOL and parameter_type == TwberParameterResource.ValueType.BOOL
