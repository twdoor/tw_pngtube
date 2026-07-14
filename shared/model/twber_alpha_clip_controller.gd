class_name TwberAlphaClipController extends Node

const CLIP_SHADER := preload("res://shared/model/twber_alpha_clip.gdshader")
const AUTHORED_CLIP_MODE_META := &"twber_alpha_clip_authored_mode"
const AUTHORED_SELF_MODULATE_META := &"twber_alpha_clip_authored_self_modulate"

var _groups: Array[Dictionary] = []


static func attach_to(model_root: Node2D) -> TwberAlphaClipController:
	for child: Node in model_root.get_children(true):
		if child is TwberAlphaClipController:
			return child
	var controller := TwberAlphaClipController.new()
	controller.name = "TwberAlphaClipController"
	model_root.add_child(controller, false, Node.INTERNAL_MODE_FRONT)
	return controller


static func get_authored_clip_mode(item: CanvasItem) -> CanvasItem.ClipChildrenMode:
	return int(item.get_meta(AUTHORED_CLIP_MODE_META, item.clip_children)) as CanvasItem.ClipChildrenMode


static func set_authored_clip_mode(item: CanvasItem, mode: CanvasItem.ClipChildrenMode) -> void:
	if item.has_meta(AUTHORED_CLIP_MODE_META):
		item.set_meta(AUTHORED_CLIP_MODE_META, int(mode))
	else:
		item.clip_children = mode


static func get_authored_self_modulate(item: CanvasItem) -> Color:
	return item.get_meta(AUTHORED_SELF_MODULATE_META, item.self_modulate) as Color


static func set_authored_self_modulate(item: CanvasItem, color: Color) -> void:
	if item.has_meta(AUTHORED_SELF_MODULATE_META):
		item.set_meta(AUTHORED_SELF_MODULATE_META, color)
		var preview_color := color
		if get_authored_clip_mode(item) == CanvasItem.CLIP_CHILDREN_ONLY:
			preview_color.a = 0.0
		item.self_modulate = preview_color
	else:
		item.self_modulate = color


func configure(model_root: Node2D) -> void:
	clear()
	if model_root == null:
		return
	for child: Node in model_root.get_children():
		_collect_clip_groups(child)
	set_process(not _groups.is_empty())
	sync_now()


func clear() -> void:
	for group: Dictionary in _groups:
		var mask_value: Variant = (group["mask"] as WeakRef).get_ref()
		if mask_value is CanvasItem:
			var mask := mask_value as CanvasItem
			mask.clip_children = get_authored_clip_mode(mask)
			mask.self_modulate = get_authored_self_modulate(mask)
			mask.remove_meta(AUTHORED_CLIP_MODE_META)
			mask.remove_meta(AUTHORED_SELF_MODULATE_META)
		for target_state: Dictionary in group["targets"]:
			var target_value: Variant = (target_state["node"] as WeakRef).get_ref()
			if target_value is CanvasItem:
				(target_value as CanvasItem).material = target_state["material"] as Material
	_groups.clear()
	set_process(false)


func sync_now(changed_layer_ids: Array[String] = []) -> void:
	for group: Dictionary in _groups:
		_sync_group(group, changed_layer_ids.has(String(group.get("layer_id", ""))))


func _process(_delta: float) -> void:
	sync_now()


func _collect_clip_groups(node: Node) -> void:
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		if canvas_item.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
			if _is_supported_mask(canvas_item):
				_create_group(canvas_item)
				return
			push_warning("Alpha-safe clipping currently supports Sprite2D and AnimatedSprite2D mask owners.")
	for child: Node in node.get_children():
		_collect_clip_groups(child)


func _create_group(mask: CanvasItem) -> void:
	var targets: Array[Dictionary] = []
	for child: Node in mask.get_children():
		_collect_visual_targets(child, targets)
	if targets.is_empty():
		return
	var group := {
		"mask": weakref(mask),
		"layer_id": String(mask.get_meta(&"twber_layer_id", "")),
		"clip_mode": mask.clip_children,
		"self_modulate": mask.self_modulate,
		"targets": targets,
	}
	mask.set_meta(AUTHORED_CLIP_MODE_META, int(mask.clip_children))
	mask.set_meta(AUTHORED_SELF_MODULATE_META, mask.self_modulate)
	mask.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	if int(group["clip_mode"]) == CanvasItem.CLIP_CHILDREN_ONLY:
		var hidden_color := mask.self_modulate
		hidden_color.a = 0.0
		mask.self_modulate = hidden_color
	for target_state: Dictionary in targets:
		var target := (target_state["node"] as WeakRef).get_ref() as CanvasItem
		var material := ShaderMaterial.new()
		material.shader = CLIP_SHADER
		target.material = material
		target_state["clip_material"] = material
	_groups.append(group)


func _collect_visual_targets(node: Node, output: Array[Dictionary]) -> void:
	if node is CanvasItem and (node as CanvasItem).clip_children != CanvasItem.CLIP_CHILDREN_DISABLED:
		return
	if node is Sprite2D or node is AnimatedSprite2D or node is TwberMeshSprite2D:
		var canvas_item := node as CanvasItem
		output.append({
			"node": weakref(canvas_item),
			"material": canvas_item.material,
		})
	for child: Node in node.get_children():
		_collect_visual_targets(child, output)


func _sync_group(group: Dictionary, capture_mask_opacity: bool) -> void:
	var mask_value: Variant = (group["mask"] as WeakRef).get_ref()
	if mask_value is not CanvasItem:
		return
	var mask := mask_value as CanvasItem
	if capture_mask_opacity:
		group["self_modulate"] = mask.self_modulate
		group["mask_opacity"] = mask.self_modulate.a
		mask.set_meta(AUTHORED_SELF_MODULATE_META, mask.self_modulate)
	else:
		var authored_color := get_authored_self_modulate(mask)
		if authored_color != group["self_modulate"]:
			group["self_modulate"] = authored_color
			group["mask_opacity"] = authored_color.a
	var mask_texture := _get_mask_texture(mask)
	if mask_texture == null:
		return
	var mapping := _get_texture_mapping(mask_texture)
	var render_texture := mapping["texture"] as Texture2D
	if render_texture == null:
		return
	var texture_size := mask_texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var mask_top_left := _get_mask_top_left(mask, texture_size)
	var mask_inverse := (mask as Node2D).global_transform.affine_inverse()
	var mask_opacity := float(group.get("mask_opacity", (group["self_modulate"] as Color).a))
	if int(group["clip_mode"]) == CanvasItem.CLIP_CHILDREN_ONLY:
		var hidden_color := group["self_modulate"] as Color
		hidden_color.a = 0.0
		mask.self_modulate = hidden_color
	for target_state: Dictionary in group["targets"]:
		var target_value: Variant = (target_state["node"] as WeakRef).get_ref()
		var material := target_state.get("clip_material") as ShaderMaterial
		if target_value is not Node2D or material == null:
			continue
		var child_to_mask := mask_inverse * (target_value as Node2D).global_transform
		material.set_shader_parameter("mask_texture", render_texture)
		material.set_shader_parameter("child_to_mask_x", child_to_mask.x)
		material.set_shader_parameter("child_to_mask_y", child_to_mask.y)
		material.set_shader_parameter("child_to_mask_origin", child_to_mask.origin)
		material.set_shader_parameter("mask_top_left", mask_top_left)
		material.set_shader_parameter("mask_size", texture_size)
		material.set_shader_parameter("mask_region_position", mapping["position"])
		material.set_shader_parameter("mask_region_size", mapping["size"])
		material.set_shader_parameter("mask_flip", _get_mask_flip(mask))
		material.set_shader_parameter("mask_opacity", mask_opacity)


func _is_supported_mask(mask: CanvasItem) -> bool:
	return mask is Sprite2D or mask is AnimatedSprite2D


func _get_mask_texture(mask: CanvasItem) -> Texture2D:
	if mask is Sprite2D:
		return (mask as Sprite2D).texture
	if mask is not AnimatedSprite2D:
		return null
	var animated := mask as AnimatedSprite2D
	if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
		return null
	var frame_count := animated.sprite_frames.get_frame_count(animated.animation)
	if frame_count <= 0:
		return null
	return animated.sprite_frames.get_frame_texture(
		animated.animation,
		clampi(animated.frame, 0, frame_count - 1),
	)


func _get_mask_top_left(mask: CanvasItem, texture_size: Vector2) -> Vector2:
	if mask is Sprite2D:
		var sprite := mask as Sprite2D
		return sprite.offset - texture_size * 0.5 if sprite.centered else sprite.offset
	var animated := mask as AnimatedSprite2D
	return animated.offset - texture_size * 0.5 if animated.centered else animated.offset


func _get_mask_flip(mask: CanvasItem) -> Vector2:
	if mask is Sprite2D:
		var sprite := mask as Sprite2D
		return Vector2(float(sprite.flip_h), float(sprite.flip_v))
	var animated := mask as AnimatedSprite2D
	return Vector2(float(animated.flip_h), float(animated.flip_v))


func _get_texture_mapping(texture: Texture2D) -> Dictionary:
	if texture is AtlasTexture:
		var atlas_texture := texture as AtlasTexture
		if atlas_texture.atlas == null:
			return {"texture": null, "position": Vector2.ZERO, "size": Vector2.ZERO}
		var atlas_size := atlas_texture.atlas.get_size()
		return {
			"texture": atlas_texture.atlas,
			"position": atlas_texture.region.position / atlas_size,
			"size": atlas_texture.region.size / atlas_size,
		}
	return {"texture": texture, "position": Vector2.ZERO, "size": Vector2.ONE}
