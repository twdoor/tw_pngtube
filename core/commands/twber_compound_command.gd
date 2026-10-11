class_name TwberCompoundCommand extends TwberDocumentCommand

var commands: Array[TwberDocumentCommand] = []


func _init(value_label: String, value_commands: Array[TwberDocumentCommand]) -> void:
	label = value_label
	commands = value_commands.duplicate()


func apply(model: TwberModelResource) -> Error:
	did_change = false
	kinds = 0
	layer_ids.clear()
	for command: TwberDocumentCommand in commands:
		if command == null:
			return ERR_INVALID_PARAMETER
		command.error_message = ""
		var error := command.apply(model)
		if error != OK:
			error_message = command.error_message
			return error
		if not command.did_change:
			continue
		did_change = true
		kinds |= command.kinds
		for id: String in command.layer_ids:
			if not layer_ids.has(id):
				layer_ids.append(id)
	return OK
