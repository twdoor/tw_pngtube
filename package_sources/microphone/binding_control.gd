extends TwberInputBindingControl

@onready var _bool_settings: VBoxContainer = %BoolSettings
@onready var _threshold: SpinBox = %Threshold
@onready var _bool_meter: Control = %BoolMeter
@onready var _bool_preview_label: Label = %BoolPreviewLabel
@onready var _range_settings: VBoxContainer = %RangeSettings
@onready var _minimum: SpinBox = %Minimum
@onready var _maximum: SpinBox = %Maximum
@onready var _range_meter: Control = %RangeMeter
@onready var _preview_label: Label = %PreviewLabel

var _updating := false


func _ready() -> void:
	_threshold.value_changed.connect(_on_configuration_changed)
	_minimum.value_changed.connect(_on_configuration_changed)
	_maximum.value_changed.connect(_on_configuration_changed)


func configure(value: TwberParameterResource, configuration: Dictionary = {}) -> void:
	super.configure(value, configuration)
	var is_bool := parameter.value_type == TwberParameterResource.ValueType.BOOL
	_bool_settings.visible = is_bool
	_range_settings.visible = not is_bool
	_updating = true
	_threshold.value = float(configuration.get("threshold_db", -40.0))
	_minimum.value = float(configuration.get("minimum_db", -60.0))
	_maximum.value = float(configuration.get("maximum_db", -10.0))
	_updating = false
	_bool_meter.set_threshold_db(_threshold.value)


func get_configuration() -> Dictionary:
	if parameter != null and parameter.value_type == TwberParameterResource.ValueType.BOOL:
		return {"threshold_db": _threshold.value}
	return {
		"minimum_db": minf(_minimum.value, _maximum.value),
		"maximum_db": maxf(_minimum.value, _maximum.value),
	}


func apply_source_value(value: Variant) -> Variant:
	if value is not float or parameter == null:
		return value
	var level_db := float(value)
	if parameter.value_type == TwberParameterResource.ValueType.BOOL:
		return level_db >= float(get_configuration().get("threshold_db", -40.0))
	var settings := get_configuration()
	var amount := clampf(inverse_lerp(float(settings["minimum_db"]), float(settings["maximum_db"]), level_db), 0.0, 1.0)
	var mapped := lerpf(parameter.get_scalar_min(), parameter.get_scalar_max(), amount)
	if parameter.value_type == TwberParameterResource.ValueType.INT:
		return int(roundf(mapped))
	return mapped


func set_preview(raw_value: Variant, mapped_value: Variant) -> void:
	if raw_value is not float:
		return
	var level_db := float(raw_value)
	if parameter.value_type == TwberParameterResource.ValueType.BOOL:
		_bool_meter.set_level_db(level_db)
		_bool_preview_label.text = "%0.1f dB  |  %s" % [level_db, "On" if bool(mapped_value) else "Off"]
		return
	_range_meter.set_level_db(level_db)
	_preview_label.text = "%0.1f dB  |  %s" % [level_db, _format_mapped_value(mapped_value)]


func _on_configuration_changed(_value: float) -> void:
	_bool_meter.set_threshold_db(_threshold.value)
	if not _updating:
		configuration_changed.emit(get_configuration())


func _format_mapped_value(value: Variant) -> String:
	if parameter != null and parameter.value_type == TwberParameterResource.ValueType.INT:
		return str(int(value))
	var value_step := maxf(parameter.step, 0.0001) if parameter != null else 0.01
	var decimals := clampi(int(ceil(-log(value_step) / log(10.0))), 0, 3) if value_step < 1.0 else 0
	var result := String.num(float(value), decimals)
	if result.contains("."):
		while result.ends_with("0"):
			result = result.trim_suffix("0")
		result = result.trim_suffix(".")
	return result
