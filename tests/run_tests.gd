extends SceneTree
## Headless test runner: godot --headless --path . -s res://tests/run_tests.gd
## Exit code 0 passes, 1 fails. Add `-- --soak` to drive every level to the end.

var _failed := 0
var _passed := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	test_map_is_real_and_connected()
	test_every_road_is_drivable()
	test_clear_road_reaches_the_finish()
	test_landmarks_on_route()
	test_left_hand_traffic()
	test_penalty_ladder()
	test_road_containment()
	test_closure_is_hidden_until_seen()
	test_ditches_stay_put()
	test_every_level_builds()
	test_campaign_advances_by_itself()
	test_kampala_fleet()
	if args.has("--soak"):
		for lv: Dictionary in Rules.data()["levels"]:
			if not args.has("--only") or args.has(lv["id"]):
				soak(lv["id"], args)
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)


func test_map_is_real_and_connected() -> void:
	var map := MapData.shared()
	check(map.edge_a.size() > 20000, "map has the real road network")
	check(map.bld_start.size() > 100000, "map has real buildings")
	check(not map.edges_named("Ggaba Road").is_empty(), "Ggaba Road exists")
	check(not map.edges_named("Jinja Road").is_empty(), "Jinja Road exists")
	for road in ["St. Barnabas Road", "Kalungi Road", "Tank Hill Road", "Bukasa Road"]:
		check(not map.edges_named(road).is_empty(), "article road exists: " + road)
	var r := RouteFinder.new(map)
	var a := map.nearest_node(Vector2.ZERO)
	var far := map.nearest_node(Vector2(meta_finish().x, meta_finish().y))
	check(r.connected(a, far), "start connects to finish")


## The lookup grid must find a road everywhere a road exists, kerbs included.
func test_every_road_is_drivable() -> void:
	var map := MapData.shared()
	var hit := MapData.RoadHit.new()
	var misses := 0
	var first := ""
	for si in map.seg_edge.size():
		var a := Vector2(map.seg_xy[si * 4], map.seg_xy[si * 4 + 1])
		var b := Vector2(map.seg_xy[si * 4 + 2], map.seg_xy[si * 4 + 3])
		var hw := map.half_width(map.seg_edge[si])
		var side := (b - a).orthogonal().normalized() * hw
		for t: float in [0.13, 0.37, 0.5, 0.71, 0.94]:
			var p := a.lerp(b, t)
			for q: Vector2 in [p, p + side * 0.98, p - side * 0.98]:
				if not map.road_at(q, hit) or hit.clearance < -0.5:
					misses += 1
					if first == "":
						first = "%s on %s" % [q, map.road_name(map.seg_edge[si])]
	check(misses == 0, "road lookup finds every road: %d misses, first at %s" % [misses, first])


## With nothing in the way, a driver following the line must arrive, on every route.
func test_clear_road_reaches_the_finish() -> void:
	for level_id in ["sunday", "boxed_in"]:
		var s := RaceSession.new(Rules.level(level_id), 1)
		s.traffic.agents.clear()
		s.traffic.target_count = 0
		s.director.hazards.clear()
		s.director.floods.clear()
		s.director.convoys.clear()
		var bot := Autodriver.new(s)
		var dt := 1.0 / 30.0
		while s.status == RaceSession.Status.RUNNING:
			s.step(dt, bot.decide(dt))
		print("  clear run %s: %.0fs, %d penalties" % [level_id, s.time, s.ledger.total])
		check(s.status == RaceSession.Status.FINISHED, "clear road reaches the finish on " + level_id)


func meta_finish() -> Vector2:
	var f: Dictionary = MapData.shared().meta["finish"]
	return Vector2(f["x"], f["y"])


func test_landmarks_on_route() -> void:
	var map := MapData.shared()
	for lm_name in ["Speke Resort, Munyonyo", "Uganda Martyrs' Shrine, Namugongo", "Kibuli Mosque", "IHK", "Namboole Stadium", "Ggaba Market"]:
		check(not map.landmark_named(lm_name).is_empty(), "hero landmark present: " + lm_name)
	var s := RaceSession.new(Rules.level("sunday"), 1)
	var near := 0
	for lm: Dictionary in map.landmarks:
		var p := Vector2(lm["x"], lm["y"])
		for i in range(0, s.route_pts.size(), 3):
			if p.distance_squared_to(s.route_pts[i]) < 150.0 * 150.0:
				near += 1
				break
	check(near > 100, "route passes many named places (%d)" % near)


func test_left_hand_traffic() -> void:
	var s := RaceSession.new(Rules.level("tuesday"), 2)
	for i in 120:
		s.step(1.0 / 30.0, DriveInput.new())
	var checked := 0
	var left := 0
	var map := s.map
	for a in s.traffic.agents:
		if a.kind == TrafficSim.Kind.BODA or map.is_oneway(a.edge) or a.speed < 3.0:
			continue
		var sampled: Array = s.traffic._sample(a)
		var tan: Vector2 = sampled[1]
		var offset: Vector2 = a.pos - (sampled[0] as Vector2)
		# Screen coords: left of travel is (tan.y, -tan.x).
		checked += 1
		if offset.dot(Vector2(tan.y, -tan.x)) > 0.0:
			left += 1
	check(checked > 5, "enough cars to judge driving side (%d)" % checked)
	check(float(left) / maxf(checked, 1) > 0.9, "traffic keeps left (%d of %d)" % [left, checked])


func test_penalty_ladder() -> void:
	var defs: Dictionary = Rules.data()["penalties"]
	var top := 0
	var top_type := ""
	for type: String in defs:
		if int(defs[type]["points"]) > top:
			top = int(defs[type]["points"])
			top_type = type
	check(top_type == "run_over_boda", "running over a boda is the highest penalty")
	var s := RaceSession.new(Rules.level("sunday"), 3)
	var before := s.ledger.total
	s.incident("boda_scratch", 0.0)
	check(s.ledger.total == before + 5, "ledger adds points")
	var a := TrafficSim.Agent.new()
	a.kind = TrafficSim.Kind.BODA
	s.car.speed = 60.0
	s.car.vel = Vector2(60, 0)
	s._resolve_contact(a, Vector2.RIGHT)
	check(s.ledger.counts.has("run_over_boda"), "fast boda hit is a run-over")
	check(a.downed > 0.0, "boda goes down")
	var b := TrafficSim.Agent.new()
	b.kind = TrafficSim.Kind.BODA
	s.car.speed = 5.0
	s.car.vel = Vector2(5, 0)
	s._resolve_contact(b, Vector2.RIGHT)
	check(s.ledger.counts.has("boda_scratch"), "slow boda contact is a scratch")


func test_road_containment() -> void:
	var s := RaceSession.new(Rules.level("sunday"), 4)
	s.traffic.agents.clear()
	s.traffic.target_count = 0
	var input := DriveInput.new()
	input.throttle = 1.0
	input.steer = 0.4
	var hit := MapData.RoadHit.new()
	var worst := INF
	for i in 1800:
		s.step(1.0 / 60.0, input)
		s.map.road_at(s.car.pos, hit)
		worst = minf(worst, hit.clearance)
	check(worst > -4.0, "car stays within the road edge (worst %.1f)" % worst)


func test_closure_is_hidden_until_seen() -> void:
	var s := RaceSession.new(Rules.level("school"), 5)
	var closures := 0
	var on_route_hidden := 0
	for h in s.director.hazards:
		if h.type == "closure":
			closures += 1
			check(s.traffic.blocked.has(h.edge), "traffic knows about closure")
			if s.route_uses(h.edge):
				on_route_hidden += 1
				s.on_closure_found(h)
				check(not s.route_uses(h.edge), "Maps reroutes once the closure is seen")
				check(s.route_pts.size() > 2, "a way round exists")
				break
	check(closures > 0, "closures were placed")
	print("  closures %d, one on the route: %s" % [closures, on_route_hidden > 0])


func test_ditches_stay_put() -> void:
	var a := RaceSession.new(Rules.level("rainy"), 10)
	var b := RaceSession.new(Rules.level("rainy"), 99)
	var ditches_a := {}
	for f in a.director.floods:
		ditches_a[f.pos] = f.ditch
	var same := 0
	for f in b.director.floods:
		if ditches_a.has(f.pos):
			check(ditches_a[f.pos] == f.ditch, "ditch at same place across runs")
			same += 1
	check(same > 5, "flood sites repeat across runs (%d)" % same)
	var total_ditch := 0
	for f in a.director.floods:
		if f.ditch:
			total_ditch += 1
	check(total_ditch > 0 and total_ditch < a.director.floods.size(), "some floods hide ditches, some do not (%d/%d)" % [total_ditch, a.director.floods.size()])


func test_every_level_builds() -> void:
	for lv: Dictionary in Rules.data()["levels"]:
		var s := RaceSession.new(lv, 7)
		check(s.route_pts.size() > 5, "route exists for " + str(lv["id"]))
		check(s.traffic.agents.size() > 0, "traffic spawned for " + str(lv["id"]))
		var types := {}
		for h in s.director.hazards:
			types[h.type] = true
		print("  %-9s route %.1f km, %d hazards %s, %d floods, %d agents" % [lv["id"], s.route_length() / 1000.0, s.director.hazards.size(), types.keys(), s.director.floods.size(), s.traffic.agents.size()])


func test_kampala_fleet() -> void:
	var sprites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicle_sprites.json"))["rects"]
	var categories := {}
	for model: Dictionary in VehicleCatalog.data()["models"]:
		check(sprites.has(model["sprite"]), "sprite baked for " + str(model["sprite"]))
		categories[model["category"]] = true
	for wanted in ["taxi", "boda", "old_toyota", "suv", "lorry", "bicycle", "police", "army"]:
		check(categories.has(wanted), "the fleet includes " + wanted)
	for style in ["presidential", "vip"]:
		for v: String in VehicleCatalog.motorcade(style)["vehicles"]:
			check(sprites.has(v), "motorcade sprite baked: " + v)
	var s := RaceSession.new(Rules.level("tuesday"), 11)
	var c := TrafficSim.Agent.new()
	c.kind = TrafficSim.Kind.BICYCLE
	s.car.speed = 50.0
	s._resolve_contact(c, Vector2.RIGHT)
	check(s.ledger.counts.has("hit_cyclist"), "hitting a bicycle has its own penalty")
	var soldier := TrafficSim.Agent.new()
	soldier.security = true
	s.freeze = 0.0
	s._resolve_contact(soldier, Vector2.RIGHT)
	check(s.ledger.counts.has("hit_security"), "hitting the army has its own penalty")


func test_campaign_advances_by_itself() -> void:
	var path := "user://test_save.json"
	var c := Campaign.new()
	c.save_path = path
	check(c.current_level_id() == "sunday", "first day is Sunday morning")
	var previous := -1
	for i in c.order().size():
		var lv := c.current_level()
		if lv["id"] != "boxed_in":
			check(int(lv["traffic"]) > previous, "traffic grows day on day: " + str(lv["id"]))
			previous = int(lv["traffic"])
		c.stage = i
		c.record({"finished": false, "level_id": lv["id"], "score": 500.0})
		check(c.stage == i, "failing repeats the day")
		c.record({"finished": true, "level_id": lv["id"], "score": 500.0})
	check(c.term() == 1, "school year rolls over after the last day")
	var term_one := int(c.current_level()["traffic"])
	check(term_one > int(Rules.level("school")["traffic"]), "new term is busier than Back to School")
	c.save()
	var back := Campaign.load_saved(path)
	check(back.stage == c.stage, "progress survives a restart")
	DirAccess.remove_absolute(path)


func soak(level_id: String, _args: PackedStringArray) -> void:
	var s := RaceSession.new(Rules.level(level_id), 42)
	var result := {}
	s.ended.connect(func(r: Dictionary) -> void: result.merge(r))
	s.enforce_licence = false
	var bot := Autodriver.new(s)
	var args_has_trace := _args.has("--trace")
	var t0 := Time.get_ticks_msec()
	var dt := 1.0 / 30.0
	var steps := 0
	while s.status == RaceSession.Status.RUNNING and steps < 30 * 2300:
		s.step(dt, bot.decide(dt))
		steps += 1
		if args_has_trace and steps % 1500 == 0:
			var slow := 0
			for a in s.traffic.nearby(s.car.pos, 80.0):
				if a.speed < 2.0:
					slow += 1
			var hit := MapData.RoadHit.new()
			var jam := s.map.road_at(s.car.pos, hit) and s.traffic.is_jammed(hit.edge)
			print("    t=%.0f left=%.1fkm speed=%.0f agents=%d near=%d stopped=%d jam=%s frz=%.0f off=%.0f pen=%d road=%s" % [s.time, s.distance_left() / 1000.0, s.car.speed, s.traffic.agents.size(), s.traffic.nearby(s.car.pos, 80.0).size(), slow, jam, s.freeze, s.route_off, s.ledger.total, s.current_road])
	var ms := Time.get_ticks_msec() - t0
	print("  soak %-9s %s time %.0fs left %.1f km penalties %d landmarks %d; %s; %.1f ms/step, closures found %d" % [level_id, "FINISHED" if result.get("finished", false) else "NOT FINISHED", s.time, s.distance_left() / 1000.0, s.ledger.total, s.passed.size(), str(s.ledger.counts), float(ms) / maxf(steps, 1), s.known_closures.size()])
	check(result.get("finished", false), "bot finishes " + level_id)
