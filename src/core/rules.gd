class_name Rules
extends RefCounted
## Game tuning, loaded once from assets/data/game_rules.json.

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/game_rules.json"))
	return _data


static func level(level_id: String) -> Dictionary:
	for lv: Dictionary in data()["levels"]:
		if lv["id"] == level_id:
			return lv
	push_error("Unknown level: " + level_id)
	return data()["levels"][0]


static func rating_for(score: float, par: float) -> String:
	var ratio := score / par
	for r: Dictionary in data()["ratings"]:
		if ratio <= float(r["max_ratio"]):
			return r["title"]
	return ""
