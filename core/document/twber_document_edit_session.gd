class_name TwberDocumentEditSession extends RefCounted

# Drafts are produced by native commands, never by capturing rendered nodes.
# One gesture keeps one baseline and one draft, independent of pointer-event count.
var _document: TwberModelDocument
var _baseline: TwberModelResource
var _draft: TwberModelResource
var _revision: int
var _label: String
var _kinds := 0
var _ids: Array[String] = []
var _changed := false
var _active := true
var diagnostics: Array[String] = []


func _init(document: TwberModelDocument, label: String) -> void:
	_document = document
	_revision = document.get_revision()
	_baseline = document.snapshot().to_model_resource()
	_draft = _baseline
	_label = label


# Replace recomputes a drag from its baseline; append accumulates a paint stroke.
func update(command: TwberDocumentCommand, replace := false) -> Error:
	if not _active or _document.get_revision() != _revision:
		diagnostics = ["The edit session is closed or its document has changed"]
		return ERR_BUSY
	var candidate := (_baseline if replace else _draft).duplicate(true) as TwberModelResource
	command.error_message = ""
	var error := command.apply(candidate)
	if error != OK:
		diagnostics = [command.error_message if not command.error_message.is_empty() else error_string(error)]
		return error
	diagnostics = TwberDocumentValidator.validate(candidate)
	if not diagnostics.is_empty():
		return ERR_INVALID_DATA
	if replace:
		_kinds = 0
		_ids.clear()
		_changed = false
	if command.did_change:
		_changed = true
		_kinds |= command.kinds
		for id: String in command.layer_ids:
			if not _ids.has(id):
				_ids.append(id)
	_draft = candidate.duplicate(true) as TwberModelResource
	return OK


func to_model_resource() -> TwberModelResource:
	return _draft.duplicate(true) as TwberModelResource if _draft != null else null


func commit() -> Error:
	if not _active or _document.get_revision() != _revision:
		cancel()
		return ERR_BUSY
	_active = false
	if not _changed:
		_release()
		return OK
	var command := CommitDraft.new()
	command.result = _draft
	command.label = _label
	command.kinds = _kinds
	command.layer_ids = _ids.duplicate()
	var error := _document.execute(command)
	_release()
	return error


func cancel() -> void:
	_active = false
	_release()


func _release() -> void:
	_document = null
	_baseline = null
	_draft = null


class CommitDraft extends TwberDocumentCommand:
	var result: TwberModelResource

	func apply(model: TwberModelResource) -> Error:
		model.copy_contents_from(result)
		did_change = true
		return OK
