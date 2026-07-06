class_name TwberModelResource extends Resource

const FORMAT_VERSION := 1

@export var format_version := FORMAT_VERSION
@export var root_position := Vector2.ZERO
@export var root_scale := Vector2.ONE
@export var root_rotation := 0.0
@export var root_layer_ids: Array[String] = []
@export var layers: Array[Resource] = []
@export var textures: Dictionary = {}
@export var texture_sources: Dictionary = {}
