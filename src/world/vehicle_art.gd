class_name VehicleArt
extends RefCounted
## Draws vehicles from the baked atlas (tools/art). One texture, so one batch.

static var _tex: Texture2D
static var _rects: Dictionary = {}
static var _px := 20.0


static func draw(ci: CanvasItem, sprite: String) -> void:
	if _tex == null:
		_load()
	var src: Rect2 = _rects.get(sprite, Rect2())
	if src.size == Vector2.ZERO:
		push_error("No vehicle sprite: " + sprite)
		return
	var size := src.size / _px
	ci.draw_texture_rect_region(_tex, Rect2(-size * 0.5, size), src)


static func _load() -> void:
	_tex = load("res://assets/vehicles/atlas.png")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicle_sprites.json"))
	_px = data["px_per_wu"]
	var rects: Dictionary = data["rects"]
	for key: String in rects:
		var r: Array = rects[key]
		_rects[key] = Rect2(r[0], r[1], r[2], r[3])
