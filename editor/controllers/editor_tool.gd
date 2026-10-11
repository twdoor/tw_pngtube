class_name TwberEditorTool extends Node

signal document_layer_selected(id: String)

@export var panels: Array[Control] = []
@export var _model_root: Node2D
@export var _overlay: Control
@export var tool_active := false


func set_tool_active(value: bool) -> void:
	tool_active = value
	_overlay.visible = value


func get_panel_control(id: String) -> Node:
	# Each panel scene owns its unique names. Moving its dock preserves that owner.
	for panel: Control in panels:
		var control := panel.get_node_or_null(NodePath("%" + id))
		if control != null:
			return control
	return null
