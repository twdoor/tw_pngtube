class_name TwberInputMapping extends RefCounted

# Optional package contract. Mapping receives data only; acquisition and widgets
# belong to their own adapters. Display geometry, when needed, is injected.
func map_value(_parameter: TwberParameterResource, _configuration: Dictionary, value: Variant, _context: Dictionary = {}) -> Variant:
	return value
