class_name PenaltyLedger
extends RefCounted
## Every incident in the run. One penalty point is one second on the final score.

var defs: Dictionary
var total := 0
var counts: Dictionary = {}
var _rng: RandomNumberGenerator


func _init(penalty_defs: Dictionary, rng: RandomNumberGenerator) -> void:
	defs = penalty_defs
	_rng = rng


## Returns {type, points, label, line} for the HUD.
func record(type: String) -> Dictionary:
	var def: Dictionary = defs[type]
	var pts: int = def["points"]
	total += pts
	counts[type] = int(counts.get(type, 0)) + 1
	var lines: Array = def["lines"]
	return {"type": type, "points": pts, "label": def["label"], "line": lines[_rng.randi() % lines.size()]}


func rows() -> Array:
	var out := []
	for type: String in defs:
		if counts.has(type):
			out.append({"label": defs[type]["label"], "count": counts[type], "points": int(counts[type]) * int(defs[type]["points"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["points"] > b["points"])
	return out
