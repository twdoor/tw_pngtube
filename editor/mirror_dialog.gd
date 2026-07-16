class_name TwberMirrorDialog extends AcceptDialog

signal mirror_requested(settings: Dictionary)

@onready var _geometry_x: CheckBox = %GeometryX
@onready var _geometry_y: CheckBox = %GeometryY
@onready var _bindings_x: CheckBox = %BindingsX
@onready var _bindings_y: CheckBox = %BindingsY
@onready var _new_parameter: CheckBox = %NewParameter


func _ready() -> void:
	confirmed.connect(_on_confirmed)
	canceled.connect(queue_free)
	close_requested.connect(queue_free)


func _on_confirmed() -> void:
	mirror_requested.emit({
		"geometry_x": _geometry_x.button_pressed,
		"geometry_y": _geometry_y.button_pressed,
		"bindings_x": _bindings_x.button_pressed,
		"bindings_y": _bindings_y.button_pressed,
		"new_parameter": _new_parameter.button_pressed,
	})
	queue_free()
