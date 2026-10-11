class_name TwberDocumentCommand extends RefCounted

# apply() only receives an isolated candidate document. The owner publishes it
# after validation, so failed commands never partially edit the live document.
var label := "Edit model"
var kinds := 0
var layer_ids: Array[String] = []
var did_change := false
var error_message := ""


func apply(_model: TwberModelResource) -> Error:
	return ERR_UNAVAILABLE
