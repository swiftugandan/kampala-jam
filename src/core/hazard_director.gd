class_name HazardDirector
extends RefCounted
## Everything on the road that is not traffic: road works, closures, flag-wavers,
## floods with hidden ditches, the rain, and the presidential convoy.

## Fixed so a ditch stays where it was. Kampala drivers remember; so can you.
const WORLD_SEED := 25041962
const SIGHT := 115.0
const CONVOY_CORRIDOR := 75.0
const CONVOY_GAP := 15.0

class Hazard:
	var type := ""
	var pos := Vector2.ZERO
	var tangent := Vector2.RIGHT
	var hl := 2.0
	var hw := 2.0
	var edge := -1
	var solid := false
	var revealed := false
	var cooldown := 0.0
	var flag_green := true
	var flag_timer := 0.0
	var sign_text := ""
	var side := 1.0

	func local(p: Vector2) -> Vector2:
		var d := p - pos
		return Vector2(d.dot(tangent), d.dot(Vector2(tangent.y, -tangent.x)))

class Flood:
	var pos := Vector2.ZERO
	var radius := 36.0
	var ditch := false
	var ditch_pos := Vector2.ZERO
	var ditch_r := 9.0
	var water := ""
	var discovered := false
	var cooldown := 0.0

class Convoy:
	var path := PackedVector2Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var phase := 0  ## 0 scheduled, 1 warning, 2 passing, 3 done.
	var timer := 0.0
	var start_at := 0.0
	var head := 0.0
	var penalty_cd := 0.0
	var style := "presidential"
	var cfg: Dictionary = {}
	var vehicles: Array = []

	func tail_gap() -> float:
		return CONVOY_GAP * (vehicles.size() - 1)

	func pos_at(d: float) -> Array:
		var dist := clampf(d, 0.0, length)
		var i := clampi(cum.bsearch(dist) - 1, 0, path.size() - 2)
		var seg := cum[i + 1] - cum[i]
		var t := 0.0 if seg < 0.001 else (dist - cum[i]) / seg
		return [path[i].lerp(path[i + 1], t), (path[i + 1] - path[i]).normalized()]

var session: RaceSession
var map: MapData
var rng: RandomNumberGenerator
var level: Dictionary
var hazards: Array[Hazard] = []
var floods: Array[Flood] = []
var convoys: Array[Convoy] = []
var rain := 0.0
var flood_level := 0.0
var rain_start := -1.0
var rain_end := -1.0
var _hit := MapData.RoadHit.new()
var _reveal_acc := 0.0


func _init(race: RaceSession, level_data: Dictionary, random: RandomNumberGenerator) -> void:
	session = race
	map = race.map
	level = level_data
	rng = random


func build() -> void:
	var counts: Dictionary = level["hazards"]
	var off: float = counts["off_route_factor"]
	for spec: Dictionary in level.get("authored", []):
		_place_authored(spec)
	for type: String in ["rebar", "open_drain", "marram", "trench", "flagger", "partial", "closure"]:
		var n := int(counts.get(type, 0))
		for i in n:
			_place_on_route(type)
		for i in int(n * off):
			_place_near_route(type)
	_place_floods(int(level["floods"]))
	_schedule_weather()
	_schedule_convoys()
	_update_zones()


# --------------------------------------------------------- placement ------
func _place_authored(spec: Dictionary) -> void:
	var edges := map.edges_named(spec["road"])
	var best := -1
	var best_len := 0.0
	for e in edges:
		var length := map.edge_path(e).length
		if length > best_len and not _edge_taken(e):
			best_len = length
			best = e
	if best < 0:
		push_warning("No free edge on " + str(spec["road"]))
		return
	_place_at_edge(spec["type"], best, 0.5)


func _edge_taken(e: int) -> bool:
	for h in hazards:
		if h.edge == e:
			return true
	return false


func _place_on_route(type: String) -> void:
	for attempt in 12:
		var pts := session.route_pts
		if pts.size() < 8:
			return
		# Leave the first stretch clear so the player gets going.
		var i := rng.randi_range(mini(6, pts.size() - 2), pts.size() - 3)
		if pts[i].distance_to(pts[0]) < 180.0 or pts[i].distance_to(pts[pts.size() - 1]) < 80.0:
			continue
		if _try_place(type, pts[i].lerp(pts[i + 1], rng.randf())):
			return


func _place_near_route(type: String) -> void:
	for attempt in 12:
		var pts := session.route_pts
		var i := rng.randi_range(0, pts.size() - 1)
		var p := pts[i] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(100.0, 800.0)
		if p.distance_to(pts[0]) > 180.0 and _try_place(type, p):
			return


func _try_place(type: String, p: Vector2) -> bool:
	if not map.road_at(p, _hit) or _hit.clearance < 0.0:
		return false
	if type == "closure" or type == "trench" or type == "flagger" or type == "partial":
		var length := map.edge_path(_hit.edge).length
		if length < 50.0 or _edge_taken(_hit.edge):
			return false
		return _place_at_edge(type, _hit.edge, rng.randf_range(0.35, 0.65))
	for h in hazards:
		if h.pos.distance_squared_to(_hit.closest) < 90.0 * 90.0:
			return false
	return _place_pose(type, _hit.edge, _hit.closest, _hit.tangent)


func _place_at_edge(type: String, e: int, frac: float) -> bool:
	var path := map.edge_path(e)
	var sampled: Array = path.sample(path.length * frac)
	return _place_pose(type, e, sampled[0], sampled[1])


func _place_pose(type: String, e: int, p: Vector2, tangent: Vector2) -> bool:
	var hw := map.half_width(e)
	var left := Vector2(tangent.y, -tangent.x)
	var h := Hazard.new()
	h.type = type
	h.edge = e
	h.tangent = tangent
	h.side = 1.0 if rng.randf() < 0.5 else -1.0
	var names: Array = Rules.data()["works_names"]
	match type:
		"rebar":
			h.pos = p + left * h.side * hw * rng.randf_range(0.15, 0.7)
			h.hl = 2.0
			h.hw = 2.0
		"open_drain":
			h.pos = p + left * h.side * hw * 0.74
			h.hl = rng.randf_range(16.0, 34.0)
			h.hw = 2.4
		"marram":
			h.pos = p + left * h.side * hw * rng.randf_range(0.1, 0.5)
			h.hl = 12.0
			h.hw = 6.0
		"trench":
			h.pos = p
			h.hl = 3.2
			h.hw = hw + 2.5
			h.sign_text = names[rng.randi() % names.size()]
		"closure":
			if map.edge_class[e] == 0 or not _can_close(e):
				return false
			h.pos = p
			h.hl = 3.0
			h.hw = hw + 3.0
			h.solid = true
			h.sign_text = names[rng.randi() % names.size()]
			session.traffic.blocked[e] = true
		"partial":
			# Most of the road is coned off; the rest is shared by everyone.
			h.pos = p + left * h.side * hw * 0.34
			h.hl = minf(map.edge_path(e).length * 0.32, 42.0)
			h.hw = hw * 0.66 + 1.0
			h.solid = true
			h.sign_text = names[rng.randi() % names.size()]
			session.traffic.lane_override[e] = -h.side * 0.68
		"flagger":
			h.pos = p
			h.hl = 3.0
			h.hw = hw
			h.flag_timer = rng.randf_range(2.0, 7.0)
			h.flag_green = rng.randf() < 0.5
		_:
			return false
	hazards.append(h)
	return true


## A closure may not cut the start or finish off from the road network.
func _can_close(e: int) -> bool:
	var router := session.router
	router.block_edge(e)
	var ok := router.connected(map.edge_a[e], session.finish_node) and router.connected(map.edge_b[e], session.finish_node) and router.connected(session.start_node, session.finish_node)
	router.unblock_edge(e)
	return ok


func _place_floods(count: int) -> void:
	if count <= 0:
		return
	var pts := session.route_pts
	var candidates: Array = []
	for site: Dictionary in map.flood_sites:
		var p := Vector2(site["x"], site["y"])
		var best := INF
		var i := 0
		while i < pts.size():
			best = minf(best, p.distance_squared_to(pts[i]))
			i += 2
		if best < 420.0 * 420.0:
			candidates.append({"pos": p, "water": site["water"], "d": best})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	var used := 0
	for c: Dictionary in candidates:
		if used >= count:
			break
		_add_flood(c["pos"], c["water"])
		used += 1
	# Low spots on the route itself, placed from the fixed seed so they stay put.
	var fixed := RandomNumberGenerator.new()
	fixed.seed = WORLD_SEED
	var low_spots := maxi(count / 3, 2)
	for i in low_spots:
		var idx := int(float(i + 1) / float(low_spots + 1) * pts.size())
		_add_flood(pts[clampi(idx, 0, pts.size() - 1)], "")
	fixed = null


func _add_flood(p: Vector2, water: String) -> void:
	if p.distance_to(session.route_pts[0]) < 200.0:
		return
	var f := Flood.new()
	f.pos = p
	f.water = water
	var key := int(round(p.x / 10.0)) * 73856093 ^ int(round(p.y / 10.0)) * 19349663 ^ WORLD_SEED
	var h := absi(key)
	f.ditch = h % 100 < 38
	f.radius = 30.0 + float(h % 18)
	if map.road_at(p, _hit):
		var left := Vector2(_hit.tangent.y, -_hit.tangent.x)
		f.ditch_pos = _hit.closest + left * map.half_width(_hit.edge) * (float(h % 80) / 100.0 - 0.4)
		f.ditch_r = map.half_width(_hit.edge) * 0.72
	floods.append(f)


func _schedule_weather() -> void:
	if rng.randf() >= float(level["rain_chance"]):
		return
	rain_start = float(level.get("rain_start", rng.randf_range(60.0, 240.0)))
	rain_end = rain_start + rng.randf_range(150.0, 260.0)


func _schedule_convoys() -> void:
	var chance: float = level["convoys"]
	if rng.randf() < chance:
		_add_convoy("presidential", rng.randf_range(70.0, 200.0))
	if chance >= 1.0 and rng.randf() < 0.5:
		_add_convoy("presidential", rng.randf_range(260.0, 420.0))
	if rng.randf() < float(level.get("vip_convoys", 0.0)):
		_add_convoy("vip", rng.randf_range(40.0, 300.0))


func _add_convoy(style: String, at: float) -> void:
	var c := Convoy.new()
	c.style = style
	c.cfg = VehicleCatalog.motorcade(style)
	c.vehicles = c.cfg["vehicles"]
	c.start_at = at
	convoys.append(c)


# -------------------------------------------------------------- step ------
func step(dt: float) -> void:
	_step_weather(dt)
	var car := session.car
	for h in hazards:
		h.cooldown = maxf(h.cooldown - dt, 0.0)
		if h.type == "flagger":
			h.flag_timer -= dt
			if h.flag_timer <= 0.0:
				# "waving flags in a random fashion, as if they are lost themselves"
				h.flag_green = rng.randf() < 0.55
				h.flag_timer = rng.randf_range(1.5, 8.0)
		if h.pos.distance_squared_to(car.pos) > 200.0 * 200.0:
			continue
		_check_hazard(h)
	_reveal_acc -= dt
	if _reveal_acc <= 0.0:
		_reveal_acc = 0.25
		_update_zones()
		for h in hazards:
			if h.type == "closure" and not h.revealed and h.pos.distance_squared_to(car.pos) < SIGHT * SIGHT:
				h.revealed = true
				session.on_closure_found(h)
	for f in floods:
		f.cooldown = maxf(f.cooldown - dt, 0.0)
		_check_flood(f)
	for c in convoys:
		_step_convoy(c, dt)


func _step_weather(dt: float) -> void:
	var t := session.time
	var raining := rain_start >= 0.0 and t >= rain_start and t < rain_end
	var was_dry := rain < 0.05
	rain = move_toward(rain, 1.0 if raining else 0.0, dt / 12.0)
	if raining and was_dry and rain > 0.0 and t - rain_start < 0.2:
		session.announce("The sky has opened. Low roads will flood.", "warn")
	flood_level = move_toward(flood_level, 1.0 if raining else 0.0, dt / (40.0 if raining else 70.0))


func top_speed_factor() -> float:
	var f := 1.0
	var p := session.car.pos
	for h in hazards:
		if h.type == "marram" and absf(h.local(p).x) < h.hl and absf(h.local(p).y) < h.hw:
			f = minf(f, 0.42)
	if flood_level > 0.2:
		for fl in floods:
			if fl.pos.distance_squared_to(p) < fl.radius * fl.radius:
				f = minf(f, lerpf(1.0, 0.32, flood_level))
	return f


func is_flooded(fl: Flood) -> bool:
	return flood_level > 0.2 and fl != null


func _check_hazard(h: Hazard) -> void:
	var car := session.car
	var rules: Dictionary = session.incident_cfg
	var loc := h.local(car.pos)
	var r: float = session.car_radius
	var inside := absf(loc.x) < h.hl + r and absf(loc.y) < h.hw + r
	var speed := absf(car.speed)
	match h.type:
		"rebar":
			if inside and h.cooldown <= 0.0:
				h.cooldown = 6.0
				car.speed *= 0.7
				session.incident("rebar_scratch", 0.0)
		"open_drain":
			if absf(loc.x) < h.hl and absf(loc.y) < h.hw + 0.6 and h.cooldown <= 0.0:
				h.cooldown = 8.0
				session.incident("open_drain", rules["freeze_drain"])
				car.pos += Vector2(h.tangent.y, -h.tangent.x) * -signf(h.local(h.pos).y + (loc.y if absf(loc.y) > 0.1 else 1.0)) * (h.hw + r + 2.0) * 0.0
				_nudge_to_centre()
		"trench":
			if inside and h.cooldown <= 0.0 and speed > float(rules["trench_safe_speed"]):
				h.cooldown = 6.0
				session.incident("trench", rules["freeze_trench"])
				_push_along(h, loc, h.hl + r + 3.0)
		"flagger":
			if inside and h.cooldown <= 0.0 and not h.flag_green and speed > 10.0:
				h.cooldown = 10.0
				session.incident("flag_ignored", 0.0)
		"closure", "partial":
			if inside:
				_solid(h, loc, r)


func _solid(h: Hazard, loc: Vector2, r: float) -> void:
	var car := session.car
	var over_x := h.hl + r - absf(loc.x)
	var over_y := h.hw + r - absf(loc.y)
	var left := Vector2(h.tangent.y, -h.tangent.x)
	if over_x < over_y:
		car.pos += h.tangent * signf(loc.x if loc.x != 0.0 else 1.0) * over_x
	else:
		car.pos += left * signf(loc.y if loc.y != 0.0 else 1.0) * over_y
	var rules: Dictionary = session.incident_cfg
	if absf(car.speed) > float(rules["obstruction_speed"]) and h.cooldown <= 0.0:
		h.cooldown = 3.0
		session.incident("obstruction", 0.0)
	car.speed *= 0.3
	car.vel *= 0.3


func _push_along(h: Hazard, loc: Vector2, amount: float) -> void:
	session.car.pos = h.pos + h.tangent * signf(loc.x if loc.x != 0.0 else 1.0) * amount + Vector2(h.tangent.y, -h.tangent.x) * loc.y
	session.car.speed = 0.0
	session.car.vel = Vector2.ZERO


func _nudge_to_centre() -> void:
	var car := session.car
	if map.road_at(car.pos, _hit):
		car.pos = car.pos.lerp(_hit.closest, 0.55)
	car.speed = 0.0
	car.vel = Vector2.ZERO


func _check_flood(f: Flood) -> void:
	if flood_level < 0.2 or f.ditch_r <= 0.0:
		return
	var car := session.car
	if f.pos.distance_squared_to(car.pos) > f.radius * f.radius:
		return
	if not f.discovered and f.cooldown <= 0.0:
		f.cooldown = 25.0
		session.announce("Water ahead. No way to tell how deep.", "warn")
	if f.ditch and flood_level > 0.4 and f.ditch_pos.distance_to(car.pos) < f.ditch_r and absf(car.speed) > 1.0:
		f.discovered = true
		session.incident("flooded_ditch", session.incident_cfg["freeze_ditch"])
		# Recovered to the far side, wet and much poorer.
		var out := car.pos + car.forward() * (f.radius + 14.0)
		if map.road_at(out, _hit) and _hit.clearance > 0.0:
			car.pos = _hit.closest
		else:
			car.pos = car.pos - car.forward() * (f.radius + 14.0)
		car.speed = 0.0
		car.vel = Vector2.ZERO


func _update_zones() -> void:
	var zones: Array = []
	var car_pos := session.car.pos if session.car else Vector2.ZERO
	for h in hazards:
		if h.pos.distance_squared_to(car_pos) > 700.0 * 700.0:
			continue
		match h.type:
			"trench":
				zones.append({"pos": h.pos, "r": h.hw + 14.0, "cap": 9.0})
			"partial":
				zones.append({"pos": h.pos, "r": h.hl + 12.0, "cap": 12.0})
			"flagger":
				if not h.flag_green:
					zones.append({"pos": h.pos - h.tangent * 0.0, "r": h.hw + 10.0, "cap": 0.0})
			"marram":
				zones.append({"pos": h.pos, "r": 18.0, "cap": 16.0})
	if flood_level > 0.4:
		for f in floods:
			if f.pos.distance_squared_to(car_pos) < 700.0 * 700.0:
				zones.append({"pos": f.pos, "r": f.radius + 8.0, "cap": 0.0, "turn_back": true})
	session.traffic.zones = zones


# ------------------------------------------------------------ convoy ------
func convoy_active() -> Convoy:
	for c in convoys:
		if c.phase == 1 or c.phase == 2:
			return c
	return null


func in_corridor(c: Convoy, p: Vector2) -> bool:
	var i := 0
	while i < c.path.size():
		if c.path[i].distance_squared_to(p) < CONVOY_CORRIDOR * CONVOY_CORRIDOR:
			return true
		i += 1
	return false


func _is_halted(p: Vector2) -> bool:
	var c := convoy_active()
	return c != null and in_corridor(c, p)


func _step_convoy(c: Convoy, dt: float) -> void:
	c.penalty_cd = maxf(c.penalty_cd - dt, 0.0)
	match c.phase:
		0:
			if session.time >= c.start_at:
				_begin_convoy(c)
		1:
			c.timer -= dt
			if c.timer <= 0.0:
				c.phase = 2
				session.announce("Here it comes. Do not move.", "warn")
		2:
			c.head += float(c.cfg["speed"]) * dt
			var car := session.car
			if in_corridor(c, car.pos) and absf(car.speed) > 7.0 and c.penalty_cd <= 0.0:
				c.penalty_cd = 12.0
				session.incident("convoy_violation", session.incident_cfg["freeze_convoy"])
			for i in c.vehicles.size():
				var along := c.head - CONVOY_GAP * i
				if along > 0.0 and along < c.length:
					var v: Vector2 = c.pos_at(along)[0]
					if v.distance_to(car.pos) < 8.0 and c.penalty_cd <= 0.0:
						c.penalty_cd = 12.0
						session.incident("convoy_violation", session.incident_cfg["freeze_convoy"])
			if c.head - c.tail_gap() > c.length:
				c.phase = 3
				session.traffic.halt_query = Callable()
				session.announce("Convoy gone. Everyone moves at once.", "good")


## The convoy comes down your road, toward you, from well ahead.
func _begin_convoy(c: Convoy) -> void:
	# A second motorcade waits its turn behind one already passing.
	if convoy_active() != null:
		c.start_at = session.time + 20.0
		return
	var pts := session.route_ahead_polyline(c.cfg["ahead"], c.cfg["behind"])
	if pts.size() < 3:
		c.phase = 3
		return
	c.path = pts
	c.cum.resize(pts.size())
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		c.cum[i] = acc
	c.length = acc
	c.phase = 1
	c.timer = c.cfg["warning"]
	session.traffic.halt_query = _is_halted
	session.announce(c.cfg["announce"], "danger")
	session.convoy_started.emit()
