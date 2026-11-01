class_name RaceSession
extends RefCounted
## One run, start to finish, with no rendering. The game draws it; the tests
## drive it headless.

signal penalty_incurred(info: Dictionary)
signal announced(text: String, kind: String)
signal landmark_passed(display_name: String)
signal convoy_started
signal honked
signal ended(result: Dictionary)

enum Status { RUNNING, FINISHED, FAILED }

var map: MapData
var router: RouteFinder
var rng := RandomNumberGenerator.new()
var level: Dictionary
var rules: Dictionary
var incident_cfg: Dictionary
var car: CarModel
var car_radius := 2.9
var car_half_len := 5.6
var ledger: PenaltyLedger
var traffic: TrafficSim
var director: HazardDirector
var status := Status.RUNNING
var time := 0.0
var freeze := 0.0
var freeze_reason := ""
var start_node := 0
var finish_node := 0
var finish_pos := Vector2.ZERO
var start_name := ""
var finish_name := ""
var route_nodes := PackedInt64Array()
var route_pts := PackedVector2Array()
var route_cum := PackedFloat32Array()
var route_idx := 0
var route_s := 0.0  ## Distance along the route of the car's projection.
var route_off := 0.0  ## How far the car is from the route line.
var current_road := ""
var current_place := ""
var surface_unpaved := false
var off_route_time := 0.0
var passed: Array[String] = []
var known_closures: Array[Vector2] = []
var horn_cd := 0.0
var enforce_licence := true  ## The soak test bot only proves a route can be driven.

var _hit := MapData.RoadHit.new()
var _last_ok := Vector2.ZERO
var _slow_acc := 0.0
var _no_input := DriveInput.new()
var _tier1: Array = []
var _start_dist := 1.0


func _init(level_data: Dictionary, seed_value: int) -> void:
	map = MapData.shared()
	rules = Rules.data()
	level = level_data
	incident_cfg = rules["incident"]
	rng.seed = seed_value
	router = RouteFinder.new(map)
	var route_spec: Dictionary = rules[level["route"]]
	var start_lm := map.landmark_named(route_spec["start"])
	var finish_lm := map.landmark_named(route_spec["finish"])
	assert(not start_lm.is_empty() and not finish_lm.is_empty(), "route landmarks missing")
	start_name = start_lm["name"]
	finish_name = finish_lm["name"]
	start_node = map.nearest_node(Vector2(start_lm["x"], start_lm["y"]))
	finish_node = map.nearest_node(Vector2(finish_lm["x"], finish_lm["y"]))
	finish_pos = map.node_pos(finish_node)
	_set_route(router.node_path(start_node, finish_node))
	assert(route_pts.size() > 2, "no route between start and finish")
	var cfg: Dictionary = rules["car"]
	car = CarModel.new(cfg)
	car.pos = route_pts[0]
	car.heading = (route_pts[1] - route_pts[0]).angle()
	car_radius = cfg["radius"]
	car_half_len = cfg["half_length"]
	_last_ok = car.pos
	_start_dist = maxf(route_length(), 1.0)
	ledger = PenaltyLedger.new(rules["penalties"], rng)
	traffic = TrafficSim.new(map, level, rng)
	traffic.route_sampler = route_ahead_point
	traffic.player_pos = car.pos
	director = HazardDirector.new(self, level, rng)
	director.build()
	traffic.populate()
	for lm: Dictionary in map.landmarks:
		if int(lm["tier"]) == 1:
			_tier1.append(lm)


func step(dt: float, input: DriveInput) -> void:
	if status != Status.RUNNING:
		return
	time += dt
	horn_cd = maxf(horn_cd - dt, 0.0)
	var active := input
	if freeze > 0.0:
		freeze -= dt
		active = _no_input
		car.speed = 0.0
		car.vel = Vector2.ZERO
	if active.horn and horn_cd <= 0.0:
		horn_cd = 0.5
		traffic.honk(car.pos, car.forward())
		honked.emit()
	var grip: float = lerpf(float(rules["car"]["grip_dry"]), float(rules["car"]["grip_wet"]), director.rain)
	var top := director.top_speed_factor()
	if surface_unpaved:
		top *= float(rules["car"]["unpaved_top_speed"])
	car.step(dt, active, grip, top)
	_contain_on_road()
	traffic.player_pos = car.pos
	traffic.player_vel = car.vel
	traffic.player_heading = car.heading
	traffic.step(dt)
	_collide_traffic()
	director.step(dt)
	_slow_updates(dt)
	_update_route_progress()
	_check_end()


func route_length() -> float:
	return route_cum[route_cum.size() - 1] if not route_cum.is_empty() else 0.0


func distance_left() -> float:
	return maxf(route_length() - route_s, 0.0) + route_off


func route_ahead_point(distance: float) -> Vector2:
	var want := route_s + distance
	var i := clampi(route_cum.bsearch(want), 1, route_pts.size() - 1)
	var seg := route_cum[i] - route_cum[i - 1]
	var t := 0.0 if seg < 0.001 else clampf((want - route_cum[i - 1]) / seg, 0.0, 1.0)
	return route_pts[i - 1].lerp(route_pts[i], t)


## Polyline from `ahead` metres in front of the car back to `behind` metres past
## it, densified so corridor checks by point spacing stay accurate.
func route_ahead_polyline(ahead: float, behind: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d := ahead
	while d >= -behind:
		var want := route_s + d
		if want >= 0.0 and want <= route_length():
			out.append(route_ahead_point(d))
		d -= 50.0
	return out


func incident(type: String, freeze_seconds: float) -> void:
	var info := ledger.record(type)
	if freeze_seconds > 0.0:
		freeze = maxf(freeze, freeze_seconds)
		freeze_reason = info["line"]
		car.speed = 0.0
		car.vel = Vector2.ZERO
	penalty_incurred.emit(info)
	if enforce_licence and ledger.total >= int(rules["licence_limit"]):
		_end(Status.FAILED, "Your licence has been withdrawn.")


func announce(text: String, kind: String) -> void:
	announced.emit(text, kind)


func on_closure_found(h: HazardDirector.Hazard) -> void:
	known_closures.append(h.pos)
	router.block_edge(h.edge)
	var name := map.road_name(h.edge)
	announce("ROAD CLOSED%s. No diversion signs, obviously." % ((" on " + name) if name != "" else ""), "warn")
	if route_uses(h.edge):
		_replan()


func route_uses(edge: int) -> bool:
	return router.edges_of(route_nodes).has(edge)


## `from_pos` starts the line at the car, so a fresh route is never already "left".
func _set_route(nodes: PackedInt64Array, from_pos: Variant = null) -> void:
	route_nodes = nodes
	route_pts = router.polyline(nodes)
	if from_pos != null:
		route_pts.insert(0, from_pos)
	route_cum.resize(route_pts.size())
	var acc := 0.0
	for i in route_pts.size():
		if i > 0:
			acc += route_pts[i].distance_to(route_pts[i - 1])
		route_cum[i] = acc
	route_idx = 0
	route_s = 0.0


func _replan() -> void:
	var from_node := _nearest_end_node()
	var nodes := router.node_path(from_node, finish_node)
	if nodes.size() < 2:
		return
	_set_route(nodes, car.pos)


func _nearest_end_node() -> int:
	if not map.road_at(car.pos, _hit):
		return map.nearest_node(car.pos)
	var a := map.edge_a[_hit.edge]
	var b := map.edge_b[_hit.edge]
	var fwd := car.forward()
	var score_a := map.node_pos(a).distance_to(car.pos) - (map.node_pos(a) - car.pos).dot(fwd) * 0.6
	var score_b := map.node_pos(b).distance_to(car.pos) - (map.node_pos(b) - car.pos).dot(fwd) * 0.6
	return a if score_a < score_b else b


func _contain_on_road() -> void:
	if not map.road_at(car.pos, _hit):
		car.pos = _last_ok
		car.speed *= 0.3
		car.vel = Vector2.ZERO
		return
	current_road = map.road_name(_hit.edge)
	surface_unpaved = map.is_unpaved(_hit.edge)
	var limit := -1.5
	if _hit.clearance >= limit:
		_last_ok = car.pos
		return
	# Past the verge there is always something: wall, kiosk, ditch, somebody's fence.
	car.pos = _hit.closest + _hit.normal * (map.half_width(_hit.edge) + 1.4)
	var into := car.vel.dot(_hit.normal)
	if into > float(incident_cfg["obstruction_speed"]):
		incident("obstruction", 0.0)
		car.speed *= 0.25
	else:
		car.speed *= 0.86
	car.vel -= _hit.normal * maxf(into, 0.0)
	_last_ok = car.pos


func _collide_traffic() -> void:
	var fwd := car.forward()
	var a0 := car.pos - fwd * (car_half_len - car_radius)
	var a1 := car.pos + fwd * (car_half_len - car_radius)
	for a in traffic.nearby(car.pos, 22.0):
		if a.downed > 0.0:
			continue
		var af := Vector2.from_angle(a.heading)
		var span := maxf(a.hl - a.radius, 0.0)
		var d := _seg_seg_distance(a0, a1, a.pos - af * span, a.pos + af * span)
		var touching := car_radius + a.radius
		if d > touching:
			continue
		# One incident per contact: staying in touch does not charge again, and
		# nobody is charged for being hit while stopped, except by a passing boda.
		var two_wheels := a.kind == TrafficSim.Kind.BODA or a.kind == TrafficSim.Kind.BICYCLE
		if a.hit_cd <= 0.0 and freeze <= 0.0 and (two_wheels or absf(car.speed) > 6.0):
			_resolve_contact(a, af)
		a.hit_cd = maxf(a.hit_cd, 1.5)
		_separate(a, touching - d)


## Vehicles shove apart rather than pass through each other. The agent gives way
## when it can, since the player's car must stay inside the road.
func _separate(a: TrafficSim.Agent, overlap: float) -> void:
	var away := car.pos - a.pos
	away = away.normalized() if away.length_squared() > 0.01 else car.forward()
	car.pos += away * minf(overlap * 0.5 + 0.1, 1.2)
	a.pos -= away * minf(overlap * 0.5 + 0.1, 1.2)
	a.speed *= 0.8
	var into := car.vel.dot(-away)
	if into > 0.0:
		car.vel += away * into
		car.speed *= 0.93


func _resolve_contact(a: TrafficSim.Agent, af: Vector2) -> void:
	var player_speed := absf(car.speed)
	var rel := (car.vel - af * a.speed).length()
	var cfg := incident_cfg
	if a.kind == TrafficSim.Kind.BICYCLE:
		if player_speed >= float(cfg["altercation_speed"]):
			a.downed = 22.0
			a.speed = 0.0
			incident("hit_cyclist", cfg["freeze_cyclist"])
		else:
			incident("boda_scratch", 0.0)
		return
	if a.kind == TrafficSim.Kind.BODA:
		if player_speed >= float(cfg["run_over_speed"]):
			a.downed = 22.0
			a.speed = 0.0
			incident("run_over_boda", cfg["freeze_run_over"])
		elif player_speed >= float(cfg["altercation_speed"]):
			a.arguing = float(cfg["freeze_altercation"]) + 1.0
			a.speed = 0.0
			incident("altercation", cfg["freeze_altercation"])
		else:
			incident("boda_scratch", 0.0)
		return
	if a.security:
		a.arguing = float(cfg["freeze_security"]) + 1.0
		a.speed = 0.0
		incident("hit_security", cfg["freeze_security"])
		return
	if rel >= float(cfg["collision_rel_speed"]):
		a.arguing = float(cfg["freeze_collision"]) + 1.0
		a.speed *= 0.2
		incident("minor_collision", cfg["freeze_collision"])
	else:
		incident("vehicle_contact", 0.0)
		car.speed *= 0.72


func _slow_updates(dt: float) -> void:
	_slow_acc -= dt
	if _slow_acc > 0.0:
		return
	_slow_acc = 0.5
	for lm: Dictionary in _tier1:
		var name: String = lm["name"]
		if passed.has(name):
			continue
		var p := Vector2(lm["x"], lm["y"])
		if p.distance_squared_to(car.pos) < 170.0 * 170.0:
			passed.append(name)
			landmark_passed.emit(name)
	var best_d := INF
	var best := ""
	for pl: Dictionary in map.places:
		if int(pl["rank"]) != 0:
			continue
		var d := Vector2(pl["x"], pl["y"]).distance_squared_to(car.pos)
		if d < best_d:
			best_d = d
			best = pl["name"]
	if best != current_place:
		var first := current_place == ""
		current_place = best
		if not first:
			announce("Entering " + best, "place")
	# Maps recalculates when you leave its line, a beat late, like the real one.
	if route_off > 50.0:
		off_route_time += 0.5
		if off_route_time >= 1.0:
			off_route_time = 0.0
			_replan()
	else:
		off_route_time = 0.0


## Projects the car onto the route, searching forward from where it last was so
## a road that doubles back cannot make progress jump.
func _update_route_progress() -> void:
	var best_d := INF
	var last := mini(route_idx + 40, route_pts.size() - 2)
	var first := maxi(route_idx - 1, 0)
	for i in range(first, last + 1):
		var q := Geometry2D.get_closest_point_to_segment(car.pos, route_pts[i], route_pts[i + 1])
		var d := q.distance_squared_to(car.pos)
		if d < best_d:
			best_d = d
			route_idx = i
			route_s = route_cum[i] + q.distance_to(route_pts[i])
	route_off = sqrt(best_d)


func _check_end() -> void:
	if status != Status.RUNNING:
		return
	if car.pos.distance_to(finish_pos) < 26.0:
		_end(Status.FINISHED, "")
	elif time > float(level["time_cap"]):
		_end(Status.FAILED, "The sun has set. Nobody is getting to " + finish_name + " today.")


func _end(new_status: Status, reason: String) -> void:
	status = new_status
	var score := time + ledger.total
	ended.emit({
		"finished": new_status == Status.FINISHED,
		"reason": reason,
		"level_id": level["id"],
		"level_name": level["name"],
		"time": time,
		"penalties": ledger.total,
		"score": score,
		"rows": ledger.rows(),
		"passed": passed,
		"rating": Rules.rating_for(score, level["par"]) if new_status == Status.FINISHED else "",
	})


static func _seg_seg_distance(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> float:
	var pts := Geometry2D.get_closest_points_between_segments(p1, q1, p2, q2)
	return pts[0].distance_to(pts[1])
