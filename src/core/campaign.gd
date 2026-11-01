class_name Campaign
extends RefCounted
## Decides what day it is, so the player never has to. Finishing a run moves on
## to the next, harder day; failing repeats it. After the last day the school
## year rolls over and each new term is busier than the one before.

const SAVE_PATH := "user://save.json"

var stage := 0  ## Runs completed so far; indexes the campaign order, then terms.
var best: Dictionary = {}
var last_result: Dictionary = {}
var save_path := SAVE_PATH  ## Tests point this elsewhere so they never touch a real save.


static func load_saved(path: String = SAVE_PATH) -> Campaign:
	var c := Campaign.new()
	c.save_path = path
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			c.stage = maxi(int(parsed.get("stage", 0)), 0)
			c.best = parsed.get("best", {})
	return c


func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"stage": stage, "best": best}))


## Which number school term this stage falls in; 0 during the first days.
func term() -> int:
	var n := order().size()
	return 0 if stage < n else stage - n + 1


func day_number() -> int:
	return stage + 1


func order() -> Array:
	return Rules.data()["campaign"]["order"]


func current_level_id() -> String:
	var o := order()
	return o[mini(stage, o.size() - 1)]


## The level for today, scaled up once past the last authored day.
func current_level() -> Dictionary:
	var level: Dictionary = Rules.level(current_level_id()).duplicate(true)
	var t := term()
	if t > 0:
		var cfg: Dictionary = Rules.data()["campaign"]
		level["traffic"] = int(float(level["traffic"]) * (1.0 + float(cfg["term_traffic_step"]) * t))
		level["jam"] = minf(float(level["jam"]) + float(cfg["term_jam_step"]) * t, 0.7)
		level["name"] = "%s, Term %d" % [level["name"], t + 1]
	return level


## Records the outcome and moves the calendar. Returns true on a new best.
func record(result: Dictionary) -> bool:
	last_result = result
	var is_best := false
	if result["finished"]:
		var id: String = result["level_id"]
		var score: float = result["score"]
		if not best.has(id) or score < float(best[id]):
			best[id] = score
			is_best = true
		stage += 1
	save()
	return is_best
