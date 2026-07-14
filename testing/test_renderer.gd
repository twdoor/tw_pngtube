extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		print("Twber renderer pixel test skipped: a real graphics backend is required.")
		quit(0)
		return
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	get_root().add_child(viewport)
	var model_root := Node2D.new()
	viewport.add_child(model_root)

	var blue_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	blue_image.fill(Color.BLUE)
	var blue_texture := ImageTexture.create_from_image(blue_image)
	var red_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	red_image.fill(Color.RED)
	var red_texture := ImageTexture.create_from_image(red_image)

	var mesh_sprite := TwberMeshSprite2D.new()
	mesh_sprite.texture = blue_texture
	mesh_sprite.mesh_data = TwberMeshResource.new()
	mesh_sprite.mesh_data.vertices = PackedVector2Array([
		Vector2(8, 8),
		Vector2(40, 8),
		Vector2(40, 40),
		Vector2(8, 40),
	])
	mesh_sprite.mesh_data.rest_vertices = mesh_sprite.mesh_data.vertices.duplicate()
	mesh_sprite.mesh_data.uvs = PackedVector2Array([
		Vector2(0, 0),
		Vector2(8, 0),
		Vector2(8, 8),
		Vector2(0, 8),
	])
	mesh_sprite.mesh_data.triangles = PackedInt32Array([0, 1, 2, 0, 2, 3])
	model_root.add_child(mesh_sprite)
	mesh_sprite.sync_mesh()

	var sprite := Sprite2D.new()
	sprite.texture = red_texture
	sprite.position = Vector2(52, 12)
	sprite.scale = Vector2(2, 2)
	model_root.add_child(sprite)
	var animated_sprite := AnimatedSprite2D.new()
	animated_sprite.sprite_frames = SpriteFrames.new()
	animated_sprite.sprite_frames.clear(&"default")
	animated_sprite.sprite_frames.add_frame(&"default", red_texture)
	animated_sprite.sprite_frames.add_frame(&"default", blue_texture)
	animated_sprite.position = Vector2(12, 52)
	animated_sprite.scale = Vector2(2, 2)
	model_root.add_child(animated_sprite)
	var atlas_result := TwberTextureAtlasBuilder.optimize_model_root(model_root, -1)
	_expect(atlas_result.get("atlas_pages", 0) == 1, "Editor optimizer created an in-memory atlas")

	var batch_renderer := TwberModelBatchRenderer2D.attach_to(model_root)
	_expect(batch_renderer.configure(model_root), "Compatible model enabled batched rendering")
	_expect(batch_renderer.get_batch_count() == 1, "Atlas-backed mesh and sprite share one render batch")

	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	_expect(rendered != null and not rendered.is_empty(), "Offscreen renderer produced an image")
	if rendered != null and not rendered.is_empty():
		var center := rendered.get_pixel(24, 24)
		_expect(center.b > 0.9 and center.r < 0.1 and center.a > 0.9, "Direct mesh renderer sampled the blue atlas region")
		var outside := rendered.get_pixel(2, 2)
		_expect(outside.a < 0.01, "Direct mesh renderer preserved transparent background")
		var red_sample := rendered.get_pixel(52, 12)
		_expect(
				red_sample.r > 0.9 and red_sample.b < 0.1,
				"Batch renderer sampled a second atlas region: %s" % red_sample,
		)
		var animated_red := rendered.get_pixel(12, 52)
		_expect(animated_red.r > 0.9 and animated_red.b < 0.1, "Batch renderer drew the initial animation atlas frame")
	_expect(mesh_sprite.get_node_or_null("MeshPolygon") == null, "Direct renderer created no Polygon2D")

	sprite.position = Vector2(52, 52)
	var moved_nodes: Array[Node2D] = [sprite]
	batch_renderer.update_dynamic_geometry_for_nodes(moved_nodes)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await RenderingServer.frame_post_draw
	var moved_render := viewport.get_texture().get_image()
	var old_position := moved_render.get_pixel(52, 12)
	var new_position := moved_render.get_pixel(52, 52)
	_expect(old_position.a < 0.01, "Editor-style transform invalidation removed the old batched quad: %s" % old_position)
	_expect(new_position.r > 0.9 and new_position.a > 0.9, "Editor-style transform invalidation updated batched vertices: %s" % new_position)

	animated_sprite.frame = 1
	var animated_nodes: Array[Node2D] = [animated_sprite]
	batch_renderer.update_dynamic_geometry_for_nodes(animated_nodes)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await RenderingServer.frame_post_draw
	var animated_render := viewport.get_texture().get_image()
	var animated_blue := animated_render.get_pixel(12, 52)
	_expect(animated_blue.b > 0.9 and animated_blue.r < 0.1, "Animation frame change updated only batched atlas UVs")

	batch_renderer.clear()
	sprite.visible = false
	animated_sprite.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await process_frame
	await RenderingServer.frame_post_draw
	var standalone_render := viewport.get_texture().get_image()
	var standalone_mesh := standalone_render.get_pixel(24, 24)
	_expect(
			standalone_mesh.b > 0.9 and standalone_mesh.r < 0.1 and standalone_mesh.a > 0.9,
			"Standalone mesh submits direct RenderingServer triangles without Polygon2D",
	)

	viewport.queue_free()
	var clip_viewport := SubViewport.new()
	clip_viewport.size = Vector2i(32, 32)
	clip_viewport.transparent_bg = true
	clip_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	get_root().add_child(clip_viewport)
	var clip_root := Node2D.new()
	clip_viewport.add_child(clip_root)
	var mask_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	mask_image.fill(Color.WHITE)
	mask_image.fill_rect(Rect2i(8, 8, 4, 4), Color.TRANSPARENT)
	var mask_sprite := Sprite2D.new()
	mask_sprite.texture = ImageTexture.create_from_image(mask_image)
	mask_sprite.centered = false
	mask_sprite.position = Vector2(8, 8)
	mask_sprite.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	clip_root.add_child(mask_sprite)
	var sparse_child := Sprite2D.new()
	sparse_child.texture = red_texture
	sparse_child.centered = false
	sparse_child.position = Vector2(4, 4)
	mask_sprite.add_child(sparse_child)
	var clip_controller := TwberAlphaClipController.attach_to(clip_root)
	clip_controller.configure(clip_root)
	await process_frame
	await RenderingServer.frame_post_draw
	var clip_render := clip_viewport.get_texture().get_image()
	var empty_mask_area := clip_render.get_pixel(9, 9)
	var allowed_child := clip_render.get_pixel(13, 13)
	var eye_hole := clip_render.get_pixel(17, 17)
	_expect(empty_mask_area.a < 0.01, "Alpha-safe clipping leaves opaque mask areas empty when children have no pixels")
	_expect(allowed_child.r > 0.9 and allowed_child.a > 0.9, "Alpha-safe clipping preserves child pixels allowed by the mask")
	_expect(eye_hole.a < 0.01, "Alpha-safe clipping punches transparent holes through child pixels")

	clip_viewport.queue_free()
	if _failures.is_empty():
		print("Twber renderer test passed.")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
