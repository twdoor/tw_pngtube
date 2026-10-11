class_name TwberDocumentSnapshot extends RefCounted

# The compatibility schema is private. Consumers receive a disposable copy;
# neither rendering nor a legacy serializer can mutate the captured revision.
var _model: TwberModelResource
var _owner: RefCounted
var _state: RefCounted
var _revision: int


func _init(model: TwberModelResource, owner: RefCounted, state: RefCounted, revision: int) -> void:
	_model = model.duplicate(true)
	_owner = owner
	_state = state
	_revision = revision


func to_model_resource() -> TwberModelResource:
	return _model.duplicate(true)


func get_revision() -> int:
	return _revision


func belongs_to(owner: RefCounted) -> bool:
	return _owner == owner


func get_state_token() -> RefCounted:
	return _state
