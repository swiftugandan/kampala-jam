class_name VehicleCatalog
extends RefCounted
## The vehicles and motorcades of Kampala, from assets/data/vehicle_catalog.json.

static var _data: Dictionary
static var _by_category: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicle_catalog.json"))
		for model: Dictionary in _data["models"]:
			(_by_category.get_or_add(model["category"], []) as Array).append(model)
	return _data


static func models_in(category: String) -> Array:
	data()
	return _by_category.get(category, [])


static func motorcade(style: String) -> Dictionary:
	return data()["motorcades"][style]
