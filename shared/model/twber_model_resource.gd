class_name TwberModelResource extends Resource

const FORMAT_VERSION := 12

@export var format_version := FORMAT_VERSION
@export var root_position := Vector2.ZERO
@export var root_scale := Vector2.ONE
@export var root_rotation := 0.0
@export var root_layer_ids: Array[String] = []
@export var layers: Array[TwberLayerResource] = []
@export var textures: Dictionary[String, Texture2D] = {}
@export var texture_sources: Dictionary[String, String] = {}
@export var parameters: Array[TwberParameterResource] = []
@export var timeline_animations: Array[TwberTimelineAnimationResource] = []


func copy_contents_from(source: TwberModelResource) -> void:
	var copy := source.duplicate(true) as TwberModelResource
	format_version = copy.format_version
	root_position = copy.root_position
	root_rotation = copy.root_rotation
	root_scale = copy.root_scale
	root_layer_ids = copy.root_layer_ids
	layers = copy.layers
	textures = copy.textures
	texture_sources = copy.texture_sources
	parameters = copy.parameters
	timeline_animations = copy.timeline_animations
