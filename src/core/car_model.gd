class_name CarModel
extends RefCounted
## Arcade car: heading, signed speed, and a velocity that lags the heading so
## wet roads slide.

var cfg: Dictionary
var pos := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var vel := Vector2.ZERO


func _init(car_cfg: Dictionary) -> void:
	cfg = car_cfg


func forward() -> Vector2:
	return Vector2.from_angle(heading)


func step(dt: float, input: DriveInput, grip: float, top_speed_factor: float) -> void:
	var top: float = cfg["top_speed"] * top_speed_factor
	var steer := input.steer
	if input.has_target:
		var delta := wrapf(input.target_heading - heading, -PI, PI)
		steer = clampf(delta * 3.0, -1.0, 1.0)
	if input.throttle > 0.0 and speed < top:
		speed += float(cfg["accel"]) * input.throttle * (1.0 - clampf(speed / top, 0.0, 0.92)) * dt * 1.4
	if input.brake > 0.0:
		if speed > 0.5:
			speed -= float(cfg["brake"]) * input.brake * dt
		else:
			speed = maxf(speed - float(cfg["accel"]) * 0.7 * input.brake * dt, -float(cfg["reverse_speed"]))
	if input.throttle <= 0.0 and input.brake <= 0.0:
		speed = move_toward(speed, 0.0, float(cfg["coast_drag"]) * dt)
	if speed > top:
		speed = move_toward(speed, top, float(cfg["brake"]) * 0.6 * dt)
	if input.throttle > 0.0 and speed < -0.5:
		speed = move_toward(speed, 0.0, float(cfg["brake"]) * dt)
	var authority := clampf(absf(speed) / 16.0, 0.0, 1.0) / (1.0 + absf(speed) / 170.0)
	heading = wrapf(heading + steer * float(cfg["turn_rate"]) * authority * signf(speed) * dt, -PI, PI)
	vel = vel.lerp(forward() * speed, clampf(grip * dt, 0.0, 1.0))
	pos += vel * dt
