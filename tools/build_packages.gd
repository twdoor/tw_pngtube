@tool
extends EditorScript

const PackageBuilder = preload("res://tools/twber_package_builder.gd")


func _run() -> void:
	var error := PackageBuilder.new().build_all()
	var editor_interface := get_editor_interface()
	if editor_interface != null:
		editor_interface.get_resource_filesystem().scan()
	if error != OK:
		push_error("One or more packages failed to build. See the errors above.")
