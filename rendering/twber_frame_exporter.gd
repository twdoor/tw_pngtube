class_name TwberFrameExporter extends RefCounted

signal progress(completed: int, total: int)
const MAX_FRAMES := 100000
var running := false
var _cancelled := false
var _staging := ""
var _files: Array[String] = []


func cancel() -> void:
	_cancelled = true


static func frame_count(duration: float, fps: float) -> int:
	if not is_finite(duration) or not is_finite(fps) or duration <= 0.0 or fps < 1.0 or fps > 120.0:
		return 0
	if duration * fps > MAX_FRAMES:
		return 0
	# Half-open [0, duration): a loop never exports a duplicate endpoint.
	var count := ceili(duration * fps)
	if count > 1 and float(count - 1) / fps >= duration:
		count -= 1
	return count if count <= MAX_FRAMES else 0


func export_sequence(parent: Node, source: TwberModelResource, animation_id: String, destination: String,
		size := Vector2i(512, 512), fps := 30.0, zoom := 1.0, center := Vector2.ZERO) -> Error:
	if running:
		return ERR_BUSY
	if source == null or not is_instance_valid(parent) or not parent.is_inside_tree() or not TwberDocumentValidator.validate(source).is_empty():
		return ERR_INVALID_DATA
	var model := source.duplicate(true) as TwberModelResource
	var clip := TwberEditTimeline.find(model, animation_id)
	if clip == null or size.x < 1 or size.y < 1 or size.x > 4096 or size.y > 4096 or not is_finite(zoom) or zoom <= 0.0 or not center.is_finite():
		return ERR_INVALID_PARAMETER
	var count := frame_count(clip.duration, fps)
	if count == 0:
		return ERR_INVALID_PARAMETER
	if DisplayServer.get_name() == "headless":
		return ERR_UNAVAILABLE
	var path := ProjectSettings.globalize_path(destination).simplify_path().trim_suffix("/")
	if not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return ERR_FILE_BAD_PATH
	if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	_staging = path + ".partial-" + str(Time.get_ticks_usec())
	var error := DirAccess.make_dir_absolute(_staging)
	if error != OK:
		return error
	running = true
	_cancelled = false
	_files.clear()
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * zoom, 0.0, Vector2(size) * 0.5 - center * zoom)
	var runtime := TwberRuntimeModel.new()
	runtime.enable_runtime_atlases = false
	viewport.add_child(runtime)
	runtime.set_model(model)
	runtime.set_process(false)
	var times: Array[float] = []
	for index: int in count:
		if _cancelled or not is_instance_valid(parent) or not is_instance_valid(viewport):
			return _finish(viewport, ERR_SKIP)
		var time := float(index) / fps
		error = runtime.seek_animation(animation_id, time)
		if error != OK:
			return _finish(viewport, error)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await parent.get_tree().process_frame
		await RenderingServer.frame_post_draw
		if _cancelled or not is_instance_valid(viewport):
			return _finish(viewport, ERR_SKIP)
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			return _finish(viewport, ERR_CANT_CREATE)
		var file := "frame_%06d.png" % index
		_files.append(file)
		error = image.save_png(_staging.path_join(file))
		if error != OK:
			return _finish(viewport, error)
		times.append(time)
		progress.emit(index + 1, count)
	if _cancelled or not is_instance_valid(parent) or not is_instance_valid(viewport):
		return _finish(viewport, ERR_SKIP)
	var manifest := {"format": "twber_png_sequence", "version": 1, "animation_id": animation_id,
		"fps": fps, "duration": clip.duration, "width": size.x, "height": size.y,
		"zoom": zoom, "center": [center.x, center.y], "frame_times": times, "transparent": true}
	_files.append("sequence.json")
	var file := FileAccess.open(_staging.path_join("sequence.json"), FileAccess.WRITE)
	if file == null:
		return _finish(viewport, FileAccess.get_open_error())
	file.store_string(JSON.stringify(manifest, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return _finish(viewport, error)
	if DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path):
		return _finish(viewport, ERR_ALREADY_EXISTS)
	error = DirAccess.rename_absolute(_staging, path)
	return _finish(viewport, error)


func _finish(viewport: Variant, error: Error) -> Error:
	if is_instance_valid(viewport):
		viewport.free()
	if error != OK:
		for file: String in _files:
			DirAccess.remove_absolute(_staging.path_join(file))
		DirAccess.remove_absolute(_staging)
	_files.clear()
	_staging = ""
	running = false
	return error
