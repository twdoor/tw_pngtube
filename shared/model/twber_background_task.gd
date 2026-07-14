class_name TwberBackgroundTask extends Node

signal completed(result: Variant)

var _thread := Thread.new()
var _started := false


func start(callable: Callable) -> Error:
	if _started or not callable.is_valid():
		return ERR_INVALID_PARAMETER
	var error := _thread.start(callable)
	if error != OK:
		return error
	_started = true
	set_process(true)
	return OK


func _process(_delta: float) -> void:
	if not _started or _thread.is_alive():
		return
	set_process(false)
	var result: Variant = _thread.wait_to_finish()
	_started = false
	completed.emit(result)
	free()


func _exit_tree() -> void:
	if _started:
		_thread.wait_to_finish()
		_started = false
