class_name RunScreen
extends Node
## A single drive: owns the session, feeds it input, shows the world and HUD.

signal run_ended(result: Dictionary)
signal quit_to_title
signal restart_requested

var session: RaceSession
var world := GameWorld.new()
var hud := Hud.new()
var touch := TouchControls.new()
var audio := GameAudio.new()
var bot: Autodriver  ## Set only by capture runs.
var _input := DriveInput.new()
var _canvas := CanvasLayer.new()
var _rain := RainOverlay.new()
var _big_map: Minimap
var _pause_panel: Control


func start(level: Dictionary, seed_value: int) -> void:
	session = RaceSession.new(level, seed_value)
	add_child(world)
	world.setup(session)
	add_child(_canvas)
	_rain.session = session
	_canvas.add_child(_rain)
	hud.setup(session)
	_canvas.add_child(hud)
	touch.visible = Ui.has_touch() or OS.get_cmdline_user_args().has("--kj-touch")
	_canvas.add_child(touch)
	hud.pause_button.pressed.connect(_toggle_pause)
	hud.map_button.pressed.connect(_toggle_map)
	add_child(audio)
	audio.setup(session)
	session.ended.connect(_on_ended)


func _physics_process(delta: float) -> void:
	if session == null or session.status != RaceSession.Status.RUNNING:
		return
	session.step(delta, bot.decide(delta) if bot else _read_input())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_P):
		_toggle_pause()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_M:
		_toggle_map()
	elif event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
		_toggle_pause()


func _read_input() -> DriveInput:
	var i := _input
	i.has_target = false
	i.steer = 0.0
	i.throttle = 0.0
	i.brake = 0.0
	i.horn = false
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		i.throttle = 1.0
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		i.brake = 1.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		i.steer -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		i.steer += 1.0
	if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_H):
		i.horn = true
	for device in Input.get_connected_joypads():
		var stick := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.25:
			i.has_target = true
			i.target_heading = stick.angle()
			i.throttle = maxf(i.throttle, clampf(stick.length(), 0.0, 1.0))
		i.throttle = maxf(i.throttle, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT))
		i.brake = maxf(i.brake, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT))
		if Input.is_joy_button_pressed(device, JOY_BUTTON_B):
			i.brake = 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
			i.horn = true
	if touch.visible:
		if touch.stick_vector.length() > 0.2:
			i.has_target = true
			i.target_heading = touch.stick_vector.angle()
			i.throttle = maxf(i.throttle, touch.stick_vector.length())
		if touch.brake:
			i.brake = 1.0
			i.throttle = 0.0
		i.horn = i.horn or touch.horn
	return i


func _toggle_map() -> void:
	if _big_map:
		_big_map.queue_free()
		_big_map = null
		if _pause_panel == null:
			get_tree().paused = false
		return
	_big_map = Minimap.new()
	_big_map.setup(session, true)
	_big_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_map.process_mode = Node.PROCESS_MODE_ALWAYS
	_big_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_big_map.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_toggle_map())
	_canvas.add_child(_big_map)
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true


func _toggle_pause() -> void:
	if session.status != RaceSession.Status.RUNNING:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _pause_panel:
		_pause_panel.queue_free()
		_pause_panel = null
		get_tree().paused = false
		return
	get_tree().paused = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas.add_child(dim)
	_pause_panel = dim
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	col.add_child(Ui.label("HOLDING AT THE ROADSIDE", 30, Ui.YELLOW, true))
	var resume := Ui.button("CARRY ON")
	resume.pressed.connect(_toggle_pause)
	col.add_child(resume)
	var again := Ui.button("START THIS DAY AGAIN", false, 20)
	again.pressed.connect(func() -> void:
		get_tree().paused = false
		restart_requested.emit())
	col.add_child(again)
	var quit := Ui.button("GO HOME", false, 20)
	quit.pressed.connect(func() -> void:
		get_tree().paused = false
		quit_to_title.emit())
	col.add_child(quit)
	resume.grab_focus()


func _on_ended(result: Dictionary) -> void:
	audio.stop_all()
	run_ended.emit(result)
