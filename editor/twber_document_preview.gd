class_name TwberDocumentPreview extends TwberRuntimeModel

# One-way bridge for the new document API. Render nodes are disposable and
# parameter playback is isolated from authored data. Legacy tabs are migrated
# separately; they must not write back from this preview into the document.
var _document: TwberModelDocument


func bind_document(document: TwberModelDocument) -> void:
	if _document != null and _document.changed.is_connected(_on_document_changed):
		_document.changed.disconnect(_on_document_changed)
	_document = document
	if _document != null:
		_document.changed.connect(_on_document_changed)
	_sync_document()


func _on_document_changed(_change: TwberDocumentChange) -> void:
	_sync_document()


func _sync_document() -> void:
	var values := get_parameter_values()
	set_model(_document.snapshot().to_model_resource() if _document != null else null)
	if model != null and set_parameter_values(values):
		evaluate_parameters()
