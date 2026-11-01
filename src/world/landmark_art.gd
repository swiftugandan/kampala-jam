class_name LandmarkArt
extends RefCounted
## Small hand-drawn sign for each kind of place. Drawn in screen pixels, centred
## on the origin of the canvas transform; `s` is the sign's height in pixels.


static func draw(ci: CanvasItem, kind: String, s: float) -> void:
	var white := Color("f8f4ea")
	match kind:
		"mosque":
			var g := Color("2f9e57")
			ci.draw_rect(Rect2(-s * 0.32, -s * 0.05, s * 0.64, s * 0.4), white)
			ci.draw_circle(Vector2(0, -s * 0.06), s * 0.26, g)
			ci.draw_rect(Rect2(s * 0.34, -s * 0.46, s * 0.09, s * 0.81), white)
			ci.draw_circle(Vector2(s * 0.385, -s * 0.48), s * 0.06, g)
		"church":
			ci.draw_rect(Rect2(-s * 0.26, -s * 0.05, s * 0.52, s * 0.4), white)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-s * 0.32, -s * 0.05), Vector2(0, -s * 0.34), Vector2(s * 0.32, -s * 0.05)]), Color("b5352b"))
			ci.draw_rect(Rect2(-s * 0.03, -s * 0.55, s * 0.06, s * 0.24), white)
			ci.draw_rect(Rect2(-s * 0.1, -s * 0.48, s * 0.2, s * 0.05), white)
		"shrine":
			# The great thatched cone of a Buganda hut, which the Martyrs' shrines echo.
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-s * 0.42, s * 0.3), Vector2(0, -s * 0.52), Vector2(s * 0.42, s * 0.3)]), Color("b9833f"))
			ci.draw_line(Vector2(0, -s * 0.52), Vector2(0, s * 0.3), Color("7a4a26"), s * 0.05)
			ci.draw_rect(Rect2(-s * 0.1, s * 0.08, s * 0.2, s * 0.26), Color("3a2412"))
		"hospital":
			ci.draw_rect(Rect2(-s * 0.36, -s * 0.36, s * 0.72, s * 0.72), white)
			ci.draw_rect(Rect2(-s * 0.08, -s * 0.26, s * 0.16, s * 0.52), Color("d62f24"))
			ci.draw_rect(Rect2(-s * 0.26, -s * 0.08, s * 0.52, s * 0.16), Color("d62f24"))
		"mall":
			ci.draw_rect(Rect2(-s * 0.4, -s * 0.3, s * 0.8, s * 0.62), Color("6fa8c7"))
			for i in 3:
				ci.draw_rect(Rect2(-s * 0.33 + i * s * 0.24, -s * 0.2, s * 0.17, s * 0.2), white)
			ci.draw_rect(Rect2(-s * 0.11, s * 0.08, s * 0.22, s * 0.24), Color("23323a"))
		"market":
			for i in 4:
				var c := Color("e08a2c") if i % 2 == 0 else white
				ci.draw_rect(Rect2(-s * 0.4 + i * s * 0.2, -s * 0.28, s * 0.2, s * 0.26), c)
			ci.draw_rect(Rect2(-s * 0.36, -s * 0.02, s * 0.72, s * 0.32), Color("7a4a26"))
		"stadium":
			ci.draw_circle(Vector2.ZERO, s * 0.42, Color("c9c9c4"))
			ci.draw_circle(Vector2.ZERO, s * 0.26, Color("3f9e4a"))
		"university", "school":
			ci.draw_rect(Rect2(-s * 0.38, -s * 0.05, s * 0.76, s * 0.36), Color("a8552f") if kind == "university" else Color("d9a441"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-s * 0.44, -s * 0.05), Vector2(0, -s * 0.3), Vector2(s * 0.44, -s * 0.05)]), Color("3a2412"))
			ci.draw_rect(Rect2(-s * 0.02, -s * 0.55, s * 0.03, s * 0.27), white)
			ci.draw_rect(Rect2(s * 0.01, -s * 0.55, s * 0.18, s * 0.11), Color("f5c518"))
		"hotel":
			ci.draw_rect(Rect2(-s * 0.26, -s * 0.42, s * 0.52, s * 0.76), Color("3e9a8c"))
			for row in 3:
				for col in 2:
					ci.draw_rect(Rect2(-s * 0.17 + col * s * 0.22, -s * 0.33 + row * s * 0.2, s * 0.12, s * 0.11), white)
		"fuel":
			ci.draw_rect(Rect2(-s * 0.2, -s * 0.34, s * 0.34, s * 0.68), Color("e23b2e"))
			ci.draw_rect(Rect2(-s * 0.13, -s * 0.26, s * 0.2, s * 0.18), white)
			ci.draw_line(Vector2(s * 0.14, -s * 0.1), Vector2(s * 0.3, s * 0.1), white, s * 0.05)
		"police":
			ci.draw_rect(Rect2(-s * 0.32, -s * 0.28, s * 0.64, s * 0.6), Color("2f5ca8"))
			ci.draw_circle(Vector2.ZERO, s * 0.14, white)
		"taxi_park":
			ci.draw_rect(Rect2(-s * 0.4, -s * 0.2, s * 0.8, s * 0.4), white)
			ci.draw_rect(Rect2(-s * 0.4, -s * 0.02, s * 0.8, s * 0.09), Color("1d5fa8"))
		_:
			ci.draw_circle(Vector2.ZERO, s * 0.28, Color("8c5fb0"))
			ci.draw_circle(Vector2.ZERO, s * 0.11, white)
