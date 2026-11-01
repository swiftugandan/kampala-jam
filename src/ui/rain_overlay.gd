class_name RainOverlay
extends Control
## Rain across the windscreen. Darkens the world with intensity.

var session: RaceSession
var _drops := PackedVector2Array()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_drops.resize(170)
	for i in _drops.size():
		_drops[i] = Vector2(rng.randf(), rng.randf())


func _process(delta: float) -> void:
	var rain := session.director.rain if session else 0.0
	visible = rain > 0.01
	if not visible:
		return
	for i in _drops.size():
		var d := _drops[i]
		d += Vector2(-0.25, 1.4) * delta * (0.8 + float(i % 5) * 0.12)
		d.x = fposmod(d.x, 1.0)
		d.y = fposmod(d.y, 1.0)
		_drops[i] = d
	queue_redraw()


func _draw() -> void:
	var rain: float = session.director.rain
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.12, 0.2, 0.4 * rain))
	var col := Color(0.8, 0.88, 1.0, 0.45 * rain)
	var count := int(_drops.size() * rain)
	for i in count:
		var p := _drops[i] * size
		draw_line(p, p + Vector2(-5, 24), col, 1.5)
