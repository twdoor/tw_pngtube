extends VBoxContainer

@onready var _inspector: Control = %Inspector
@onready var _empty_selection: Label = %EmptySelection


func _ready() -> void:
	_inspector.visibility_changed.connect(_refresh_hint)
	_refresh_hint()


func _refresh_hint() -> void:
	_empty_selection.visible = not _inspector.visible
