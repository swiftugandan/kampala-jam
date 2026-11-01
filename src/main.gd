extends Node
## The whole game flow: title, today's card, the drive, the result, tomorrow.
## The player never picks a difficulty; Campaign decides what day it is.

var campaign: Campaign
var _screen: Node
var _capture: Dictionary = {}


func _ready() -> void:
	campaign = Campaign.load_saved()
	_parse_capture_args()
	if not _capture.is_empty():
		_start_capture()
		return
	_show_title()


func _swap(screen: Node) -> void:
	if _screen:
		_screen.queue_free()
	_screen = screen
	add_child(screen)


func _show_title() -> void:
	var page := _page(Color("17140f"))
	var col: VBoxContainer = page.get_meta("col")
	var title := Ui.label("KAMPALA JAM", 86, Ui.YELLOW, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Ui.label("Munyonyo to Namugongo, on the real roads. Mind the boda bodas.", 26, Ui.PAPER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_spacer(26))
	var level := campaign.current_level()
	var day := Ui.label("DAY %d: %s" % [campaign.day_number(), String(level["name"]).to_upper()], 22, Ui.MURRAM.lightened(0.3), true)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(day)
	var drive := Ui.button("DRIVE", true, 40)
	drive.custom_minimum_size = Vector2(320, 86)
	drive.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drive.pressed.connect(_show_day_card)
	col.add_child(drive)
	col.add_child(_spacer(14))
	var how := Ui.label(_controls_text(), 18, Ui.MUTED)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(how)
	col.add_child(_spacer(10))
	var idea := Ui.label("Based on an idea in an article by Dr Ian Clarke in New Vision.", 18, Ui.PAPER)
	idea.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idea.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(idea)
	var credit := Ui.label(str(MapData.shared().meta["attribution"]).replace("(c)", "©") + ". Bungee and Archivo Narrow fonts under the SIL OFL. A work of comedy: contractors in the game are invented.", 14, Ui.MUTED)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(credit)
	_swap(page)
	drive.grab_focus()


func _controls_text() -> String:
	if Ui.has_touch():
		return "Left thumb: point where you want to go, push further to go faster. Right thumb: brake and hoot."
	return "Arrows or WASD to drive, Space to hoot, M for the map. A gamepad works too."


func _show_day_card() -> void:
	var page := _page(Color("b5562c"))
	var col: VBoxContainer = page.get_meta("col")
	var level := campaign.current_level()
	var day := Ui.label("DAY %d" % campaign.day_number(), 30, Ui.INK, true)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(day)
	var name_label := Ui.label(String(level["name"]).to_upper(), 58, Ui.YELLOW, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_label)
	var blurb := Ui.label(level["blurb"], 28, Ui.PAPER)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(blurb)
	col.add_child(_spacer(20))
	var loading := Ui.label("Finding the car keys...", 22, Ui.INK)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(loading)
	_swap(page)
	# Let the card paint before the map loads, then give it a moment to be read.
	await get_tree().create_timer(2.2).timeout
	if _screen == page:
		_start_run(level)


func _start_run(level: Dictionary, seed_value: int = -1) -> RunScreen:
	var run := RunScreen.new()
	_swap(run)
	run.start(level, seed_value if seed_value >= 0 else randi())
	run.run_ended.connect(_show_result)
	run.quit_to_title.connect(_show_title)
	run.restart_requested.connect(_show_day_card)
	return run


func _show_result(result: Dictionary) -> void:
	var was_best := campaign.record(result)
	get_tree().paused = false
	var finished: bool = result["finished"]
	var page := _page(Color("17140f"))
	var col: VBoxContainer = page.get_meta("col")
	var head := Ui.label(result["rating"] if finished else "NOT TODAY", 46, Ui.YELLOW if finished else Ui.RED, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(head)
	if not finished:
		var why := Ui.label(result["reason"], 24, Ui.PAPER)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(why)
	var score := Ui.label("%s  +  %d penalties  =  %d%s" % [Ui.format_time(result["time"]), result["penalties"], int(result["score"]), "   NEW BEST" if was_best else ""], 30, Ui.PAPER, true)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(score)
	col.add_child(_spacer(6))
	var rows: Array = result["rows"]
	for i in mini(rows.size(), 5):
		var r: Dictionary = rows[i]
		var row := Ui.label("%d x %s:  %d" % [r["count"], r["label"], r["points"]], 20, Ui.MUTED)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(row)
	var passed: Array = result["passed"]
	if not passed.is_empty():
		var seen := Ui.label("You passed: " + ", ".join(PackedStringArray(passed.slice(0, 8))), 18, Ui.PAPER)
		seen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(seen)
	col.add_child(_spacer(10))
	var question := Ui.label("So. Where do you live?", 22, Ui.MURRAM.lightened(0.35))
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(question)
	var next := Ui.button("TOMORROW" if finished else "TRY AGAIN", true, 30)
	next.custom_minimum_size = Vector2(320, 76)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.pressed.connect(_show_day_card)
	col.add_child(next)
	_swap(page)
	next.grab_focus()


func _page(bg: Color) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = bg
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	root.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(minf(980.0, get_viewport().get_visible_rect().size.x - 60.0), 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	root.set_meta("col", col)
	return root


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


# ------------------------------------------------- automated screenshots ---
# godot --path . -- --kj-capture=out.png --kj-stage=2 --kj-at="Kibuli Mosque" --kj-wait=6
func _parse_capture_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kj-"):
			var kv := arg.trim_prefix("--kj-").split("=", true, 1)
			_capture[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _start_capture() -> void:
	campaign = Campaign.new()
	campaign.stage = int(_capture.get("stage", "0"))
	var screen: String = _capture.get("screen", "run")
	if screen == "title":
		_show_title()
	elif screen == "card":
		_show_day_card()
	elif screen == "result":
		_show_result({"finished": true, "level_id": "sunday", "time": 412.0, "penalties": 95, "score": 507.0, "rating": "Kampala Driver", "passed": ["Kassam Mosque, Kabalagala", "Lugogo Mall", "Forest Mall, Lugogo"], "rows": [{"label": "Minor collision", "count": 1, "points": 50}, {"label": "Altercation with boda rider", "count": 1, "points": 25}, {"label": "Vehicle contact", "count": 2, "points": 20}]})
	else:
		var run := _start_run(campaign.current_level(), int(_capture.get("seed", "42")))
		run.bot = Autodriver.new(run.session)
		var s := run.session
		if _capture.has("at"):
			var lm := s.map.landmark_named(_capture["at"])
			if lm.is_empty():
				push_error("Unknown landmark " + str(_capture["at"]))
			var p := s.map.node_pos(s.map.nearest_node(Vector2(lm["x"], lm["y"])))
			s.car.pos = p
			s._replan()
			s.traffic.agents.clear()
			s.traffic.player_pos = p
			s.traffic.populate()
			run.world.camera.position = p
		if _capture.has("rain"):
			s.director.rain_start = 0.0
			s.director.rain_end = 9999.0
			s.director.flood_level = 1.0
			s.director.rain = 1.0
		if _capture.has("convoy"):
			s.director._add_convoy(_capture["convoy"], 0.0)
		if _capture.has("map"):
			run._toggle_map()
	await get_tree().create_timer(float(_capture.get("wait", "4"))).timeout
	await RenderingServer.frame_post_draw
	var path: String = _capture.get("capture", "user://shot.png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("captured %s: %s, %.0f fps" % [path, error_string(err), Engine.get_frames_per_second()])
	get_tree().quit()
