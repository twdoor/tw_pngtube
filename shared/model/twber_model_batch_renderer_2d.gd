class_name TwberModelBatchRenderer2D extends Node2D

const NODE_NAME := "TwberBatchRenderer"
const SOURCE_VISIBILITY_LAYER := 1 << 19
const MAX_VERTICES_PER_BATCH := 65535

static var _viewport_mask_user_counts := {}
static var _viewport_mask_originally_enabled := {}

var _model_root: Node2D
var _active := false
var _dirty := false
var _dynamic_dirty := false
var _dynamic_update_all := false
var _batches: Array[Dictionary] = []
var _dynamic_entries: Array[Dictionary] = []
var _dynamic_entry_indices_by_node_id := {}
var _pending_dynamic_node_ids := {}
var _source_states: Array[Dictionary] = []
var _observed_nodes: Array[WeakRef] = []
var _root_inverse_transform := Transform2D.IDENTITY
var _masked_viewport: WeakRef
var _masked_viewport_id := 0


static func attach_to(model_root: Node2D) -> TwberModelBatchRenderer2D:
	if model_root == null:
		return null
	var existing := find_on(model_root)
	if existing != null:
		return existing
	var renderer := TwberModelBatchRenderer2D.new()
	renderer.name = NODE_NAME
	model_root.add_child(renderer, false, Node.INTERNAL_MODE_FRONT)
	return renderer


static func find_on(model_root: Node2D) -> TwberModelBatchRenderer2D:
	if model_root == null:
		return null
	for child: Node in model_root.get_children(true):
		if child is TwberModelBatchRenderer2D:
			return child
	return null


func _enter_tree() -> void:
	_acquire_source_cull_mask()


func configure(model_root: Node2D) -> bool:
	_release_source_cull_mask()
	_restore_sources()
	_disconnect_observed_nodes()
	_model_root = model_root
	_batches.clear()
	_dynamic_entries.clear()
	_dynamic_entry_indices_by_node_id.clear()
	_pending_dynamic_node_ids.clear()
	_active = false
	_dirty = false
	_dynamic_dirty = false
	_dynamic_update_all = false
	set_process(false)
	queue_redraw()
	if _model_root == null or _has_batching_barrier(_model_root):
		return false

	var visual_nodes: Array[CanvasItem] = []
	_collect_visual_nodes(_model_root, visual_nodes)
	if visual_nodes.size() < 2:
		return false

	for node: CanvasItem in visual_nodes:
		_source_states.append({
			"node": weakref(node),
			"visibility_layer": node.visibility_layer,
		})
		node.visibility_layer = SOURCE_VISIBILITY_LAYER
		if node is TwberMeshSprite2D:
			(node as TwberMeshSprite2D).standalone_rendering_enabled = false

	_observe_model_tree(_model_root)
	_active = true
	_acquire_source_cull_mask()
	rebuild_now()
	return true


func request_rebuild() -> void:
	if not _active or _dirty:
		return
	_dirty = true
	set_process(true)


func request_dynamic_update() -> void:
	if not _active or _dirty:
		return
	_dynamic_update_all = true
	_dynamic_dirty = true
	set_process(true)


func request_dynamic_update_for_node(node: Node2D) -> void:
	if not _active or _dirty or node == null or _dynamic_update_all:
		return
	_pending_dynamic_node_ids[node.get_instance_id()] = true
	_dynamic_dirty = true
	set_process(true)


func rebuild_now() -> void:
	if not _active or _model_root == null or not is_instance_valid(_model_root):
		return
	_batches.clear()
	_dynamic_entries.clear()
	_dynamic_entry_indices_by_node_id.clear()
	_pending_dynamic_node_ids.clear()
	_root_inverse_transform = _model_root.get_global_transform().affine_inverse()
	_append_model_children(_model_root, true)
	_dirty = false
	_dynamic_dirty = false
	_dynamic_update_all = false
	set_process(false)
	queue_redraw()


func update_dynamic_geometry() -> void:
	if not _active:
		return
	if _dirty:
		rebuild_now()
		return
	var entry_indices: Array[int] = []
	for entry_index: int in _dynamic_entries.size():
		entry_indices.append(entry_index)
	if not _update_dynamic_entry_indices(entry_indices):
		rebuild_now()
		return
	_pending_dynamic_node_ids.clear()
	_dynamic_update_all = false
	_dynamic_dirty = false
	set_process(false)


func update_dynamic_geometry_for_nodes(nodes: Array[Node2D]) -> void:
	if not _active:
		return
	if _dirty:
		rebuild_now()
		return
	var requested_node_ids := _pending_dynamic_node_ids.duplicate()
	for node: Node2D in nodes:
		if node != null:
			requested_node_ids[node.get_instance_id()] = true
	var seen_entry_indices := {}
	var entry_indices: Array[int] = []
	for node_id: Variant in requested_node_ids:
		for entry_index: int in _dynamic_entry_indices_by_node_id.get(node_id, []):
			if seen_entry_indices.has(entry_index):
				continue
			seen_entry_indices[entry_index] = true
			entry_indices.append(entry_index)
	if _dynamic_update_all:
		update_dynamic_geometry()
		return
	if not _update_dynamic_entry_indices(entry_indices):
		rebuild_now()
		return
	_pending_dynamic_node_ids.clear()
	_dynamic_dirty = false
	set_process(false)


func _update_dynamic_entry_indices(entry_indices: Array[int]) -> bool:
	if entry_indices.is_empty():
		return true
	_root_inverse_transform = _model_root.get_global_transform().affine_inverse()
	for entry_index: int in entry_indices:
		if entry_index < 0 or entry_index >= _dynamic_entries.size():
			request_rebuild()
			return false
		var entry: Dictionary = _dynamic_entries[entry_index]
		var reference: WeakRef = entry["node"]
		var value: Variant = reference.get_ref()
		if value is not Node2D:
			request_rebuild()
			return false
		var node: Node2D = value
		if not node.is_visible_in_tree():
			request_rebuild()
			return false
		var local_vertices := _get_dynamic_local_vertices(node, String(entry["kind"]))
		if local_vertices.size() != int(entry["vertex_count"]):
			request_rebuild()
			return false
		var current_texture := _get_dynamic_render_texture(node, String(entry["kind"]))
		if current_texture != entry["texture"]:
			request_rebuild()
			return false

		var batch_index := int(entry["batch_index"])
		if batch_index < 0 or batch_index >= _batches.size():
			request_rebuild()
			return false
		var batch: Dictionary = _batches[batch_index]
		var vertices: PackedVector2Array = batch["vertices"]
		var colors: PackedColorArray = batch["colors"]
		var batch_uvs: PackedVector2Array = batch["uvs"]
		var vertex_start := int(entry["vertex_start"])
		var relative_transform := _get_relative_transform(node)
		var dynamic_uvs := (
				_get_dynamic_quad_uvs(node)
				if String(entry["kind"]) == "quad"
				else PackedVector2Array()
		)
		for vertex_index: int in local_vertices.size():
			vertices[vertex_start + vertex_index] = relative_transform * local_vertices[vertex_index]
			colors[vertex_start + vertex_index] = node.self_modulate
			if dynamic_uvs.size() == local_vertices.size():
				batch_uvs[vertex_start + vertex_index] = dynamic_uvs[vertex_index]
		batch["vertices"] = vertices
		batch["colors"] = colors
		batch["uvs"] = batch_uvs
	queue_redraw()
	return true


func is_batching_active() -> bool:
	return _active


func get_batch_count() -> int:
	return _batches.size()


func clear() -> void:
	_release_source_cull_mask()
	_restore_sources()
	_disconnect_observed_nodes()
	_model_root = null
	_active = false
	_dirty = false
	_dynamic_dirty = false
	_batches.clear()
	_dynamic_entries.clear()
	_dynamic_entry_indices_by_node_id.clear()
	_pending_dynamic_node_ids.clear()
	set_process(false)
	_dynamic_update_all = false
	queue_redraw()


func _exit_tree() -> void:
	_release_source_cull_mask()
	_restore_sources()
	_disconnect_observed_nodes()


func _process(_delta: float) -> void:
	if _dirty:
		rebuild_now()
	elif _dynamic_dirty:
		if _dynamic_update_all:
			update_dynamic_geometry()
		else:
			var nodes: Array[Node2D] = []
			update_dynamic_geometry_for_nodes(nodes)
	else:
		set_process(false)


func _draw() -> void:
	for batch: Dictionary in _batches:
		var texture: Texture2D = batch["texture"] as Texture2D
		if texture == null:
			continue
		RenderingServer.canvas_item_add_triangle_array(
				get_canvas_item(),
				batch["indices"],
				batch["vertices"],
				batch["colors"],
				batch["uvs"],
				PackedInt32Array(),
				PackedFloat32Array(),
				texture.get_rid(),
				-1,
		)


func _has_batching_barrier(node: Node) -> bool:
	if node != _model_root and node is not Node2D:
		# The flat traversal is defined for the model's Node2D hierarchy. Unknown
		# container types may hide an interleaved CanvasItem, so keep them intact.
		return true
	if node is CanvasItem:
		var canvas_item: CanvasItem = node
		if (
				canvas_item.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED
				or canvas_item.material != null
				or canvas_item.use_parent_material
				or canvas_item.modulate != Color.WHITE
				or canvas_item.z_index != 0
				or canvas_item.y_sort_enabled
				or canvas_item.show_behind_parent
				or canvas_item.visibility_layer != 1
				or canvas_item.light_mask != 1
				or canvas_item.texture_filter != 0
				or canvas_item.texture_repeat != 0
		):
			return true
		if canvas_item is not Node2D:
			return true
	if node is Node2D and (node as Node2D).top_level:
		return true
	if (
			node != _model_root
			and node is Node2D
			and not _is_supported_visual(node)
			and (node.get_class() != "Node2D" or node.get_script() != null)
	):
		# Flattening across an unsupported drawing node would change interleaved
		# order. Treat unfamiliar/scripted Node2D types as a correctness barrier.
		return true
	if node is Sprite2D:
		var sprite: Sprite2D = node
		if sprite.region_enabled or sprite.hframes != 1 or sprite.vframes != 1:
			return true
	for child: Node in node.get_children():
		if _has_batching_barrier(child):
			return true
	return false


func _collect_visual_nodes(parent: Node, output: Array[CanvasItem]) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue
		if _is_supported_visual(child):
			output.append(child)
		_collect_visual_nodes(child, output)


func _observe_model_tree(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue
		var node_2d: Node2D = child
		_observed_nodes.append(weakref(node_2d))
		if not node_2d.visibility_changed.is_connected(request_rebuild):
			node_2d.visibility_changed.connect(request_rebuild)
		if node_2d is TwberMeshSprite2D:
			var mesh_sprite: TwberMeshSprite2D = node_2d
			var mesh_callback := _on_mesh_render_data_changed.bind(mesh_sprite)
			if not mesh_sprite.render_data_changed.is_connected(mesh_callback):
				mesh_sprite.render_data_changed.connect(mesh_callback)
		elif node_2d is AnimatedSprite2D:
			var animated_sprite: AnimatedSprite2D = node_2d
			var animation_callback := _on_animated_sprite_render_data_changed.bind(animated_sprite)
			if not animated_sprite.frame_changed.is_connected(animation_callback):
				animated_sprite.frame_changed.connect(animation_callback)
			if not animated_sprite.animation_changed.is_connected(animation_callback):
				animated_sprite.animation_changed.connect(animation_callback)
		_observe_model_tree(node_2d)


func _disconnect_observed_nodes() -> void:
	for node_reference: WeakRef in _observed_nodes:
		var value: Variant = node_reference.get_ref()
		if value is not Node2D:
			continue
		var node_2d: Node2D = value
		if node_2d.visibility_changed.is_connected(request_rebuild):
			node_2d.visibility_changed.disconnect(request_rebuild)
		if node_2d is TwberMeshSprite2D:
			var mesh_sprite: TwberMeshSprite2D = node_2d
			var mesh_callback := _on_mesh_render_data_changed.bind(mesh_sprite)
			if mesh_sprite.render_data_changed.is_connected(mesh_callback):
				mesh_sprite.render_data_changed.disconnect(mesh_callback)
		elif node_2d is AnimatedSprite2D:
			var animated_sprite: AnimatedSprite2D = node_2d
			var animation_callback := _on_animated_sprite_render_data_changed.bind(animated_sprite)
			if animated_sprite.frame_changed.is_connected(animation_callback):
				animated_sprite.frame_changed.disconnect(animation_callback)
			if animated_sprite.animation_changed.is_connected(animation_callback):
				animated_sprite.animation_changed.disconnect(animation_callback)
	_observed_nodes.clear()


func _on_mesh_render_data_changed(
		topology_changed: bool,
		mesh_sprite: TwberMeshSprite2D,
) -> void:
	if topology_changed:
		request_rebuild()
	else:
		request_dynamic_update_for_node(mesh_sprite)


func _on_animated_sprite_render_data_changed(animated_sprite: AnimatedSprite2D) -> void:
	request_dynamic_update_for_node(animated_sprite)


func _restore_sources() -> void:
	for state: Dictionary in _source_states:
		var reference: WeakRef = state["node"]
		var value: Variant = reference.get_ref()
		if value is not CanvasItem:
			continue
		var canvas_item: CanvasItem = value
		canvas_item.visibility_layer = int(state["visibility_layer"])
		if canvas_item is TwberMeshSprite2D:
			(canvas_item as TwberMeshSprite2D).standalone_rendering_enabled = true
	_source_states.clear()


func _acquire_source_cull_mask() -> void:
	if not _active or _source_states.is_empty() or _masked_viewport != null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_id := viewport.get_instance_id()
	var user_count := int(_viewport_mask_user_counts.get(viewport_id, 0))
	if user_count == 0:
		_viewport_mask_originally_enabled[viewport_id] = (
				(viewport.canvas_cull_mask & SOURCE_VISIBILITY_LAYER) != 0
		)
	_viewport_mask_user_counts[viewport_id] = user_count + 1
	viewport.canvas_cull_mask &= ~SOURCE_VISIBILITY_LAYER
	_masked_viewport = weakref(viewport)
	_masked_viewport_id = viewport_id


func _release_source_cull_mask() -> void:
	if _masked_viewport_id == 0:
		return
	var viewport_id := _masked_viewport_id
	var viewport_value: Variant = (
			_masked_viewport.get_ref()
			if _masked_viewport != null
			else null
	)
	_masked_viewport = null
	_masked_viewport_id = 0
	var next_user_count := maxi(
			int(_viewport_mask_user_counts.get(viewport_id, 1)) - 1,
			0,
	)
	if next_user_count > 0:
		_viewport_mask_user_counts[viewport_id] = next_user_count
		return
	_viewport_mask_user_counts.erase(viewport_id)
	if (
			viewport_value is Viewport
			and bool(_viewport_mask_originally_enabled.get(viewport_id, false))
	):
		(viewport_value as Viewport).canvas_cull_mask |= SOURCE_VISIBILITY_LAYER
	_viewport_mask_originally_enabled.erase(viewport_id)


func _append_model_children(parent: Node, parent_visible: bool) -> void:
	for child: Node in parent.get_children():
		if child is not Node2D:
			continue
		var node_2d: Node2D = child
		var effective_visible := parent_visible and node_2d.visible
		if effective_visible:
			if node_2d is TwberMeshSprite2D:
				_append_mesh_sprite(node_2d)
			elif node_2d is AnimatedSprite2D:
				_append_animated_sprite(node_2d)
			elif node_2d is Sprite2D:
				_append_sprite(node_2d)
		_append_model_children(node_2d, effective_visible)


func _append_mesh_sprite(mesh_sprite: TwberMeshSprite2D) -> void:
	if (
			mesh_sprite.texture == null
			or mesh_sprite.mesh_data == null
			or mesh_sprite.mesh_data.vertices.size() < 3
			or mesh_sprite.mesh_data.triangles.size() < 3
	):
		if mesh_sprite.texture != null and (
				mesh_sprite.mesh_data == null
				or mesh_sprite.mesh_data.cut_edges.is_empty()
		):
			_append_texture_quad(
					mesh_sprite,
					mesh_sprite.texture,
					mesh_sprite.get_texture_origin(),
					false,
					false,
					false,
			)
		return
	_append_geometry(
			mesh_sprite,
			"mesh",
			mesh_sprite.get_render_texture(),
			mesh_sprite.mesh_data.vertices,
			mesh_sprite.get_render_uvs(),
			mesh_sprite.mesh_data.triangles,
			_get_relative_transform(mesh_sprite),
			mesh_sprite.self_modulate,
	)


func _append_sprite(sprite: Sprite2D) -> void:
	_append_texture_quad(sprite, sprite.texture, sprite.offset, sprite.centered, sprite.flip_h, sprite.flip_v)


func _append_animated_sprite(animated_sprite: AnimatedSprite2D) -> void:
	if animated_sprite.sprite_frames == null:
		return
	var animation := animated_sprite.animation
	if not animated_sprite.sprite_frames.has_animation(animation):
		return
	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation)
	if frame_count <= 0:
		return
	var texture := animated_sprite.sprite_frames.get_frame_texture(
			animation,
			clampi(animated_sprite.frame, 0, frame_count - 1),
	)
	_append_texture_quad(
			animated_sprite,
			texture,
			animated_sprite.offset,
			animated_sprite.centered,
			animated_sprite.flip_h,
			animated_sprite.flip_v,
	)


func _append_texture_quad(
		node: Node2D,
		texture: Texture2D,
		offset: Vector2,
		centered: bool,
		flip_h: bool,
		flip_v: bool,
) -> void:
	if texture == null:
		return
	var texture_size := texture.get_size()
	var top_left := offset - texture_size * 0.5 if centered else offset
	var vertices := PackedVector2Array([
		top_left,
		top_left + Vector2(texture_size.x, 0.0),
		top_left + texture_size,
		top_left + Vector2(0.0, texture_size.y),
	])
	var mapping := _get_texture_mapping(texture)
	var uv_rect: Rect2 = mapping["region"]
	var uv_left := uv_rect.end.x if flip_h else uv_rect.position.x
	var uv_right := uv_rect.position.x if flip_h else uv_rect.end.x
	var uv_top := uv_rect.end.y if flip_v else uv_rect.position.y
	var uv_bottom := uv_rect.position.y if flip_v else uv_rect.end.y
	var uvs := PackedVector2Array([
		Vector2(uv_left, uv_top),
		Vector2(uv_right, uv_top),
		Vector2(uv_right, uv_bottom),
		Vector2(uv_left, uv_bottom),
	])
	_append_geometry(
			node,
			"quad",
			mapping["texture"],
			vertices,
			uvs,
			PackedInt32Array([0, 1, 2, 0, 2, 3]),
			_get_relative_transform(node),
			node.self_modulate,
	)


func _get_texture_mapping(texture: Texture2D) -> Dictionary:
	if texture is AtlasTexture:
		var atlas_texture: AtlasTexture = texture
		if atlas_texture.atlas == null:
			return {"texture": null, "region": Rect2()}
		var atlas_size := atlas_texture.atlas.get_size()
		return {
			"texture": atlas_texture.atlas,
			"region": Rect2(
					atlas_texture.region.position / atlas_size,
					atlas_texture.region.size / atlas_size,
			),
		}
	return {"texture": texture, "region": Rect2(Vector2.ZERO, Vector2.ONE)}


func _append_geometry(
		source_node: Node2D,
		kind: String,
		texture: Texture2D,
		local_vertices: PackedVector2Array,
		uvs: PackedVector2Array,
		indices: PackedInt32Array,
		geometry_transform: Transform2D,
		color: Color,
) -> void:
	if texture == null or local_vertices.is_empty() or indices.is_empty():
		return
	var batch: Dictionary
	if not _batches.is_empty():
		var candidate: Dictionary = _batches[_batches.size() - 1]
		if (
				candidate["texture"] == texture
				and candidate["vertices"].size() + local_vertices.size() <= MAX_VERTICES_PER_BATCH
		):
			batch = candidate
	if batch.is_empty():
		batch = {
			"texture": texture,
			"indices": PackedInt32Array(),
			"vertices": PackedVector2Array(),
			"colors": PackedColorArray(),
			"uvs": PackedVector2Array(),
		}
		_batches.append(batch)

	var batch_vertices: PackedVector2Array = batch["vertices"]
	var batch_uvs: PackedVector2Array = batch["uvs"]
	var batch_colors: PackedColorArray = batch["colors"]
	var batch_indices: PackedInt32Array = batch["indices"]
	var vertex_offset := batch_vertices.size()
	var transformed_vertices := PackedVector2Array()
	transformed_vertices.resize(local_vertices.size())
	var vertex_colors := PackedColorArray()
	vertex_colors.resize(local_vertices.size())
	vertex_colors.fill(color)
	for vertex_index: int in local_vertices.size():
		transformed_vertices[vertex_index] = geometry_transform * local_vertices[vertex_index]
	batch_vertices.append_array(transformed_vertices)
	batch_colors.append_array(vertex_colors)
	if uvs.size() == local_vertices.size():
		batch_uvs.append_array(uvs)
	else:
		var safe_uvs := PackedVector2Array()
		safe_uvs.resize(local_vertices.size())
		for vertex_index: int in mini(uvs.size(), safe_uvs.size()):
			safe_uvs[vertex_index] = uvs[vertex_index]
		batch_uvs.append_array(safe_uvs)
	var adjusted_indices := indices.duplicate()
	for index_position: int in adjusted_indices.size():
		adjusted_indices[index_position] += vertex_offset
	batch_indices.append_array(adjusted_indices)
	batch["vertices"] = batch_vertices
	batch["uvs"] = batch_uvs
	batch["colors"] = batch_colors
	batch["indices"] = batch_indices
	var entry_index := _dynamic_entries.size()
	_dynamic_entries.append({
		"node": weakref(source_node),
		"kind": kind,
		"texture": texture,
		"batch_index": _batches.size() - 1,
		"vertex_start": vertex_offset,
		"vertex_count": local_vertices.size(),
	})
	var mapped_node: Node2D = source_node
	while mapped_node != null:
		var node_id := mapped_node.get_instance_id()
		var mapped_indices: Array = _dynamic_entry_indices_by_node_id.get(node_id, [])
		mapped_indices.append(entry_index)
		_dynamic_entry_indices_by_node_id[node_id] = mapped_indices
		if mapped_node == _model_root:
			break
		mapped_node = mapped_node.get_parent() as Node2D


func _get_dynamic_local_vertices(node: Node2D, kind: String) -> PackedVector2Array:
	if kind == "mesh" and node is TwberMeshSprite2D:
		var mesh_sprite: TwberMeshSprite2D = node
		return (
				mesh_sprite.mesh_data.vertices
				if mesh_sprite.mesh_data != null
				else PackedVector2Array()
		)
	var texture := _get_current_node_texture(node)
	if texture == null:
		return PackedVector2Array()
	var offset := Vector2.ZERO
	var centered := false
	if node is TwberMeshSprite2D:
		offset = (node as TwberMeshSprite2D).get_texture_origin()
	elif node is AnimatedSprite2D:
		offset = (node as AnimatedSprite2D).offset
		centered = (node as AnimatedSprite2D).centered
	elif node is Sprite2D:
		offset = (node as Sprite2D).offset
		centered = (node as Sprite2D).centered
	var texture_size := texture.get_size()
	var top_left := offset - texture_size * 0.5 if centered else offset
	return PackedVector2Array([
		top_left,
		top_left + Vector2(texture_size.x, 0.0),
		top_left + texture_size,
		top_left + Vector2(0.0, texture_size.y),
	])


func _get_dynamic_render_texture(node: Node2D, kind: String) -> Texture2D:
	if kind == "mesh" and node is TwberMeshSprite2D:
		return (node as TwberMeshSprite2D).get_render_texture()
	var texture := _get_current_node_texture(node)
	if texture == null:
		return null
	return _get_texture_mapping(texture)["texture"] as Texture2D


func _get_dynamic_quad_uvs(node: Node2D) -> PackedVector2Array:
	var texture := _get_current_node_texture(node)
	if texture == null:
		return PackedVector2Array()
	var flip_h := false
	var flip_v := false
	if node is AnimatedSprite2D:
		flip_h = (node as AnimatedSprite2D).flip_h
		flip_v = (node as AnimatedSprite2D).flip_v
	elif node is Sprite2D:
		flip_h = (node as Sprite2D).flip_h
		flip_v = (node as Sprite2D).flip_v
	var mapping := _get_texture_mapping(texture)
	var uv_rect: Rect2 = mapping["region"]
	var uv_left := uv_rect.end.x if flip_h else uv_rect.position.x
	var uv_right := uv_rect.position.x if flip_h else uv_rect.end.x
	var uv_top := uv_rect.end.y if flip_v else uv_rect.position.y
	var uv_bottom := uv_rect.position.y if flip_v else uv_rect.end.y
	return PackedVector2Array([
		Vector2(uv_left, uv_top),
		Vector2(uv_right, uv_top),
		Vector2(uv_right, uv_bottom),
		Vector2(uv_left, uv_bottom),
	])


func _get_current_node_texture(node: Node2D) -> Texture2D:
	if node is TwberMeshSprite2D:
		return (node as TwberMeshSprite2D).texture
	if node is Sprite2D:
		return (node as Sprite2D).texture
	if node is not AnimatedSprite2D:
		return null
	var animated_sprite: AnimatedSprite2D = node
	if animated_sprite.sprite_frames == null:
		return null
	var animation := animated_sprite.animation
	if not animated_sprite.sprite_frames.has_animation(animation):
		return null
	var frame_count := animated_sprite.sprite_frames.get_frame_count(animation)
	if frame_count <= 0:
		return null
	return animated_sprite.sprite_frames.get_frame_texture(
			animation,
			clampi(animated_sprite.frame, 0, frame_count - 1),
	)


func _get_relative_transform(node: Node2D) -> Transform2D:
	return _root_inverse_transform * node.get_global_transform()


func _is_supported_visual(node: Node) -> bool:
	return node is Sprite2D or node is AnimatedSprite2D or node is TwberMeshSprite2D
