class_name TwberLayerResource extends Resource

enum LayerType {
	EMPTY,
	SPRITE,
	ANIMATED_SPRITE,
	MESH_SPRITE,
}

@export var id := ""
@export var name := ""
@export var type := LayerType.EMPTY
@export var children: Array[String] = []
@export var visible := true
@export var position := Vector2.ZERO
@export var scale := Vector2.ONE
@export var rotation := 0.0
@export var modulate := Color.WHITE
@export var clip_children := CanvasItem.CLIP_CHILDREN_DISABLED
@export var show_behind_parent := false
@export var texture_id := ""
@export var offset := Vector2.ZERO
@export var centered := true
@export var current_animation := "default"
@export var animations: Array[TwberAnimationResource] = []
@export var mesh: TwberMeshResource
