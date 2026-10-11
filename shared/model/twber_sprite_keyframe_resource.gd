class_name TwberSpriteKeyframeResource extends Resource

# Phase is measured in relative frame durations, before loop wrapping. An anchor
# preserves a live clock offset; rate advances it until the next anchor.
@export var layer_id := ""
@export var time := 0.0
@export var animation_name := ""
@export var phase := 0.0
@export var rate := 0.0


func state_at(at: float) -> Dictionary:
	return {"animation": animation_name, "phase": phase + maxf(at - time, 0.0) * rate, "rate": rate}
