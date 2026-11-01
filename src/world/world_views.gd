class_name WorldViews
extends RefCounted
## Thin views of the simulation. Each only reads the session and draws.

class RouteLine extends Node2D:
	var session: RaceSession

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var pts := PackedVector2Array()
		var d := 0.0
		while d <= 900.0:
			pts.append(session.route_ahead_point(d))
			d += 24.0
		if pts.size() > 1:
			draw_polyline(pts, Color(0.2, 0.6, 1.0, 0.5), 2.4, true)

class Hazards extends Node2D:
	var session: RaceSession
	var camera: Camera2D
	var clock := 0.0

	func _process(d: float) -> void:
		clock += d
		queue_redraw()

	func _draw() -> void:
		var focus := camera.get_screen_center_position()
		var dir := session.director
		for f in dir.floods:
			if dir.flood_level > 0.08 and f.pos.distance_squared_to(focus) < 560.0 * 560.0:
				_flood(f, dir.flood_level)
		for h in dir.hazards:
			if h.pos.distance_squared_to(focus) < 560.0 * 560.0:
				draw_set_transform(h.pos, h.tangent.angle())
				_hazard(h)
		draw_set_transform(Vector2.ZERO)
		var c := dir.convoy_active()
		if c != null and c.phase == 2:
			_convoy(c)

	func _flood(f: HazardDirector.Flood, level: float) -> void:
		draw_set_transform(f.pos)
		var r := f.radius * clampf(level * 1.6, 0.2, 1.0)
		var col := Color("6f6240")
		col.a = 0.82 * clampf(level * 1.5, 0.0, 1.0)
		draw_circle(Vector2.ZERO, r, col)
		draw_circle(Vector2(r * 0.25, -r * 0.2), r * 0.7, Color(0.5, 0.45, 0.3, col.a * 0.4))
		for i in 4:
			var phase := fmod(clock * 0.5 + i * 0.25, 1.0)
			draw_arc(Vector2(sin(i * 2.1) * r * 0.5, cos(i * 3.3) * r * 0.5), 1.5 + phase * 7.0, 0.0, TAU, 14, Color(1, 1, 1, 0.3 * (1.0 - phase)), 0.4)
		if f.discovered:
			# Someone stuck a branch in it, the way people do. Now you know.
			draw_line(f.ditch_pos - f.pos, f.ditch_pos - f.pos + Vector2(0, -9), Color("4b3320"), 0.8)
			draw_rect(Rect2(f.ditch_pos - f.pos + Vector2(0, -9), Vector2(4, 2.5)), Ui.RED)

	func _hazard(h: HazardDirector.Hazard) -> void:
		match h.type:
			"rebar":
				draw_circle(Vector2.ZERO, 2.7, Color("2a2622"))
				draw_arc(Vector2.ZERO, 2.7, 0.0, TAU, 14, Color("8a8378"), 0.5)
				for i in 5:
					var a := TAU * i / 5.0 + 0.4
					draw_line(Vector2.from_angle(a) * 1.4, Vector2.from_angle(a) * 3.9, Color("b5612f"), 0.45)
			"open_drain":
				draw_rect(Rect2(-h.hl, -h.hw, h.hl * 2.0, h.hw * 2.0), Color("211c14"))
				draw_rect(Rect2(-h.hl, -0.7, h.hl * 2.0, 1.4), Color("56603a"))
				var x := -h.hl
				while x < h.hl:
					draw_line(Vector2(x, -h.hw), Vector2(x, h.hw), Color("6c665c"), 0.2)
					x += 6.0
			"marram":
				draw_circle(Vector2(-h.hl * 0.4, 0), h.hw * 0.95, Color("b5562c"))
				draw_circle(Vector2(h.hl * 0.1, -h.hw * 0.2), h.hw, Color("c56a39"))
				draw_circle(Vector2(h.hl * 0.55, h.hw * 0.2), h.hw * 0.85, Color("a94f27"))
			"trench":
				draw_rect(Rect2(-h.hl, -h.hw, h.hl * 2.0, h.hw * 2.0), Color("2a1b10"))
				draw_rect(Rect2(-h.hl - 1.4, -h.hw, 1.4, h.hw * 2.0), Color("b5562c"))
				draw_rect(Rect2(-h.hl - 1.6, -2.5, h.hl * 2.0 + 3.2, 1.6), Color("8e6b42"))
				draw_rect(Rect2(-h.hl - 1.6, 1.0, h.hl * 2.0 + 3.2, 1.6), Color("8e6b42"))
				_cones(Vector2(-h.hl - 4.0, -h.hw), Vector2(-h.hl - 4.0, h.hw), 5)
				_cones(Vector2(h.hl + 4.0, -h.hw), Vector2(h.hl + 4.0, h.hw), 5)
			"closure":
				_barrier(h)
				_cones(Vector2(-7.0, -h.hw), Vector2(-7.0, h.hw), 7)
				_cones(Vector2(7.0, -h.hw), Vector2(7.0, h.hw), 7)
			"partial":
				draw_rect(Rect2(-h.hl, -h.hw, h.hl * 2.0, h.hw * 2.0), Color(0.68, 0.34, 0.17, 0.92))
				var edge_y := h.hw * (-1.0 if h.side > 0.0 else 1.0)
				_cones(Vector2(-h.hl, edge_y), Vector2(h.hl, edge_y), int(h.hl / 5.0) + 2)
				_cones(Vector2(-h.hl, -edge_y), Vector2(-h.hl, edge_y), 4)
				_cones(Vector2(h.hl, -edge_y), Vector2(h.hl, edge_y), 4)
			"flagger":
				draw_line(Vector2(0, -h.hw), Vector2(0, h.hw), Color(1, 1, 1, 0.35), 0.5)
				var p := Vector2(0, -h.hw * 0.86)
				draw_circle(p, 1.5, Color("f05a22"))
				draw_circle(p, 0.8, Color("43291a"))
				var flag := Ui.GREEN if h.flag_green else Ui.RED
				var wave := sin(clock * 9.0) * 1.2
				draw_line(p, p + Vector2(wave, 4.5), Color(0.9, 0.9, 0.9), 0.3)
				draw_rect(Rect2(p + Vector2(wave, 4.5), Vector2(3.4, 2.4)), flag)

	func _barrier(h: HazardDirector.Hazard) -> void:
		var y := -h.hw
		var red := true
		while y < h.hw:
			draw_rect(Rect2(-1.2, y, 2.4, minf(3.0, h.hw - y)), Ui.RED if red else Color("f4f2ec"))
			red = not red
			y += 3.0

	func _cones(a: Vector2, b: Vector2, n: int) -> void:
		for i in n:
			var p := a.lerp(b, float(i) / maxf(n - 1, 1))
			draw_circle(p, 0.9, Color("ef6a1f"))
			draw_circle(p, 0.35, Color("f8f4ea"))

	func _convoy(c: HazardDirector.Convoy) -> void:
		for i in c.vehicles.size():
			var along := c.head - HazardDirector.CONVOY_GAP * i
			if along <= 0.0 or along >= c.length:
				continue
			var at: Array = c.pos_at(along)
			var tangent: Vector2 = at[1]
			draw_set_transform(at[0], tangent.angle())
			VehicleArt.draw(self, c.vehicles[i])
			var flash := fmod(clock * 6.0 + i * 0.37, 1.0) < 0.5
			draw_circle(Vector2(1, -1.2), 1.0, Color("ff3a2e") if flash else Color("3a7bff"))
			draw_circle(Vector2(1, 1.2), 1.0, Color("3a7bff") if flash else Color("ff3a2e"))
		draw_set_transform(Vector2.ZERO)

class Traffic extends Node2D:
	var session: RaceSession
	var clock := 0.0

	func _process(d: float) -> void:
		clock += d
		queue_redraw()

	func _draw() -> void:
		for a in session.traffic.agents:
			draw_set_transform(a.pos, a.heading + (1.3 if a.downed > 0.0 else 0.0))
			VehicleArt.draw(self, a.sprite)
			if a.downed > 0.0:
				_crowd(a)
			elif a.arguing > 0.0:
				draw_set_transform(a.pos)
				var bob := sin(clock * 10.0) * 0.5
				draw_circle(Vector2(0, -6 + bob), 2.2, Ui.RED)
				draw_rect(Rect2(-0.3, -7.4 + bob, 0.6, 1.8), Color.WHITE)
				draw_rect(Rect2(-0.3, -5.2 + bob, 0.6, 0.6), Color.WHITE)
		draw_set_transform(Vector2.ZERO)

	func _crowd(a: TrafficSim.Agent) -> void:
		# People run over to look. A crowd is what you get, and it costs you.
		draw_set_transform(a.pos)
		for i in 9:
			var t := i * 2.4 + a.pos.x
			var p := Vector2.from_angle(t) * (5.5 + fmod(t * 7.0, 3.0)) + Vector2(sin(clock * 3.0 + t), cos(clock * 2.0 + t)) * 0.4
			draw_circle(p, 0.9, [Color("c9553d"), Color("3a6ea5"), Color("e3c15a"), Color("3a8a55")][i % 4])
			draw_circle(p, 0.42, Color("3b2619"))

class Player extends Node2D:
	var session: RaceSession
	var clock := 0.0

	func _process(d: float) -> void:
		clock += d
		queue_redraw()

	func _draw() -> void:
		var car := session.car
		draw_set_transform(car.pos, car.heading)
		var hl := session.car_half_len
		if session.freeze > 0.0 and fmod(clock * 3.0, 1.0) < 0.5:
			draw_circle(Vector2.ZERO, hl + 2.0, Color(1, 0.2, 0.1, 0.35))
		VehicleArt.draw(self, "player")
		draw_set_transform(Vector2.ZERO)
