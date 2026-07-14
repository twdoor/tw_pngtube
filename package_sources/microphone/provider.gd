extends TwberInputProvider

const LEVEL_DB_ID := &"level_db"
const CAPTURE_BUS_NAME := &"Twber Microphone"
const MAX_CAPTURE_FRAMES := 4_096

@onready var _microphone_player: AudioStreamPlayer = $MicrophonePlayer

var _enabled := false
var _audio_feedback := false
var _capture_effect: AudioEffectCapture
var _last_level_db := -81.0
var _created_capture_bus := false
var _audio_input_supported := true
var _input_device := ""


func _ready() -> void:
	get_tree().root.tree_exiting.connect(_release_audio_input)
	_audio_input_supported = DisplayServer.get_name() != "headless"
	if not _audio_input_supported:
		set_process(false)
		return
	_capture_effect = _ensure_capture_effect()
	_microphone_player.stream = AudioStreamMicrophone.new()
	_microphone_player.bus = CAPTURE_BUS_NAME
	_apply_enabled_state()


func _exit_tree() -> void:
	_release_audio_input()


func _process(delta: float) -> void:
	if _capture_effect == null:
		return
	var available_frames := _capture_effect.get_frames_available()
	if available_frames <= 0:
		return
	var samples := _capture_effect.get_buffer(mini(available_frames, MAX_CAPTURE_FRAMES))
	var measured_level_db := _calculate_decibels(samples)
	var response: float = 1.0 - exp(-delta / 0.12)
	_publish_level_db(lerpf(_last_level_db if _last_level_db >= -80.0 else measured_level_db, measured_level_db, response))


func get_provider_id() -> StringName:
	return &"microphone"


func get_provider_name() -> String:
	return "Microphone Input"


func get_default_enabled() -> bool:
	return false


func is_provider_enabled() -> bool:
	return _enabled


func set_provider_enabled(value: bool) -> void:
	_enabled = value
	_apply_enabled_state()


func get_value_descriptors() -> Array[Dictionary]:
	return [{
		"id": LEVEL_DB_ID,
		"name": "Microphone level",
		"type": TYPE_FLOAT,
		"binding_scene": "res://package_sources/microphone/binding_control.tscn",
	}]


func get_package_settings() -> Dictionary:
	return {
		"input_device": _input_device,
		"audio_feedback": _audio_feedback,
	}


func apply_package_settings(settings: Dictionary) -> void:
	_audio_feedback = bool(settings.get("audio_feedback", false))
	var requested_device := String(settings.get("input_device", ""))
	if not requested_device.is_empty() and AudioServer.get_input_device_list().has(requested_device):
		_input_device = requested_device
		AudioServer.input_device = requested_device
	_apply_audio_feedback()


func get_available_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func _calculate_decibels(samples: PackedVector2Array) -> float:
	if samples.is_empty():
		return -80.0
	var sum_of_squares := 0.0
	for sample: Vector2 in samples:
		sum_of_squares += (sample.x * sample.x + sample.y * sample.y) * 0.5
	var linear_volume := sqrt(sum_of_squares / float(samples.size()))
	return -80.0 if linear_volume <= 0.0001 else clampf(linear_to_db(linear_volume), -80.0, 0.0)


func _apply_enabled_state() -> void:
	if not is_inside_tree() or not _audio_input_supported:
		set_process(false)
		return
	set_process(_enabled)
	if _enabled:
		if not _microphone_player.playing:
			_microphone_player.play()
	else:
		_microphone_player.stop()
		_publish_level_db(-80.0)


func _ensure_capture_effect() -> AudioEffectCapture:
	var bus_index := AudioServer.get_bus_index(CAPTURE_BUS_NAME)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		_created_capture_bus = true
		AudioServer.set_bus_name(bus_index, CAPTURE_BUS_NAME)
		AudioServer.set_bus_send(bus_index, &"Master")
	for effect_index: int in AudioServer.get_bus_effect_count(bus_index):
		var effect := AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectCapture:
			_apply_audio_feedback()
			return effect
	var effect := AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_index, effect)
	_apply_audio_feedback()
	return effect


func _apply_audio_feedback() -> void:
	var bus_index := AudioServer.get_bus_index(CAPTURE_BUS_NAME)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, not _audio_feedback)


func _publish_level_db(level_db: float) -> void:
	var clamped := clampf(level_db, -80.0, 0.0)
	if is_equal_approx(clamped, _last_level_db):
		return
	_last_level_db = clamped
	value_changed.emit(LEVEL_DB_ID, clamped)


func _release_audio_input() -> void:
	if _microphone_player != null:
		_microphone_player.stop()
		_microphone_player.stream = null
	if _created_capture_bus:
		var bus_index := AudioServer.get_bus_index(CAPTURE_BUS_NAME)
		if bus_index >= 0:
			AudioServer.remove_bus(bus_index)
