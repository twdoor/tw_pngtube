extends SceneTree

const PackageBuilder = preload("res://tools/twber_package_builder.gd")


func _initialize() -> void:
	var builder := PackageBuilder.new()
	var error: Error = builder.build_all()
	quit(0 if error == OK else 1)
