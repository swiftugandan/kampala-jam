class_name TrafficSim
extends RefCounted
## Everyone else on the road. Uganda drives on the left. Agents live on the road
## graph, spawn out of sight around the player and vanish when far behind.

enum Kind { CAR, TAXI, TRUCK, VAN, BODA, BICYCLE }

const BEHAVIOUR := {"car": Kind.CAR, "taxi": Kind.TAXI, "truck": Kind.TRUCK, "van": Kind.VAN, "boda": Kind.BODA, "bicycle": Kind.BICYCLE}
const CLASS_SPEED: Array[float] = [58.0, 48.0, 42.0, 36.0, 30.0, 24.0]
const SPAWN_ACCEPT: Array[float] = [1.0, 1.0, 0.9, 0.8, 0.4, 0.14]
const TURN_WEIGHT: Array[float] = [6.0, 6.0, 4.0, 3.0, 0.9, 0.35]
const THINK_INTERVAL := 0.1
const HASH_CELL := 36.0
const SPAWN_MIN := 350.0
const SPAWN_MAX := 500.0
const DESPAWN := 560.0

class Agent:
	var kind := 0
	var edge := -1
	var dir := 1
	var s := 0.0
	var lane := 0.42
	var target_lane := 0.42
	var speed := 0.0
	var target_speed := 0.0
	var pos := Vector2.ZERO
	var heading := 0.0
	var hl := 5.0
	var radius := 2.6
	var stop_timer := 0.0
	var next_stop := 20.0
	var stuck := 0.0
	var ghost := 0.0
	var hurry := 0.0
	var wobble := 0.0
	var hit_cd := 0.0
	var downed := 0.0  ## Boda tipped over: stays as a wreck until this runs out.
	var arguing := 0.0
	var sprite := "saloon_0"
	var speed_mul := 1.0
	var security := false
	var pulled_over := false
	var hold := 0.0  ## Seconds waiting at something that will not clear soon.
	var patience := 10.0

var map: MapData
var rng: RandomNumberGenerator
var agents: Array[Agent] = []
var target_count := 100
var local_density_cap := 3  ## Most agents allowed within 80 wu of a spawn point.
var jam := 0.1
var speed_factor := 1.0
var blocked: Dictionary = {}  ## Edges closed to traffic, seen by the player or not.
var lane_override: Dictionary = {}  ## Edge -> lane fraction, around partial closures.
var zones: Array = []  ## Slow or stop areas from hazards: {pos, r, cap}.
var halt_query: Callable = Callable()  ## bool(pos): is this spot held for a convoy?
var player_pos := Vector2.ZERO
var player_vel := Vector2.ZERO
var player_heading := 0.0
var route_sampler: Callable = Callable()  ## Vector2(distance_ahead) on the route.
var time := 0.0

var _categories := PackedStringArray()
var _think_acc := 0.0
var _hash: Dictionary = {}
var _hit := MapData.RoadHit.new()


func _init(map_data: MapData, level: Dictionary, random: RandomNumberGenerator) -> void:
	map = map_data
	rng = random
	target_count = int(level["traffic"])
	local_density_cap = clampi(int(float(level["traffic"]) / 45.0), 2, 7)
	jam = level["jam"]
	speed_factor = level["speed"]
	var mix: Dictionary = level["mix"]
	for category: String in mix:
		assert(not VehicleCatalog.models_in(category).is_empty(), "no vehicles in category " + category)
		for i in int(mix[category]):
			_categories.append(category)


## Fills the neighbourhood before the first frame, then keeps it topped up.
func populate() -> void:
	var tries := target_count * 8
	while agents.size() < target_count and tries > 0:
		tries -= 1
		_try_spawn(70.0, SPAWN_MAX)


func step(dt: float) -> void:
	time += dt
	var budget := 6
	while agents.size() < target_count and budget > 0:
		budget -= 1
		_try_spawn(SPAWN_MIN, SPAWN_MAX)
	_think_acc += dt
	if _think_acc >= THINK_INTERVAL:
		_think_acc = 0.0
		_rebuild_hash()
		for a in agents:
			_think(a)
	var i := agents.size() - 1
	while i >= 0:
		var a := agents[i]
		_move(a, dt)
		if a.pos.distance_squared_to(player_pos) > DESPAWN * DESPAWN:
			agents.remove_at(i)
		i -= 1


func is_jammed(edge: int) -> bool:
	if map.edge_class[edge] > 3:
		return false
	var h := (edge * 2654435761 + int(time / 50.0) * 40503) & 0xFFFF
	return float(h) / 65536.0 < jam


func nearby(pos: Vector2, radius: float) -> Array[Agent]:
	var out: Array[Agent] = []
	for a in agents:
		if a.pos.distance_squared_to(pos) < radius * radius:
			out.append(a)
	return out


## Bodas swerve away from a horn and everyone ahead hurries a little.
func honk(pos: Vector2, fwd: Vector2) -> void:
	for a in nearby(pos + fwd * 26.0, 34.0):
		a.hurry = 1.6
		if a.kind == Kind.BODA:
			a.target_lane = clampf(a.target_lane + (0.3 if a.target_lane > 0.0 else -0.3), -0.9, 0.9)


func _try_spawn(rmin: float, rmax: float) -> void:
	var p: Vector2
	var on_route := route_sampler.is_valid() and rng.randf() < 0.55
	if on_route:
		p = route_sampler.call(rng.randf_range(rmin, rmax))
		if p.distance_to(player_pos) < rmin * 0.9:
			return
	else:
		var centre := player_pos + player_vel * 2.0
		p = centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if p.distance_to(player_pos) < rmin:
			return
	if not map.road_at(p, _hit) or _hit.clearance < 0.0:
		return
	var e := _hit.edge
	if blocked.has(e):
		return
	for z: Dictionary in zones:
		if z.get("turn_back", false) and _hit.closest.distance_squared_to(z["pos"]) < 90.0 * 90.0:
			return
	var cls := map.edge_class[e]
	var accept := SPAWN_ACCEPT[cls] * (2.5 if is_jammed(e) else 1.0)
	if not on_route and rng.randf() > accept:
		return
	var path := map.edge_path(e)
	if path.length < 8.0:
		return
	# Traffic is capped by local density, so the route never fills nose to tail
	# unless today's traffic really is that bad.
	var crowd := 0
	var crowd_cap := local_density_cap * (3 if is_jammed(e) else 1)
	for other in agents:
		var d2 := other.pos.distance_squared_to(_hit.closest)
		if d2 < 324.0:
			return
		if d2 < 6400.0:
			crowd += 1
			if crowd >= crowd_cap:
				return
	var a := Agent.new()
	var models: Array = VehicleCatalog.models_in(_categories[rng.randi() % _categories.size()])
	var model: Dictionary = models[rng.randi() % models.size()]
	a.kind = BEHAVIOUR[model["behaviour"]]
	a.sprite = model["sprite"]
	a.hl = model["hl"]
	a.radius = model["radius"]
	a.speed_mul = model["speed"]
	a.security = model.get("security", false)
	a.edge = e
	a.dir = 1 if map.is_oneway(e) or rng.randf() < 0.5 else -1
	# Project onto the path to find s from the start of travel.
	var best_s := 0.0
	var best_d := INF
	for k in path.pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(_hit.closest, path.pts[k], path.pts[k + 1])
		var d := q.distance_squared_to(_hit.closest)
		if d < best_d:
			best_d = d
			best_s = path.cum[k] + q.distance_to(path.pts[k])
	a.s = best_s if a.dir > 0 else path.length - best_s
	_setup_lane(a)
	a.lane = a.target_lane
	a.wobble = rng.randf() * TAU
	a.next_stop = rng.randf_range(8.0, 40.0)
	a.patience = rng.randf_range(5.0, 14.0)
	a.speed = CLASS_SPEED[cls] * speed_factor * 0.6
	var sampled := _sample(a)
	a.pos = sampled[0]
	a.heading = (sampled[1] as Vector2).angle()
	agents.append(a)


func _setup_lane(a: Agent) -> void:
	if lane_override.has(a.edge):
		a.target_lane = lane_override[a.edge] * (1.0 if a.dir > 0 else -1.0)
		return
	var cls := map.edge_class[a.edge]
	if a.kind == Kind.BICYCLE:
		a.target_lane = 0.9
	elif a.kind == Kind.BODA:
		a.target_lane = rng.randf_range(0.5, 0.9)
		if map.is_oneway(a.edge) and rng.randf() < 0.5:
			a.target_lane = -a.target_lane
	elif map.is_oneway(a.edge):
		a.target_lane = 0.4 if rng.randf() < 0.5 else -0.4
	elif cls <= 1:
		a.target_lane = 0.28 if rng.randf() < 0.45 else 0.66
	else:
		a.target_lane = 0.45


func _rebuild_hash() -> void:
	_hash.clear()
	for a in agents:
		var key := Vector2i(int(floor(a.pos.x / HASH_CELL)), int(floor(a.pos.y / HASH_CELL)))
		var bucket: Array = _hash.get_or_add(key, [])
		bucket.append(a)


func _think(a: Agent) -> void:
	if a.downed > 0.0 or a.arguing > 0.0:
		a.target_speed = 0.0
		return
	var cls := map.edge_class[a.edge]
	var want := CLASS_SPEED[cls] * a.speed_mul * speed_factor
	if map.is_unpaved(a.edge):
		want *= 0.75
	if a.hurry > 0.0:
		want *= 1.25
	var jammed := is_jammed(a.edge)
	if jammed:
		if a.kind == Kind.BODA:
			want = minf(want, 22.0)
		elif a.kind != Kind.BICYCLE:
			want = minf(want, rng.randf_range(4.0, 9.0))
	var held := false
	for z: Dictionary in zones:
		if a.pos.distance_squared_to(z["pos"]) < float(z["r"]) * float(z["r"]):
			want = minf(want, z["cap"])
			held = held or z.get("turn_back", false)
	if held:
		# Nobody knows how deep it is. Wait a bit, then go another way.
		a.hold += THINK_INTERVAL
		if a.hold > a.patience and a.kind != Kind.BODA:
			a.hold = 0.0
			_turn_round(a)
			return
		if a.kind != Kind.BODA:
			a.stuck = 0.0
			a.ghost = 0.0
			a.target_speed = 0.0
			return
	else:
		a.hold = 0.0
	var halted: bool = halt_query.is_valid() and bool(halt_query.call(a.pos))
	a.pulled_over = halted
	if halted:
		a.target_speed = 0.0
		a.target_lane = 0.92 if a.target_lane >= 0.0 else -0.92
		return
	if a.stop_timer > 0.0:
		a.target_speed = 0.0
		return
	var fwd := Vector2.from_angle(a.heading)
	var look := 12.0 + a.speed * 0.95
	var limit := want
	if a.ghost > 0.0:
		limit = minf(limit, 12.0)
	else:
		limit = _follow(a, fwd, look, limit)
		var to_player := player_pos - a.pos
		var ahead := to_player.dot(fwd)
		if ahead > 0.0 and ahead < look and absf(to_player.cross(fwd)) < a.radius + 3.6:
			var gap := ahead - a.hl - 5.6
			limit = minf(limit, maxf(0.0, player_vel.dot(fwd)) + maxf(gap, 0.0) * 1.1)
			if a.kind == Kind.BODA:
				a.target_lane = 0.9 if rng.randf() < 0.5 else -0.3
				limit = maxf(limit, 14.0)
	a.target_speed = limit
	if a.kind == Kind.BODA and limit < want * 0.6:
		# A boda does not queue: it finds a gap, on either side of anything.
		a.target_lane = clampf(a.target_lane + (rng.randf_range(-0.5, 0.5)), -0.75, 0.95)
		a.target_speed = maxf(limit, 11.0)


func _follow(a: Agent, fwd: Vector2, look: float, limit: float) -> float:
	var cx := int(floor(a.pos.x / HASH_CELL))
	var cy := int(floor(a.pos.y / HASH_CELL))
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var bucket: Array = _hash.get(Vector2i(cx + ox, cy + oy), [])
			for other: Agent in bucket:
				if other == a:
					continue
				var rel := other.pos - a.pos
				var ahead := rel.dot(fwd)
				if ahead <= 0.0 or ahead > look:
					continue
				if absf(rel.cross(fwd)) > a.radius + other.radius + 0.6:
					continue
				var other_fwd := Vector2.from_angle(other.heading)
				var along := other.speed * other_fwd.dot(fwd)
				if along < -4.0:
					continue  # Oncoming, and it will sort itself out.
				var gap := ahead - a.hl - other.hl
				limit = minf(limit, maxf(along, 0.0) + maxf(gap - 1.0, 0.0) * 1.1)
	return limit


func _move(a: Agent, dt: float) -> void:
	a.hit_cd = maxf(a.hit_cd - dt, 0.0)
	a.ghost = maxf(a.ghost - dt, 0.0)
	a.hurry = maxf(a.hurry - dt, 0.0)
	a.arguing = maxf(a.arguing - dt, 0.0)
	if a.downed > 0.0:
		a.downed -= dt
		a.speed = 0.0
		if a.downed <= 0.0:
			a.pos = Vector2(1e7, 1e7)  # Collected; despawned on this frame's check.
		return
	if a.stop_timer > 0.0:
		a.stop_timer -= dt
	else:
		a.next_stop -= dt
		if a.next_stop <= 0.0:
			a.next_stop = rng.randf_range(10.0, 45.0)
			if a.kind == Kind.TAXI or (a.kind == Kind.VAN and rng.randf() < 0.5):
				a.stop_timer = rng.randf_range(2.5, 7.0)
				a.target_lane = 0.85 if a.target_lane >= 0.0 else -0.85
	var accel := 34.0 if a.kind == Kind.BODA else 20.0
	var decel := 80.0
	a.speed = move_toward(a.speed, a.target_speed, (accel if a.target_speed > a.speed else decel) * dt)
	if a.speed < 1.0 and a.stop_timer <= 0.0 and a.arguing <= 0.0 and not a.pulled_over:
		a.stuck += dt
		if a.stuck > 3.5 and a.target_speed < 1.0:
			# Nobody waits long in Kampala: pull out and go round whatever it is.
			a.ghost = 3.0
			a.stuck = 0.0
			a.target_speed = 10.0
			a.target_lane = -0.15 if a.target_lane > 0.0 else 0.15
	else:
		a.stuck = 0.0
	a.s += a.speed * dt
	var path := map.edge_path(a.edge)
	if a.s >= path.length:
		_advance(a, a.s - path.length)
	if a.kind == Kind.BODA:
		a.wobble += dt * 2.3
	a.lane = move_toward(a.lane, a.target_lane, dt * (0.9 if a.kind == Kind.BODA else 0.45))
	var sampled := _sample(a)
	var p: Vector2 = sampled[0]
	var tan: Vector2 = sampled[1]
	var left := Vector2(tan.y, -tan.x)
	var hw := map.half_width(a.edge)
	var off := a.lane * hw
	if a.kind == Kind.BODA:
		off += sin(a.wobble) * 0.8
	var target := p + left * off
	a.pos = a.pos.lerp(target, clampf(dt * 7.0, 0.0, 1.0))
	if a.speed > 0.5:
		a.heading = lerp_angle(a.heading, tan.angle(), clampf(dt * 7.0, 0.0, 1.0))


func _turn_round(a: Agent) -> void:
	if map.is_oneway(a.edge):
		a.pos = Vector2(1e7, 1e7)  # Reverses up the one-way, out of sight.
		return
	a.s = map.edge_path(a.edge).length - a.s
	a.dir = -a.dir
	a.speed = 0.0
	a.heading = wrapf(a.heading + PI, -PI, PI)


func _sample(a: Agent) -> Array:
	var path := map.edge_path(a.edge)
	if a.dir > 0:
		return path.sample(a.s)
	var r: Array = path.sample(path.length - a.s)
	return [r[0], -(r[1] as Vector2)]


func _advance(a: Agent, overshoot: float) -> void:
	var node := map.edge_b[a.edge] if a.dir > 0 else map.edge_a[a.edge]
	var best := -1
	var total := 0.0
	for j in range(map.adj_start[node], map.adj_start[node + 1]):
		var e := map.adj_edges[j]
		if e == a.edge or blocked.has(e):
			continue
		if map.is_oneway(e) and map.edge_a[e] != node:
			continue
		var weight := TURN_WEIGHT[map.edge_class[e]]
		total += weight
		if rng.randf() * total <= weight:
			best = e
	if best < 0:
		# Dead end. Turn round, unless the road only goes the other way.
		if map.is_oneway(a.edge):
			a.pos = Vector2(1e7, 1e7)
			a.s = 0.0
			return
		a.dir = -a.dir
		a.s = 0.0
		return
	a.dir = 1 if map.edge_a[best] == node else -1
	a.edge = best
	a.s = overshoot
	var keep_side := a.target_lane
	_setup_lane(a)
	if a.kind == Kind.BODA:
		a.target_lane = keep_side
