class_name Hud
extends Control
## The driver's information: time, penalties, road, journey, and what just went wrong.

const TOAST_LIFE := 4.5

var session: RaceSession
var _time: Label
var _penalty: Label
var _road: Label
var _left: Label
var _progress: ProgressBar
var _toasts: VBoxContainer
var _freeze_panel: PanelContainer
var _freeze_text: Label
var _freeze_time: Label
var minimap: Minimap
var pause_button: Button
var map_button: Button


func setup(race: RaceSession) -> void:
	session = race
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left_box := PanelContainer.new()
	left_box.add_theme_stylebox_override("panel", Ui.box(Color(0.07, 0.07, 0.06, 0.82), 6, 10))
	left_box.position = Vector2(14, 12)
	left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_box)
	var col := VBoxContainer.new()
	left_box.add_child(col)
	_time = Ui.label("0:00", 40, Ui.YELLOW, true)
	col.add_child(_time)
	_penalty = Ui.label("+0 PENALTIES", 16, Ui.PAPER, true)
	col.add_child(_penalty)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-220, 12)
	top.custom_minimum_size = Vector2(440, 0)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_road = Ui.label("", 24, Ui.PAPER, true)
	_road.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_road.add_theme_constant_override("outline_size", 7)
	_road.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	top.add_child(_road)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 10)
	_progress.add_theme_stylebox_override("background", Ui.box(Color(0, 0, 0, 0.65), 4, 0))
	_progress.add_theme_stylebox_override("fill", Ui.box(Ui.YELLOW, 4, 0))
	_progress.max_value = 1.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_progress)
	_left = Ui.label("", 15, Ui.PAPER)
	_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left.add_theme_constant_override("outline_size", 5)
	_left.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	top.add_child(_left)

	minimap = Minimap.new()
	minimap.setup(race, false)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-214, 12)
	minimap.size = Vector2(200, 150)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	var buttons := HBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	buttons.position = Vector2(-214, 170)
	add_child(buttons)
	map_button = Ui.button("MAP", false, 16)
	map_button.custom_minimum_size = Vector2(98, 48)
	buttons.add_child(map_button)
	pause_button = Ui.button("PAUSE", false, 16)
	pause_button.custom_minimum_size = Vector2(98, 48)
	buttons.add_child(pause_button)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.position = Vector2(-330, -210)
	_toasts.custom_minimum_size = Vector2(660, 200)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	_freeze_panel = PanelContainer.new()
	_freeze_panel.add_theme_stylebox_override("panel", Ui.box(Color(0.5, 0.07, 0.05, 0.93), 6, 14))
	_freeze_panel.set_anchors_preset(Control.PRESET_CENTER)
	_freeze_panel.position = Vector2(-280, -120)
	_freeze_panel.custom_minimum_size = Vector2(560, 0)
	_freeze_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_freeze_panel.visible = false
	add_child(_freeze_panel)
	var fbox := VBoxContainer.new()
	_freeze_panel.add_child(fbox)
	_freeze_text = Ui.label("", 21, Ui.PAPER)
	_freeze_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_freeze_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fbox.add_child(_freeze_text)
	_freeze_time = Ui.label("", 28, Ui.YELLOW, true)
	_freeze_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fbox.add_child(_freeze_time)

	race.penalty_incurred.connect(_on_penalty)
	race.announced.connect(_on_announce)
	race.landmark_passed.connect(func(n: String) -> void: _toast("Passing " + n, Ui.YELLOW, Ui.INK))
	_toast("%s  to  %s" % [race.start_name, race.finish_name], Ui.INK, Ui.YELLOW)


func _process(_delta: float) -> void:
	if session == null:
		return
	_time.text = Ui.format_time(session.time)
	_penalty.text = "+%d PENALTIES" % session.ledger.total
	var road := session.current_road if session.current_road != "" else session.current_place
	_road.text = road.to_upper()
	_progress.value = clampf(1.0 - session.distance_left() / maxf(session.route_length() + session.route_s * 0.0, 1.0), 0.0, 1.0)
	_left.text = "%.1f km to %s  |  %s" % [session.distance_left() / 1000.0, session.finish_name, session.current_place]
	_freeze_panel.visible = session.freeze > 0.0
	if session.freeze > 0.0:
		_freeze_text.text = session.freeze_reason
		_freeze_time.text = "%d" % ceili(session.freeze)


func _on_penalty(info: Dictionary) -> void:
	_toast("+%d  %s" % [info["points"], info["label"]], Ui.RED, Color.WHITE)
	if session.freeze <= 0.0:
		_toast(info["line"], Color(0.1, 0.1, 0.09, 0.85), Ui.PAPER)


func _on_announce(text: String, kind: String) -> void:
	match kind:
		"danger":
			_toast(text, Ui.RED, Color.WHITE)
		"warn":
			_toast(text, Color("e0792a"), Color.WHITE)
		"good":
			_toast(text, Ui.GREEN, Color.WHITE)
		_:
			_toast(text, Color(0.1, 0.1, 0.09, 0.88), Ui.YELLOW)


func _toast(text: String, bg: Color, fg: Color) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.box(bg, 5, 7))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := Ui.label(text, 20, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	panel.add_child(l)
	_toasts.add_child(panel)
	while _toasts.get_child_count() > 4:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tween := panel.create_tween()
	tween.tween_interval(TOAST_LIFE)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
