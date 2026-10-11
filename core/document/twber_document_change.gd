class_name TwberDocumentChange extends RefCounted

enum Kind { STRUCTURE = 1, REST_POSE = 2, RIG = 4, ANIMATION = 8, ASSETS = 16 }

var revision := 0
var label := ""
var kinds := 0
var layer_ids: Array[String] = []


func _init(value_revision := 0, value_label := "", value_kinds := 0, value_ids: Array[String] = []) -> void:
	revision = value_revision
	label = value_label
	kinds = value_kinds
	layer_ids = value_ids.duplicate()
