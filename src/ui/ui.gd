class_name Ui
extends RefCounted
## The game's look: signwriter lettering on hazard yellow and road black.

const YELLOW := Color("f5c518")
const INK := Color("17140f")
const PAPER := Color("f6efe0")
const MURRAM := Color("b5562c")
const RED := Color("d62f24")
const GREEN := Color("2f9e57")
const MUTED := Color("b9b2a3")

static var _title: Font
static var _body: Font


static func title_font() -> Font:
	if _title == null:
		_title = load("res://assets/fonts/Bungee-Regular.ttf")
	return _title


static func body_font() -> Font:
	if _body == null:
		_body = load("res://assets/fonts/ArchivoNarrow.ttf")
	return _body


static func label(text: String, size: int, colour: Color = PAPER, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font() if title else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


static func box(bg: Color, radius := 6, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func button(text: String, primary := true, size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 60)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", title_font())
	b.add_theme_font_size_override("font_size", size)
	var bg := YELLOW if primary else Color("2b2720")
	var fg := INK if primary else PAPER
	b.add_theme_stylebox_override("normal", box(bg, 6, 14))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.15), 6, 14))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.2), 6, 14))
	b.add_theme_stylebox_override("focus", box(bg.lightened(0.15), 6, 14))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	return b


static func has_touch() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
