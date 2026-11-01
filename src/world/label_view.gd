class_name LabelView
extends Node2D
## What makes it Kampala: landmark signs, place names and road names, drawn at a
## fixed screen size whatever the camera zoom. Rebuilt a few times a second.

const RANGE: Array[float] = [0.0, 430.0, 230.0, 120.0]
const REDRAW := 0.12
const CHUNK := 480.0
const MAX_ROAD_LABELS := 8

var map: MapData
var camera: Camera2D
var _by_cell: Dictionary = {}
var _acc := 0.0
var _hit := MapData.RoadHit.new()
var title_font: Font
var body_font: Font
var highlight_finish := ""


func _ready() -> void:
	map = MapData.shared()
	title_font = Ui.title_font()
	body_font = Ui.body_font()
	for lm: Dictionary in map.landmarks:
		var c := Vector2i(int(float(lm["x"]) / CHUNK), int(float(lm["y"]) / CHUNK))
		(_by_cell.get_or_add(c, []) as Array).append(lm)


func _process(delta: float) -> void:
	_acc -= delta
	if _acc <= 0.0:
		_acc = REDRAW
		queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var focus := camera.get_screen_center_position()
	var unscale := Vector2.ONE / camera.zoom
	var taken: Array[Rect2] = []
	_draw_places(focus, unscale, taken)
	var near: Array = _gather(focus)
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in near:
		_draw_landmark(entry[1], unscale, taken)
	_draw_road_names(focus, unscale, taken)


func _gather(focus: Vector2) -> Array:
	var out := []
	var cc := Vector2i(int(focus.x / CHUNK), int(focus.y / CHUNK))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for lm: Dictionary in _by_cell.get(cc + Vector2i(dx, dy), []):
				var tier := int(lm["tier"])
				var d := Vector2(lm["x"], lm["y"]).distance_to(focus)
				if d < RANGE[tier]:
					out.append([tier * 1000.0 + d, lm])
	return out


func _free_rect(world: Vector2, size: Vector2, unscale: Vector2, taken: Array[Rect2]) -> bool:
	var rect := Rect2(world - Vector2(size.x * 0.5 * unscale.x, size.y * unscale.y), size * unscale)
	for other in taken:
		if rect.intersects(other):
			return false
	taken.append(rect)
	return true


func _draw_landmark(lm: Dictionary, unscale: Vector2, taken: Array[Rect2]) -> void:
	var tier := int(lm["tier"])
	var p := Vector2(lm["x"], lm["y"])
	var name_text: String = lm["name"]
	var kind: String = lm["kind"]
	if tier == 1:
		var size := title_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		if not _free_rect(p, Vector2(size.x + 24.0, 74.0), unscale, taken):
			return
		draw_set_transform(p, 0.0, unscale)
		draw_circle(Vector2(0, -38), 27.0, Color(0.09, 0.08, 0.06, 0.9))
		draw_arc(Vector2(0, -38), 27.0, 0.0, TAU, 28, Ui.YELLOW, 2.0)
		draw_set_transform(p + Vector2(0, -38) * unscale, 0.0, unscale)
		LandmarkArt.draw(self, kind, 38.0)
		draw_set_transform(p, 0.0, unscale)
		draw_style_box(_plate(), Rect2(-size.x * 0.5 - 8.0, -8.0, size.x + 16.0, 25.0))
		draw_string(title_font, Vector2(-size.x * 0.5, 11.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Ui.YELLOW)
	elif tier == 2:
		var size := body_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		if not _free_rect(p, Vector2(size.x + 30.0, 22.0), unscale, taken):
			return
		draw_set_transform(p, 0.0, unscale)
		draw_circle(Vector2(-size.x * 0.5 - 9.0, -7.0), 10.0, Color(0.09, 0.08, 0.06, 0.82))
		draw_set_transform(p + Vector2(-size.x * 0.5 - 9.0, -7.0) * unscale, 0.0, unscale)
		LandmarkArt.draw(self, kind, 16.0)
		draw_set_transform(p, 0.0, unscale)
		draw_string_outline(body_font, Vector2(-size.x * 0.5 + 3.0, -2.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.85))
		draw_string(body_font, Vector2(-size.x * 0.5 + 3.0, -2.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fffbe9"))
	else:
		var size := body_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		if not _free_rect(p, Vector2(size.x + 4.0, 16.0), unscale, taken):
			return
		draw_set_transform(p, 0.0, unscale)
		draw_string_outline(body_font, Vector2(-size.x * 0.5, 0.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.7))
		draw_string(body_font, Vector2(-size.x * 0.5, 0.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.98, 0.9, 0.9))
	draw_set_transform(Vector2.ZERO)


func _plate() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.08, 0.06, 0.9)
	s.set_corner_radius_all(4)
	return s


func _draw_places(focus: Vector2, unscale: Vector2, taken: Array[Rect2]) -> void:
	for pl: Dictionary in map.places:
		var p := Vector2(pl["x"], pl["y"])
		if p.distance_squared_to(focus) > 400.0 * 400.0:
			continue
		var text := String(pl["name"]).to_upper()
		var size := 26 if int(pl["rank"]) == 0 else 18
		var w := title_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if not _free_rect(p, Vector2(w, float(size)), unscale, taken):
			continue
		draw_set_transform(p, 0.0, unscale)
		draw_string_outline(title_font, Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.32))
		draw_string(title_font, Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.55))
	draw_set_transform(Vector2.ZERO)


## Real road names, laid along the road. Sampled so each name appears once nearby.
func _draw_road_names(focus: Vector2, unscale: Vector2, taken: Array[Rect2]) -> void:
	var shown := {}
	var count := 0
	var step := 70.0
	var y := -210.0
	while y <= 210.0 and count < MAX_ROAD_LABELS:
		var x := -350.0
		while x <= 350.0 and count < MAX_ROAD_LABELS:
			var q := focus + Vector2(x, y)
			x += step
			if not map.road_at(q, _hit) or _hit.clearance < 0.0:
				continue
			var road := map.road_name(_hit.edge)
			if road == "" or shown.has(road) or map.edge_class[_hit.edge] > 4:
				continue
			var w := body_font.get_string_size(road, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			if not _free_rect(_hit.closest, Vector2(w, 16.0), unscale, taken):
				continue
			shown[road] = true
			count += 1
			var angle := _hit.tangent.angle()
			if absf(wrapf(angle, -PI, PI)) > PI * 0.5:
				angle += PI
			draw_set_transform(_hit.closest, angle, unscale)
			draw_string_outline(body_font, Vector2(-w * 0.5, 4.0), road, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.7))
			draw_string(body_font, Vector2(-w * 0.5, 4.0), road, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f6efe0"))
		y += step
	draw_set_transform(Vector2.ZERO)
