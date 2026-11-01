class_name Autodriver
extends RefCounted
## A deliberately cautious bot. It proves every level can be finished, and drives
## the attract and screenshot runs. It knows nothing the player does not.

var session: RaceSession
var input := DriveInput.new()
var _stuck := 0.0
var _reverse := 0.0
var _pass_timer := 0.0
var _pass_side := -0.55
var _hit := MapData.RoadHit.new()
var _blocked_for := 0.0


func _init(race: RaceSession) -> void:
	session = race


func decide(dt: float) -> DriveInput:
	var car := session.car
	var look := clampf(absf(car.speed) * 0.6, 14.0, 38.0)
	var target := session.route_ahead_point(look)
	# Drive on the left, as everyone does. Pull out to the right to pass.
	var along := (target - car.pos).normalized()
	var left := Vector2(along.y, -along.x)
	_pass_timer = maxf(_pass_timer - dt, 0.0)
	var keep := _pass_side if _pass_timer > 0.0 else 0.45
	var half := 9.0
	if session.map.road_at(car.pos, _hit):
		half = session.map.half_width(_hit.edge)
	target += left * half * keep
	target = _aim_for_the_gap(target)
	input.has_target = true
	input.target_heading = (target - car.pos).angle()
	input.horn = false
	var want := 86.0
	# Slow for bends: how far the road ahead turns away from the car.
	var far := session.route_ahead_point(look + 45.0)
	var bend := absf(wrapf((far - car.pos).angle() - car.heading, -PI, PI))
	want = minf(want, lerpf(86.0, 20.0, clampf(bend / 1.1, 0.0, 1.0)))
	var fwd := car.forward()
	# Look along the line it means to drive, so pulling out can actually clear things.
	var aim := (target - car.pos).normalized()
	for a in session.traffic.nearby(car.pos + aim * 20.0, 28.0):
		var rel := a.pos - car.pos
		var ahead := rel.dot(aim)
		if ahead > 0.0 and absf(rel.cross(aim)) < a.radius + 3.2:
			want = minf(want, maxf(a.speed * 0.8, 0.0) + maxf(ahead - 10.0, 0.0) * 1.6)
			input.horn = a.kind == TrafficSim.Kind.BODA
	_blocked_for = _blocked_for + dt if want < 30.0 and bend < 0.4 else 0.0
	if _blocked_for > 1.5:
		_blocked_for = 0.0
		_pass_timer = 3.0
	var c := session.director.convoy_active()
	if c != null and session.director.in_corridor(c, car.pos):
		want = 0.0
	for h in session.director.hazards:
		if h.pos.distance_squared_to(car.pos) > 70.0 * 70.0:
			continue
		if h.type == "trench":
			want = minf(want, 14.0)
		elif h.type == "flagger" and not h.flag_green:
			want = minf(want, 8.0)
	var waiting_on_law := c != null and session.director.in_corridor(c, car.pos)
	_stuck = _stuck + dt if absf(car.speed) < 2.0 and session.freeze <= 0.0 and not waiting_on_law else 0.0
	if _stuck > 3.0:
		_stuck = 0.0
		_reverse = 1.0
		_pass_timer = 5.0
		_pass_side = -_pass_side
	if _reverse > 0.0:
		_reverse -= dt
		input.throttle = 0.0
		input.brake = 1.0
		input.has_target = false
		input.steer = 0.0
		return input
	if car.speed > want + 1.0:
		input.brake = clampf((car.speed - want) / 25.0, 0.1, 1.0)
		input.throttle = 0.0
	else:
		input.brake = 0.0
		input.throttle = 1.0 if car.speed < want else 0.0
	return input


## If the point it is aiming at sits inside a coned-off stretch, aim past its edge.
func _aim_for_the_gap(target: Vector2) -> Vector2:
	for h in session.director.hazards:
		if h.type != "partial" or h.pos.distance_squared_to(session.car.pos) > 90.0 * 90.0:
			continue
		var loc := h.local(target)
		if absf(loc.x) < h.hl + 8.0 and absf(loc.y) < h.hw + 4.0:
			var side := Vector2(h.tangent.y, -h.tangent.x)
			var away := -h.side  # The open part of the road is opposite the cones.
			return h.pos + h.tangent * loc.x + side * away * (h.hw + 4.0)
	return target
