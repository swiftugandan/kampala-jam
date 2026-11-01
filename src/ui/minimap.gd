class_name Minimap
extends Control
## The main roads, your position and the line Maps wants you to follow. Small in
## the corner while driving; `full` shows the whole journey with landmarks.

var session: RaceSession
var full := false
var _mesh: ArrayMesh
var _acc := 0.0
var _world_span := 2600.0


func setup(race: RaceSession, whole_map: bool) -> void:
	session = race
	full = whole_map
	clip_contents = true
	var map := session.map
	var verts := PackedVector2Array()
	var colours := PackedColorArray()
	var palette := [Color("f5c518"), Color("f0e6c8"), Color("c9c2ad")]
	for si in map.seg_edge.size():
		var cls := map.edge_class[map.seg_edge[si]]
		if cls > 2:
			continue
		verts.append(Vector2(map.seg_xy[si * 4], map.seg_xy[si * 4 + 1]))
		verts.append(Vector2(map.seg_xy[si * 4 + 2], map.seg_xy[si * 4 + 3]))
		colours.append(palette[cls])
		colours.append(palette[cls])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)


func _process(delta: float) -> void:
	_acc -= delta
	if _acc <= 0.0:
		_acc = 0.1
		queue_redraw()


func _draw() -> void:
	if session == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.07, 0.07, 0.06, 0.86 if not full else 1.0))
	var origin: Vector2
	var scale_v: float
	if full:
		var pts := session.route_pts
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		box = box.expand(session.car.pos).grow(350.0)
		scale_v = minf(size.x / box.size.x, size.y / box.size.y)
		origin = size * 0.5 - box.get_center() * scale_v
	else:
		scale_v = minf(size.x, size.y) / _world_span
		origin = size * 0.5 - session.car.pos * scale_v
	draw_set_transform(origin, 0.0, Vector2.ONE * scale_v)
	draw_mesh(_mesh, null)
	var route := session.route_pts
	var from := maxi(session.route_idx, 0)
	var line := route.slice(from)
	if line.size() > 1:
		draw_polyline(line, Color(0.25, 0.65, 1.0), 2.6 / scale_v)
	draw_set_transform(Vector2.ZERO)
	_landmarks(origin, scale_v)
	for c in session.known_closures:
		var p := origin + c * scale_v
		draw_line(p - Vector2(4, 4), p + Vector2(4, 4), Ui.RED, 2.0)
		draw_line(p - Vector2(-4, 4), p + Vector2(-4, 4), Ui.RED, 2.0)
	var finish := origin + session.finish_pos * scale_v
	if not rect.has_point(finish):
		finish = _clamp_to_edge(finish)
	draw_circle(finish, 6.0, Ui.INK)
	draw_circle(finish, 4.5, Ui.GREEN)
	var carp := origin + session.car.pos * scale_v
	var dir := Vector2.from_angle(session.car.heading)
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([carp + dir * 8.0, carp - dir * 5.0 + side * 5.0, carp - dir * 5.0 - side * 5.0]), Ui.RED)
	draw_rect(rect, Ui.YELLOW, false, 2.0)


func _landmarks(origin: Vector2, scale_v: float) -> void:
	var font := Ui.body_font()
	var taken: Array[Rect2] = []
	for lm: Dictionary in session.map.landmarks:
		if int(lm["tier"]) != 1:
			continue
		var p: Vector2 = origin + Vector2(lm["x"], lm["y"]) * scale_v
		if not Rect2(Vector2.ZERO, size).has_point(p):
			continue
		var name_text: String = lm["name"]
		var visited := session.passed.has(name_text)
		draw_circle(p, 3.2 if not full else 4.0, Ui.GREEN if visited else Ui.YELLOW)
		if full:
			# Try the label on each side and stacked, so close neighbours stay readable.
			var w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			for offset: Vector2 in [Vector2(7, 5), Vector2(-w - 7, 5), Vector2(7, -10), Vector2(-w - 7, -10), Vector2(7, 20), Vector2(-w - 7, 20)]:
				var box := Rect2(p + offset + Vector2(0, -13), Vector2(w, 17))
				var free := true
				for other in taken:
					if other.intersects(box):
						free = false
						break
				if free:
					taken.append(box)
					draw_string_outline(font, p + offset, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.9))
					draw_string(font, p + offset, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Ui.PAPER)
					break


func _clamp_to_edge(p: Vector2) -> Vector2:
	var c := size * 0.5
	var d := p - c
	var k := minf(absf((c.x - 8.0) / maxf(absf(d.x), 0.001)), absf((c.y - 8.0) / maxf(absf(d.y), 0.001)))
	return c + d * minf(k, 1.0)
