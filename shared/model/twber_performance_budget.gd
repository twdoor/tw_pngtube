class_name TwberPerformanceBudget extends RefCounted

const TARGET_DRAW_CALLS := 100
const TARGET_TEXTURE_VRAM_BYTES := 256 * 1024 * 1024
const TARGET_VERTICES := 50000
const TARGET_PARAMETER_MESH_VERTICES := 500000
const TARGET_CLIPPED_LAYERS := 16


static func get_warnings(summary: Dictionary) -> Array[String]:
	var warnings: Array[String] = []
	var draw_calls := int(summary.get("estimated_draw_calls", 0))
	if draw_calls > TARGET_DRAW_CALLS:
		warnings.append(
				"Estimated draw calls (%d) exceed the recommended %d; atlas compatible layers."
				% [draw_calls, TARGET_DRAW_CALLS]
		)

	var texture_vram := int(summary.get("estimated_texture_vram_bytes", 0))
	if texture_vram > TARGET_TEXTURE_VRAM_BYTES:
		warnings.append(
				"Estimated texture VRAM (%s) exceeds the recommended %s."
				% [format_bytes(texture_vram), format_bytes(TARGET_TEXTURE_VRAM_BYTES)]
		)

	var vertices := int(summary.get("vertices", 0))
	if vertices > TARGET_VERTICES:
		warnings.append(
				"Mesh vertices (%d) exceed the recommended %d."
				% [vertices, TARGET_VERTICES]
		)

	var parameter_vertices := int(summary.get("parameter_mesh_vertices", 0))
	if parameter_vertices > TARGET_PARAMETER_MESH_VERTICES:
		warnings.append(
				"Stored parameter mesh vertices (%d) may increase load and evaluation time."
				% parameter_vertices
		)

	var clipped_layers := int(summary.get("clipped_layers", 0))
	if clipped_layers > TARGET_CLIPPED_LAYERS:
		warnings.append(
				"Clipped layers (%d) exceed the recommended %d; masks can split batches."
				% [clipped_layers, TARGET_CLIPPED_LAYERS]
		)
	return warnings


static func format_bytes(byte_count: int) -> String:
	var size := float(maxi(byte_count, 0))
	for unit: String in ["B", "KiB", "MiB", "GiB"]:
		if size < 1024.0 or unit == "GiB":
			return "%.1f %s" % [size, unit]
		size /= 1024.0
	return "0 B"
