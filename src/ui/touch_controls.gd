class_name TouchControls
extends Control
## Thumb controls. Left thumb points where you want to go, and how far you push
## is your speed. Right thumb brakes and hoots. Hidden unless the device has touch.

const STICK_RADIUS := 78.0

var stick_active := false
var stick_vector := Vector2.ZERO
var brake := false
var horn := false
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _brake_finger := -1
var _horn_finger := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _brake_rect() -> Rect2:
	var v := size
	return Rect2(v.x - 190.0, v.y - 190.0, 170.0, 170.0)


func _horn_rect() -> Rect2:
	var v := size
	return Rect2(v.x - 340.0, v.y - 130.0, 130.0, 110.0)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if _brake_rect().has_point(e.position):
				_brake_finger = e.index
				brake = true
			elif _horn_rect().has_point(e.position):
				_horn_finger = e.index
				horn = true
			elif e.position.x < size.x * 0.5 and e.position.y > size.y * 0.22 and _stick_finger < 0:
				_stick_finger = e.index
				_stick_origin = e.position
				stick_active = true
				stick_vector = Vector2.ZERO
		else:
			if e.index == _stick_finger:
				_stick_finger = -1
				stick_active = false
				stick_vector = Vector2.ZERO
			if e.index == _brake_finger:
				_brake_finger = -1
				brake = false
			if e.index == _horn_finger:
				_horn_finger = -1
				horn = false
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			stick_vector = ((d.position - _stick_origin) / STICK_RADIUS).limit_length(1.0)
			queue_redraw()


func _draw() -> void:
	var font := Ui.title_font()
	if stick_active:
		draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(_stick_origin + stick_vector * STICK_RADIUS, 30.0, Color(0.96, 0.77, 0.09, 0.8))
	else:
		var c := Vector2(130.0, size.y - 130.0)
		draw_arc(c, STICK_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 3.0)
		draw_string(font, c + Vector2(-34, 6), "DRIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.4))
	_button(_brake_rect(), "BRAKE", brake, Ui.RED)
	_button(_horn_rect(), "HOOT", horn, Ui.YELLOW)


func _button(r: Rect2, text: String, down: bool, col: Color) -> void:
	var font := Ui.title_font()
	var c := col
	c.a = 0.8 if down else 0.42
	draw_circle(r.get_center(), r.size.y * 0.5, c)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, r.get_center() + Vector2(-w * 0.5, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
